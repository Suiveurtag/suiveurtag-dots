#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_NAME="Suiveurtag Dots"
readonly PROJECT_REPO="${SUIVEURTAG_PROJECT_REPO:-https://github.com/Suiveurtag/suiveurtag-dots}"
readonly PROJECT_ARCHIVE="${SUIVEURTAG_PROJECT_ARCHIVE:-${PROJECT_REPO}/archive/refs/heads/main.tar.gz}"
CURRENT_STAGE="Initialisation"
STEP_INDEX=0
STEP_TOTAL=5
LOCAL_SOURCE=false
TEMP_DIRS=()
CREATED_TEMP_DIR=""
ORIGINAL_ARGS=("$@")

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    MAGENTA=$'\033[35m'
    CYAN=$'\033[36m'
else
    RESET=""
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
fi

cleanup() {
    local directory
    for directory in "${TEMP_DIRS[@]:-}"; do
        [[ -n "$directory" && -d "$directory" ]] || continue
        case "$directory" in
            /tmp/*|"${TMPDIR:-/tmp}"/*) rm -rf -- "$directory" ;;
        esac
    done
}

on_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"

    trap - ERR
    printf "\n${RED}${BOLD}✗ Installation failed${RESET}\n" >&2
    printf "${RED}  Stage:${RESET} %s\n" "$CURRENT_STAGE" >&2
    printf "${RED}  Cause:${RESET} command returned exit code %s\n" "$exit_code" >&2
    printf "${RED}  Line:${RESET} %s\n" "$line_number" >&2
    printf "${RED}  Command:${RESET} %s\n" "$command" >&2
    printf "${DIM}  The failing program's detailed message is shown above.${RESET}\n" >&2
    exit "$exit_code"
}

trap cleanup EXIT
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

info() {
    printf "${BLUE}  •${RESET} %s\n" "$*"
}

success() {
    printf "${GREEN}  ✓${RESET} %s\n" "$*"
}

warn() {
    printf "${YELLOW}  ! %s${RESET}\n" "$*" >&2
}

die() {
    local message="$1"
    local hint="${2:-}"
    printf "\n${RED}${BOLD}✗ %s${RESET}\n" "$message" >&2
    printf "${RED}  Stage:${RESET} %s\n" "$CURRENT_STAGE" >&2
    if [[ -n "$hint" ]]; then
        printf "${YELLOW}  Fix:${RESET} %s\n" "$hint" >&2
    fi
    exit 1
}

step() {
    STEP_INDEX=$((STEP_INDEX + 1))
    CURRENT_STAGE="$1"
    printf "\n${CYAN}${BOLD}[%s/%s] %s${RESET}\n" "$STEP_INDEX" "$STEP_TOTAL" "$CURRENT_STAGE"
    if [[ -n "${2:-}" ]]; then
        printf "${DIM}      %s${RESET}\n" "$2"
    fi
}

banner() {
    printf "\n${MAGENTA}${BOLD}"
    printf "╭──────────────────────────────────────────────────────────────╮\n"
    printf "│                      SUIVEURTAG DOTS                         │\n"
    printf "│           Serpantinum V2 + personal addons                  │\n"
    printf "╰──────────────────────────────────────────────────────────────╯"
    printf "${RESET}\n"
    printf "${DIM}Guided, repeatable, and update-resistant installation.${RESET}\n"
}

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --no-color    Disable colored output
  -h, --help    Show this help

Remote installation:
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/suiveurtag-dots/main/install.sh)"
EOF
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --local-source) LOCAL_SOURCE=true ;;
            --no-color)
                RESET=""
                BOLD=""
                DIM=""
                RED=""
                GREEN=""
                YELLOW=""
                BLUE=""
                MAGENTA=""
                CYAN=""
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1" "Use ./install.sh --help to show the available options."
                ;;
        esac
        shift
    done
}

require_command() {
    local command_name="$1"
    local install_hint="${2:-}"
    if [[ -z "$install_hint" ]]; then
        install_hint="Install the package providing this command, then rerun the installer."
    fi
    command -v "$command_name" >/dev/null 2>&1 \
        || die "Required command not found: $command_name" "$install_hint"
}

new_temp_dir() {
    CREATED_TEMP_DIR="$(mktemp -d)"
    TEMP_DIRS+=("$CREATED_TEMP_DIR")
}

script_source_dir() {
    local source_path="${BASH_SOURCE[0]:-}"
    [[ -n "$source_path" && -f "$source_path" ]] || return 1
    cd "$(dirname "$source_path")" && pwd
}

has_local_sources() {
    local source_dir="$1"
    [[ -f "$source_dir/scripts/install-addons.sh" \
        && -d "$source_dir/addons" \
        && -d "$source_dir/systemd/user" ]]
}

bootstrap_repository() {
    CURRENT_STAGE="Downloading the Suiveurtag repository"
    banner
    printf "\n${CYAN}${BOLD}[bootstrap] Downloading installer files${RESET}\n"

    require_command curl "Install curl, then copy the command from the README."
    require_command tar "Install tar, then copy the command from the README."
    require_command mktemp

    local temporary archive
    new_temp_dir
    temporary="$CREATED_TEMP_DIR"
    archive="$temporary/suiveurtag-dots.tar.gz"

    info "Downloading ${PROJECT_REPO} (main branch)…"
    if ! curl --fail --location --silent --show-error \
        --retry 3 --retry-delay 2 \
        "$PROJECT_ARCHIVE" -o "$archive"; then
        die "Unable to download the Suiveurtag repository." \
            "Check your Internet connection and access to github.com."
    fi

    info "Extracting addons into a temporary directory…"
    if ! tar -xzf "$archive" -C "$temporary"; then
        die "The downloaded archive is invalid or incomplete." \
            "Clear any broken HTTP proxy/cache, then try again."
    fi

    local extracted_candidates=("$temporary"/suiveurtag-dots-*)
    local extracted="${extracted_candidates[0]:-}"
    if [[ ! -f "$extracted/install.sh" ]]; then
        die "The downloaded repository does not contain install.sh." \
            "Check that the main branch of ${PROJECT_REPO} is available."
    fi

    success "Repository ready."
    info "Starting the full installer…"
    CURRENT_STAGE="Running the Suiveurtag installer"
    if ! bash "$extracted/install.sh" --local-source "${ORIGINAL_ARGS[@]}"; then
        die "The downloaded Suiveurtag installer failed." \
            "The exact cause was printed by the installer above."
    fi
}

distro_is_supported() {
    [[ -f /etc/os-release ]] || return 1
    local distro_id distro_like
    distro_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    distro_like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    case "$distro_id" in
        arch|endeavouros|manjaro|cachyos|parch|garuda) return 0 ;;
    esac
    [[ " $distro_like " == *" arch "* ]]
}

ensure_tor_runtime() {
    local packages=()

    command -v tor >/dev/null 2>&1 || packages+=(tor)
    command -v proxychains4 >/dev/null 2>&1 || packages+=(proxychains-ng)
    command -v bwrap >/dev/null 2>&1 || packages+=(bubblewrap)
    command -v socat >/dev/null 2>&1 || packages+=(socat)

    if ((${#packages[@]} > 0)); then
        require_command sudo "Install sudo, then rerun the installer as your normal user."
        require_command pacman "The Tor panel requires Arch Linux or an Arch-based distribution."
        info "Installing the isolated Tor runtime: ${packages[*]}"
        if ! sudo pacman -S --needed --noconfirm "${packages[@]}"; then
            die "Unable to install the Tor runtime." \
                "Install manually: sudo pacman -S --needed tor proxychains-ng bubblewrap socat"
        fi
    fi

    local command_name
    for command_name in tor proxychains4 bwrap socat; do
        command -v "$command_name" >/dev/null 2>&1 \
            || die "Tor runtime is incomplete: $command_name was not found." \
                "Install: sudo pacman -S --needed tor proxychains-ng bubblewrap socat"
    done
    success "Isolated Tor runtime is ready."
}

hypr_base_dir() {
    printf '%s\n' "${HYPR_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
}

serpantinum_home_dir() {
    printf '%s\n' "${SERPANTINUM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum}"
}

serpantinum_quickshell_dir() {
    printf '%s\n' "$(serpantinum_home_dir)/src/quickshell"
}

serpantinum_is_present() {
    local quickshell_dir
    quickshell_dir="$(serpantinum_quickshell_dir)"
    [[ -f "$quickshell_dir/Shell.qml" ]]
}

describe_missing_serpantinum() {
    local quickshell_dir
    quickshell_dir="$(serpantinum_quickshell_dir)"

    local required=(
        "$quickshell_dir/Shell.qml"
    )
    local path missing=()
    for path in "${required[@]}"; do
        [[ -f "$path" ]] || missing+=("$path")
    done
    if ((${#missing[@]} > 0)); then
        printf '%s' "${missing[*]}"
    else
        printf '%s' "Serpantinum was not found in $(serpantinum_home_dir)"
    fi
}

verify_serpantinum_present() {
    if ! serpantinum_is_present; then
        die "Serpantinum's base shell was not found." \
            "Install Serpantinum separately, then rerun this installer. Missing path: $(describe_missing_serpantinum)"
    fi
    success "Serpantinum base shell found: addons will be layered on top."
}

verify_installation() {
    local hypr_base quickshell_dir addons_dir systemd_dir
    hypr_base="$(hypr_base_dir)"
    quickshell_dir="$(serpantinum_quickshell_dir)"
    addons_dir="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons"
    systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

    [[ -f "$quickshell_dir/Shell.qml" ]] \
        || die "Serpantinum's base shell is missing after installation." "$quickshell_dir/Shell.qml"
    [[ -x "$addons_dir/apply-serpantinum-v2.py" ]] \
        || die "The Serpantinum V2 integration script was not installed correctly." "$addons_dir/apply-serpantinum-v2.py is missing."
    [[ -x "$HOME/.local/bin/cycle-mouse-monitor" ]] \
        || die "The monitor-switch shortcut was not installed." "$HOME/.local/bin/cycle-mouse-monitor is missing."
    [[ -x "$addons_dir/tor-panel/tor_panelctl.py" ]] \
        || die "The Tor panel backend was not installed correctly." "$addons_dir/tor-panel/tor_panelctl.py is missing."
    [[ -f "$systemd_dir/tor-panel-tor.service" ]] \
        || die "The user Tor service was not installed." "$systemd_dir/tor-panel-tor.service is missing."

    if [[ -n "${XDG_RUNTIME_DIR:-}" ]] && command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-enabled serpantinum-addons.path >/dev/null 2>&1; then
            success "Serpantinum V2 watcher is enabled."
        else
            warn "Files are installed, but the Serpantinum V2 watcher is not enabled yet."
        fi
    else
        warn "User systemd session unavailable: watchers will activate after graphical login."
    fi

    if command -v hyprctl >/dev/null 2>&1 && hyprctl monitors >/dev/null 2>&1; then
        local config_errors border_state animation_state layout_state
        config_errors="$(hyprctl configerrors 2>/dev/null || true)"
        [[ -z "$config_errors" ]] \
            || die "Hyprland reports an error in the generated configuration." "$config_errors"

        border_state="$(hyprctl getoption general:border_size -j 2>/dev/null || true)"
        animation_state="$(hyprctl getoption animations:enabled -j 2>/dev/null || true)"
        layout_state="$(hyprctl getoption input:kb_layout -j 2>/dev/null || true)"
        if grep -Eq '"set":[[:space:]]*true' <<<"$border_state" \
            && grep -Eq '"set":[[:space:]]*true' <<<"$animation_state" \
            && grep -Eq '"set":[[:space:]]*true' <<<"$layout_state"; then
            success "Hyprland borders, animations, and keyboard layouts are loaded."
        else
            die "Hyprland is running but did not load the generated settings." \
                "Run hyprctl reload, then check the Lua configuration under $hypr_base/config/"
        fi
    else
        warn "Hyprland is not reachable: settings will be checked at the next session."
    fi

    if pgrep -x quickshell >/dev/null 2>&1; then
        success "Quickshell is running and the configuration was reloaded."
    else
        warn "Quickshell is not running yet. It will start with the next Hyprland session."
    fi
}

main() {
    parse_args "$@"

    local source_dir=""
    source_dir="$(script_source_dir 2>/dev/null || true)"
    if [[ "$LOCAL_SOURCE" != true ]] && ! has_local_sources "$source_dir"; then
        bootstrap_repository
        return
    fi
    if ! has_local_sources "$source_dir"; then
        die "The local repository sources are incomplete." \
            "Clone ${PROJECT_REPO}, then run ./install.sh from its root."
    fi

    banner

    step "Checking the environment" "Distribution, user, and required commands"
    [[ "$(id -u)" -ne 0 ]] \
        || die "Do not run this installer as root." "Run it as your normal user; sudo is requested only when needed."
    distro_is_supported \
        || die "Distribution is not supported by Serpantinum V2." \
            "Use Arch Linux or a compatible derivative: EndeavourOS, Manjaro, CachyOS, Parch, or Garuda."
    require_command bash
    require_command curl "Install curl with: sudo pacman -S --needed curl"
    require_command mktemp
    success "Compatible environment detected."

    step "Checking the Serpantinum base shell" "Addons will be layered onto the existing shell"
    verify_serpantinum_present

    step "Preparing Suiveurtag addons" "Dependencies, components, and systemd units"
    info "Local sources: $source_dir"
    ensure_tor_runtime
    success "Sources verified."

    step "Applying and enabling addons" "Idempotent patches, settings, keybinds, and watchers"
    local core_installer="$source_dir/scripts/install-addons.sh"
    if ! bash "$core_installer"; then
        die "One or more addons could not be applied." \
            "The exact details are shown above. Fix the reported file or dependency, then rerun the same command."
    fi
    success "All addons were applied."

    step "Final verification" "Checking files, watchers, and Quickshell"
    verify_installation

    printf "\n${GREEN}${BOLD}╭──────────────────────────────────────────────────────────────╮\n"
    printf "│                    INSTALLATION COMPLETE                    │\n"
    printf "╰──────────────────────────────────────────────────────────────╯${RESET}\n"
    printf "${BOLD}Serpantinum V2 and the Suiveurtag addons are ready.${RESET}\n"
    printf "${DIM}You can rerun the same command to update the addons.${RESET}\n\n"
}

main "$@"
