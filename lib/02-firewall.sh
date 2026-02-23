#!/usr/bin/env bash
# lib/02-firewall.sh — UFW configuration
# Sourced by setup.sh via run_module. Expects common.sh already loaded.

log_info "Installing UFW..."
ensure_pkg ufw

log_info "Configuring UFW default policies..."
ufw default deny incoming
ufw default allow outgoing

log_info "Allowing SSH (port 22)..."
ufw allow 22/tcp

log_info "Allowing RDP (port 3389) from Tailscale subnet ($TAILSCALE_SUBNET)..."
ufw allow from "$TAILSCALE_SUBNET" to any port 3389 proto tcp

log_info "Allowing RDP (port 3389) from local network ($LOCAL_NETWORK)..."
ufw allow from "$LOCAL_NETWORK" to any port 3389 proto tcp

log_info "Allowing all traffic on tailscale0 interface..."
ufw allow in on tailscale0

log_info "Enabling UFW..."
ufw --force enable

log_info "UFW status:"
ufw status verbose
