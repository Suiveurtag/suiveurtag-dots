#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import signal
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


NODE_NAME = "headset_audio_microphone"
LOOPBACK_NAME = "headset-audio-microphone"
SOURCE_DESCRIPTION = "Headset Audio"
XDG_RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
STATE_DIR = XDG_RUNTIME_DIR / "quickshell-addons" / "headset-mic-loopback"
PID_FILE = STATE_DIR / "pw-loopback.pid"
INFO_FILE = STATE_DIR / "route.json"


class LoopbackError(RuntimeError):
    pass


def process_matches(pid: int) -> bool:
    try:
        command = (Path("/proc") / str(pid) / "cmdline").read_bytes().split(b"\0")
    except (OSError, ValueError):
        return False
    arguments = [item.decode("utf-8", errors="replace") for item in command if item]
    return bool(arguments) and Path(arguments[0]).name == "pw-loopback" and any(
        item == LOOPBACK_NAME for item in arguments
    )


def matching_processes() -> list[int]:
    matches: set[int] = set()
    try:
        pid = int(PID_FILE.read_text(encoding="utf-8").strip())
        if process_matches(pid):
            matches.add(pid)
    except (OSError, ValueError):
        pass

    proc = Path("/proc")
    try:
        entries = list(proc.iterdir())
    except OSError:
        entries = []
    for entry in entries:
        if entry.name.isdigit():
            pid = int(entry.name)
            if process_matches(pid):
                matches.add(pid)
    return sorted(matches)


def read_info() -> dict[str, str]:
    try:
        data = json.loads(INFO_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def source_exists() -> bool:
    result = subprocess.run(
        ["pactl", "list", "short", "sources"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        return False
    return any(
        len(fields := line.split("\t")) > 1 and fields[1] == NODE_NAME
        for line in result.stdout.splitlines()
    )


def status() -> dict[str, object]:
    processes = matching_processes()
    enabled = bool(processes) and source_exists()
    if not enabled and not processes:
        PID_FILE.unlink(missing_ok=True)
        INFO_FILE.unlink(missing_ok=True)
    info = read_info()
    return {
        "enabled": enabled,
        "source": SOURCE_DESCRIPTION,
        "output": str(info.get("output", "")),
        "output_name": str(info.get("output_name", "")),
    }


def inspect_default_sink() -> tuple[str, str]:
    result = subprocess.run(
        ["wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise LoopbackError("could not inspect the default audio output")

    name = ""
    description = ""
    for line in result.stdout.splitlines():
        key, separator, value = line.partition("=")
        if not separator:
            continue
        key = key.strip().lstrip("*").strip()
        value = value.strip().strip('"')
        if key == "node.name":
            name = value
        elif key == "node.description":
            description = value
    if not name:
        raise LoopbackError("the default audio output has no PipeWire node name")
    return name, description or name


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def enable() -> dict[str, object]:
    current = status()
    if current["enabled"]:
        return current
    if not shutil.which("pw-loopback") or not shutil.which("wpctl") or not shutil.which("pactl"):
        raise LoopbackError("pw-loopback, wpctl and pactl are required")

    for pid in matching_processes():
        stop_process(pid)

    output_name, output_description = inspect_default_sink()
    command = [
        "pw-loopback",
        "--name",
        LOOPBACK_NAME,
        "--channels",
        "2",
        "--channel-map",
        "[ FL, FR ]",
        "--latency",
        "20",
        "--capture",
        output_name,
        "--capture-props",
        "{ stream.capture.sink = true node.passive = true node.dont-reconnect = false }",
        "--playback-props",
        (
            "{ media.class = Audio/Source "
            f"node.name = {NODE_NAME} "
            f'node.description = "{SOURCE_DESCRIPTION}" '
            "node.virtual = true }"
        ),
    ]
    process = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    atomic_write(PID_FILE, f"{process.pid}\n")
    atomic_write(
        INFO_FILE,
        json.dumps({"output": output_description, "output_name": output_name}, ensure_ascii=False) + "\n",
    )

    for _ in range(30):
        if process.poll() is not None:
            break
        if source_exists():
            return status()
        time.sleep(0.1)

    if process.poll() is None:
        stop_process(process.pid)
    PID_FILE.unlink(missing_ok=True)
    INFO_FILE.unlink(missing_ok=True)
    raise LoopbackError("PipeWire did not create the virtual microphone")


def stop_process(pid: int) -> None:
    if not process_matches(pid):
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(20):
        if not process_matches(pid):
            return
        time.sleep(0.05)
    if process_matches(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def disable() -> dict[str, object]:
    for pid in matching_processes():
        stop_process(pid)
    PID_FILE.unlink(missing_ok=True)
    INFO_FILE.unlink(missing_ok=True)
    return status()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Expose the current audio output as a virtual microphone")
    parser.add_argument("action", choices=("status", "enable", "disable", "toggle"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    current = status()
    if args.action == "enable":
        current = enable()
    elif args.action == "disable":
        current = disable()
    elif args.action == "toggle":
        current = disable() if current["enabled"] else enable()
    print(json.dumps(current, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except LoopbackError as error:
        print(f"headset-mic-loopback: {error}", file=sys.stderr)
        raise SystemExit(1)
