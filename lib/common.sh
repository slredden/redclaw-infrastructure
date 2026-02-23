#!/usr/bin/env bash
# lib/common.sh — Shared functions for infrastructure setup scripts
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
CONFIG_DIR="$PROJECT_DIR/config"
SENTINEL_PREFIX="/etc/infrastructure-done"

# ── Colors ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' YELLOW='' GREEN='' BLUE='' BOLD='' NC=''
fi

# ── Logging ────────────────────────────────────────────────────────────
log_info()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" >&2; }

# ── Preconditions ──────────────────────────────────────────────────────
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)."
        exit 1
    fi
}

require_ubuntu_2404() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS — /etc/os-release not found."
        exit 1
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || ! "${VERSION_ID:-}" =~ ^24\.04 ]]; then
        log_error "This script requires Ubuntu 24.04 LTS. Detected: ${PRETTY_NAME:-unknown}"
        exit 1
    fi
}

# ── Sentinels (idempotency) ────────────────────────────────────────────
sentinel_file() { echo "${SENTINEL_PREFIX}-${1}"; }

sentinel_check() {
    local name="$1"
    [[ -f "$(sentinel_file "$name")" ]]
}

sentinel_set() {
    local name="$1"
    date '+%Y-%m-%dT%H:%M:%S' > "$(sentinel_file "$name")"
    log_info "Sentinel set: $name"
}

# ── Package management ─────────────────────────────────────────────────
is_pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

ensure_pkg() {
    local to_install=()
    for pkg in "$@"; do
        if ! is_pkg_installed "$pkg"; then
            to_install+=("$pkg")
        fi
    done
    if [[ ${#to_install[@]} -gt 0 ]]; then
        log_info "Installing: ${to_install[*]}"
        apt-get install -y "${to_install[@]}"
    fi
}

# ── File backup ────────────────────────────────────────────────────────
backup_config() {
    local filepath="$1"
    if [[ -f "$filepath" ]]; then
        local backup="${filepath}.bak.$(date '+%Y%m%d-%H%M%S')"
        cp "$filepath" "$backup"
        log_info "Backed up $filepath → $backup"
    fi
}

# ── Interactive prompts (for configure.sh) ─────────────────────────────
confirm() {
    local message="${1:-Continue?}"
    local default="${2:-n}"
    local prompt suffix
    if [[ "$default" =~ ^[Yy] ]]; then
        suffix="[Y/n]"
    else
        suffix="[y/N]"
    fi
    prompt="${BOLD}${message} ${suffix}${NC} "
    echo -en "$prompt"
    read -r answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

prompt_value() {
    local message="$1"
    local default="$2"
    local result
    echo -en "${BOLD}${message}${NC} [${default}]: "
    read -r result
    echo "${result:-$default}"
}

prompt_password() {
    local message="$1"
    local result
    echo -en "${BOLD}${message}${NC}: "
    read -rs result
    echo
    echo "$result"
}

# ── Configuration ──────────────────────────────────────────────────────
load_config() {
    local config_file="${CONFIG_DIR}/system.conf"
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration not found: $config_file"
        log_error "Run ./configure.sh first to generate configuration."
        exit 1
    fi
    log_info "Loading configuration from $config_file"
    # shellcheck source=/dev/null
    source "$config_file"
}

load_defaults() {
    local defaults_file="${CONFIG_DIR}/defaults.conf"
    if [[ ! -f "$defaults_file" ]]; then
        log_error "Defaults file not found: $defaults_file"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$defaults_file"
}

# ── DRY_RUN support ───────────────────────────────────────────────────
# When DRY_RUN=true, modules can check this before making changes.
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"

run_module() {
    local name="$1"
    local script="$2"
    local skip_var="${3:-}"

    # Check if module is disabled in config
    if [[ -n "$skip_var" && "${!skip_var:-true}" == "false" ]]; then
        log_info "Module $name: skipped (disabled in config)"
        MODULES_SKIPPED+=("$name (disabled)")
        return 0
    fi

    # Check sentinel
    if [[ "$FORCE" != "true" ]] && sentinel_check "$name"; then
        log_info "Module $name: skipped (already completed)"
        MODULES_SKIPPED+=("$name (already done)")
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Module $name: would run (dry-run)"
        MODULES_PLANNED+=("$name")
        return 0
    fi

    log_info "Module $name: running..."
    # shellcheck source=/dev/null
    source "$script"
    sentinel_set "$name"
    MODULES_RAN+=("$name")
}

# Tracking arrays for summary
MODULES_RAN=()
MODULES_SKIPPED=()
MODULES_PLANNED=()
REBOOT_NEEDED=false
