pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

Item {
    id: manager

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (homeDir + "/.local/state")
    readonly property string settingsPath: stateHome + "/quickshell/custom-alarm-clock/settings.json"
    readonly property url defaultSound: Qt.resolvedUrl("default-alarm.wav")
    readonly property var modeNames: ({
        timer: "Timer",
        stopwatch: "Stopwatch",
        pomodoro: "Pomodoro",
        alarm: "Alarm"
    })

    readonly property var alarms: settingsData.alarms || []
    readonly property int stopwatchTargetMs: Math.max(1000, Number(settingsData.stopwatchTargetMs) || 300000)
    readonly property bool stopwatchEnabled: settingsData.stopwatchEnabled === true
    readonly property bool isRinging: ringingMode !== ""
    readonly property bool isPreviewing: previewMode !== ""

    property string ringingMode: ""
    property string ringingTitle: ""
    property string ringingMessage: ""
    property string ringingAlarmId: ""
    property string ringingAlarmLabel: ""
    property string previewMode: ""
    property string lastError: ""
    property bool fallbackAttempted: false
    property double schedulerLastEpoch: Date.now() - 60000
    property var ringQueue: []

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function modeLabel(mode) {
        return modeNames[mode] || "Alarm";
    }

    function soundFor(mode) {
        const allSounds = settingsData.sounds || {};
        const selected = allSounds[mode] || {};
        const volume = Math.max(0, Math.min(100, Number(selected.volume) || 85));
        return {
            source: String(selected.source || ""),
            volume: volume
        };
    }

    function soundName(mode) {
        const source = soundFor(mode).source;
        if (source === "") return "Built-in chime";
        const clean = decodeURIComponent(source.split("?")[0]);
        const pieces = clean.split("/");
        return pieces[pieces.length - 1] || "Custom sound";
    }

    function soundSource(mode) {
        const configured = soundFor(mode).source;
        return configured === "" ? defaultSound : configured;
    }

    function saveSounds(updatedSounds) {
        settingsData.sounds = updatedSounds;
        settingsFile.writeAdapter();
    }

    function setSound(mode, sourceUrl) {
        const updated = clone(settingsData.sounds || {});
        const previous = soundFor(mode);
        updated[mode] = {
            source: String(sourceUrl || ""),
            volume: previous.volume
        };
        saveSounds(updated);
    }

    function resetSound(mode) {
        setSound(mode, "");
    }

    function setVolume(mode, value) {
        const updated = clone(settingsData.sounds || {});
        const previous = soundFor(mode);
        updated[mode] = {
            source: previous.source,
            volume: Math.max(0, Math.min(100, Math.round(Number(value))))
        };
        saveSounds(updated);
        if ((ringingMode === mode || previewMode === mode) && player.playing) {
            audioOutput.volume = updated[mode].volume / 100.0;
        }
    }

    function setStopwatchTarget(targetMs, enabled) {
        settingsData.stopwatchTargetMs = Math.max(1000, Math.min(99 * 3600000, Math.round(targetMs)));
        settingsData.stopwatchEnabled = enabled === true;
        settingsFile.writeAdapter();
    }

    function formatClockTime(hour, minute) {
        return String(hour).padStart(2, "0") + ":" + String(minute).padStart(2, "0");
    }

    function dateKey(date) {
        return date.getFullYear() + "-"
            + String(date.getMonth() + 1).padStart(2, "0") + "-"
            + String(date.getDate()).padStart(2, "0");
    }

    function dateFromKey(key) {
        const parts = String(key || "").split("-");
        if (parts.length !== 3) return null;
        const parsed = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0);
        return isNaN(parsed.getTime()) ? null : parsed;
    }

    function newAlarmId() {
        return Date.now().toString(36) + "-" + Math.floor(Math.random() * 1679616).toString(36);
    }

    function addAlarm(hour, minute, label, repeatMode, alarmDate) {
        const updated = clone(alarms);
        updated.push({
            id: newAlarmId(),
            hour: Math.max(0, Math.min(23, Math.round(hour))),
            minute: Math.max(0, Math.min(59, Math.round(minute))),
            label: String(label || "Alarm").trim().slice(0, 80) || "Alarm",
            enabled: true,
            repeat: repeatMode === "daily" ? "daily" : "once",
            date: repeatMode === "daily" ? "" : String(alarmDate || ""),
            lastFired: ""
        });
        settingsData.alarms = updated;
        settingsFile.writeAdapter();
    }

    function updateAlarm(alarmId, hour, minute, label, repeatMode, alarmDate) {
        const updated = clone(alarms);
        for (let index = 0; index < updated.length; index++) {
            if (updated[index].id !== alarmId) continue;
            updated[index].hour = Math.max(0, Math.min(23, Math.round(hour)));
            updated[index].minute = Math.max(0, Math.min(59, Math.round(minute)));
            updated[index].label = String(label || "Alarm").trim().slice(0, 80) || "Alarm";
            updated[index].repeat = repeatMode === "daily" ? "daily" : "once";
            updated[index].date = repeatMode === "daily" ? "" : String(alarmDate || "");
            updated[index].lastFired = "";
            settingsData.alarms = updated;
            settingsFile.writeAdapter();
            return;
        }
    }

    function toggleAlarm(alarmId) {
        const updated = clone(alarms);
        for (let index = 0; index < updated.length; index++) {
            if (updated[index].id !== alarmId) continue;
            updated[index].enabled = updated[index].enabled !== true;
            updated[index].lastFired = "";
            settingsData.alarms = updated;
            settingsFile.writeAdapter();
            return;
        }
    }

    function deleteAlarm(alarmId) {
        const updated = [];
        for (let index = 0; index < alarms.length; index++) {
            if (alarms[index].id !== alarmId) updated.push(clone(alarms[index]));
        }
        settingsData.alarms = updated;
        settingsFile.writeAdapter();
    }

    function nextAlarmText() {
        const now = new Date();
        let nextEpoch = 0;
        let nextLabel = "";
        for (let index = 0; index < alarms.length; index++) {
            const alarm = alarms[index];
            if (alarm.enabled !== true) continue;
            let candidate;
            if (alarm.repeat !== "daily" && String(alarm.date || "") !== "") {
                const exactDate = dateFromKey(alarm.date);
                if (!exactDate) continue;
                candidate = new Date(
                    exactDate.getFullYear(), exactDate.getMonth(), exactDate.getDate(),
                    Number(alarm.hour), Number(alarm.minute), 0, 0
                );
                if (candidate.getTime() <= now.getTime()) continue;
            } else {
                candidate = new Date(
                    now.getFullYear(), now.getMonth(), now.getDate(),
                    Number(alarm.hour), Number(alarm.minute), 0, 0
                );
                if (candidate.getTime() <= now.getTime()) candidate.setDate(candidate.getDate() + 1);
            }
            if (nextEpoch === 0 || candidate.getTime() < nextEpoch) {
                nextEpoch = candidate.getTime();
                nextLabel = Qt.formatDate(candidate, "ddd d MMM") + " · "
                    + formatClockTime(alarm.hour, alarm.minute) + " · " + alarm.label;
            }
        }
        return nextLabel;
    }

    function notify(title, message, icon, critical) {
        const command = [
            "notify-send",
            "-a", "Quickshell Alarm",
            "-i", icon || "preferences-system-time"
        ];
        if (critical === true) command.push("-u", "critical", "-t", "0");
        command.push(title, message);
        Quickshell.execDetached(command);
    }

    function enqueueRing(mode, title, message, alarmId, alarmLabel) {
        const updated = clone(ringQueue);
        updated.push({
            mode: mode,
            title: title,
            message: message,
            alarmId: alarmId || "",
            alarmLabel: alarmLabel || ""
        });
        ringQueue = updated;
    }

    function ring(mode, title, message, alarmId, alarmLabel) {
        if (isRinging) {
            enqueueRing(mode, title, message, alarmId, alarmLabel);
            return;
        }

        player.stop();
        previewStopTimer.stop();
        previewMode = "";
        fallbackAttempted = false;
        lastError = "";
        ringingMode = mode;
        ringingTitle = title;
        ringingMessage = message;
        ringingAlarmId = alarmId || "";
        ringingAlarmLabel = alarmLabel || "";
        audioOutput.volume = soundFor(mode).volume / 100.0;
        player.loops = mode === "alarm" ? MediaPlayer.Infinite : 3;
        player.source = soundSource(mode);
        player.play();
        autoStopTimer.interval = mode === "alarm" ? 10 * 60 * 1000 : 30 * 1000;
        autoStopTimer.restart();
        notify(title, message + "  Open the timer panel to dismiss.", "preferences-system-time", mode === "alarm");
    }

    function preview(mode) {
        player.stop();
        autoStopTimer.stop();
        fallbackAttempted = false;
        lastError = "";
        ringingMode = "";
        ringingTitle = "";
        ringingMessage = "";
        previewMode = mode;
        audioOutput.volume = soundFor(mode).volume / 100.0;
        player.loops = MediaPlayer.Once;
        player.source = soundSource(mode);
        player.play();
        previewStopTimer.restart();
    }

    function stopPlayback(clearQueue) {
        player.stop();
        autoStopTimer.stop();
        previewStopTimer.stop();
        const hadAlarm = ringingMode !== "";
        ringingMode = "";
        ringingTitle = "";
        ringingMessage = "";
        ringingAlarmId = "";
        ringingAlarmLabel = "";
        previewMode = "";
        if (clearQueue === true) ringQueue = [];
        if (hadAlarm && clearQueue !== true && ringQueue.length > 0) {
            queueAdvanceTimer.restart();
        }
    }

    function snoozeCurrent(minutes) {
        if (ringingMode !== "alarm") return;
        const date = new Date(Date.now() + Math.max(1, minutes) * 60000);
        addAlarm(
            date.getHours(),
            date.getMinutes(),
            (ringingAlarmLabel || ringingTitle || "Alarm") + " (snoozed)",
            "once",
            dateKey(date)
        );
        stopPlayback(false);
    }

    function advanceQueue() {
        if (isRinging || ringQueue.length === 0) return;
        const updated = clone(ringQueue);
        const next = updated.shift();
        ringQueue = updated;
        ring(next.mode, next.title, next.message, next.alarmId, next.alarmLabel);
    }

    function scheduledEpochFor(date, alarm) {
        return new Date(
            date.getFullYear(),
            date.getMonth(),
            date.getDate(),
            Number(alarm.hour),
            Number(alarm.minute),
            0,
            0
        ).getTime();
    }

    function checkScheduledAlarms() {
        const now = new Date();
        const nowEpoch = now.getTime();
        const previousEpoch = schedulerLastEpoch;
        schedulerLastEpoch = nowEpoch;
        const today = dateKey(now);
        const graceMs = 10 * 60 * 1000;
        const updated = clone(alarms);
        const due = [];
        let changed = false;

        for (let index = 0; index < updated.length; index++) {
            const alarm = updated[index];
            if (alarm.enabled !== true || alarm.lastFired === today) continue;
            if (alarm.repeat !== "daily"
                    && String(alarm.date || "") !== ""
                    && String(alarm.date) !== today) continue;
            const scheduledEpoch = scheduledEpochFor(now, alarm);
            const crossed = scheduledEpoch > previousEpoch && scheduledEpoch <= nowEpoch;
            const currentMinute = now.getHours() === Number(alarm.hour)
                && now.getMinutes() === Number(alarm.minute);
            const recentEnough = nowEpoch - scheduledEpoch <= graceMs;
            if (!(currentMinute || (crossed && recentEnough))) continue;

            alarm.lastFired = today;
            if (alarm.repeat !== "daily") alarm.enabled = false;
            due.push(clone(alarm));
            changed = true;
        }

        if (!changed) return;
        settingsData.alarms = updated;
        settingsFile.writeAdapter();
        for (let index = 0; index < due.length; index++) {
            const alarm = due[index];
            if (!isRinging && index === 0) {
                ring(
                    "alarm",
                    alarm.label || "Alarm",
                    "Scheduled for " + formatClockTime(alarm.hour, alarm.minute),
                    alarm.id,
                    alarm.label
                );
            } else {
                enqueueRing(
                    "alarm",
                    alarm.label || "Alarm",
                    "Scheduled for " + formatClockTime(alarm.hour, alarm.minute),
                    alarm.id,
                    alarm.label
                );
            }
        }
    }

    function handlePlaybackError(errorString) {
        if (!fallbackAttempted && String(player.source) !== String(defaultSound)) {
            fallbackAttempted = true;
            player.stop();
            player.source = defaultSound;
            player.play();
            return;
        }
        lastError = errorString || "The selected audio file could not be played.";
        notify("Alarm sound unavailable", lastError, "dialog-warning", false);
        stopPlayback(false);
    }

    FileView {
        id: settingsFile
        path: manager.settingsPath
        blockLoading: true
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: settingsData
            property int version: 2
            property var sounds: ({
                timer: { source: "", volume: 85 },
                stopwatch: { source: "", volume: 85 },
                pomodoro: { source: "", volume: 85 },
                alarm: { source: "", volume: 85 }
            })
            property int stopwatchTargetMs: 5 * 60 * 1000
            property bool stopwatchEnabled: false
            property var alarms: []
        }
    }

    AudioOutput {
        id: audioOutput
        volume: 0.85
    }

    MediaPlayer {
        id: player
        audioOutput: audioOutput
        onErrorOccurred: (error, errorString) => manager.handlePlaybackError(errorString)
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia && manager.previewMode !== "") {
                manager.previewMode = "";
                previewStopTimer.stop();
            }
        }
    }

    Timer {
        id: scheduler
        interval: 1000
        repeat: true
        running: true
        onTriggered: manager.checkScheduledAlarms()
    }

    Timer {
        id: previewStopTimer
        interval: 8000
        repeat: false
        onTriggered: manager.stopPlayback(false)
    }

    Timer {
        id: autoStopTimer
        repeat: false
        onTriggered: manager.stopPlayback(false)
    }

    Timer {
        id: queueAdvanceTimer
        interval: 250
        repeat: false
        onTriggered: manager.advanceQueue()
    }
}
