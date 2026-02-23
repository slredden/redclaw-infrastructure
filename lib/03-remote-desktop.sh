#!/usr/bin/env bash
# lib/03-remote-desktop.sh — Remove xrdp, configure GDM3 + GNOME + GRD
# Sourced by setup.sh via run_module. Expects common.sh already loaded.

# ── Phase A: Remove xrdp ──────────────────────────────────────────────
if [[ "${REMOVE_XRDP:-false}" == "true" ]]; then
    if is_pkg_installed xrdp; then
        log_info "Stopping xrdp services..."
        systemctl stop xrdp xrdp-sesman 2>/dev/null || true
        systemctl disable xrdp xrdp-sesman 2>/dev/null || true

        log_info "Removing xrdp and related packages..."
        apt-get remove --purge -y xrdp xorgxrdp 2>/dev/null || true
        # Remove pipewire xrdp modules if present
        apt-get remove --purge -y pipewire-module-xrdp libpipewire-0.3-modules-xrdp 2>/dev/null || true
        apt-get autoremove -y
    else
        log_info "xrdp not installed, skipping removal."
    fi
fi

# ── Phase B: Remove LightDM ──────────────────────────────────────────
if [[ "${REMOVE_LIGHTDM:-false}" == "true" ]]; then
    if is_pkg_installed lightdm; then
        log_info "Removing LightDM..."
        apt-get remove --purge -y lightdm 2>/dev/null || true
        apt-get autoremove -y
    else
        log_info "LightDM not installed, skipping removal."
    fi
fi

# ── Phase C: Ensure GNOME + GDM3 ─────────────────────────────────────
log_info "Ensuring ubuntu-desktop is installed..."
ensure_pkg ubuntu-desktop

log_info "Verifying GDM3 is the default display manager..."
if [[ -f /etc/X11/default-display-manager ]]; then
    current_dm="$(cat /etc/X11/default-display-manager)"
    if [[ "$current_dm" != "/usr/sbin/gdm3" ]]; then
        log_info "Setting GDM3 as default display manager (was: $current_dm)..."
        echo "/usr/sbin/gdm3" > /etc/X11/default-display-manager
        dpkg-reconfigure -f noninteractive gdm3
        REBOOT_NEEDED=true
    fi
else
    echo "/usr/sbin/gdm3" > /etc/X11/default-display-manager
    REBOOT_NEEDED=true
fi

# Set default session for the user
ACCOUNTSSERVICE_DIR="/var/lib/AccountsService/users"
ACCOUNTSSERVICE_FILE="$ACCOUNTSSERVICE_DIR/$DEFAULT_USER"
if [[ -d "$ACCOUNTSSERVICE_DIR" ]]; then
    backup_config "$ACCOUNTSSERVICE_FILE"
    if [[ -f "$ACCOUNTSSERVICE_FILE" ]]; then
        # Update existing session line or add it
        if grep -q '^Session=' "$ACCOUNTSSERVICE_FILE"; then
            sed -i "s/^Session=.*/Session=$GNOME_SESSION/" "$ACCOUNTSSERVICE_FILE"
        else
            echo "Session=$GNOME_SESSION" >> "$ACCOUNTSSERVICE_FILE"
        fi
    else
        cat > "$ACCOUNTSSERVICE_FILE" << EOF
[User]
Session=$GNOME_SESSION
SystemAccount=false
EOF
    fi
    log_info "Default session for $DEFAULT_USER set to $GNOME_SESSION"
fi

# ── Phase D: Configure GNOME Remote Desktop ──────────────────────────
log_info "Configuring GNOME Remote Desktop (GRD)..."

# GRD configuration must run as the target user with a D-Bus session.
# We use machinectl shell which provides a proper login session,
# falling back to runuser if machinectl is not available.
run_as_user() {
    if command -v machinectl &>/dev/null; then
        machinectl shell "$DEFAULT_USER@" /bin/bash -c "$1"
    else
        runuser -u "$DEFAULT_USER" -- bash -c "
            export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$DEFAULT_USER")/bus
            $1
        "
    fi
}

run_as_user "grdctl rdp enable"
run_as_user "grdctl rdp disable-view-only"
run_as_user "grdctl rdp set-credentials '$RDP_USER' '$RDP_PASSWORD'"

if [[ "${RDP_MODE:-console}" == "headless" ]]; then
    log_info "Configuring headless RDP mode..."
    run_as_user "grdctl rdp set-mode headless"
else
    log_info "Configuring console-sharing RDP mode..."
    run_as_user "grdctl rdp set-mode console"
fi

# Enable the systemd user service for GRD
run_as_user "systemctl --user enable gnome-remote-desktop.service"
run_as_user "systemctl --user restart gnome-remote-desktop.service" || true

log_info "GNOME Remote Desktop configured."

# Verify port 3389
sleep 2
if ss -tlnp | grep -q ':3389 '; then
    log_info "Port 3389 is listening — GRD is active."
else
    log_warn "Port 3389 is not yet listening. GRD may start after next login or reboot."
    REBOOT_NEEDED=true
fi
