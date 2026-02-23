#!/usr/bin/env bash
# lib/04-tailscale.sh — Install and configure Tailscale VPN
# Sourced by setup.sh via run_module. Expects common.sh already loaded.

if ! command -v tailscale &>/dev/null; then
    log_info "Installing Tailscale..."

    # Add Tailscale GPG key and repo
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
        | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
        | tee /etc/apt/sources.list.d/tailscale.list >/dev/null

    apt-get update -y
    apt-get install -y tailscale
else
    log_info "Tailscale already installed."
fi

log_info "Enabling and starting tailscaled..."
systemctl enable --now tailscaled

if tailscale status &>/dev/null; then
    log_info "Tailscale is already connected."
    tailscale status
else
    log_warn "Tailscale is not connected. Running 'tailscale up'..."
    log_warn "This may require browser authentication — check the URL below."
    tailscale up
fi

log_info "Tailscale setup complete."
tailscale status
