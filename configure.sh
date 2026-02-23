#!/usr/bin/env bash
# configure.sh — Interactive configuration for infrastructure setup
# Detects current system state, asks questions, writes config/system.conf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared libraries
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"

require_root

echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Infrastructure Setup — Configuration${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo

# Load defaults as starting values
load_defaults
log_info "Loaded defaults from config/defaults.conf"

# ── Detect current system state ────────────────────────────────────────
echo
echo -e "${BLUE}Detecting current system state...${NC}"

CURRENT_DM="$(detect_display_manager)"
log_info "Display manager: $CURRENT_DM"

CURRENT_SESSIONS="$(detect_desktop_environment)"
log_info "Desktop sessions: $(echo "$CURRENT_SESSIONS" | tr '\n' ' ')"

RDP_STATE="$(detect_rdp_service)"
log_info "RDP state: $(echo "$RDP_STATE" | tr '\n' ', ')"

FW_STATE="$(detect_firewall)"
log_info "Firewall: $(echo "$FW_STATE" | head -2 | tr '\n' ', ')"

TS_STATE="$(detect_tailscale)"
log_info "Tailscale: $(echo "$TS_STATE" | tr '\n' ', ')"

NODE_STATE="$(detect_node)"
log_info "Node.js: $(echo "$NODE_STATE" | tr '\n' ', ')"

SENTINELS="$(detect_existing_sentinels)"
if [[ "$SENTINELS" != "none" ]]; then
    log_info "Previous runs detected:"
    echo "$SENTINELS" | while read -r line; do echo "  - $line"; done
fi

# ── System Base ────────────────────────────────────────────────────────
echo
echo -e "${BOLD}── System Base ──${NC}"

current_tz="$(timedatectl show -p Timezone --value 2>/dev/null || echo "unknown")"
if [[ "$current_tz" != "$TIMEZONE" ]]; then
    log_info "Current timezone: $current_tz (default: $TIMEZONE)"
fi
TIMEZONE="$(prompt_value "Timezone" "$TIMEZONE")"

DEFAULT_USER="$(prompt_value "Default (non-root) user" "$DEFAULT_USER")"

# ── Firewall ───────────────────────────────────────────────────────────
echo
echo -e "${BOLD}── Firewall ──${NC}"

# Parse firewall state
eval "$(echo "$FW_STATE" | grep -E '^ufw_(installed|active)=')"

if [[ "${ufw_active:-false}" == "true" ]]; then
    log_info "UFW is already active with these rules:"
    echo "$FW_STATE" | sed -n '/---UFW-RULES---/,/---END-RULES---/{ /---/d; p; }'
    if confirm "Reconfigure firewall rules?" "n"; then
        INSTALL_FIREWALL=true
    else
        INSTALL_FIREWALL=false
    fi
else
    if confirm "Install and configure UFW firewall?" "y"; then
        INSTALL_FIREWALL=true
    else
        INSTALL_FIREWALL=false
    fi
fi

if [[ "$INSTALL_FIREWALL" == "true" ]]; then
    LOCAL_NETWORK="$(prompt_value "Local network CIDR (for RDP access)" "$LOCAL_NETWORK")"
    TAILSCALE_SUBNET="$(prompt_value "Tailscale subnet CIDR (for RDP access)" "$TAILSCALE_SUBNET")"
fi

# ── Remote Desktop ─────────────────────────────────────────────────────
echo
echo -e "${BOLD}── Remote Desktop ──${NC}"

# Parse RDP state
eval "$(echo "$RDP_STATE" | grep -E '^(xrdp_installed|xrdp_active|grd_enabled)=')"

if [[ "${xrdp_installed:-false}" == "true" ]]; then
    if [[ "${xrdp_active:-false}" == "true" ]]; then
        log_warn "xrdp is installed and active."
    else
        log_info "xrdp is installed but not running."
    fi
    echo "  GNOME Remote Desktop (GRD) shares the console session natively over RDP,"
    echo "  allowing simultaneous console and remote use — unlike xrdp."
    if confirm "Remove xrdp and switch to GNOME Remote Desktop?" "y"; then
        REMOVE_XRDP=true
    else
        REMOVE_XRDP=false
    fi
else
    REMOVE_XRDP=false
    log_info "xrdp not installed."
fi

if [[ "$CURRENT_DM" == "lightdm" ]]; then
    log_info "LightDM detected. GDM3 is required for GNOME Remote Desktop."
    if confirm "Remove LightDM and switch to GDM3?" "y"; then
        REMOVE_LIGHTDM=true
    else
        REMOVE_LIGHTDM=false
    fi
elif [[ "$CURRENT_DM" == "gdm3" ]]; then
    REMOVE_LIGHTDM=false
    log_info "GDM3 already active."
else
    REMOVE_LIGHTDM=false
fi

if [[ "${grd_enabled:-false}" == "true" ]]; then
    log_info "GNOME Remote Desktop appears to be configured already."
    if ! confirm "Reconfigure GRD credentials?" "n"; then
        RDP_USER=""
        RDP_PASSWORD=""
    fi
fi

if [[ -z "${RDP_USER:-}" ]]; then
    echo
    echo "  RDP credentials for GNOME Remote Desktop:"
    RDP_USER="$(prompt_value "RDP username" "$DEFAULT_USER")"
    RDP_PASSWORD="$(prompt_password "RDP password")"
    if [[ -z "$RDP_PASSWORD" ]]; then
        log_error "RDP password cannot be empty."
        exit 1
    fi
fi

RDP_MODE="$(prompt_value "RDP mode (console or headless)" "$RDP_MODE")"

GNOME_SESSION="$(prompt_value "GNOME session (ubuntu or ubuntu-xorg)" "$GNOME_SESSION")"

# ── Tailscale ──────────────────────────────────────────────────────────
echo
echo -e "${BOLD}── Tailscale ──${NC}"

eval "$(echo "$TS_STATE" | grep -E '^tailscale_(installed|connected|ip)=')"

if [[ "${tailscale_installed:-false}" == "true" ]]; then
    if [[ "${tailscale_connected:-false}" == "true" ]]; then
        log_info "Tailscale is installed and connected (IP: ${tailscale_ip:-unknown})."
        INSTALL_TAILSCALE=false
    else
        log_info "Tailscale is installed but not connected."
        INSTALL_TAILSCALE=true
    fi
else
    if confirm "Install Tailscale VPN?" "y"; then
        INSTALL_TAILSCALE=true
    else
        INSTALL_TAILSCALE=false
    fi
fi

# ── Openclaw Prerequisites ─────────────────────────────────────────────
echo
echo -e "${BOLD}── Openclaw Prerequisites ──${NC}"

eval "$(echo "$NODE_STATE" | grep -E '^(node_installed|node_version|openclaw_installed|openclaw_version)=')"

if [[ "${node_installed:-false}" == "true" ]]; then
    log_info "Node.js: ${node_version:-unknown}"
fi
if [[ "${openclaw_installed:-false}" == "true" ]]; then
    log_info "Openclaw: ${openclaw_version:-unknown}"
fi

if [[ "${node_installed:-false}" == "true" && "${openclaw_installed:-false}" == "true" ]]; then
    if confirm "Node.js and Openclaw already installed. Reinstall/update?" "n"; then
        INSTALL_OPENCLAW_PREREQS=true
    else
        INSTALL_OPENCLAW_PREREQS=false
    fi
else
    if confirm "Install Node.js 22+ and Openclaw?" "y"; then
        INSTALL_OPENCLAW_PREREQS=true
    else
        INSTALL_OPENCLAW_PREREQS=false
    fi
fi

# ── Write config/system.conf ──────────────────────────────────────────
echo
log_info "Writing configuration..."

cat > "$CONFIG_DIR/system.conf" << CONF
# config/system.conf — Generated by configure.sh on $(date '+%Y-%m-%d %H:%M:%S')
# Machine-specific configuration. Do not commit to git.

# System base
TIMEZONE="$TIMEZONE"
DEFAULT_USER="$DEFAULT_USER"

# Firewall
INSTALL_FIREWALL=$INSTALL_FIREWALL
LOCAL_NETWORK="$LOCAL_NETWORK"
TAILSCALE_SUBNET="$TAILSCALE_SUBNET"

# Remote desktop
REMOVE_XRDP=$REMOVE_XRDP
REMOVE_LIGHTDM=$REMOVE_LIGHTDM
GNOME_SESSION="$GNOME_SESSION"
RDP_MODE="$RDP_MODE"
RDP_USER="$RDP_USER"
RDP_PASSWORD="$RDP_PASSWORD"

# Tailscale
INSTALL_TAILSCALE=$INSTALL_TAILSCALE

# Openclaw
INSTALL_OPENCLAW_PREREQS=$INSTALL_OPENCLAW_PREREQS
CONF

chmod 600 "$CONFIG_DIR/system.conf"
log_info "Configuration written to config/system.conf (mode 600)"

# ── Summary ────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Configuration Summary${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo "  Timezone:          $TIMEZONE"
echo "  Default user:      $DEFAULT_USER"
echo "  Firewall:          $INSTALL_FIREWALL"
echo "  Remove xrdp:       $REMOVE_XRDP"
echo "  Remove LightDM:    $REMOVE_LIGHTDM"
echo "  GNOME session:     $GNOME_SESSION"
echo "  RDP mode:          $RDP_MODE"
echo "  RDP user:          $RDP_USER"
echo "  Tailscale:         $INSTALL_TAILSCALE"
echo "  Openclaw prereqs:  $INSTALL_OPENCLAW_PREREQS"
echo
echo -e "Review ${BOLD}config/system.conf${NC}, then run:"
echo -e "  ${GREEN}sudo ./setup.sh${NC}"
echo
