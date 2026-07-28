#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_NAME="Suiveurtag Dots"
readonly PROJECT_REPO="${SUIVEURTAG_PROJECT_REPO:-https://github.com/Suiveurtag/suiveurtag-dots}"
readonly PROJECT_ARCHIVE="${SUIVEURTAG_PROJECT_ARCHIVE:-${PROJECT_REPO}/archive/refs/heads/main.tar.gz}"
readonly ILYAMIRO_REPO="${SUIVEURTAG_ILYAMIRO_REPO:-https://github.com/ilyamiro/imperative-dots}"
readonly ILYAMIRO_INSTALL_URL="${SUIVEURTAG_ILYAMIRO_INSTALL_URL:-https://raw.githubusercontent.com/ilyamiro/imperative-dots/master/install.sh}"

CURRENT_STAGE="Initialisation"
STEP_INDEX=0
STEP_TOTAL=5
FORCE_DOTS=false
SKIP_DOTS=false
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
    printf "│        ilyamiro imperative-dots + addons personnels          │\n"
    printf "╰──────────────────────────────────────────────────────────────╯"
    printf "${RESET}\n"
    printf "${DIM}Installation guidée, relançable et résistante aux mises à jour.${RESET}\n"
}

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --force-dots  Relancer l'installateur ilyamiro même si les dots sont présents
  --skip-dots   Ne pas lancer l'installateur ilyamiro
  --no-color    Désactiver les couleurs
  -h, --help    Afficher cette aide

Installation distante:
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/suiveurtag-dots/main/install.sh)"
EOF
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --force-dots) FORCE_DOTS=true ;;
            --skip-dots) SKIP_DOTS=true ;;
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

    if [[ "$FORCE_DOTS" == true && "$SKIP_DOTS" == true ]]; then
        die "Les options --force-dots et --skip-dots sont incompatibles."
    fi
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

hypr_base_dir() {
    printf '%s\n' "${HYPR_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
}

quickshell_dir_for() {
    local hypr_base="$1"
    if [[ -n "${HYPR_QUICKSHELL_DIR:-}" ]]; then
        printf '%s\n' "$HYPR_QUICKSHELL_DIR"
    elif [[ -f "$hypr_base/scripts/quickshell/WindowRegistry.js" ]]; then
        printf '%s\n' "$hypr_base/scripts/quickshell"
    elif [[ -f "$hypr_base/hypr/scripts/quickshell/WindowRegistry.js" ]]; then
        printf '%s\n' "$hypr_base/hypr/scripts/quickshell"
    else
        printf '%s\n' "$hypr_base/scripts/quickshell"
    fi
}

dots_are_ready() {
    local hypr_base quickshell_dir
    hypr_base="$(hypr_base_dir)"
    quickshell_dir="$(quickshell_dir_for "$hypr_base")"

    [[ -f "$hypr_base/settings.json" \
        && -f "$hypr_base/scripts/qs_manager.sh" \
        && -f "$quickshell_dir/WindowRegistry.js" \
        && -f "$quickshell_dir/TopBar.qml" ]] || return 1

    if [[ -f "$hypr_base/hyprland.conf" ]] \
        && grep -q 'autogenerated = 1' "$hypr_base/hyprland.conf"; then
        return 1
    fi
}

describe_missing_dots() {
    local hypr_base quickshell_dir
    hypr_base="$(hypr_base_dir)"
    quickshell_dir="$(quickshell_dir_for "$hypr_base")"

    local required=(
        "$hypr_base/settings.json"
        "$hypr_base/scripts/qs_manager.sh"
        "$quickshell_dir/WindowRegistry.js"
        "$quickshell_dir/TopBar.qml"
    )
    local path missing=()
    for path in "${required[@]}"; do
        [[ -f "$path" ]] || missing+=("$path")
    done
    if ((${#missing[@]} > 0)); then
        printf '%s' "${missing[*]}"
    else
        printf '%s' "$hypr_base/hyprland.conf est encore une configuration Hyprland auto-générée"
    fi
}

install_ilyamiro_dots() {
    if [[ "$SKIP_DOTS" == true ]]; then
        warn "Installation des dots ignorée à la demande (--skip-dots)."
        return 0
    fi

    if dots_are_ready && [[ "$FORCE_DOTS" != true ]]; then
        success "Dots ilyamiro déjà fonctionnels, aucune réinstallation nécessaire."
        info "Utilise --force-dots pour relancer volontairement l'installateur amont."
        return 0
    fi

    require_command curl "Installe curl avec pacman, puis relance cette commande."

    local temporary upstream_script
    new_temp_dir
    temporary="$CREATED_TEMP_DIR"
    upstream_script="$temporary/ilyamiro-install.sh"

    info "Téléchargement de l'installateur officiel ilyamiro…"
    info "L'installateur amont est interactif et peut demander sudo."
    warn "L'installateur ilyamiro annonce une télémétrie anonyme dans son README."

    if ! curl --fail --location --silent --show-error \
        --retry 3 --retry-delay 2 \
        "$ILYAMIRO_INSTALL_URL" -o "$upstream_script"; then
        die "Impossible de télécharger l'installateur ilyamiro." \
            "Vérifie la connexion Internet et l'accès à raw.githubusercontent.com."
    fi

    chmod +x "$upstream_script"
    info "Démarrage de l'interface officielle ilyamiro (${ILYAMIRO_REPO})…"
    if ! bash "$upstream_script"; then
        die "L'installateur ilyamiro s'est terminé avec une erreur." \
            "Lis son dernier message ci-dessus : paquet en échec, sudo refusé ou étape annulée."
    fi

    if ! dots_are_ready; then
        die "L'installateur ilyamiro s'est terminé, mais les fichiers nécessaires sont absents." \
            "Fichiers/état manquants : $(describe_missing_dots)"
    fi

    success "Dots ilyamiro installés et prêts."
}

verify_installation() {
    local hypr_base quickshell_dir addons_dir
    hypr_base="$(hypr_base_dir)"
    quickshell_dir="$(quickshell_dir_for "$hypr_base")"
    addons_dir="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-addons"

    [[ -f "$quickshell_dir/TopBar.qml" ]] \
        || die "La TopBar Quickshell est absente après installation." "$quickshell_dir/TopBar.qml"
    [[ -x "$addons_dir/topbar-button-effects/apply.sh" ]] \
        || die "Les addons n'ont pas été copiés correctement." "$addons_dir/topbar-button-effects/apply.sh est absent."

    if [[ -n "${XDG_RUNTIME_DIR:-}" ]] && command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-enabled topbar-button-effects-addon.path >/dev/null 2>&1; then
            success "Watchers systemd activés."
        else
            warn "Les fichiers sont installés, mais les watchers systemd ne sont pas encore activés."
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
                "Relance avec hyprctl reload, puis vérifie : $hypr_base/hyprland.conf"
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
        || die "Distribution non prise en charge par les dots ilyamiro." \
            "Utilise Arch Linux ou un dérivé compatible : EndeavourOS, Manjaro, CachyOS, Parch ou Garuda."
    require_command bash
    require_command curl "Installe curl avec : sudo pacman -S --needed curl"
    require_command mktemp
    success "Environnement compatible."

    step "Installation des dots ilyamiro" "Cette étape est ignorée automatiquement si les dots sont déjà présents"
    install_ilyamiro_dots

    step "Préparation des addons Suiveurtag" "Copie des composants et unités systemd"
    info "Sources locales : $source_dir"
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
    printf "${BOLD}Les dots ilyamiro et les addons Suiveurtag sont prêts.${RESET}\n"
    printf "${DIM}Tu peux relancer exactement la même commande pour mettre les addons à jour.${RESET}\n\n"
}

main "$@"
