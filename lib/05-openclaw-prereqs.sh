#!/usr/bin/env bash
# lib/05-openclaw-prereqs.sh — Node.js 22+, npm, jq, curl, openclaw global
# Sourced by setup.sh via run_module. Expects common.sh already loaded.

# ── Node.js 22 via NodeSource ─────────────────────────────────────────
if ! command -v node &>/dev/null || [[ "$(node --version | sed 's/v//' | cut -d. -f1)" -lt 22 ]]; then
    log_info "Installing Node.js 22 via NodeSource..."

    # Add NodeSource GPG key and repo
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
else
    log_info "Node.js $(node --version) already installed (>= 22)."
fi

# ── Additional packages ───────────────────────────────────────────────
log_info "Ensuring supporting packages..."
ensure_pkg jq curl gettext-base openssl

# ── Openclaw global install ───────────────────────────────────────────
log_info "Installing openclaw globally..."
npm install -g openclaw@latest

# ── Backward compatibility sentinel ──────────────────────────────────
# redbot-provision checks for this file
touch /etc/openclaw-prereqs-done
log_info "Created /etc/openclaw-prereqs-done for redbot-provision compatibility."

# ── Verification ──────────────────────────────────────────────────────
log_info "Node.js version: $(node --version)"
log_info "npm version: $(npm --version)"
log_info "openclaw version: $(openclaw --version 2>/dev/null || echo 'not found')"
