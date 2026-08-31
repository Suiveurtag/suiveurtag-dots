#!/usr/bin/env python3
"""Deploy the useful Suiveurtag addons on top of Serpantinum 2.x."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


HOME = Path.home()
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
SERPANTINUM_HOME = Path(
    os.environ.get("SERPANTINUM_HOME", XDG_DATA_HOME / "serpantinum")
)
QS_DIR = SERPANTINUM_HOME / "src/quickshell"
ADDONS_ROOT = XDG_DATA_HOME / "quickshell-addons"
HYPR_DIR = XDG_CONFIG_HOME / "hypr"
BACKUP_DIR = ADDONS_ROOT / "backups/serpantinum-v2"


class ApplyError(RuntimeError):
    pass


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        if path.exists():
            os.chmod(temporary, path.stat().st_mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def backup(path: Path) -> None:
    if not path.is_file():
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{stamp}")


def update(path: Path, transform) -> bool:
    if not path.is_file():
        raise ApplyError(f"required Serpantinum file not found: {path}")
    original = path.read_text(encoding="utf-8")
    patched = transform(original)
    if patched == original:
        return False
    backup(path)
    atomic_write(path, patched)
    return True


def add_before(text: str, anchor: str, block: str, marker: str) -> str:
    if marker in text:
        return text
    if anchor not in text:
        raise ApplyError(f"anchor not found for {marker}: {anchor!r}")
    return text.replace(anchor, block + anchor, 1)


def copy_file(source: Path, target: Path) -> bool:
    if not source.is_file():
        raise ApplyError(f"addon payload missing: {source}")
    if target.is_file() and target.read_bytes() == source.read_bytes():
        return False
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        backup(target)
    shutil.copy2(source, target)
    return True


def patch_registry(text: str) -> str:
    launcher_block = '''        // BEGIN user-addon: serpantinum-v2 launcher entries
        {
            id: "emoji",
            name: tr("widgets.emoji.name", "Emoji Picker"),
            description: tr("widgets.emoji.desc", "Search and copy emoji"),
            icon: "face-smile",
            fontIcon: "󰞅"
        },
        {
            id: "tor",
            name: tr("widgets.tor.name", "Tor Routing"),
            description: tr("widgets.tor.desc", "Route selected applications through Tor"),
            icon: "tor-browser",
            fontIcon: "󰖟"
        },
        // END user-addon: serpantinum-v2 launcher entries
'''
    if "BEGIN user-addon: serpantinum-v2 launcher entries" not in text:
        start = text.find("function getWidgetLauncherEntries")
        end = text.find("function getLayout", start)
        insertion = text.rfind("    ];", start, end)
        if start < 0 or end < 0 or insertion < 0:
            raise ApplyError("WindowRegistry launcher array not found")
        text = text[:insertion] + launcher_block + text[insertion:]

    text = text.replace(
        '        }\n        // BEGIN user-addon: serpantinum-v2 launcher entries',
        '        },\n        // BEGIN user-addon: serpantinum-v2 launcher entries',
        1,
    )

    layout_block = '''        // BEGIN user-addon: serpantinum-v2 layouts
        "emoji": {
            w: 900, h: 680, comp: "emoji/EmojiPicker.qml",
            pos: {
                "top": { anchor: "center" }, "bottom": { anchor: "center" },
                "left": { anchor: "center" }, "right": { anchor: "center" }
            }
        },
        "tor": {
            w: 980, h: 720, comp: "tor/TorPanel.qml",
            pos: {
                "top": { anchor: "center" }, "bottom": { anchor: "center" },
                "left": { anchor: "center" }, "right": { anchor: "center" }
            }
        },
        "legacysettings": {
            w: 500, h: "fill", comp: "settings/SettingsPopup.qml",
            pos: {
                "top": { anchor: "left" }, "bottom": { anchor: "left" },
                "left": { anchor: "left" }, "right": { anchor: "left" }
            }
        },
        // END user-addon: serpantinum-v2 layouts
'''
    text = add_before(
        text,
        '        "hidden": {',
        layout_block,
        "BEGIN user-addon: serpantinum-v2 layouts",
    )
    if '"legacysettings"' not in text:
        entry = '''        "legacysettings": {
            w: 500, h: "fill", comp: "settings/SettingsPopup.qml",
            pos: {
                "top": { anchor: "left" }, "bottom": { anchor: "left" },
                "left": { anchor: "left" }, "right": { anchor: "left" }
            }
        },
'''
        text = text.replace("        // END user-addon: serpantinum-v2 layouts\n", entry + "        // END user-addon: serpantinum-v2 layouts\n", 1)
    text = re.sub(
        r'("legacysettings"\s*:\s*\{\s*w:\s*)1200',
        r'\g<1>500',
        text,
        count=1,
    )
    return text


def patch_main(text: str) -> str:
    if '"legacysettings"' not in text and '"tor"' in text:
        text = text.replace('"emoji", "tor"]', '"emoji", "tor", "legacysettings"]', 1)
    if '"emoji", "tor"' in text:
        return text
    pattern = re.compile(r'(property var _allWidgetNames: \[[^\]]*)(\])')
    match = pattern.search(text)
    if not match:
        raise ApplyError("Main.qml widget preload list not found")
    return text[: match.start()] + match.group(1) + ', "emoji", "tor"' + match.group(2) + text[match.end() :]


def patch_floating(text: str) -> str:
    if '"actions/DrawingNotesAction.qml"' not in text:
        anchor = '"actions/DrawAction.qml"'
        if anchor not in text:
            raise ApplyError("Floating.qml DrawAction module not found")
        text = text.replace(anchor, '"actions/DrawingNotesAction.qml"', 1)
    if '"actions/AlarmAction.qml"' not in text:
        anchor = '                "actions/Timer.qml",\n'
        if anchor not in text:
            raise ApplyError("Floating.qml Timer module not found")
        text = text.replace(anchor, anchor + '                "actions/AlarmAction.qml",\n', 1)
    return text


def patch_network_compat(text: str) -> str:
    duplicate = '''    // BEGIN user-addon: serpantinum-v2 network compatibility
    readonly property string scriptsDir: Caching.qsDir + "/network"
'''
    text = text.replace(
        duplicate,
        "    // BEGIN user-addon: serpantinum-v2 network compatibility\n",
        1,
    )
    if "BEGIN user-addon: serpantinum-v2 network compatibility" in text:
        return text
    block = '''
    // BEGIN user-addon: serpantinum-v2 network compatibility
    readonly property color base: ThemeBackend.base
    readonly property color mantle: ThemeBackend.mantle
    readonly property color crust: ThemeBackend.crust
    readonly property color text: ThemeBackend.text
    readonly property color subtext0: ThemeBackend.subtext0
    readonly property color surface0: ThemeBackend.surface0
    readonly property color surface1: ThemeBackend.surface1
    readonly property color surface2: ThemeBackend.surface2
    readonly property color sapphire: ThemeBackend.sapphire
    readonly property color blue: ThemeBackend.blue
    readonly property color mauve: ThemeBackend.mauve
    readonly property color pink: ThemeBackend.pink
    readonly property color peach: ThemeBackend.peach
    // END user-addon: serpantinum-v2 network compatibility
'''
    anchor = "Item {\n    id: window\n"
    if anchor not in text:
        raise ApplyError("NetworkPopup root item not found")
    return text.replace(anchor, anchor + block, 1)


def patch_wallpaper(text: str) -> str:
    import_block = '''// BEGIN user-addon: wallpaper-random import
import "." as WallpaperRandom
// END user-addon: wallpaper-random import

'''
    text = add_before(
        text,
        "Item {\n    id: window",
        import_block,
        "BEGIN user-addon: wallpaper-random import",
    )
    function_block = '''    // BEGIN user-addon: serpantinum-v2 random wallpaper
    function applyRandomWallpaper() {
        let modelRef = window.activeModel;
        if (!modelRef || modelRef.count <= 0 || window.isApplying) return;
        let next = Math.floor(Math.random() * modelRef.count);
        if (modelRef.count > 1 && next === view.currentIndex) next = (next + 1) % modelRef.count;
        let item = modelRef.get(next);
        if (!item || !item.fileName) return;
        view.currentIndex = next;
        window.applyWallpaper(String(item.fileName), !!item.isVideo);
    }
    // END user-addon: serpantinum-v2 random wallpaper

'''
    text = add_before(
        text,
        "    function getOriginalFileName(safeFileName) {",
        function_block,
        "BEGIN user-addon: serpantinum-v2 random wallpaper",
    )
    button_block = '''            // BEGIN user-addon: serpantinum-v2 random wallpaper button
            WallpaperRandom.RandomWallpaperButton {
                uiScale: window.s(1)
                active: false
                available: window.activeModel && window.activeModel.count > 0 && !window.isApplying
                textColor: ThemeBackend.text
                surface1Color: ThemeBackend.surface1
                surface2Color: ThemeBackend.surface2
                onTriggered: window.applyRandomWallpaper()
            }
            // END user-addon: serpantinum-v2 random wallpaper button

'''
    button_pattern = re.compile(
        r"            // BEGIN user-addon: serpantinum-v2 random wallpaper button\n"
        r".*?"
        r"            // END user-addon: serpantinum-v2 random wallpaper button\n",
        re.DOTALL,
    )
    if button_pattern.search(text):
        return button_pattern.sub(button_block, text, count=1)
    return add_before(
        text,
        "            Item {\n                id: searchControlContainer",
        button_block,
        "BEGIN user-addon: serpantinum-v2 random wallpaper button",
    )


def patch_guide(text: str) -> str:
    if "BEGIN user-addon: serpantinum-v2 legacy settings tabs" in text:
        return text
    start = text.index("    property var tabsModel: [")
    end = text.index("\n    ]", start) + len("\n    ]")
    tabs = '''    // BEGIN user-addon: serpantinum-v2 legacy settings tabs
    property var tabsModel: [
        { id: "Addons", key: "addons", name: "Addons", icon: "󰐱", file: "LegacyAddonsTab.qml" },
        { id: "Keybinds", key: "keybinds", name: "Keybinds", icon: "󰌌", file: "LegacyKeybindsTab.qml" },
        { id: "Monitors", key: "monitors", name: "Monitors", icon: "󰍹", file: "DisplayTab.qml" }
    ]
    // END user-addon: serpantinum-v2 legacy settings tabs'''
    return text[:start] + tabs + text[end:]


def patch_shell(text: str) -> str:
    # The old panel must live in Main's widget stack so its left edge is
    # included in Main.qml's topBarHole calculation, like the battery panel.
    legacy_block = re.compile(
        r'\n    Loader \{\n        id: legacySettingsLoader.*?\n    \}\n\n    IpcHandler \{\n        target: "legacysettings".*?\n    \}\n',
        re.DOTALL,
    )
    return legacy_block.sub("\n", text, count=1)


def patch_launcher(text: str) -> str:
    web_function = '''    // BEGIN user-addon: serpantinum-v2 web search
    function searchWeb(query) {
        let trimmed = String(query || "").trim();
        if (trimmed.length === 0) return;
        Quickshell.execDetached(["zen-browser", "https://www.google.com/search?q=" + encodeURIComponent(trimmed)]);
        closeLauncher();
    }
    // END user-addon: serpantinum-v2 web search

'''
    text = add_before(
        text,
        "    function activateIndex(index) {",
        web_function,
        "BEGIN user-addon: serpantinum-v2 web search",
    )

    tab_block = '''                    // BEGIN user-addon: serpantinum-v2 web search key
                    Keys.onTabPressed: function(event) {
                        launcherWindow.searchWeb(searchInput.text);
                        event.accepted = true;
                    }
                    // END user-addon: serpantinum-v2 web search key
'''
    if "BEGIN user-addon: serpantinum-v2 web search key" not in text:
        escape_anchor = "                    Keys.onEscapePressed: function(event) {"
        text = add_before(text, escape_anchor, tab_block, "serpantinum-v2 web search key")

    if "user-addon: serpantinum-v2 tor routing" not in text:
        pattern = re.compile(
            r"    function launchApp\(appName, desktopId\) \{.*?^    \}",
            re.MULTILINE | re.DOTALL,
        )
        match = pattern.search(text)
        if not match:
            raise ApplyError("Launcher launchApp function not found")
        replacement = '''    function launchApp(appName, desktopId) {
        // user-addon: serpantinum-v2 tor routing
        let dataHome = Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share");
        let managerPath = dataHome + "/quickshell-addons/tor-panel/tor_panelctl.py";
        Quickshell.execDetached(["python3", managerPath, "launch", "--desktop-id", desktopId]);
        if (Caching.qsDir) {
            Quickshell.execDetached(["python3", Caching.qsDir + "/launcher/app_rank.py", "--log-launch", "--name", appName]);
        }
        closeLauncher();
    }'''
        text = text[: match.start()] + replacement + text[match.end() :]
    return text


def patch_keybinds(text: str) -> str:
    block = '''
-- BEGIN user-addon: serpantinum-v2 keybinds
hl.bind(mainMod .. " + J", hl.dsp.exec_cmd("serpantinum msg toggle emoji"))
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("serpantinum msg toggle tor"))
hl.bind(mainMod .. " + ALT + Z", hl.dsp.exec_cmd("~/.local/share/quickshell-addons/zoomit/zoomit.py zoom-toggle"))
hl.bind(mainMod .. " + ALT + D", hl.dsp.exec_cmd("~/.local/share/quickshell-addons/zoomit/zoomit.py draw-toggle"))
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("serpantinum ipc call legacysettings toggle"))
-- END user-addon: serpantinum-v2 keybinds
'''
    if "BEGIN user-addon: serpantinum-v2 keybinds" in text:
        text = text.replace(
            'hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("serpantinum ipc call legacysettings toggle"))',
            'hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("serpantinum msg toggle legacysettings"))',
            1,
        )
        if "serpantinum msg toggle legacysettings" not in text:
            text = text.replace(
                "-- END user-addon: serpantinum-v2 keybinds",
                'hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("serpantinum msg toggle legacysettings"))\n'
                "-- END user-addon: serpantinum-v2 keybinds",
                1,
            )
        text = text.replace(
            'hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("serpantinum msg toggle legacysettings"))',
            'hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("serpantinum msg toggle legacysettings"))',
        )
        text = text.replace(
            'hl.bind(mainMod .. " + H", hl.dsp.exec_cmd("serpantinum msg toggle guide"))',
            'hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("serpantinum msg toggle guide"))',
        )
        return text
    anchor = 'local terminal = _G.terminal or "kitty"\n'
    if anchor not in text:
        raise ApplyError("Hyprland Lua keybind anchor not found")
    return text.replace(anchor, anchor + block, 1)


def patch_bar(text: str) -> str:
    text = text.replace(
        '            property bool isNotifOpen: activeWidget === "notifications"\n            property bool isSysOpen: activeWidget === "system"',
        '            property bool isNotifOpen: activeWidget === "notifications"\n            property bool isLeftOpen: activeWidget === "legacysettings"\n            property bool isSysOpen: activeWidget === "system"',
        1,
    )
    text = text.replace(
        'if (!barWindow.isNotifOpen && !barWindow.isSysOpen && barWindow.pendingReload)',
        'if (!barWindow.isNotifOpen && !barWindow.isLeftOpen && !barWindow.isSysOpen && barWindow.pendingReload)',
        1,
    )
    return text


def run_legacy_compatible(addon: str, extra_env: dict[str, str]) -> None:
    script = ADDONS_ROOT / addon / "apply.py"
    environment = os.environ.copy()
    environment.update(
        {
            "XDG_DATA_HOME": str(XDG_DATA_HOME),
            "XDG_CONFIG_HOME": str(XDG_CONFIG_HOME),
            "HYPR_QUICKSHELL_DIR": str(QS_DIR),
            **extra_env,
        }
    )
    result = subprocess.run(
        ["python3", str(script)],
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise ApplyError((result.stdout + result.stderr).strip())
    if result.stdout.strip():
        print(result.stdout.strip())


def main() -> int:
    if not (QS_DIR / "Shell.qml").is_file():
        raise ApplyError(f"Serpantinum 2 shell not found under {QS_DIR}")

    changed: list[str] = []
    copies = {
        ADDONS_ROOT / "emoji-picker/EmojiPicker.qml": QS_DIR / "emoji/EmojiPicker.qml",
        ADDONS_ROOT / "emoji-picker/emojis.json": QS_DIR / "emoji/emojis.json",
        ADDONS_ROOT / "tor-panel/TorPanel.qml": QS_DIR / "tor/TorPanel.qml",
        ADDONS_ROOT / "drawing-notes/DrawingNotesAction.qml": QS_DIR / "quickactions/actions/DrawingNotesAction.qml",
        ADDONS_ROOT / "custom-alarm-clock/AlarmAction.qml": QS_DIR / "quickactions/actions/AlarmAction.qml",
        ADDONS_ROOT / "serpantinum-settings/SettingsPopup.qml": QS_DIR / "settings/SettingsPopup.qml",
        ADDONS_ROOT / "serpantinum-settings/SettingsWindow.qml": QS_DIR / "settings/SettingsWindow.qml",
        ADDONS_ROOT / "serpantinum-settings/Config.qml": QS_DIR / "singletons/Config.qml",
        ADDONS_ROOT / "serpantinum-settings/keybinds_v2.py": ADDONS_ROOT / "serpantinum-settings/keybinds_v2.py",
        ADDONS_ROOT / "music-preview-rounded/AddonSettingsPage.qml": QS_DIR / "settings/AddonSettingsPage.qml",
        ADDONS_ROOT / "matugen-vibrant/VibrantMatugenCard.qml": QS_DIR / "settings/VibrantMatugenCard.qml",
        ADDONS_ROOT / "screenshot-freeze/ScreenshotFreezeCard.qml": QS_DIR / "settings/ScreenshotFreezeCard.qml",
        ADDONS_ROOT / "music-preview-rounded/MusicVisualizerCard.qml": QS_DIR / "settings/MusicVisualizerCard.qml",
        ADDONS_ROOT / "idle-inhibit/IdleInhibitCard.qml": QS_DIR / "settings/IdleInhibitCard.qml",
        ADDONS_ROOT / "wallpaper-random/RandomWallpaperButton.qml": QS_DIR / "wallpaper/RandomWallpaperButton.qml",
        ADDONS_ROOT / "wallpaper-random/random.svg": QS_DIR / "wallpaper/random.svg",
        ADDONS_ROOT / "calendar-legacy/CalendarPopup.qml": QS_DIR / "calendar/CalendarPopup.qml",
    }
    alarm_source = ADDONS_ROOT / "custom-alarm-clock"
    for source in alarm_source.iterdir():
        if source.is_file() and source.name not in {"AlarmAction.qml", "OneUiClock.qml", "apply.py", "apply.sh"}:
            copies[source] = QS_DIR / "quickactions/actions/alarm" / source.name
    for source, target in copies.items():
        if copy_file(source, target):
            changed.append(str(target))

    targets = (
        (QS_DIR / "WindowRegistry.js", patch_registry),
        (QS_DIR / "Main.qml", patch_main),
        (QS_DIR / "launcher/Launcher.qml", patch_launcher),
        (QS_DIR / "quickactions/Floating.qml", patch_floating),
        (QS_DIR / "network/NetworkPopup.qml", patch_network_compat),
        (QS_DIR / "wallpaper/WallpaperPicker.qml", patch_wallpaper),
        (QS_DIR / "Shell.qml", patch_shell),
        (QS_DIR / "bar/Bar.qml", patch_bar),
        (HYPR_DIR / "config/keybinds.lua", patch_keybinds),
    )
    for path, transform in targets:
        if update(path, transform):
            changed.append(str(path))

    run_legacy_compatible(
        "headset-mic-loopback",
        {"HEADSET_MIC_VOLUME_POPUP": str(QS_DIR / "volume/VolumePopup.qml")},
    )
    run_legacy_compatible(
        "dns-mode-toggle",
        {"DNS_MODE_TOGGLE_NETWORK_POPUP": str(QS_DIR / "network/NetworkPopup.qml")},
    )
    run_legacy_compatible("wifi-hold-sound", {})
    run_legacy_compatible("captive-portal", {})
    run_legacy_compatible("speedtest", {})

    if changed:
        print(f"serpantinum-v2: updated {len(changed)} core/assets file(s)")
    else:
        print("serpantinum-v2: core integration already current")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ApplyError as error:
        print(f"serpantinum-v2: {error}", file=os.sys.stderr)
        raise SystemExit(1)
