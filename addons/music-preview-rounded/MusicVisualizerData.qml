pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (homeDir + "/.local/share")
    readonly property string settingsPath: homeDir + "/.config/hypr/settings.json"
    readonly property string cavaConfig: dataHome + "/quickshell-addons/music-preview-rounded/cava.conf"

    property bool enabled: false
    property bool available: true
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    function resetBands() {
        bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    }

    function consumeFrame(frame) {
        const values = frame.trim().split(";").filter(value => value !== "");
        if (values.length < 12) return;
        const normalized = [];
        for (let index = 0; index < 12; index++) {
            const value = Number(values[index]);
            normalized.push(isNaN(value) ? 0 : Math.max(0, Math.min(1, value / 100)));
        }
        bands = normalized;
    }

    Process {
        id: settingsReader
        command: ["cat", root.settingsPath]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const settings = JSON.parse(this.text || "{}");
                    root.enabled = settings.musicVisualizerEnabled === true;
                } catch (error) {
                    root.enabled = false;
                }
            }
        }
    }

    Process {
        id: settingsWatcher
        command: ["bash", "-c", "while [ ! -f '" + root.settingsPath + "' ]; do sleep 1; done; inotifywait -qq -e modify,close_write '" + root.settingsPath + "'"]
        running: true
        onExited: {
            settingsReader.running = false;
            settingsReader.running = true;
            settingsWatcher.running = false;
            settingsWatcher.running = true;
        }
    }

    Process {
        id: cavaProcess
        command: ["bash", "-c", "command -v cava >/dev/null 2>&1 || exit 127; exec cava -p '" + root.cavaConfig + "'"]
        running: root.enabled
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: frame => root.consumeFrame(frame)
        }
        onStarted: root.available = true
        onExited: exitCode => {
            root.resetBands();
            if (root.enabled) {
                root.available = false;
                if (exitCode !== 127) restartTimer.restart();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!root.enabled) return;
            root.available = true;
            cavaProcess.running = false;
            cavaProcess.running = true;
        }
    }

    onEnabledChanged: {
        if (!enabled) {
            restartTimer.stop();
            available = true;
            resetBands();
        }
    }
}
