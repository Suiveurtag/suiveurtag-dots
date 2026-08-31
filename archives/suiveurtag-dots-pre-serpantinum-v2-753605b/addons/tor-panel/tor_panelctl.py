#!/usr/bin/env python3
"""Control the Tor panel and launch selected desktop applications fail-closed."""

from __future__ import annotations

import argparse
import fcntl
import json
import locale
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


HOME = Path.home()
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")).expanduser()
XDG_STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")).expanduser()
XDG_RUNTIME_DIR = Path(
    os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
).expanduser()

ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/tor-panel"
STATE_DIR = XDG_STATE_HOME / "quickshell/tor-panel"
ROUTES_FILE = STATE_DIR / "routes.json"
LOCK_FILE = STATE_DIR / "routes.lock"
RUNTIME_DIR = XDG_RUNTIME_DIR / "tor-panel"
SOCKS_SOCKET = RUNTIME_DIR / "socks"
CONTROL_SOCKET = RUNTIME_DIR / "control"
CONTROL_COOKIE = RUNTIME_DIR / "control.authcookie"
SERVICE = "tor-panel-tor.service"

DEPENDENCIES = {
    "tor": "tor",
    "proxychains": "proxychains4",
    "bubblewrap": "bwrap",
    "socat": "socat",
}

BROWSER_MARKERS = (
    "firefox",
    "zen-browser",
    " zen ",
    "chromium",
    "google-chrome",
    "brave",
    "vivaldi",
    "opera",
    "microsoft-edge",
)
TORRENT_MARKERS = ("qbittorrent", "transmission", "deluge", "aria2c")
PRIVILEGED_MARKERS = ("pkexec", "sudo", "doas")


class TorPanelError(RuntimeError):
    pass


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def notify(title: str, body: str, urgency: str = "normal") -> None:
    command = shutil.which("notify-send")
    if not command:
        return
    subprocess.Popen(
        [command, "-a", "Tor Panel", "-u", urgency, "-i", "network-vpn", title, body],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def ensure_state_dir() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        STATE_DIR.chmod(0o700)
    except OSError:
        pass


def default_routes() -> dict[str, Any]:
    return {"version": 1, "routes": {}}


def load_routes() -> dict[str, Any]:
    ensure_state_dir()
    if not ROUTES_FILE.is_file():
        return default_routes()
    try:
        data = json.loads(ROUTES_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default_routes()
    if not isinstance(data, dict) or not isinstance(data.get("routes"), dict):
        return default_routes()
    data["version"] = 1
    return data


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    ensure_state_dir()
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        temporary.chmod(0o600)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def update_route(desktop_id: str, enabled: bool) -> dict[str, Any]:
    catalog = {app["desktopId"]: app for app in application_catalog()}
    app = catalog.get(desktop_id)
    if not app:
        raise TorPanelError(f"Application not found: {desktop_id}")
    if enabled and app["support"] != "strict":
        raise TorPanelError(app["reason"] or "This application cannot be strictly isolated.")

    ensure_state_dir()
    with LOCK_FILE.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        data = load_routes()
        routes = data["routes"]
        if enabled:
            routes[desktop_id] = {
                "name": app["name"],
                "exec": app["exec"],
                "icon": app["icon"],
                "enabled": True,
            }
        else:
            routes.pop(desktop_id, None)
        atomic_write_json(ROUTES_FILE, data)
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
    return app


def data_directories() -> list[Path]:
    raw_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    candidates = [XDG_DATA_HOME]
    candidates.extend(Path(item).expanduser() for item in raw_dirs.split(":") if item)
    candidates.extend(
        [
            HOME / ".local/share/flatpak/exports/share",
            Path("/var/lib/flatpak/exports/share"),
            HOME / ".nix-profile/share",
            Path("/run/current-system/sw/share"),
        ]
    )
    unique: list[Path] = []
    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate)
        if key not in seen:
            seen.add(key)
            unique.append(candidate)
    return unique


def localized_name(values: dict[str, str]) -> str:
    language = (locale.getlocale()[0] or os.environ.get("LANG", "")).split(".")[0]
    variants = []
    if language:
        variants.append(f"Name[{language}]")
        if "_" in language:
            variants.append(f"Name[{language.split('_', 1)[0]}]")
    variants.append("Name")
    for key in variants:
        if values.get(key):
            return values[key]
    return ""


def parse_desktop_file(path: Path, desktop_id: str) -> dict[str, str] | None:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None
    values: dict[str, str] = {}
    in_desktop_entry = False
    for raw_line in lines:
        line = raw_line.strip()
        if line == "[Desktop Entry]":
            in_desktop_entry = True
            continue
        if line.startswith("["):
            if in_desktop_entry:
                break
            continue
        if not in_desktop_entry or not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values.setdefault(key, value)

    if values.get("Type", "Application") != "Application":
        return None
    if values.get("Hidden", "false").lower() == "true":
        return None
    if values.get("NoDisplay", "false").lower() == "true":
        return None
    name = localized_name(values)
    raw_exec = values.get("Exec", "").strip()
    if not name or not raw_exec:
        return None

    # Match the command string exposed by ilyamiro's app_fetcher.py. Field
    # codes carry a file/URL selected by a launcher and are absent on Meta+D.
    launcher_exec = raw_exec.split(" %", 1)[0].split(" @@", 1)[0].strip()
    if not launcher_exec:
        return None
    return {
        "desktopId": desktop_id,
        "name": name,
        "exec": launcher_exec,
        "icon": values.get("Icon", "application-x-executable"),
        "categories": values.get("Categories", ""),
        "terminal": values.get("Terminal", "false"),
    }


def support_for(app: dict[str, str]) -> tuple[str, str]:
    command = f" {app['exec'].lower()} "
    categories = app.get("categories", "").lower()
    if "flatpak run" in command or "/snap/bin/" in command or " snap run " in command:
        return "unsupported", "Nested application sandbox: strict routing cannot be guaranteed"
    if "steam://" in command or re.search(r"(^|\s)steam(\s|$)", command):
        return "unsupported", "Steam and games often use UDP and are not supported"
    if "game;" in categories:
        return "unsupported", "Games and their UDP traffic are not supported"
    if any(marker in command for marker in TORRENT_MARKERS):
        return "unsupported", "BitTorrent must not be used over the Tor network"
    if any(marker in command for marker in BROWSER_MARKERS):
        return "unsupported", "For web browsing, use Tor Browser and its anti-fingerprinting protections"
    if any(re.search(rf"(^|\s){re.escape(marker)}(\s|$)", command) for marker in PRIVILEGED_MARKERS):
        return "unsupported", "A privileged application cannot remain inside the user sandbox"
    return "strict", "TCP and DNS isolated; UDP and direct network access blocked"


def application_catalog() -> list[dict[str, Any]]:
    routes = load_routes().get("routes", {})
    catalog: dict[str, dict[str, Any]] = {}
    names: set[str] = set()
    for data_root in data_directories():
        applications_dir = data_root / "applications"
        if not applications_dir.is_dir():
            continue
        for path in sorted(applications_dir.rglob("*.desktop")):
            try:
                relative = path.relative_to(applications_dir)
            except ValueError:
                continue
            desktop_id = str(relative).replace(os.sep, "-")
            if desktop_id in catalog:
                continue
            parsed = parse_desktop_file(path, desktop_id)
            if not parsed:
                continue
            # Match the existing launcher, which exposes a single item per name.
            folded_name = parsed["name"].casefold()
            if folded_name in names:
                continue
            names.add(folded_name)
            support, reason = support_for(parsed)
            catalog[desktop_id] = {
                **parsed,
                "support": support,
                "reason": reason,
                "routed": bool(routes.get(desktop_id, {}).get("enabled")),
            }
    return sorted(catalog.values(), key=lambda item: item["name"].casefold())


def dependencies() -> dict[str, bool]:
    return {label: shutil.which(command) is not None for label, command in DEPENDENCIES.items()}


def systemctl(*arguments: str, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["systemctl", "--user", *arguments],
        capture_output=True,
        text=True,
        check=check,
    )


def service_properties() -> dict[str, str]:
    result = systemctl(
        "show",
        SERVICE,
        "--property=LoadState,ActiveState,SubState,Result,ActiveEnterTimestampMonotonic",
    )
    if result.returncode:
        return {"LoadState": "not-found", "ActiveState": "inactive", "SubState": "dead", "Result": ""}
    properties: dict[str, str] = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            properties[key] = value
    return properties


def read_control_reply(stream: Any) -> tuple[int, str]:
    lines: list[str] = []
    expected_code = -1
    while True:
        raw_line = stream.readline()
        if not raw_line:
            raise TorPanelError("The Tor control port closed the connection")
        line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
        if len(line) < 4 or not line[:3].isdigit():
            raise TorPanelError(f"Invalid Tor control response: {line}")
        code = int(line[:3])
        separator = line[3]
        if expected_code < 0:
            expected_code = code
        elif code != expected_code:
            raise TorPanelError(f"Inconsistent Tor control codes: {expected_code}/{code}")
        lines.append(line)

        if separator == "+":
            while True:
                data_line = stream.readline()
                if not data_line:
                    raise TorPanelError("Incomplete Tor control data block")
                decoded = data_line.decode("utf-8", errors="replace").rstrip("\r\n")
                if decoded == ".":
                    break
                lines.append(decoded[1:] if decoded.startswith("..") else decoded)
        elif separator == " ":
            return expected_code, "\n".join(lines)
        elif separator != "-":
            raise TorPanelError(f"Invalid Tor control separator: {separator}")


def control_exchange(*commands: str) -> list[str]:
    if not CONTROL_SOCKET.exists() or not CONTROL_COOKIE.is_file():
        raise TorPanelError("The Tor control port is not ready yet")
    cookie = CONTROL_COOKIE.read_bytes().hex()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as control:
        control.settimeout(1.5)
        control.connect(str(CONTROL_SOCKET))
        stream = control.makefile("rb")
        control.sendall(f"AUTHENTICATE {cookie}\r\n".encode("ascii"))
        auth_code, auth_reply = read_control_reply(stream)
        if auth_code != 250:
            raise TorPanelError(f"Tor control authentication rejected: {auth_reply}")

        replies: list[str] = []
        for command in commands:
            control.sendall((command + "\r\n").encode("ascii"))
            code, reply = read_control_reply(stream)
            if code != 250:
                raise TorPanelError(f"Tor command rejected ({command}): {reply}")
            replies.append(reply)
        return replies


def control_status() -> tuple[int, str, int]:
    bootstrap_reply, circuits_reply = control_exchange(
        "GETINFO status/bootstrap-phase", "GETINFO circuit-status"
    )
    progress_match = re.search(r"PROGRESS=(\d+)", bootstrap_reply)
    summary_match = re.search(r'SUMMARY="([^"]*)"', bootstrap_reply)
    progress = int(progress_match.group(1)) if progress_match else 0
    summary = summary_match.group(1) if summary_match else "Connecting to the Tor network"
    circuits = len(re.findall(r"(?m)^\d+\s+BUILT\s", circuits_reply))
    return progress, summary, circuits


def uptime_seconds(properties: dict[str, str]) -> int:
    try:
        entered = int(properties.get("ActiveEnterTimestampMonotonic", "0")) / 1_000_000
        boot_uptime = float(Path("/proc/uptime").read_text(encoding="ascii").split()[0])
        return max(0, int(boot_uptime - entered)) if entered else 0
    except (OSError, ValueError, IndexError):
        return 0


def status_payload() -> dict[str, Any]:
    props = service_properties()
    active_state = props.get("ActiveState", "inactive")
    progress = 0
    summary = "Tor is disconnected"
    circuits = 0
    control_error = ""
    if active_state in {"active", "activating"}:
        try:
            progress, summary, circuits = control_status()
        except (OSError, TorPanelError) as error:
            control_error = str(error)
            summary = "Starting the Tor client"

    if props.get("LoadState") == "not-found":
        state = "unavailable"
        summary = "User Tor service is missing"
    elif active_state == "failed" or props.get("Result") not in {"", "success"}:
        state = "error"
        summary = "The Tor service encountered an error"
    elif active_state == "active" and progress >= 100:
        state = "connected"
        summary = "Tor circuit ready"
    elif active_state in {"active", "activating", "reloading"}:
        state = "connecting"
    else:
        state = "disconnected"

    routes = load_routes().get("routes", {})
    deps = dependencies()
    return {
        "ok": True,
        "state": state,
        "progress": progress,
        "summary": summary,
        "circuits": circuits,
        "uptime": uptime_seconds(props) if state == "connected" else 0,
        "selectedCount": sum(1 for value in routes.values() if value.get("enabled")),
        "socks": "private Unix socket",
        "dependencies": deps,
        "runtimeReady": all(deps.values()),
        "serviceState": active_state,
        "controlError": control_error,
    }


def network_action(action: str) -> dict[str, Any]:
    if not dependencies()["tor"]:
        raise TorPanelError("Tor is not installed")
    if service_properties().get("LoadState") == "not-found":
        raise TorPanelError("The tor-panel-tor.service user service is not installed")
    if action == "start":
        result = systemctl("--no-block", "start", SERVICE)
    else:
        result = systemctl("stop", SERVICE)
    if result.returncode:
        details = (result.stderr or result.stdout).strip()
        raise TorPanelError(details or f"Unable to {action} Tor")
    time.sleep(0.15)
    return status_payload()


def new_identity() -> dict[str, Any]:
    control_exchange("SIGNAL NEWNYM")
    payload = status_payload()
    payload["identityChanged"] = True
    return payload


def parsed_exec(command: str) -> list[str]:
    try:
        argv = shlex.split(command)
    except ValueError as error:
        raise TorPanelError(f"Invalid .desktop command: {error}") from error
    if not argv:
        raise TorPanelError("Empty application command")
    return argv


def catalog_route_for_exec(command: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    wanted = parsed_exec(command)
    matches = [app for app in application_catalog() if parsed_exec(app["exec"]) == wanted]
    if not matches:
        raise TorPanelError(
            "Command not found in the application catalog; launch refused to prevent a routing bypass"
        )

    routes = load_routes().get("routes", {})
    routed = [
        app
        for app in matches
        if routes.get(app["desktopId"], {}).get("enabled")
    ]
    if len(matches) > 1 and 0 < len(routed) < len(matches):
        names = ", ".join(app["name"] for app in matches)
        raise TorPanelError(
            f"Command shared by multiple entries ({names}) with different modes; make their Tor choices consistent"
        )
    if routed:
        app = routed[0]
        return app, routes[app["desktopId"]]
    return matches[0], None


def wait_until_connected(timeout: float = 90.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        payload = status_payload()
        if payload["state"] == "connected":
            return True
        if payload["state"] in {"error", "unavailable"}:
            return False
        time.sleep(0.5)
    return False


def direct_launch(command: str) -> None:
    argv = parsed_exec(command)
    subprocess.Popen(
        argv,
        cwd=HOME,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def sandbox_bindings() -> list[str]:
    runtime = XDG_RUNTIME_DIR
    runtime_parent = runtime.parent
    args: list[str] = [
        "--tmpfs",
        "/run",
        "--dir",
        str(runtime_parent),
        "--dir",
        str(runtime),
    ]
    created_dirs: set[Path] = {Path("/run"), runtime_parent, runtime}

    def ensure_dir(path: Path) -> None:
        if path in created_dirs:
            return
        parent = path.parent
        ensure_dir(parent)
        args.extend(["--dir", str(path)])
        created_dirs.add(path)

    def bind_socket(path: Path) -> None:
        if not path.exists():
            return
        ensure_dir(path.parent)
        args.extend(["--ro-bind", str(path), str(path)])

    ensure_dir(RUNTIME_DIR)
    bind_socket(SOCKS_SOCKET)

    wayland_display = os.environ.get("WAYLAND_DISPLAY", "")
    if wayland_display:
        bind_socket(runtime / wayland_display)

    for relative in ("pipewire-0", "pipewire-0-manager", "pulse/native"):
        bind_socket(runtime / relative)

    display = os.environ.get("DISPLAY", "")
    if display.startswith(":"):
        display_number = display[1:].split(".", 1)[0]
        x_socket = Path("/tmp/.X11-unix") / f"X{display_number}"
        if x_socket.exists():
            args.extend(["--dir", "/tmp/.X11-unix", "--ro-bind", str(x_socket), str(x_socket)])
    return args


def tor_launch(app: dict[str, Any]) -> None:
    missing = [label for label, ready in dependencies().items() if not ready]
    if missing:
        raise TorPanelError("Incomplete Tor runtime: " + ", ".join(missing))

    if app["support"] != "strict":
        raise TorPanelError(app["reason"])

    current = status_payload()
    if current["state"] != "connected":
        notify("Connecting to Tor", f"Preparing to launch {app['name']}…")
        network_action("start")
        if not wait_until_connected():
            raise TorPanelError("Tor did not establish a circuit; launch canceled without a direct connection")

    argv = parsed_exec(app["exec"])
    desktop_id = app["desktopId"]
    bwrap = shutil.which("bwrap")
    entry = ADDON_DIR / "tor_sandbox_entry.sh"
    if not bwrap or not entry.is_file():
        raise TorPanelError("The isolated Tor launcher is incomplete")

    environment = os.environ.copy()
    environment["TOR_PANEL_SOCKS_SOCKET"] = str(SOCKS_SOCKET)
    environment["TOR_PANEL_ROUTE_ID"] = desktop_id
    environment["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={RUNTIME_DIR}/no-session-bus"
    environment["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=/run/dbus/no-system-bus"
    environment.pop("AT_SPI_BUS_ADDRESS", None)

    sandbox = [
        bwrap,
        "--unshare-net",
        "--unshare-pid",
        "--unshare-uts",
        "--new-session",
        "--die-with-parent",
        "--bind",
        "/",
        "/",
        "--dev-bind",
        "/dev",
        "/dev",
        "--proc",
        "/proc",
        "--tmpfs",
        "/tmp",
        *sandbox_bindings(),
        "--setenv",
        "XDG_RUNTIME_DIR",
        str(XDG_RUNTIME_DIR),
        "--setenv",
        "DBUS_SESSION_BUS_ADDRESS",
        environment["DBUS_SESSION_BUS_ADDRESS"],
        "--setenv",
        "DBUS_SYSTEM_BUS_ADDRESS",
        environment["DBUS_SYSTEM_BUS_ADDRESS"],
        "--setenv",
        "SUIVEURTAG_TOR_ROUTE",
        desktop_id,
        "--",
        str(entry),
        *argv,
    ]
    notify("Launched through Tor", f"{app['name']} is using an isolated network namespace.")
    os.execvpe(bwrap, sandbox, environment)


def launch(command: str) -> None:
    app, route = catalog_route_for_exec(command)
    if route is None:
        direct_launch(app["exec"])
    else:
        tor_launch(app)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    subparsers.add_parser("apps")

    route_parser = subparsers.add_parser("set-route")
    route_parser.add_argument("desktop_id")
    route_parser.add_argument("mode", choices=("on", "off", "tor", "direct"))

    network_parser = subparsers.add_parser("network")
    network_parser.add_argument("action", choices=("start", "stop"))

    subparsers.add_parser("new-identity")
    launch_parser = subparsers.add_parser("launch")
    launch_parser.add_argument("--exec", dest="exec_command", required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "status":
            emit(status_payload())
        elif args.command == "apps":
            apps = application_catalog()
            emit(
                {
                    "ok": True,
                    "apps": apps,
                    "count": len(apps),
                    "routedCount": sum(1 for app in apps if app["routed"]),
                }
            )
        elif args.command == "set-route":
            enabled = args.mode in {"on", "tor"}
            app = update_route(args.desktop_id, enabled)
            emit({"ok": True, "desktopId": args.desktop_id, "routed": enabled, "name": app["name"]})
        elif args.command == "network":
            emit(network_action(args.action))
        elif args.command == "new-identity":
            emit(new_identity())
        elif args.command == "launch":
            launch(args.exec_command)
        return 0
    except (OSError, ValueError, TorPanelError, subprocess.SubprocessError) as error:
        message = str(error) or error.__class__.__name__
        if args.command == "launch":
            notify("Tor launch canceled", message, "critical")
        emit({"ok": False, "error": message})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
