#!/usr/bin/env python3

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path


HOME = Path.home()
HYPR_BASE = Path(
    os.environ.get("HYPR_CONFIG_DIR", f"{os.environ.get('XDG_CONFIG_HOME', str(HOME / '.config'))}/hypr")
).expanduser()
ADDON_DIR = Path(
    os.environ.get("XDG_DATA_HOME", str(HOME / ".local/share"))
).expanduser() / "quickshell-addons/captive-portal"
QS_DIR = Path(
    os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")
).expanduser()
NETWORK_POPUP = QS_DIR / "network/NetworkPopup.qml"
NETWORK_DIR = NETWORK_POPUP.parent
BACKUP_DIR = ADDON_DIR / "backups"

STATE_BLOCK = """    // BEGIN user-addon: captive-portal state
    property string captivePortalState: "offline"
    property string captivePortalUrl: ""
    property string captivePortalHost: ""
    property string captivePortalMessage: ""
    readonly property bool captivePortalNeedsAttention: window.isWifiConn && (window.captivePortalState === "portal" || window.captivePortalState === "limited")
    readonly property color captivePortalAccent: Qt.lighter(window.peach, 1.08)

    function shellQuote(value) {
        let safe = String(value === undefined || value === null ? "" : value);
        return "'" + safe.replace(/'/g, "'\\\\''") + "'";
    }

    function triggerCaptivePortalPoll() {
        if (captivePortalPoller.running) return;
        captivePortalPoller.running = true;
    }

    function processCaptivePortalJson(textData) {
        if (textData === "") return;
        try {
            let data = JSON.parse(textData);
            window.captivePortalState = data.state || "unknown";
            window.captivePortalUrl = data.url || "";
            window.captivePortalHost = data.host || "";
            window.captivePortalMessage = data.message || "";
            if (window.activeMode === "wifi" && window.currentConn) window.updateInfoNodes();
        } catch(e) {}
    }

    Process {
        id: captivePortalPoller
        command: ["bash", window.scriptsDir + "/captive_portal_status.sh"]
        stdout: StdioCollector {
            onStreamFinished: processCaptivePortalJson(this.text.trim())
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: {
            if (window.isWifiConn && !captivePortalPoller.running) captivePortalPoller.running = true;
        }
    }
    // END user-addon: captive-portal state
"""

WIFI_INFO_BLOCK = """                    if (window.captivePortalNeedsAttention) {
                        let portalLabel = window.captivePortalHost !== "" ? window.captivePortalHost : "Captive Portal";
                        let portalUrl = window.captivePortalUrl !== "" ? window.captivePortalUrl : "http://neverssl.com/";
                        nodes.push({ id: "portal_state_" + i, name: portalLabel, icon: "󰖩", action: "Login Required", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                        nodes.push({ id: "portal_action_" + i, name: "Open Login Page", icon: "󰌌", action: "Connect to Internet", isInfoNode: true, isActionable: true, cmdStr: "bash " + window.shellQuote(window.scriptsDir + "/captive_portal_open.sh") + " " + window.shellQuote(portalUrl), parentIndex: -1 });
                    }
"""

WIFI_LIST_BLOCK = """            if (window.captivePortalNeedsAttention) {
                let portalUrl = window.captivePortalUrl !== "" ? window.captivePortalUrl : "http://neverssl.com/";
                newNetworks.push({
                    id: "action_portal",
                    ssid: "Captive Portal",
                    mac: "",
                    name: "Open Login Page",
                    icon: "󰖩",
                    security: "",
                    action: "Internet login required",
                    isInfoNode: false,
                    isActionable: true,
                    cmdStr: "bash " + window.shellQuote(window.scriptsDir + "/captive_portal_open.sh") + " " + window.shellQuote(portalUrl),
                    parentIndex: -1
                });
            }
"""

WIFI_TAB_BADGE = """                            Item {
                                visible: window.captivePortalNeedsAttention
                                implicitWidth: window.s(16)
                                implicitHeight: window.s(16)

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: window.s(10)
                                    height: window.s(10)
                                    radius: width / 2
                                    color: window.captivePortalAccent
                                }
                            }
"""


class PatchError(RuntimeError):
    pass


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def backup(path: Path) -> None:
    if not path.exists():
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{timestamp}")


def validate_qml(path: Path) -> None:
    qmllint = shutil.which("qmllint")
    if not qmllint:
        raise PatchError("qmllint is required but was not found")
    result = subprocess.run(
        [qmllint, "-I", str(QS_DIR), str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise PatchError((result.stdout + result.stderr).strip())


def install_assets() -> bool:
    changed = False
    NETWORK_DIR.mkdir(parents=True, exist_ok=True)
    for name in ("captive_portal_status.sh", "captive_portal_open.sh"):
        source = ADDON_DIR / name
        target = NETWORK_DIR / name
        if not source.is_file():
            raise PatchError(f"missing addon asset: {source}")
        if target.is_file() and target.read_bytes() == source.read_bytes():
            continue
        shutil.copy2(source, target)
        target.chmod(0o755)
        changed = True
    return changed


def patch_popup(text: str) -> str:
    if "BEGIN user-addon: captive-portal state" not in text:
        anchor_match = re.search(r'^    readonly property string scriptsDir: .*$', text, re.MULTILINE)
        if not anchor_match:
            raise PatchError("network scriptsDir anchor not found")
        anchor = anchor_match.group(0) + "\n"
        text = text.replace(anchor, anchor + "\n" + STATE_BLOCK, 1)

    if "portal_action_" not in text:
        wifi_info_match = re.search(
            r'(?m)^\s*if \(obj\.freq\) nodes\.push\(\{ id: "freq_" \+ i,.*$',
            text,
        )
        if not wifi_info_match:
            raise PatchError("wifi info anchor not found")
        insertion = wifi_info_match.end()
        text = text[:insertion] + "\n" + WIFI_INFO_BLOCK + text[insertion:]

    if 'id: "action_portal"' not in text:
        wifi_list_match = re.search(
            r'(?m)^\s*newNetworks\.push\(\{ id: "action_settings",.*$',
            text,
        )
        if not wifi_list_match:
            raise PatchError("wifi list action anchor not found")
        insertion = wifi_list_match.end()
        text = text[:insertion] + "\n" + WIFI_LIST_BLOCK + text[insertion:]

    handler_marker = "// user-addon: captive-portal connection poll"
    if handler_marker not in text:
        handler_anchor = "    onWifiConnectedChanged: {\n"
        if handler_anchor not in text:
            raise PatchError("onWifiConnectedChanged block not found")
        text = text.replace(
            handler_anchor,
            handler_anchor
            + "        // user-addon: captive-portal connection poll\n"
            + "        if (window.isWifiConn) triggerCaptivePortalPoll();\n",
            1,
        )

    return text


def main() -> int:
    if not NETWORK_POPUP.is_file():
        raise PatchError(f"active NetworkPopup not found: {NETWORK_POPUP}")

    original = NETWORK_POPUP.read_text(encoding="utf-8")
    patched = patch_popup(original)

    validate_qml(NETWORK_POPUP)
    assets_changed = install_assets()

    if patched != original:
        tmp_path = ADDON_DIR / ".NetworkPopup.qml.preview"
        atomic_write(tmp_path, patched)
        try:
            validate_qml(tmp_path)
        finally:
            tmp_path.unlink(missing_ok=True)
        backup(NETWORK_POPUP)
        atomic_write(NETWORK_POPUP, patched)

    status: list[str] = []
    if patched != original:
        status.append("popup")
    if assets_changed:
        status.append("scripts")
    print("captive-portal: updated " + ", ".join(status) if status else "captive-portal: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"captive-portal: {error}; no core file changed", file=sys.stderr)
        raise SystemExit(1)
