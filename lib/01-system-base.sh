#!/usr/bin/env bash
# lib/01-system-base.sh — Apt updates, baseline packages, timezone, auto-updates
# Sourced by setup.sh via run_module. Expects common.sh already loaded.

log_info "Updating package lists..."
apt-get update -y

log_info "Upgrading installed packages..."
apt-get upgrade -y

log_info "Installing baseline packages..."
ensure_pkg \
    build-essential \
    git \
    curl \
    wget \
    htop \
    tmux \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg

log_info "Setting timezone to $TIMEZONE..."
timedatectl set-timezone "$TIMEZONE"

log_info "Ensuring unattended-upgrades is installed and enabled..."
ensure_pkg unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades
