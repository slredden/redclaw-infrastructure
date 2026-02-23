#!/usr/bin/env bash
# lib/detect.sh — System state detection functions for configure.sh

detect_display_manager() {
    # Returns: gdm3, lightdm, sddm, or none
    if [[ -f /etc/X11/default-display-manager ]]; then
        local dm
        dm="$(basename "$(cat /etc/X11/default-display-manager)")"
        echo "$dm"
    elif systemctl is-active --quiet gdm3 2>/dev/null; then
        echo "gdm3"
    elif systemctl is-active --quiet lightdm 2>/dev/null; then
        echo "lightdm"
    else
        echo "none"
    fi
}

detect_desktop_environment() {
    # Returns available session names (one per line)
    local sessions=()
    for dir in /usr/share/xsessions /usr/share/wayland-sessions; do
        if [[ -d "$dir" ]]; then
            for f in "$dir"/*.desktop; do
                [[ -f "$f" ]] && sessions+=("$(basename "$f" .desktop)")
            done
        fi
    done
    if [[ ${#sessions[@]} -gt 0 ]]; then
        printf '%s\n' "${sessions[@]}" | sort -u
    else
        echo "none"
    fi
}

detect_rdp_service() {
    # Prints key=value pairs describing RDP state
    local xrdp_installed=false xrdp_active=false grd_enabled=false port_listening=false

    if is_pkg_installed xrdp; then
        xrdp_installed=true
        if systemctl is-active --quiet xrdp 2>/dev/null; then
            xrdp_active=true
        fi
    fi

    # Check GRD — try user's gsettings or systemctl
    if systemctl --user is-enabled --quiet gnome-remote-desktop.service 2>/dev/null; then
        grd_enabled=true
    elif [[ -f "/home/${DEFAULT_USER:-admin}/.local/share/gnome-remote-desktop/rdp-credentials" ]] 2>/dev/null; then
        grd_enabled=true
    fi

    if ss -tlnp 2>/dev/null | grep -q ':3389 '; then
        port_listening=true
    fi

    echo "xrdp_installed=$xrdp_installed"
    echo "xrdp_active=$xrdp_active"
    echo "grd_enabled=$grd_enabled"
    echo "port_listening=$port_listening"
}

detect_firewall() {
    local ufw_installed=false ufw_active=false rules=""

    if is_pkg_installed ufw; then
        ufw_installed=true
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            ufw_active=true
            rules="$(ufw status numbered 2>/dev/null)"
        fi
    fi

    echo "ufw_installed=$ufw_installed"
    echo "ufw_active=$ufw_active"
    if [[ -n "$rules" ]]; then
        echo "---UFW-RULES---"
        echo "$rules"
        echo "---END-RULES---"
    fi
}

detect_tailscale() {
    local installed=false connected=false ip=""

    if command -v tailscale &>/dev/null; then
        installed=true
        if tailscale status &>/dev/null; then
            connected=true
            ip="$(tailscale ip -4 2>/dev/null || true)"
        fi
    fi

    echo "tailscale_installed=$installed"
    echo "tailscale_connected=$connected"
    echo "tailscale_ip=$ip"
}

detect_node() {
    local node_installed=false node_version="" openclaw_installed=false openclaw_version=""

    if command -v node &>/dev/null; then
        node_installed=true
        node_version="$(node --version 2>/dev/null || true)"
    fi

    if command -v openclaw &>/dev/null; then
        openclaw_installed=true
        openclaw_version="$(openclaw --version 2>/dev/null || true)"
    fi

    echo "node_installed=$node_installed"
    echo "node_version=$node_version"
    echo "openclaw_installed=$openclaw_installed"
    echo "openclaw_version=$openclaw_version"
}

detect_existing_sentinels() {
    local sentinels=()
    for f in ${SENTINEL_PREFIX}-*; do
        if [[ -f "$f" ]]; then
            local name="${f#${SENTINEL_PREFIX}-}"
            local stamp
            stamp="$(cat "$f")"
            sentinels+=("$name ($stamp)")
        fi
    done
    if [[ ${#sentinels[@]} -gt 0 ]]; then
        printf '%s\n' "${sentinels[@]}"
    else
        echo "none"
    fi
}
