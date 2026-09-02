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
    printf "\n${RED}${BOLD}✗ Installation interrompue${RESET}\n" >&2
    printf "${RED}  Étape :${RESET} %s\n" "$CURRENT_STAGE" >&2
    printf "${RED}  Cause :${RESET} la commande a retourné le code %s\n" "$exit_code" >&2
    printf "${RED}  Ligne :${RESET} %s\n" "$line_number" >&2
    printf "${RED}  Commande :${RESET} %s\n" "$command" >&2
    printf "${DIM}  Le message détaillé du programme fautif se trouve juste au-dessus.${RESET}\n" >&2
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
    printf "${RED}  Étape :${RESET} %s\n" "$CURRENT_STAGE" >&2
    if [[ -n "$hint" ]]; then
        printf "${YELLOW}  Solution :${RESET} %s\n" "$hint" >&2
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
    printf "│          Serpantinum V2 + addons personnels                 │\n"
    printf "╰──────────────────────────────────────────────────────────────╯"
    printf "${RESET}\n"
    printf "${DIM}Installation guidée, relançable et résistante aux mises à jour.${RESET}\n"
}

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --no-color    Désactiver les couleurs
  -h, --help    Afficher cette aide

Installation distante:
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
                die "Option inconnue : $1" "Utilise ./install.sh --help pour afficher les options disponibles."
                ;;
        esac
        shift
    done
}

require_command() {
    local command_name="$1"
    local install_hint="${2:-}"
    if [[ -z "$install_hint" ]]; then
        install_hint="Installe le paquet qui fournit cette commande puis relance l'installation."
    fi
    command -v "$command_name" >/dev/null 2>&1 \
        || die "Commande requise introuvable : $command_name" "$install_hint"
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
    CURRENT_STAGE="Téléchargement du dépôt Suiveurtag"
    banner
    printf "\n${CYAN}${BOLD}[bootstrap] Récupération des fichiers d'installation${RESET}\n"

    require_command curl "Installe curl, puis recopie la commande du README."
    require_command tar "Installe tar, puis recopie la commande du README."
    require_command mktemp

    local temporary archive
    new_temp_dir
    temporary="$CREATED_TEMP_DIR"
    archive="$temporary/suiveurtag-dots.tar.gz"

    info "Téléchargement de ${PROJECT_REPO} (branche main)…"
    if ! curl --fail --location --silent --show-error \
        --retry 3 --retry-delay 2 \
        "$PROJECT_ARCHIVE" -o "$archive"; then
        die "Impossible de télécharger le dépôt Suiveurtag." \
            "Vérifie la connexion Internet et l'accès à github.com."
    fi

    info "Extraction des addons dans un dossier temporaire…"
    if ! tar -xzf "$archive" -C "$temporary"; then
        die "L'archive téléchargée est invalide ou incomplète." \
            "Supprime tout proxy/cache HTTP défectueux puis réessaie."
    fi

    local extracted_candidates=("$temporary"/suiveurtag-dots-*)
    local extracted="${extracted_candidates[0]:-}"
    if [[ ! -f "$extracted/install.sh" ]]; then
        die "Le dépôt téléchargé ne contient pas install.sh." \
            "Vérifie que la branche main de ${PROJECT_REPO} est disponible."
    fi

    success "Dépôt prêt."
    info "Passage à l'installateur complet…"
    CURRENT_STAGE="Exécution de l'installateur Suiveurtag"
    if ! bash "$extracted/install.sh" --local-source "${ORIGINAL_ARGS[@]}"; then
        die "L'installateur Suiveurtag téléchargé s'est terminé avec une erreur." \
            "La cause exacte a été affichée par l'installateur juste au-dessus."
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
        require_command sudo "Installe sudo, puis relance l'installation avec ton utilisateur normal."
        require_command pacman "Le panel Tor nécessite Arch Linux ou un dérivé utilisant pacman."
        info "Installation du runtime Tor isolé : ${packages[*]}"
        if ! sudo pacman -S --needed --noconfirm "${packages[@]}"; then
            die "Impossible d'installer le runtime du panel Tor." \
                "Installe manuellement : sudo pacman -S --needed tor proxychains-ng bubblewrap socat"
        fi
    fi

    local command_name
    for command_name in tor proxychains4 bwrap socat; do
        command -v "$command_name" >/dev/null 2>&1 \
            || die "Runtime Tor incomplet : $command_name est introuvable." \
                "Installe : sudo pacman -S --needed tor proxychains-ng bubblewrap socat"
    done
    success "Runtime Tor isolé prêt."
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

serpantinum_is_ready() {
    local quickshell_dir
    quickshell_dir="$(serpantinum_quickshell_dir)"
    [[ -f "$quickshell_dir/Shell.qml" \
        && -f "$quickshell_dir/Main.qml" \
        && -f "$quickshell_dir/WindowRegistry.js" \
        && -f "$quickshell_dir/wallpaper/WallpaperPicker.qml" \
        && -f "$quickshell_dir/syspanel/SystemPanel.qml" \
        && -f "$quickshell_dir/settings/SettingsPopup.qml" ]]
}

describe_missing_serpantinum() {
    local quickshell_dir
    quickshell_dir="$(serpantinum_quickshell_dir)"

    local required=(
        "$quickshell_dir/Shell.qml"
        "$quickshell_dir/Main.qml"
        "$quickshell_dir/WindowRegistry.js"
        "$quickshell_dir/wallpaper/WallpaperPicker.qml"
        "$quickshell_dir/syspanel/SystemPanel.qml"
        "$quickshell_dir/settings/SettingsPopup.qml"
    )
    local path missing=()
    for path in "${required[@]}"; do
        [[ -f "$path" ]] || missing+=("$path")
    done
    if ((${#missing[@]} > 0)); then
        printf '%s' "${missing[*]}"
    else
        printf '%s' "Serpantinum V2 n'est pas installé dans $(serpantinum_home_dir)"
    fi
}

verify_serpantinum_installation() {
    if ! serpantinum_is_ready; then
        die "Serpantinum V2 est absent ou incomplet." \
            "Installe d'abord la dernière release Serpantinum, puis relance : fichiers manquants : $(describe_missing_serpantinum)"
    fi
    success "Serpantinum V2 déjà installé : les addons seront appliqués par-dessus."
}

verify_installation() {
    local hypr_base quickshell_dir addons_dir systemd_dir
    hypr_base="$(hypr_base_dir)"
    quickshell_dir="$(serpantinum_quickshell_dir)"
    addons_dir="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons"
    systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

    [[ -f "$quickshell_dir/Shell.qml" && -f "$quickshell_dir/Main.qml" ]] \
        || die "Le shell Serpantinum V2 est introuvable après installation." "$quickshell_dir"
    [[ -x "$addons_dir/apply-serpantinum-v2.py" ]] \
        || die "L'intégrateur Serpantinum V2 n'a pas été copié correctement." "$addons_dir/apply-serpantinum-v2.py est absent."
    [[ -x "$HOME/.local/bin/cycle-mouse-monitor" ]] \
        || die "Le raccourci de changement d'écran n'a pas été installé." "$HOME/.local/bin/cycle-mouse-monitor est absent."
    [[ -x "$addons_dir/tor-panel/tor_panelctl.py" ]] \
        || die "Le backend du panel Tor n'a pas été copié correctement." "$addons_dir/tor-panel/tor_panelctl.py est absent."
    [[ -f "$systemd_dir/tor-panel-tor.service" ]] \
        || die "Le service Tor utilisateur n'a pas été installé." "$systemd_dir/tor-panel-tor.service est absent."

    if [[ -n "${XDG_RUNTIME_DIR:-}" ]] && command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-enabled serpantinum-addons.path >/dev/null 2>&1; then
            success "Watcher Serpantinum V2 activé."
        else
            warn "Les fichiers sont installés, mais le watcher Serpantinum V2 n'est pas encore activé."
        fi
    else
        warn "Session systemd utilisateur indisponible : les watchers s'activeront après connexion graphique."
    fi

    if command -v hyprctl >/dev/null 2>&1 && hyprctl monitors >/dev/null 2>&1; then
        local config_errors border_state animation_state layout_state
        config_errors="$(hyprctl configerrors 2>/dev/null || true)"
        [[ -z "$config_errors" ]] \
            || die "Hyprland signale une erreur dans la configuration générée." "$config_errors"

        border_state="$(hyprctl getoption general:border_size -j 2>/dev/null || true)"
        animation_state="$(hyprctl getoption animations:enabled -j 2>/dev/null || true)"
        layout_state="$(hyprctl getoption input:kb_layout -j 2>/dev/null || true)"
        if grep -Eq '"set":[[:space:]]*true' <<<"$border_state" \
            && grep -Eq '"set":[[:space:]]*true' <<<"$animation_state" \
            && grep -Eq '"set":[[:space:]]*true' <<<"$layout_state"; then
            success "Bordures, animations et layouts clavier chargés par Hyprland."
        else
            die "Hyprland est lancé, mais n'a pas chargé les réglages générés." \
                "Relance avec hyprctl reload, puis vérifie la configuration Lua sous $hypr_base/config/"
        fi
    else
        warn "Hyprland n'est pas joignable : les réglages seront contrôlés à la prochaine session."
    fi

    if pgrep -x quickshell >/dev/null 2>&1; then
        success "Quickshell est lancé et la configuration a été rechargée."
    else
        warn "Quickshell n'est pas encore lancé. Il démarrera avec la prochaine session Hyprland."
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
        die "Les sources locales du dépôt sont incomplètes." \
            "Clone ${PROJECT_REPO}, puis exécute ./install.sh depuis sa racine."
    fi

    banner

    step "Vérification de l'environnement" "Distribution, utilisateur et commandes indispensables"
    [[ "$(id -u)" -ne 0 ]] \
        || die "Ne lance pas cet installateur en root." "Exécute-le avec ton utilisateur normal ; sudo sera demandé uniquement si nécessaire."
    distro_is_supported \
        || die "Distribution non prise en charge par Serpantinum V2." \
            "Utilise Arch Linux ou un dérivé compatible : EndeavourOS, Manjaro, CachyOS, Parch ou Garuda."
    require_command bash
    require_command curl "Installe curl avec : sudo pacman -S --needed curl"
    require_command mktemp
    success "Environnement compatible."

    step "Vérification de Serpantinum V2" "La dernière release doit déjà être installée"
    verify_serpantinum_installation

    step "Préparation des addons Suiveurtag" "Dépendances, composants et unités systemd"
    info "Sources locales : $source_dir"
    ensure_tor_runtime
    success "Sources vérifiées."

    step "Application et activation" "Patches idempotents, réglages, keybinds et watchers"
    local core_installer="$source_dir/scripts/install-addons.sh"
    if ! bash "$core_installer"; then
        die "Un ou plusieurs addons n'ont pas pu être appliqués." \
            "Le détail exact est affiché juste au-dessus. Corrige le fichier ou la dépendance signalée puis relance la même commande."
    fi
    success "Tous les addons ont été appliqués."

    step "Vérification finale" "Contrôle des fichiers, watchers et de Quickshell"
    verify_installation

    printf "\n${GREEN}${BOLD}╭──────────────────────────────────────────────────────────────╮\n"
    printf "│                    INSTALLATION TERMINÉE                     │\n"
    printf "╰──────────────────────────────────────────────────────────────╯${RESET}\n"
    printf "${BOLD}Serpantinum V2 et les addons Suiveurtag sont prêts.${RESET}\n"
    printf "${DIM}Tu peux relancer exactement la même commande pour mettre les addons à jour.${RESET}\n\n"
}

main "$@"
