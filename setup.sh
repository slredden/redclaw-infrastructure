#!/usr/bin/env bash
# setup.sh — Non-interactive infrastructure setup orchestrator
# Reads config/system.conf and applies changes. No prompts. Safe to run unattended.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse CLI flags ────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --force)   export FORCE=true ;;
        --dry-run) export DRY_RUN=true ;;
        --help|-h)
            echo "Usage: sudo ./setup.sh [--force] [--dry-run]"
            echo "  --force    Ignore sentinels and re-run all modules"
            echo "  --dry-run  Show what would run without executing"
            exit 0
            ;;
        *)
            echo "Unknown flag: $arg" >&2
            exit 1
            ;;
    esac
done

# ── Source shared library and config ───────────────────────────────────
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
require_ubuntu_2404
load_config

echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Infrastructure Setup${NC}"
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}  DRY RUN — no changes will be made${NC}"
fi
if [[ "$FORCE" == "true" ]]; then
    echo -e "${YELLOW}  FORCE — ignoring sentinels${NC}"
fi
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo

# ── Run modules in order ──────────────────────────────────────────────
LIB_DIR="$SCRIPT_DIR/lib"

run_module "system-base"       "$LIB_DIR/01-system-base.sh"
run_module "firewall"          "$LIB_DIR/02-firewall.sh"          "INSTALL_FIREWALL"
run_module "remote-desktop"    "$LIB_DIR/03-remote-desktop.sh"
run_module "tailscale"         "$LIB_DIR/04-tailscale.sh"         "INSTALL_TAILSCALE"
run_module "openclaw-prereqs"  "$LIB_DIR/05-openclaw-prereqs.sh"  "INSTALL_OPENCLAW_PREREQS"

# ── Summary ────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Summary${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"

if [[ "$DRY_RUN" == "true" ]]; then
    if [[ ${#MODULES_PLANNED[@]} -gt 0 ]]; then
        echo -e "  ${BLUE}Would run:${NC}  ${MODULES_PLANNED[*]}"
    fi
else
    if [[ ${#MODULES_RAN[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}Ran:${NC}      ${MODULES_RAN[*]}"
    fi
fi

if [[ ${#MODULES_SKIPPED[@]} -gt 0 ]]; then
    echo -e "  ${YELLOW}Skipped:${NC}  ${MODULES_SKIPPED[*]}"
fi

if [[ "$REBOOT_NEEDED" == "true" ]]; then
    echo
    echo -e "  ${RED}${BOLD}A reboot is recommended.${NC} Run: sudo reboot"
fi

echo
log_info "Done."
