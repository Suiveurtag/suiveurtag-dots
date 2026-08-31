#!/usr/bin/env python3

from __future__ import annotations

import os
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
NETWORK_POPUP = QS_DIR / "network/NetworkPopup.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/wifi-hold-sound"
BACKUP_DIR = ADDON_DIR / "backups"

BEGIN = "// BEGIN user-addon: wifi-hold-sound"
END = "// END user-addon: wifi-hold-sound"
HOLD_BEGIN = "// BEGIN user-addon: wifi-hold-sound-hold-loop"
HOLD_END = "// END user-addon: wifi-hold-sound-hold-loop"


class PatchError(RuntimeError):
    pass


def validate_qml(path: Path) -> None:
    qmllint = shutil.which("qmllint")
    if not qmllint:
        raise PatchError("missing required command: qmllint")
    result = subprocess.run([qmllint, "-I", str(QS_DIR), str(path)], capture_output=True, text=True)
    if result.returncode:
        raise PatchError(f"qmllint rejected {path.name}:\n{(result.stdout + result.stderr).strip()}")


def patch_popup(text: str) -> str:
    if BEGIN in text or END in text:
        if BEGIN not in text or END not in text:
            raise PatchError("partial wifi-hold-sound marker detected")
    else:
        old = '                                if (window.expectedWifiPower === "on") Sounds.playSfx("network/power_on.wav"); else Sounds.playSfx("network/power_off.wav");'
        if old not in text:
            raise PatchError("Wi-Fi power sound anchor not found")
        replacement = f"                                {BEGIN}\n{old}\n                                {END}"
        text = text.replace(old, replacement, 1)

    if HOLD_BEGIN in text or HOLD_END in text:
        if HOLD_BEGIN not in text or HOLD_END not in text:
            raise PatchError("partial Wi-Fi hold sound marker detected")
        return text

    property_anchor = "                            property real disconnectFill: 0.0\n"
    if property_anchor not in text:
        raise PatchError("Wi-Fi hold state anchor not found")
    text = text.replace(
        property_anchor,
        property_anchor
        + f"                            {HOLD_BEGIN}\n"
        + "                            property int holdSoundHandle: -1\n"
        + f"                            {HOLD_END}\n",
        1,
    )
    pressed_anchor = "                                        coreDrainAnim.stop();\n                                        coreFillAnim.start();"
    pressed_replacement = (
        "                                        coreDrainAnim.stop();\n"
        "                                        if (typeof Sounds !== \"undefined\") {\n"
        "                                            if (centralCore.holdSoundHandle !== -1) Sounds.stopSfx(centralCore.holdSoundHandle);\n"
        "                                            centralCore.holdSoundHandle = Sounds.playUntilStopped(\"reusables/fillbutton/charge_loop.wav\", 0.6, false);\n"
        "                                        }\n"
        "                                        coreFillAnim.start();"
    )
    if pressed_anchor not in text:
        raise PatchError("Wi-Fi hold press anchor not found")
    text = text.replace(pressed_anchor, pressed_replacement, 1)
    released_anchor = "                                        coreFillAnim.stop();\n                                        coreDrainAnim.start();"
    released_replacement = (
        "                                        coreFillAnim.stop();\n"
        "                                        if (centralCore.holdSoundHandle !== -1 && typeof Sounds !== \"undefined\") {\n"
        "                                            Sounds.stopSfx(centralCore.holdSoundHandle);\n"
        "                                            centralCore.holdSoundHandle = -1;\n"
        "                                        }\n"
        "                                        coreDrainAnim.start();"
    )
    if released_anchor not in text:
        raise PatchError("Wi-Fi hold release anchor not found")
    return text.replace(released_anchor, released_replacement, 1)


def main() -> int:
    if not NETWORK_POPUP.is_file():
        raise PatchError(f"NetworkPopup not found: {NETWORK_POPUP}")
    original = NETWORK_POPUP.read_text(encoding="utf-8")
    patched = patch_popup(original)
    validate_qml(NETWORK_POPUP)
    if patched == original:
        print("wifi-hold-sound: addon already installed")
        return 0

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(NETWORK_POPUP, BACKUP_DIR / f"{NETWORK_POPUP.name}.{stamp}")
    fd, name = tempfile.mkstemp(prefix=f".{NETWORK_POPUP.name}.", dir=NETWORK_POPUP.parent, text=True)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(patched)
        os.chmod(temporary, NETWORK_POPUP.stat().st_mode)
        validate_qml(temporary)
        os.replace(temporary, NETWORK_POPUP)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise

    shell_qml = QS_DIR / "Shell.qml"
    if shell_qml.is_file() and shutil.which("qs"):
        subprocess.run(["qs", "-p", str(shell_qml), "ipc", "call", "main", "forceReload"], check=False)
    print("wifi-hold-sound: Wi-Fi hold sound persisted")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"wifi-hold-sound: {error}; no changes applied", file=os.sys.stderr)
        raise SystemExit(1)
