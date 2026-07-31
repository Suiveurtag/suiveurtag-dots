#!/usr/bin/env python3

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


HOME = Path.home()
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")).expanduser()
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")).expanduser()
HYPR_BASE = Path(os.environ.get("HYPR_CONFIG_DIR", XDG_CONFIG_HOME / "hypr")).expanduser()
QS_DIR = Path(os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")).expanduser()
NETWORK_POPUP = Path(
    os.environ.get("DNS_MODE_TOGGLE_NETWORK_POPUP", QS_DIR / "network/NetworkPopup.qml")
).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/dns-mode-toggle"
BACKUP_DIR = ADDON_DIR / "backups"

ASSETS = {
    ADDON_DIR / "DnsModeToggle.qml": NETWORK_POPUP.parent / "DnsModeToggle.qml",
    ADDON_DIR / "dns_mode_toggle.sh": NETWORK_POPUP.parent / "dns_mode_toggle.sh",
}

IMPORT_BEGIN = "// BEGIN user-addon: dns-mode-toggle import"
IMPORT_END = "// END user-addon: dns-mode-toggle import"
WIDGET_BEGIN = "// BEGIN user-addon: dns-mode-toggle widget"
WIDGET_END = "// END user-addon: dns-mode-toggle widget"


class PatchError(RuntimeError):
    pass


def patch_network_popup(text: str) -> str:
    import_markers = [marker for marker in (IMPORT_BEGIN, IMPORT_END) if marker in text]
    if import_markers:
        if len(import_markers) != 2:
            raise PatchError("partial DNS toggle import detected")
    else:
        block = f'\n{IMPORT_BEGIN}\nimport "." as DnsModeComponents\n{IMPORT_END}'
        speedtest_import_end = "// END user-addon: speedtest import"
        if speedtest_import_end in text:
            insert_at = text.index(speedtest_import_end) + len(speedtest_import_end)
        else:
            imports = list(re.finditer(r"(?m)^import .+$", text))
            if not imports:
                raise PatchError("NetworkPopup import anchor not found")
            insert_at = imports[-1].end()
        text = text[:insert_at] + block + text[insert_at:]

    widget_markers = [marker for marker in (WIDGET_BEGIN, WIDGET_END) if marker in text]
    if widget_markers:
        if len(widget_markers) != 2:
            raise PatchError("partial DNS toggle widget detected")
        return text

    anchor = "            // BEGIN user-addon: speedtest button"
    if anchor not in text:
        anchor = "            Item {\n                id: powerToggleContainer"
    if anchor not in text:
        raise PatchError("network bottom-controls anchor not found")

    widget = f'''            {WIDGET_BEGIN}
            DnsModeComponents.DnsModeToggle {{
                id: dnsModeToggle
                rootWindow: window
                x: window.s(30)
                y: parent.height - window.s(30) - height
                z: 102
            }}
            {WIDGET_END}

'''
    return text.replace(anchor, widget + anchor, 1)


def validate_qml(path: Path) -> None:
    qmllint = shutil.which("qmllint")
    if not qmllint:
        raise PatchError("missing required command: qmllint")
    result = subprocess.run(
        [qmllint, "-I", str(QS_DIR), str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        details = (result.stdout + result.stderr).strip()
        raise PatchError(f"qmllint rejected {path.name}:\n{details}")


def backup(path: Path) -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{stamp}")


def install_assets() -> list[str]:
    changed = []
    for source, target in ASSETS.items():
        if not source.is_file():
            raise PatchError(f"addon asset not found: {source}")
        if source.suffix == ".qml":
            validate_qml(source)
        desired = source.read_bytes()
        if target.is_file() and target.read_bytes() == desired:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(f".{target.name}.dns-mode-toggle")
        shutil.copy2(source, temporary)
        if source.suffix == ".sh":
            os.chmod(temporary, 0o755)
        os.replace(temporary, target)
        changed.append(target.name)
    return changed


def patch_popup() -> bool:
    if not NETWORK_POPUP.is_file():
        raise PatchError(f"NetworkPopup not found: {NETWORK_POPUP}")
    original = NETWORK_POPUP.read_text(encoding="utf-8")
    patched = patch_network_popup(original)
    if patched == original:
        validate_qml(NETWORK_POPUP)
        return False

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{NETWORK_POPUP.name}.", dir=NETWORK_POPUP.parent, text=True
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(patched)
        os.chmod(temporary, NETWORK_POPUP.stat().st_mode)
        validate_qml(temporary)
        backup(NETWORK_POPUP)
        os.replace(temporary, NETWORK_POPUP)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return True


def reload_quickshell() -> None:
    if not SHELL_QML.is_file() or not shutil.which("qs"):
        return
    subprocess.run(
        ["qs", "-p", str(SHELL_QML), "ipc", "call", "main", "forceReload"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def main() -> int:
    for command in ("nmcli", "jq", "flock", "resolvectl"):
        if not shutil.which(command):
            raise PatchError(f"missing required command: {command}")

    changes = []
    assets = install_assets()
    if assets:
        changes.append("DNS assets")
    if patch_popup():
        changes.append("Wi-Fi panel")
    if changes:
        reload_quickshell()
        print("dns-mode-toggle: updated " + ", ".join(changes))
    else:
        print("dns-mode-toggle: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"dns-mode-toggle: {error}; no changes applied", file=os.sys.stderr)
        raise SystemExit(1)
