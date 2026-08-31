#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import subprocess
import tempfile
import time
from datetime import datetime
from pathlib import Path


HOME = Path.home()
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")).expanduser()
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")).expanduser()
XDG_RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
HYPR_BASE = Path(os.environ.get("HYPR_CONFIG_DIR", XDG_CONFIG_HOME / "hypr")).expanduser()
SETTINGS = Path(os.environ.get("HYPR_SETTINGS", HYPR_BASE / "settings.json")).expanduser()
SETTINGS_WATCHER = HYPR_BASE / "scripts" / "settings_watcher.sh"
AUTOSTART_CONF = HYPR_BASE / "config" / "autostart.conf"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons" / "idle-inhibit"
BACKUP_DIR = ADDON_DIR / "backups"
LOCK_FILE = XDG_RUNTIME_DIR / "quickshell-addons-settings.lock"


class ApplyError(RuntimeError):
    pass


def atomic_write(path: Path, content: str) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.chmod(temporary, path.stat().st_mode)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def backup(path: Path) -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{stamp}")


def write_setting(disabled: bool | None) -> tuple[bool, bool]:
    try:
        data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ApplyError(f"invalid settings.json: {error}") from error
    if not isinstance(data, dict):
        raise ApplyError("settings.json root is not an object")

    setting_existed = "disableIdleTimeouts" in data
    requested = data.get("disableIdleTimeouts") is True if disabled is None else disabled
    changed = False
    if not setting_existed or data.get("disableIdleTimeouts") != requested:
        data["disableIdleTimeouts"] = requested
        changed = True

    startup = data.get("startup")
    if not isinstance(startup, list):
        raise ApplyError("settings.json startup is not a list")
    idle_entries = [
        item
        for item in startup
        if isinstance(item, dict) and str(item.get("command", "")).strip() == "hypridle"
    ]
    if requested and idle_entries:
        data["startup"] = [item for item in startup if item not in idle_entries]
        changed = True
    elif not requested and not idle_entries and (setting_existed or disabled is not None):
        insert_at = next(
            (
                index + 1
                for index, item in enumerate(startup)
                if isinstance(item, dict)
                and str(item.get("command", "")).strip() == "awww-daemon"
            ),
            len(startup),
        )
        startup.insert(insert_at, {"command": "hypridle"})
        changed = True

    if changed:
        backup(SETTINGS)
        atomic_write(SETTINGS, json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    return changed, requested


def generated_config_matches(disabled: bool) -> bool:
    try:
        has_hypridle = any(
            line.strip() == "exec-once = hypridle"
            for line in AUTOSTART_CONF.read_text(encoding="utf-8").splitlines()
        )
    except OSError:
        return False
    return has_hypridle != disabled


def compile_settings(disabled: bool) -> None:
    for _ in range(20):
        if generated_config_matches(disabled):
            return
        time.sleep(0.1)
    if not SETTINGS_WATCHER.is_file():
        raise ApplyError(f"settings_watcher not found: {SETTINGS_WATCHER}")
    result = subprocess.run(
        ["bash", str(SETTINGS_WATCHER), "--compile"],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        details = (result.stdout + result.stderr).strip()
        raise ApplyError(f"settings_watcher --compile failed:\n{details}")


def sync_hypridle(disabled: bool) -> None:
    running = subprocess.run(
        ["pgrep", "-x", "hypridle"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0
    if disabled:
        if running:
            subprocess.run(
                ["pkill", "-x", "hypridle"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        return
    if not running:
        if not shutil.which("hypridle"):
            raise ApplyError("missing required command: hypridle")
        subprocess.Popen(
            ["hypridle"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Disable automatic idle sleep and locking")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--disable", action="store_true")
    group.add_argument("--enable", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not SETTINGS.is_file():
        raise ApplyError(f"settings.json not found: {SETTINGS}")
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        explicit = True if args.disable else False if args.enable else None
        changed, disabled = write_setting(explicit)
        if changed:
            compile_settings(disabled)
        sync_hypridle(disabled)
    print("idle-inhibit: " + ("updated idle option" if changed else "addon already installed"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ApplyError as error:
        print(f"idle-inhibit: {error}; no settings changed", file=os.sys.stderr)
        raise SystemExit(1)
