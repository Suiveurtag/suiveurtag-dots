#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fcntl
import json
import os
import selectors
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


HOME = Path.home()
XDG_RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
ADDON_DIR = Path(__file__).resolve().parent
CONTROL_SOCKET = XDG_RUNTIME_DIR / "hypr-zoomit.sock"
DRAW_LOCK = XDG_RUNTIME_DIR / "hypr-zoomit-draw.lock"
DEFAULT_ZOOM = 2.0
MIN_ZOOM = 1.0
MAX_ZOOM = 8.0
ZOOM_STEP = 1.25
FRAME_RATE = 120.0
ANIMATION_DURATION = 0.22


class ZoomItError(RuntimeError):
    pass


def compositor_socket_from_env() -> str:
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not signature:
        raise ZoomItError("HYPRLAND_INSTANCE_SIGNATURE is not available")
    return str(XDG_RUNTIME_DIR / "hypr" / signature / ".socket.sock")


def hypr_request(socket_path: str, request: str) -> str:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(1.0)
        client.connect(socket_path)
        client.sendall(request.encode("utf-8"))
        client.shutdown(socket.SHUT_WR)
        chunks: list[bytes] = []
        while True:
            chunk = client.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks).decode("utf-8", errors="replace")


def get_option(socket_path: str, name: str) -> dict[str, Any]:
    try:
        return json.loads(hypr_request(socket_path, f"j/getoption {name}"))
    except (json.JSONDecodeError, OSError) as error:
        raise ZoomItError(f"cannot read Hyprland option {name}: {error}") from error


def option_value(data: dict[str, Any]) -> float:
    for key in ("float", "int"):
        if key in data:
            return float(data[key])
    return 0.0


def set_keyword(socket_path: str, name: str, value: str | float | int) -> None:
    response = hypr_request(socket_path, f"/keyword {name} {value}")
    if not response.startswith("ok"):
        raise ZoomItError(f"Hyprland rejected {name}: {response.strip()}")


def bind_type(binding: dict[str, Any]) -> str:
    flags = ""
    for key, flag in (
        ("locked", "l"),
        ("mouse", "m"),
        ("release", "r"),
        ("repeat", "e"),
        ("longPress", "o"),
        ("non_consuming", "n"),
    ):
        if binding.get(key):
            flags += flag
    return "bind" + flags


class ZoomDaemon:
    def __init__(self) -> None:
        self.server: socket.socket | None = None
        self.selector = selectors.DefaultSelector()
        self.running = True
        self.hypr_socket = ""
        self.current = MIN_ZOOM
        self.target = MIN_ZOOM
        self.last_zoom = DEFAULT_ZOOM
        self.animation_start = MIN_ZOOM
        self.animation_started = 0.0
        self.bindings_active = False
        self.saved_bindings: list[dict[str, Any]] = []
        self.saved_options: dict[str, float] = {}

    def open(self) -> None:
        CONTROL_SOCKET.parent.mkdir(parents=True, exist_ok=True)
        CONTROL_SOCKET.unlink(missing_ok=True)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(CONTROL_SOCKET))
        os.chmod(CONTROL_SOCKET, 0o600)
        self.server.listen(8)
        self.server.setblocking(False)
        self.selector.register(self.server, selectors.EVENT_READ)

    def initialize_compositor(self, socket_path: str) -> None:
        if socket_path == self.hypr_socket:
            return
        if self.bindings_active:
            self.restore_runtime_state()
        self.hypr_socket = socket_path
        self.current = max(MIN_ZOOM, option_value(get_option(socket_path, "cursor:zoom_factor")))
        self.target = self.current
        self.animation_start = self.current

    def install_runtime_state(self) -> None:
        if self.bindings_active or not self.hypr_socket:
            return

        option_names = (
            "cursor:zoom_rigid",
            "cursor:zoom_detached_camera",
            "binds:scroll_event_delay",
        )
        self.saved_options = {
            name: option_value(get_option(self.hypr_socket, name)) for name in option_names
        }

        try:
            all_bindings = json.loads(hypr_request(self.hypr_socket, "j/binds"))
        except (json.JSONDecodeError, OSError) as error:
            raise ZoomItError(f"cannot snapshot Hyprland bindings: {error}") from error

        captured_keys = {"mouse_up", "mouse_down"}
        self.saved_bindings = [
            item
            for item in all_bindings
            if item.get("modmask") == 0
            and item.get("submap", "") == ""
            and item.get("key") in captured_keys
        ]

        command = shlex.quote(str(Path(__file__).resolve()))
        set_keyword(self.hypr_socket, "cursor:zoom_rigid", 1)
        set_keyword(self.hypr_socket, "cursor:zoom_detached_camera", 0)
        set_keyword(self.hypr_socket, "binds:scroll_event_delay", 18)
        set_keyword(self.hypr_socket, "bind", f", mouse_up, exec, {command} zoom-out")
        set_keyword(self.hypr_socket, "bind", f", mouse_down, exec, {command} zoom-in")
        self.bindings_active = True

    def restore_runtime_state(self) -> None:
        if not self.bindings_active or not self.hypr_socket:
            return
        for key in ("mouse_up", "mouse_down"):
            try:
                set_keyword(self.hypr_socket, "unbind", f", {key}")
            except (OSError, ZoomItError):
                pass

        for item in self.saved_bindings:
            binding = (
                f", {item.get('key', '')}, {item.get('dispatcher', 'exec')}, "
                f"{item.get('arg', '')}"
            )
            try:
                set_keyword(self.hypr_socket, bind_type(item), binding)
            except (OSError, ZoomItError):
                pass

        for name, value in self.saved_options.items():
            try:
                serialized = int(value) if value.is_integer() else value
                set_keyword(self.hypr_socket, name, serialized)
            except (OSError, ZoomItError):
                pass
        self.saved_bindings = []
        self.saved_options = {}
        self.bindings_active = False

    def animate_to(self, value: float) -> None:
        self.animation_start = self.current
        self.animation_started = time.monotonic()
        self.target = min(MAX_ZOOM, max(MIN_ZOOM, value))

    def handle(self, message: dict[str, Any]) -> None:
        socket_path = str(message.get("hypr_socket", ""))
        if not socket_path:
            return
        self.initialize_compositor(socket_path)
        action = message.get("action")

        if action == "zoom-toggle":
            if self.target > MIN_ZOOM + 0.01 or self.current > MIN_ZOOM + 0.01:
                self.last_zoom = max(DEFAULT_ZOOM, self.target, self.current)
                self.animate_to(MIN_ZOOM)
            else:
                self.install_runtime_state()
                self.animate_to(max(DEFAULT_ZOOM, self.last_zoom))
        elif action == "zoom-in":
            self.install_runtime_state()
            self.animate_to(max(DEFAULT_ZOOM, self.target * ZOOM_STEP))
            self.last_zoom = self.target
        elif action == "zoom-out":
            value = self.target / ZOOM_STEP
            if value < 1.08:
                value = MIN_ZOOM
            self.animate_to(value)
            if value > MIN_ZOOM:
                self.last_zoom = value

    def accept_messages(self) -> None:
        if self.server is None:
            return
        while True:
            try:
                connection, _ = self.server.accept()
            except BlockingIOError:
                break
            with connection:
                connection.settimeout(0.2)
                payload = bytearray()
                while True:
                    chunk = connection.recv(4096)
                    if not chunk:
                        break
                    payload.extend(chunk)
                try:
                    message = json.loads(payload.decode("utf-8"))
                    self.handle(message)
                    connection.sendall(b"ok")
                except (json.JSONDecodeError, OSError, ZoomItError) as error:
                    connection.sendall(f"error: {error}".encode("utf-8"))

    def update_animation(self) -> None:
        if not self.hypr_socket or abs(self.current - self.target) < 0.000001:
            return
        elapsed = time.monotonic() - self.animation_started
        progress = min(1.0, elapsed / ANIMATION_DURATION)
        eased = 1.0 - pow(1.0 - progress, 4)
        next_value = self.animation_start + (self.target - self.animation_start) * eased
        if progress >= 1.0:
            next_value = self.target
        try:
            set_keyword(self.hypr_socket, "cursor:zoom_factor", f"{next_value:.5f}")
            self.current = next_value
        except (OSError, ZoomItError):
            self.hypr_socket = ""
            self.bindings_active = False
            return

        if self.current <= MIN_ZOOM + 0.0005 and self.target == MIN_ZOOM:
            try:
                set_keyword(self.hypr_socket, "cursor:zoom_factor", MIN_ZOOM)
            except (OSError, ZoomItError):
                pass
            self.current = MIN_ZOOM
            self.restore_runtime_state()

    def shutdown(self) -> None:
        if self.hypr_socket:
            try:
                set_keyword(self.hypr_socket, "cursor:zoom_factor", MIN_ZOOM)
            except (OSError, ZoomItError):
                pass
        self.restore_runtime_state()
        if self.server is not None:
            self.selector.unregister(self.server)
            self.server.close()
        CONTROL_SOCKET.unlink(missing_ok=True)

    def run(self) -> int:
        self.open()

        def stop(_signum: int, _frame: Any) -> None:
            self.running = False

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        frame_interval = 1.0 / FRAME_RATE
        try:
            while self.running:
                events = self.selector.select(frame_interval)
                if events:
                    self.accept_messages()
                self.update_animation()
        finally:
            self.shutdown()
        return 0


def contact_daemon(action: str) -> None:
    payload = json.dumps(
        {"action": action, "hypr_socket": compositor_socket_from_env()}
    ).encode("utf-8")

    for attempt in range(30):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(0.5)
                client.connect(str(CONTROL_SOCKET))
                client.sendall(payload)
                client.shutdown(socket.SHUT_WR)
                response = client.recv(1024).decode("utf-8", errors="replace")
                if not response.startswith("ok"):
                    raise ZoomItError(response)
                return
        except (FileNotFoundError, ConnectionRefusedError):
            if attempt == 0:
                started = subprocess.run(
                    ["systemctl", "--user", "start", "hypr-zoomit.service"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                ).returncode == 0
                if not started:
                    subprocess.Popen(
                        [sys.executable, str(Path(__file__).resolve()), "daemon"],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        start_new_session=True,
                    )
            time.sleep(0.025)
    raise ZoomItError("the zoom daemon did not start")


def focused_output() -> str:
    result = subprocess.run(
        ["hyprctl", "-j", "monitors"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise ZoomItError(result.stderr.strip() or "cannot query Hyprland monitors")
    try:
        monitors = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ZoomItError(f"invalid Hyprland monitor response: {error}") from error
    focused = next((item for item in monitors if item.get("focused")), None)
    if not focused:
        raise ZoomItError("no focused monitor found")
    return str(focused["name"])


def toggle_draw() -> None:
    DRAW_LOCK.parent.mkdir(parents=True, exist_ok=True)
    lock_handle = DRAW_LOCK.open("a+", encoding="utf-8")
    try:
        fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_handle.seek(0)
        try:
            owner = int(lock_handle.read().strip())
            os.kill(owner, signal.SIGTERM)
        except (ValueError, ProcessLookupError, PermissionError):
            pass
        lock_handle.close()
        return

    lock_handle.seek(0)
    lock_handle.truncate()
    lock_handle.write(str(os.getpid()))
    lock_handle.flush()

    output = focused_output()
    temporary = tempfile.NamedTemporaryFile(
        prefix="hypr-zoomit-", suffix=".png", dir=XDG_RUNTIME_DIR, delete=False
    )
    screenshot = Path(temporary.name)
    temporary.close()
    child: subprocess.Popen[bytes] | None = None

    def stop(_signum: int, _frame: Any) -> None:
        if child is not None and child.poll() is None:
            child.terminate()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        capture = subprocess.run(
            ["grim", "-o", output, str(screenshot)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=False,
        )
        if capture.returncode:
            raise ZoomItError(capture.stderr.decode("utf-8", errors="replace").strip())
        environment = os.environ.copy()
        environment["ZOOMIT_SCREENSHOT"] = str(screenshot)
        environment["ZOOMIT_OUTPUT"] = output
        child = subprocess.Popen(
            ["qs", "-p", str(ADDON_DIR / "DrawOverlay.qml")],
            env=environment,
        )
        child.wait()
    finally:
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                child.kill()
        screenshot.unlink(missing_ok=True)
        lock_handle.seek(0)
        lock_handle.truncate()
        fcntl.flock(lock_handle, fcntl.LOCK_UN)
        lock_handle.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ZoomIt-style tools for Hyprland")
    parser.add_argument(
        "action",
        choices=("daemon", "zoom-toggle", "zoom-in", "zoom-out", "draw-toggle"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.action == "daemon":
        return ZoomDaemon().run()
    if args.action == "draw-toggle":
        toggle_draw()
        return 0
    contact_daemon(args.action)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ZoomItError as error:
        print(f"zoomit: {error}", file=sys.stderr)
        raise SystemExit(1)
