#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave
from datetime import datetime
from pathlib import Path


HOME = Path.home()
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")).expanduser()
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")).expanduser()
XDG_STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")).expanduser()
HYPR_BASE = Path(os.environ.get("HYPR_CONFIG_DIR", XDG_CONFIG_HOME / "hypr")).expanduser()
QS_DIR = Path(
    os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")
).expanduser()
TIMER_QML = Path(
    os.environ.get("CUSTOM_ALARM_TIMER_QML", QS_DIR / "quickactions/Timer.qml")
).expanduser()
SHELL_QML = QS_DIR / "Shell.qml"
ADDON_DIR = XDG_DATA_HOME / "quickshell-addons/custom-alarm-clock"
LIVE_MODULE = QS_DIR / "alarm-system"
BACKUP_DIR = ADDON_DIR / "backups"
SETTINGS_PATH = XDG_STATE_HOME / "quickshell/custom-alarm-clock/settings.json"

MODULE_FILES = (
    "AlarmManager.qml",
    "AlarmView.qml",
    "ClockDial.qml",
    "LiquidBackground.qml",
    "OneUiClock.qml",
    "RingingOverlay.qml",
    "SoundSettings.qml",
    "qmldir",
)

DEFAULT_SETTINGS = {
    "version": 1,
    "sounds": {
        mode: {"source": "", "volume": 85}
        for mode in ("timer", "stopwatch", "pomodoro", "alarm")
    },
    "stopwatchTargetMs": 5 * 60 * 1000,
    "stopwatchEnabled": False,
    "alarms": [],
}

IMPORT_BEGIN = "// BEGIN user-addon: custom-alarm-clock import"
IMPORT_END = "// END user-addon: custom-alarm-clock import"
STATE_BEGIN = "// BEGIN user-addon: custom-alarm-clock stopwatch-state"
STATE_END = "// END user-addon: custom-alarm-clock stopwatch-state"
API_BEGIN = "// BEGIN user-addon: custom-alarm-clock api"
API_END = "// END user-addon: custom-alarm-clock api"
TOGGLE_GUARD_BEGIN = "// BEGIN user-addon: custom-alarm-clock toggle-guard"
TOGGLE_GUARD_END = "// END user-addon: custom-alarm-clock toggle-guard"
TOGGLE_BEGIN = "// BEGIN user-addon: custom-alarm-clock alarm-toggle"
TOGGLE_END = "// END user-addon: custom-alarm-clock alarm-toggle"
SHORTCUT_BEGIN = "// BEGIN user-addon: custom-alarm-clock modal-shortcut"
SHORTCUT_END = "// END user-addon: custom-alarm-clock modal-shortcut"
TIMER_RING_BEGIN = "// BEGIN user-addon: custom-alarm-clock timer-ring"
TIMER_RING_END = "// END user-addon: custom-alarm-clock timer-ring"
STOPWATCH_RING_BEGIN = "// BEGIN user-addon: custom-alarm-clock stopwatch-ring"
STOPWATCH_RING_END = "// END user-addon: custom-alarm-clock stopwatch-ring"
STOPWATCH_RESET_BEGIN = "// BEGIN user-addon: custom-alarm-clock stopwatch-reset"
STOPWATCH_RESET_END = "// END user-addon: custom-alarm-clock stopwatch-reset"
POMODORO_RING_BEGIN = "// BEGIN user-addon: custom-alarm-clock pomodoro-ring"
POMODORO_RING_END = "// END user-addon: custom-alarm-clock pomodoro-ring"
CONTROLS_BEGIN = "// BEGIN user-addon: custom-alarm-clock controls"
CONTROLS_END = "// END user-addon: custom-alarm-clock controls"
STOPWATCH_STATUS_BEGIN = "// BEGIN user-addon: custom-alarm-clock stopwatch-status"
STOPWATCH_STATUS_END = "// END user-addon: custom-alarm-clock stopwatch-status"
ALARM_VIEW_BEGIN = "// BEGIN user-addon: custom-alarm-clock alarm-view"
ALARM_VIEW_END = "// END user-addon: custom-alarm-clock alarm-view"


class ApplyError(RuntimeError):
    pass


def marker_block(begin: str, end: str, body: str, indent: str = "") -> str:
    lines = [f"{indent}{begin}"]
    lines.extend(f"{indent}{line}" if line else "" for line in body.splitlines())
    lines.append(f"{indent}{end}")
    return "\n".join(lines) + "\n"


def strip_marker_block(text: str, begin: str, end: str) -> str:
    pattern = (
        rf"(?m)^[ \t]*{re.escape(begin)}\n"
        rf".*?"
        rf"^[ \t]*{re.escape(end)}\n?"
    )
    return re.sub(pattern, "", text, flags=re.DOTALL)


def find_matching_brace(text: str, opening: int) -> int:
    depth = 0
    quote = ""
    escaped = False
    line_comment = False
    block_comment = False
    index = opening
    while index < len(text):
        character = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if character == "\n":
                line_comment = False
            index += 1
            continue
        if block_comment:
            if character == "*" and following == "/":
                block_comment = False
                index += 2
            else:
                index += 1
            continue
        if quote:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = ""
            index += 1
            continue
        if character == "/" and following == "/":
            line_comment = True
            index += 2
            continue
        if character == "/" and following == "*":
            block_comment = True
            index += 2
            continue
        if character in ('"', "'", "`"):
            quote = character
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise ApplyError("unterminated QML block")


def find_function(text: str, name: str) -> tuple[int, int]:
    match = re.search(rf"(?m)^[ \t]*function\s+{re.escape(name)}\s*\([^)]*\)\s*\{{", text)
    if not match:
        raise ApplyError(f"{name} function anchor not found")
    opening = text.find("{", match.start())
    return opening, find_matching_brace(text, opening)


def insert_after_line(text: str, pattern: str, block: str, description: str, count: int = 1) -> str:
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    if len(matches) < count:
        raise ApplyError(f"{description} anchor not found")
    match = matches[count - 1]
    line_end = text.find("\n", match.end())
    if line_end < 0:
        line_end = len(text)
    return text[: line_end + 1] + block + text[line_end + 1 :]


def insert_before_line(text: str, pattern: str, block: str, description: str, count: int = 1) -> str:
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    if len(matches) < count:
        raise ApplyError(f"{description} anchor not found")
    return text[: matches[count - 1].start()] + block + text[matches[count - 1].start() :]


def patch_timer(text: str) -> str:
    marker_pairs = (
        (IMPORT_BEGIN, IMPORT_END),
        (STATE_BEGIN, STATE_END),
        (API_BEGIN, API_END),
        (TOGGLE_GUARD_BEGIN, TOGGLE_GUARD_END),
        (TOGGLE_BEGIN, TOGGLE_END),
        (SHORTCUT_BEGIN, SHORTCUT_END),
        (TIMER_RING_BEGIN, TIMER_RING_END),
        (STOPWATCH_RING_BEGIN, STOPWATCH_RING_END),
        (STOPWATCH_RESET_BEGIN, STOPWATCH_RESET_END),
        (POMODORO_RING_BEGIN, POMODORO_RING_END),
        (CONTROLS_BEGIN, CONTROLS_END),
        (STOPWATCH_STATUS_BEGIN, STOPWATCH_STATUS_END),
        (ALARM_VIEW_BEGIN, ALARM_VIEW_END),
    )
    for begin, end in marker_pairs:
        text = strip_marker_block(text, begin, end)

    import_block = marker_block(
        IMPORT_BEGIN,
        IMPORT_END,
        'import "../alarm-system" as AlarmSystem',
    )
    text = insert_after_line(
        text,
        r"^import Quickshell\.Io\s*$",
        import_block,
        "Quickshell.Io import",
    )

    state_block = marker_block(
        STATE_BEGIN,
        STATE_END,
        "property bool swAlarmTriggered: false",
        "        ",
    )
    text = insert_after_line(
        text,
        r"^[ \t]*property int swAccumulatedMs:\s*0\s*$",
        state_block,
        "stopwatch state",
    )

    api_body = """property var modeLabels: ["Timer", "Stopwatch", "Pomodoro", "Alarm"]
property alias alarmActiveMode: stateCache.activeMode
property alias clockTimerRemainingMs: stateCache.timerRemainingMs
property alias clockTimerPresetMs: stateCache.timerPresetMs
property alias clockStopwatchMs: stopwatchView.currentDisplayMs
property alias clockPomodoroRemainingMs: stateCache.pomoRemainingMs
property alias clockPomodoroState: stateCache.pomoState
property alias clockPomodoroSessions: stateCache.pomoSessionsCount
property alias clockPomodoroTargetSessions: stateCache.pomoTargetSessions
property alias clockPomodoroWorkLimit: stateCache.pomoWorkLimit
property alias clockPomodoroShortLimit: stateCache.pomoShortBreakLimit
property alias clockPomodoroLongLimit: stateCache.pomoLongBreakLimit
readonly property bool clockTimerRunning: stateCache.timerTargetEpoch > 0
readonly property bool clockTimerIdle: !clockTimerRunning
    && stateCache.timerRemainingMs === stateCache.timerPresetMs
readonly property bool clockStopwatchRunning: stateCache.swStartEpoch > 0
readonly property bool clockPomodoroRunning: stateCache.pomoTargetEpoch > 0
readonly property var clockLapData: root.swLapData

function activeModeKey() {
    if (stateCache.activeMode === 1) return "stopwatch";
    if (stateCache.activeMode === 2) return "pomodoro";
    if (stateCache.activeMode === 3) return "alarm";
    return "timer";
}

function alarmModalOpen() {
    return alarmSoundSettings.visible
        || AlarmSystem.AlarmManager.isRinging
        || oneUiClock.alarmEditorOpen;
}

function openAlarmSoundSettings() {
    alarmSoundSettings.openFor(activeModeKey());
}

function clockSetMode(mode) {
    stateCache.activeMode = Math.max(0, Math.min(3, Number(mode)));
}

function clockToggle() {
    root.toggleActiveTabState();
}

function clockSetTimerPreset(milliseconds) {
    const value = Math.max(0, Math.min(99 * 3600000 + 59 * 60000 + 59000, Math.round(milliseconds)));
    stateCache.timerTargetEpoch = 0;
    stateCache.timerPresetMs = value;
    stateCache.timerRemainingMs = value;
}

function clockAdjustTimerSegment(segment, direction) {
    let hours = Math.floor(stateCache.timerPresetMs / 3600000);
    let minutes = Math.floor((stateCache.timerPresetMs % 3600000) / 60000);
    let seconds = Math.floor((stateCache.timerPresetMs % 60000) / 1000);
    if (segment === 0) {
        hours = (hours + direction + 100) % 100;
    } else if (segment === 1) {
        minutes = (minutes + direction + 60) % 60;
    } else {
        seconds = (seconds + direction + 60) % 60;
    }
    clockSetTimerPreset((hours * 3600 + minutes * 60 + seconds) * 1000);
}

function clockResetTimer() {
    stateCache.timerTargetEpoch = 0;
    stateCache.timerRemainingMs = stateCache.timerPresetMs;
}

function clockStopwatchSecondary() {
    if (stateCache.swStartEpoch > 0) {
        const nowMs = stopwatchView.currentDisplayMs;
        const lastMs = root.swLapData.length > 0
            ? root.swLapData[root.swLapData.length - 1].total
            : 0;
        const updated = root.swLapData.slice();
        updated.push({ total: nowMs, diff: nowMs - lastMs });
        root.swLapData = updated;
        return;
    }
    stateCache.swStartEpoch = 0;
    stateCache.swAccumulatedMs = 0;
    stateCache.swAlarmTriggered = false;
    root.swLapData = [];
    stopwatchView.currentDisplayMs = 0;
}

function clockSkipPomodoro() {
    stateCache.pomoTargetEpoch = 0;
    const phase = stateCache.pomoState;
    root.notify(
        "Pomodoro Skipped",
        phase === 0
            ? "Focus session skipped. Moving to break."
            : "Break skipped. Moving back to focus.",
        "media-skip-forward"
    );
    pomodoroView.handleSessionComplete();
}

function clockAdjustPomodoro(target, delta, minimum, maximum) {
    const next = Math.max(minimum, Math.min(maximum, Number(stateCache[target]) + delta));
    stateCache[target] = next;
    if (target === "pomoTargetSessions")
        stateCache.pomoSessionsCount = Math.min(stateCache.pomoSessionsCount, next - 1);
    if (stateCache.pomoTargetEpoch > 0)
        return;
    if (target === "pomoWorkLimit" && stateCache.pomoState === 0)
        stateCache.pomoRemainingMs = next * 60000;
    else if (target === "pomoShortBreakLimit" && stateCache.pomoState === 1)
        stateCache.pomoRemainingMs = next * 60000;
    else if (target === "pomoLongBreakLimit" && stateCache.pomoState === 2)
        stateCache.pomoRemainingMs = next * 60000;
}"""
    api_block = marker_block(API_BEGIN, API_END, api_body, "    ")
    _, notify_closing = find_function(text, "notify")
    api_suffix = text[notify_closing + 1 :].lstrip("\n")
    text = (
        text[: notify_closing + 1]
        + "\n\n"
        + api_block.rstrip("\n")
        + "\n\n"
        + api_suffix
    )

    toggle_guard_block = marker_block(
        TOGGLE_GUARD_BEGIN,
        TOGGLE_GUARD_END,
        "if (alarmSoundSettings.visible || AlarmSystem.AlarmManager.isRinging) return;",
        "        ",
    )
    text = insert_after_line(
        text,
        r"^[ \t]*if \(!root\.isActiveTab\) return;\s*$",
        toggle_guard_block,
        "active-tab toggle guard",
    )

    _, toggle_closing = find_function(text, "toggleActiveTabState")
    toggle_block = marker_block(
        TOGGLE_BEGIN,
        TOGGLE_END,
        """else if (stateCache.activeMode === 3) {
    oneUiClock.commitAlarmEditor();
}""",
        "        ",
    )
    toggle_line_start = text.rfind("\n", 0, toggle_closing) + 1
    text = text[:toggle_line_start] + toggle_block + text[toggle_line_start:]

    intercepted_match = re.search(r"(?m)^[ \t]*property var interceptedShortcuts:\s*\{", text)
    if not intercepted_match:
        raise ApplyError("interceptedShortcuts anchor not found")
    intercepted_opening = text.find("{", intercepted_match.start())
    intercepted_closing = find_matching_brace(text, intercepted_opening)
    shortcut_region = text[intercepted_opening:intercepted_closing]
    return_match = re.search(r"(?m)^(?P<indent>[ \t]*)return arr;\s*$", shortcut_region)
    if not return_match:
        raise ApplyError("interceptedShortcuts return anchor not found")
    return_absolute = intercepted_opening + return_match.start()
    shortcut_block = marker_block(
        SHORTCUT_BEGIN,
        SHORTCUT_END,
        'if (root.alarmModalOpen()) arr.push("Escape");',
        return_match.group("indent"),
    )
    text = text[:return_absolute] + shortcut_block + text[return_absolute:]

    timer_ring_block = marker_block(
        TIMER_RING_BEGIN,
        TIMER_RING_END,
        """AlarmSystem.AlarmManager.ring(
    "timer",
    "Timer Finished",
    "Your timer for " + root.formatTime(stateCache.timerPresetMs, false) + " has completed."
);""",
        "                        ",
    )
    text = insert_after_line(
        text,
        r'^[ \t]*root\.notify\("Timer Finished".*$',
        timer_ring_block,
        "timer completion notification",
    )

    stopwatch_ring_body = """if (AlarmSystem.AlarmManager.stopwatchEnabled
        && !stateCache.swAlarmTriggered
        && stopwatchView.currentDisplayMs >= AlarmSystem.AlarmManager.stopwatchTargetMs) {
    stateCache.swAlarmTriggered = true;
    AlarmSystem.AlarmManager.ring(
        "stopwatch",
        "Stopwatch Target",
        "Reached " + root.formatTime(AlarmSystem.AlarmManager.stopwatchTargetMs, false) + "."
    );
}"""
    stopwatch_ring_block = marker_block(
        STOPWATCH_RING_BEGIN,
        STOPWATCH_RING_END,
        stopwatch_ring_body,
        "                ",
    )
    text = insert_before_line(
        text,
        r"^[ \t]*// Pomodoro\s*$",
        stopwatch_ring_block,
        "global ticker Pomodoro section",
    )

    pomodoro_ring_body = """AlarmSystem.AlarmManager.ring(
    "pomodoro",
    phase === 0 ? "Focus Complete" : "Break Over",
    phase === 0
        ? "Time to take a well-deserved break."
        : "Break time is up. Let's get back to focus!"
);"""
    pomodoro_ring_block = marker_block(
        POMODORO_RING_BEGIN,
        POMODORO_RING_END,
        pomodoro_ring_body,
        "                        ",
    )
    text = insert_before_line(
        text,
        r"^[ \t]*pomodoroView\.handleSessionComplete\(\);\s*$",
        pomodoro_ring_block,
        "Pomodoro completion handler",
        count=1,
    )

    reset_block = marker_block(
        STOPWATCH_RESET_BEGIN,
        STOPWATCH_RESET_END,
        "stateCache.swAlarmTriggered = false;",
        "                                    ",
    )
    text = insert_after_line(
        text,
        r"^[ \t]*stopwatchView\.currentDisplayMs = 0;\s*$",
        reset_block,
        "stopwatch reset",
    )

    text, replacement_count = re.subn(
        r"property int activeMode:\s*0\s*//\s*0: Timer, 1: Stopwatch, 2: Pomodoro(?:, 3: Alarm)?",
        "property int activeMode: 0 // 0: Timer, 1: Stopwatch, 2: Pomodoro, 3: Alarm",
        text,
        count=1,
    )
    if replacement_count != 1:
        raise ApplyError("active mode declaration anchor not found")

    text, replacement_count = re.subn(
        r"property real stepSize:\s*\(parent\.width - root\.s\(4\)\) / (?:3|root\.modeLabels\.length)",
        "property real stepSize: (parent.width - root.s(4)) / root.modeLabels.length",
        text,
        count=1,
    )
    if replacement_count != 1:
        raise ApplyError("tab highlight width anchor not found")

    text, replacement_count = re.subn(
        r'model:\s*(?:\["Timer", "Stopwatch", "Pomodoro"\]|root\.modeLabels)',
        "model: root.modeLabels",
        text,
        count=1,
    )
    if replacement_count != 1:
        raise ApplyError("tab model anchor not found")

    text, replacement_count = re.subn(
        r"width:\s*\(tabBar\.width - root\.s\(4\)\) / (?:3|root\.modeLabels\.length)",
        "width: (tabBar.width - root.s(4)) / root.modeLabels.length",
        text,
        count=1,
    )
    if replacement_count != 1:
        raise ApplyError("tab delegate width anchor not found")

    tab_match = re.search(
        r"(?ms)(Rectangle\s*\{\s*\n[ \t]*id:\s*tabBar\b.*?^[ \t]*)width:\s*root\.s\((?:280|300)\)",
        text,
    )
    if not tab_match:
        raise ApplyError("tab bar width anchor not found")
    width_start, width_end = tab_match.span()
    matched = tab_match.group(0)
    matched = re.sub(r"width:\s*root\.s\((?:280|300)\)", "width: root.s(300)", matched, count=1)
    text = text[:width_start] + matched + text[width_end:]

    controls_body = """AlarmSystem.OneUiClock {
    id: oneUiClock
    anchors.fill: parent
    z: 100
    controller: root
    scaleFunc: root.s
    baseColor: root.cBase
    mantleColor: root.cMantle
    surface0Color: root.cSurface0
    surface1Color: root.cSurface1
    surface2Color: typeof mochaColors !== "undefined" && mochaColors
        ? mochaColors.surface2
        : "#585b70"
    textColor: root.cText
    subtextColor: root.cSubtext0
    accentColor: root.cMauve
    blueColor: typeof mochaColors !== "undefined" && mochaColors
        ? mochaColors.blue
        : "#89b4fa"
    sapphireColor: typeof mochaColors !== "undefined" && mochaColors
        ? mochaColors.sapphire
        : "#74c7ec"
    pinkColor: typeof mochaColors !== "undefined" && mochaColors
        ? mochaColors.pink
        : "#f5c2e7"
    greenColor: typeof mochaColors !== "undefined" && mochaColors
        ? mochaColors.green
        : "#a6e3a1"
    redColor: typeof mochaColors !== "undefined" && mochaColors
        ? mochaColors.red
        : "#f38ba8"
    iconFont: root.iconFont
    animateBackground: root.widgetVisible
}

AlarmSystem.SoundSettings {
    id: alarmSoundSettings
    anchors.fill: parent
    scaleFunc: root.s
    baseColor: root.cBase
    mantleColor: root.cMantle
    surface0Color: root.cSurface0
    surface1Color: root.cSurface1
    textColor: root.cText
    subtextColor: root.cSubtext0
    accentColor: root.cMauve
    iconFont: root.iconFont
}

AlarmSystem.RingingOverlay {
    anchors.fill: parent
    scaleFunc: root.s
    mantleColor: root.cMantle
    surface0Color: root.cSurface0
    surface1Color: root.cSurface1
    textColor: root.cText
    subtextColor: root.cSubtext0
    accentColor: root.cMauve
    iconFont: root.iconFont
}"""
    controls_block = marker_block(
        CONTROLS_BEGIN,
        CONTROLS_END,
        controls_body,
        "        ",
    )
    text = insert_before_line(
        text,
        r"^[ \t]*// --- VIEW CONTAINERS ---\s*$",
        controls_block,
        "view containers heading",
    )

    alarm_view_body = """AlarmSystem.AlarmView {
    id: alarmView
    anchors.fill: parent
    visible: stateCache.activeMode === 3
    opacity: visible ? 1.0 : 0.0
    scaleFunc: root.s
    baseColor: root.cBase
    mantleColor: root.cMantle
    surface0Color: root.cSurface0
    surface1Color: root.cSurface1
    textColor: root.cText
    subtextColor: root.cSubtext0
    accentColor: root.cMauve
    iconFont: root.iconFont
    Behavior on opacity { NumberAnimation { duration: 250 } }
}"""
    alarm_view_block = marker_block(
        ALARM_VIEW_BEGIN,
        ALARM_VIEW_END,
        alarm_view_body,
        "            ",
    )
    text = insert_before_line(
        text,
        r"^[ \t]*// 1\. TIMER VIEW\s*$",
        alarm_view_block,
        "Timer view heading",
    )

    stopwatch_status_body = """Rectangle {
    id: stopwatchAlarmStatus
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.s(210)
    height: root.s(25)
    radius: root.s(8)
    color: AlarmSystem.AlarmManager.stopwatchEnabled ? root.alpha(root.cMauve, 0.15) : root.cSurface0
    border.width: 1
    border.color: AlarmSystem.AlarmManager.stopwatchEnabled ? root.cMauve : root.cSurface1

    Text {
        anchors.centerIn: parent
        text: AlarmSystem.AlarmManager.stopwatchEnabled
            ? "Alarm at " + root.formatTime(AlarmSystem.AlarmManager.stopwatchTargetMs, false)
            : "Stopwatch alarm off"
        color: AlarmSystem.AlarmManager.stopwatchEnabled ? root.cMauve : root.cSubtext0
        font.family: "JetBrains Mono"
        font.bold: true
        font.pixelSize: root.s(10)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: alarmSoundSettings.openFor("stopwatch")
    }
}"""
    stopwatch_status_block = marker_block(
        STOPWATCH_STATUS_BEGIN,
        STOPWATCH_STATUS_END,
        stopwatch_status_body,
        "                        ",
    )
    text = insert_before_line(
        text,
        r"^[ \t]*// Lap List\s*$",
        stopwatch_status_block,
        "stopwatch lap list",
    )

    text = text.replace(
        "swContentArea.height - swTimeText.height - root.s(15)",
        "swContentArea.height - swTimeText.height - stopwatchAlarmStatus.height - root.s(30)",
        1,
    )

    return text


def validate_qml(path: Path, import_root: Path | None = None) -> None:
    qmllint = shutil.which("qmllint")
    if not qmllint:
        raise ApplyError("missing required command: qmllint")
    command = [qmllint]
    if import_root is not None:
        command.extend(["-I", str(import_root)])
    command.append(str(path))
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        details = (result.stdout + result.stderr).strip()
        raise ApplyError(f"QML validation failed for {path.name}:\n{details}")


def atomic_write(path: Path, content: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
        text=True,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.chmod(temporary, mode if mode is not None else 0o644)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def backup(path: Path) -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{stamp}")


def normalized_settings(value: object) -> dict:
    result = json.loads(json.dumps(DEFAULT_SETTINGS))
    if not isinstance(value, dict):
        return result
    sounds = value.get("sounds")
    if isinstance(sounds, dict):
        for mode in result["sounds"]:
            candidate = sounds.get(mode)
            if not isinstance(candidate, dict):
                continue
            result["sounds"][mode] = {
                "source": str(candidate.get("source", "")),
                "volume": max(0, min(100, int(candidate.get("volume", 85)))),
            }
    try:
        target = int(value.get("stopwatchTargetMs", result["stopwatchTargetMs"]))
    except (TypeError, ValueError):
        target = result["stopwatchTargetMs"]
    result["stopwatchTargetMs"] = max(1000, min(99 * 3600000, target))
    result["stopwatchEnabled"] = value.get("stopwatchEnabled") is True
    if isinstance(value.get("alarms"), list):
        result["alarms"] = value["alarms"]
    return result


def ensure_settings() -> bool:
    try:
        existing = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        existing = {}
    except (OSError, json.JSONDecodeError) as error:
        raise ApplyError(f"invalid alarm settings file: {error}") from error
    normalized = normalized_settings(existing)
    desired = json.dumps(normalized, ensure_ascii=False, indent=2) + "\n"
    if SETTINGS_PATH.is_file() and SETTINGS_PATH.read_text(encoding="utf-8") == desired:
        return False
    atomic_write(SETTINGS_PATH, desired, 0o600)
    return True


def generate_default_sound(path: Path) -> bool:
    if path.is_file() and path.stat().st_size > 4096:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    sample_rate = 48000
    duration = 3.2
    frames_count = int(sample_rate * duration)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".default-alarm.",
        suffix=".wav",
        dir=path.parent,
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with wave.open(str(temporary), "wb") as output:
            output.setnchannels(2)
            output.setsampwidth(2)
            output.setframerate(sample_rate)
            frames = bytearray()
            for index in range(frames_count):
                time_value = index / sample_rate
                pulse = time_value % 1.05
                envelope = math.exp(-3.2 * pulse)
                attack = min(1.0, pulse / 0.025)
                release = min(1.0, max(0.0, (duration - time_value) / 0.35))
                shimmer = (
                    math.sin(2 * math.pi * 659.25 * time_value)
                    + 0.58 * math.sin(2 * math.pi * 987.77 * time_value)
                    + 0.25 * math.sin(2 * math.pi * 1318.51 * time_value)
                )
                sample = int(32767 * 0.22 * envelope * attack * release * shimmer / 1.83)
                sample = max(-32768, min(32767, sample))
                packed = sample.to_bytes(2, byteorder="little", signed=True)
                frames.extend(packed)
                frames.extend(packed)
            output.writeframes(frames)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return True


def install_module() -> bool:
    changed = False
    LIVE_MODULE.mkdir(parents=True, exist_ok=True)
    for name in MODULE_FILES:
        source = ADDON_DIR / name
        if not source.is_file():
            raise ApplyError(f"missing addon module file: {source}")
        if source.suffix == ".qml":
            validate_qml(source, ADDON_DIR.parent)
        destination = LIVE_MODULE / name
        if destination.is_file() and destination.read_bytes() == source.read_bytes():
            continue
        temporary = destination.with_name(f".{destination.name}.custom-alarm-clock")
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
        changed = True
    if generate_default_sound(LIVE_MODULE / "default-alarm.wav"):
        changed = True
    return changed


def patch_live_timer() -> bool:
    if not TIMER_QML.is_file():
        raise ApplyError(f"Timer.qml not found: {TIMER_QML}")
    original = TIMER_QML.read_text(encoding="utf-8")
    patched = patch_timer(original)
    if patched == original:
        validate_qml(TIMER_QML, QS_DIR)
        return False

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{TIMER_QML.name}.",
        suffix=".qml",
        dir=TIMER_QML.parent,
        text=True,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(patched)
        os.chmod(temporary, TIMER_QML.stat().st_mode)
        validate_qml(temporary, QS_DIR)
        backup(TIMER_QML)
        os.replace(temporary, TIMER_QML)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return True


def reload_quickshell() -> bool:
    if not SHELL_QML.is_file() or not shutil.which("qs"):
        return False
    result = subprocess.run(
        ["qs", "-p", str(SHELL_QML), "ipc", "call", "main", "forceReload"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    changes = []
    if ensure_settings():
        changes.append("settings")
    if install_module():
        changes.append("shared module")
    if patch_live_timer():
        changes.append("Timer widget")

    if changes:
        suffix = " and reloaded Quickshell" if reload_quickshell() else ""
        print("custom-alarm-clock: updated " + ", ".join(changes) + suffix)
    else:
        print("custom-alarm-clock: addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ApplyError, OSError, ValueError) as error:
        print(f"custom-alarm-clock: {error}; no Timer widget changed", file=sys.stderr)
        raise SystemExit(1)
