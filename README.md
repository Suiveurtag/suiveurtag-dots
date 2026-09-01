# Hyprland Personal Addons

Personal addons layered on top of ilyamiro's Hyprland + Quickshell dots.

This repo currently contains:

- `wallpaper-random`: visible SVG random wallpaper button and persistent animated-wallpaper audio toggle for the wallpaper picker
- `mouse-monitor-cycle`: moves the mouse to the center of the next monitor on `Meta+Tab`, without changing fullscreen or window state
- `emoji-picker`: emoji keyboard on `Super+J`
- `matugen-vibrant`: `Off`, `Normal`, or `Vivid` wallpaper-matched color modes
- `zoomit`: smooth cursor-following magnifier and frozen-screen drawing overlay
- `drawing-notes`: toggle the floating drawing widget between its canvas and an autosaved Markdown notepad
- `screenshot-freeze`: optional Windows-style frozen screen while selecting a screenshot region
- `idle-inhibit`: Quick Settings shortcut linked to Serpantinum's native Idle System setting
- `music-preview-rounded`: rounded album artwork and the existing optional CAVA visualizer; the visualizer is not exposed in the Serpantinum V2 secondary addon settings
- `topbar-button-effects`: optional press feedback and animated Matugen outlines for active top bar panels
- `launcher-web-search`: press `Tab` in the app launcher to search the typed text with Zen
- `custom-alarm-clock`: custom sounds for Timer, Stopwatch targets and Pomodoro, plus persistent one-time or daily alarms
- `headset-mic-loopback`: expose the current headset output as a selectable virtual microphone
- `captive-portal`: detects Wi-Fi networks that still need a browser login and adds an "Open Login Page" action to the network popup
- `speedtest`: native network-panel speedtest with a separate button, live progress UI, and Cloudflare endpoint measurements
- `loading-icon`: shared white SVG loader used across wallpaper, updater, movies, network actions, and speedtest
- `wifi-text-scroll`: smoothly scrolls a long active Wi-Fi name inside the network panel
- `dns-mode-toggle`: animated per-connection switch between DHCP-provided and Mullvad DNS
- `calendar-legacy`: restored legacy Calendar/Clock panel with the V1 opening animation
- `wifi-hold-sound`: continuous charge/fill sound while holding the Wi-Fi power control
- `tor-panel`: isolated Tor network control and per-application routing on `Super+K`

Serpantinum V2 integration also restores the separate left-side `Quick Settings` panel for addon controls, keybinds, and monitors. Its shortcuts are `Meta+P` for the main settings and `Meta+Shift+P` for Quick Settings.

`Meta+Tab` cycles the mouse through the connected monitors, and `Meta+Space` switches to the next keyboard layout. The input configuration keeps French (`fr`) first, so French remains the startup layout.

The Serpantinum V2 installer also maintains the following panel and wallpaper-picker changes:

- the System panel can replace Hibernate with Logout and show the PC uptime in the action area; both options are independently toggleable in addon settings
- the secondary addon settings page contains the animated selector for Matugen colors (`Off`, `Normal`, and `Vivid`), with the Music Visualizer entry removed
- the System panel performance switcher uses the live Matugen palette with gradients: red/peach/pink for Performance, blue/sapphire/mauve for Balanced, and green/teal/yellow for Power Saver
- wallpaper navigation accepts the four arrow keys (`← ↑ ↓ →`) without applying a wallpaper; Enter applies the centered selection, and Tab cycles deterministically through categories with `Search → All`
- wallpaper selection uses the existing centered `ListView` highlight animation instead of forcing an immediate layout reposition
- the restored Calendar/Clock panel replays the V1 per-element entrance animation after it becomes visible, with a clean reset on close
- holding the Wi-Fi power control plays the fill/charge loop and stops it immediately on release

These addons are designed to stay isolated from the upstream dots:

- addon code lives in `~/.local/share/quickshell-addons/...`
- tiny systemd user path units reapply the patches after upstream updates
- the active Quickshell config only receives the minimum patched lines and copied assets

## Layout

- `addons/`: addon source files copied into `~/.local/share/quickshell-addons`
- `systemd/user/`: watcher units copied into `~/.config/systemd/user`
- `install.sh`: bootstraps ilyamiro's dots, then installs or refreshes every addon
- `scripts/install-addons.sh`: internal idempotent addon deployment used by `install.sh`

## Install

On Arch Linux or a supported Arch derivative, copy and paste this single command:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/suiveurtag-dots/main/install.sh)"
```

What it does:

- downloads this repository into a temporary directory when launched from the command above
- checks the distribution, user session, and required bootstrap commands
- downloads and runs [ilyamiro's official imperative-dots installer](https://github.com/ilyamiro/imperative-dots) when the base dots are missing
- skips the upstream installer when a working installation is already present
- copies all addons into `~/.local/share/quickshell-addons`
- copies the user systemd units into `~/.config/systemd/user`
- enables and starts the watcher path units
- preserves current-wallpaper detection for filenames containing spaces
- runs each patcher immediately
- refreshes the generated Hyprland configuration, force-reloads borders, animations and keyboard layouts, then reloads the running Quickshell instance
- displays the current stage and reports the failing command, step, and likely cause when something goes wrong

The installer is safe to run again to refresh the addons. To run it from a cloned checkout:

```bash
./install.sh
```

Useful options:

- `--force-dots`: rerun ilyamiro's installer even when the base dots are detected
- `--skip-dots`: apply only the Suiveurtag addons
- `--no-color`: disable colored output

The upstream ilyamiro installer is interactive, may request `sudo`, supports Arch Linux and its derivatives, and announces anonymous telemetry in its own README.

## Notes

- This repo does not include local backup snapshots generated by the patchers.
- The emoji picker keeps its keybind in `settings.json`, so it survives the dots' keybind regeneration flow.
- In the app launcher, `Enter` still opens the selected application; `Tab` searches the typed text in a new Zen tab.
- The floating Timer widget now includes an **Alarm** tab. Create one-time or daily alarms, enable or remove them, and use the music-note button to choose a separate WAV, OGG, MP3, FLAC, M4A, AAC, or Opus sound and volume for Timer, Stopwatch, Pomodoro, and Alarm.
- Stopwatch alarms are tied to an optional count-up target. Open its sound settings, choose the target in one-minute steps, and enable it; scheduled alarms can be snoozed for five minutes or dismissed while ringing.
- Timer, Stopwatch, Pomodoro, and Alarm share a One UI-inspired clock layout with circular controls, a floating bottom navigation pill, state morphs, and slowly drifting background lights sourced from the current Matugen palette.
- Alarm settings are stored under `~/.local/state/quickshell/custom-alarm-clock/`. The shared player and scheduler are singletons, so multi-monitor sessions produce one alarm rather than one per monitor.
- In the audio panel's **Streams** tab, **Headset audio as microphone** creates a `Headset Audio` input from the current output. Select that input in Discord, OBS, or another recording app; turning the option off removes it.
- When the current wallpaper is animated, the wallpaper picker shows a speaker button. It enables or mutes `mpvpaper` audio, remembers the choice, and applies it to subsequent animated wallpapers without changing the system volume.
- Matugen color mode is selectable under **Quick Settings → Addons**: **Off** restores the preset colors, **Normal** uses wallpaper colors as-is, and **Vivid** lifts colors that would otherwise be too dark while preserving distinct accents.
- Frozen screenshot selection is enabled by default under **Settings → Addons → Freeze screen during selection**. It freezes regional screenshots, including edit mode, while full-screen screenshots remain instant and screen recording stays live.
- Existing CAVA visualizer state remains compatible, but the visualizer option is no longer exposed in the Serpantinum V2 secondary **Settings → Addons** page.
- **Settings → Addons → Animated top bar buttons** is enabled by default. Mouse presses shrink and gray the button briefly; opening a panel by mouse or shortcut keeps a flowing Matugen gradient around its matching top bar button.
- **Quick Settings → Enable idle system** is linked to the native **Settings → Idle → Enable Idle System** control and writes the same `idle.enabled` value.
- **Quick Settings → Keybinds** edits are compiled into the active Hyprland Lua bindings, including French-layout-safe Meta shortcuts. Wallpaper and screenshot shortcuts therefore apply immediately after saving.
- The system panel volume slider uses a two-color Matugen gradient, and the performance switcher uses live Matugen gradients for Performance, Balanced, and Power Saver.
- **Settings → Bar** has separate time formats for the top bar clock (`bar.time.format`) and calendar panel clock (`calendar.time.format`).
- The Matugen addon saves the latest upstream Quickshell color template before overriding it. Disabling the option restores that template, and the watcher repeats the process after dots updates.
- ZoomIt-style shortcuts are added to **Settings → Keybinds** and can be edited there:
  - `Super+Alt+Z`: smoothly toggle a 2× cursor-following zoom. While active, use the wheel to zoom further in or return to 1×.
  - `Super+Alt+D`: toggle drawing on a frozen image of the screen under the cursor.
- Drawing controls follow ZoomIt conventions: drag to draw, `Shift`+drag for a line, `Ctrl`+drag for a rectangle, `Ctrl+Shift`+drag for an arrow, and hold `Tab` (or `Alt`) while dragging for an ellipse. `R/G/B/Y/O/P` select colors, `Ctrl+wheel` changes pen width, `Ctrl+Z` undoes, `E` clears, `W`/`K` select a white/black board, and right-click or `Esc` exits.
- The zoom uses Hyprland's native compositor magnifier, with anti-aliasing enabled and a 120 fps eased transition. The drawing overlay requires the commands `grim`, `qs`, and `qmllint` (already present in ilyamiro's dots setup).
- Installation refreshes the running Quickshell instance so newly added ZoomIt shortcuts appear in **Settings → Keybinds** immediately.
- Custom ZoomIt key combinations selected in **Settings → Keybinds** are preserved by the addon watcher; defaults are only recreated when an addon entry is missing.
- The captive portal addon uses `nmcli` for connectivity state and `curl` to discover the login redirect URL when a hotspot requires web authentication.
- The speedtest addon uses `curl` against Cloudflare's `speed.cloudflare.com` download/upload endpoints and shows live download/upload progress, latency, and final results in its own Matugen-styled network panel view.
- A long active Wi-Fi name scrolls automatically and continuously in the panel's central connection circle; other network cards, Ethernet, Bluetooth, and the top bar keep their original text behavior.
- The Wi-Fi panel DNS toggle preserves the current mode during installation. **Maison** clears manual DNS and uses the DHCP-provided resolvers; **Mullvad** applies `194.242.2.2` and `2a07:e340::2` over authenticated DNS-over-TLS (`dns.mullvad.net`) only to the active Wi-Fi profile through NetworkManager.
- `Super+K` opens the Tor panel. Its main switch starts a hardened user-level Tor client; the application list chooses which compatible native applications are launched through Tor from the regular `Super+D` app launcher.
- Tor-routed applications start in a network namespace with no direct Internet interface. TCP and DNS go through a private Unix socket, and stopping Tor cuts their connectivity instead of falling back to the normal connection. The selection applies to new launches, not processes that are already open.
- The Tor panel installs `tor`, `proxychains-ng`, `bubblewrap`, and `socat` when needed. Its route choices are stored under `~/.local/state/quickshell/tor-panel/`; the Tor service is not enabled at login and only starts on demand.
- Flatpak apps, Steam/games, UDP-heavy software, and regular browsers are marked unsupported where strict routing cannot be guaranteed. For anonymous web browsing, use Tor Browser: routing another browser through Tor does not provide Tor Browser's anti-fingerprinting protections.
- If you pull new upstream dots later, the path units should reapply the addons automatically.
