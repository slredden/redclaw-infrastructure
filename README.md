# Infrastructure

Repeatable setup scripts for preparing a fresh Ubuntu 24.04 LTS install as an Openclaw server.

Handles OS-level infrastructure: system packages, firewall, remote desktop (GNOME Remote Desktop), Tailscale VPN, and Openclaw prerequisites. Per-bot provisioning remains in `redbot-provision`.

## Quick Start

```bash
# 1. Interactive — detects system state, asks questions, writes config
sudo ./configure.sh

# 2. Review the generated config
cat config/system.conf

# 3. Non-interactive — applies configuration
sudo ./setup.sh
```

## Two-Step Workflow

### `configure.sh` (interactive)

Detects current system state (display manager, xrdp, firewall rules, Tailscale, Node.js), then walks through each module's settings. On a fresh install this is mostly accepting defaults. On an existing system it highlights differences and asks before planning changes.

Writes answers to `config/system.conf` (git-ignored, per-machine).

### `setup.sh` (non-interactive)

Reads `config/system.conf` and applies changes. No prompts. Safe to run unattended or from documentation.

**Flags:**
- `--dry-run` — show what would run without making changes
- `--force` — ignore sentinels and re-run all modules

## Modules

| Module | What it does |
|--------|-------------|
| **01-system-base** | `apt update/upgrade`, baseline packages, timezone, unattended-upgrades |
| **02-firewall** | UFW: SSH open, RDP restricted to Tailscale + LAN |
| **03-remote-desktop** | Remove xrdp, configure GDM3 + GNOME + GNOME Remote Desktop |
| **04-tailscale** | Install Tailscale VPN (requires browser auth on first run) |
| **05-openclaw-prereqs** | Node.js 22+, npm, jq, curl, `openclaw` global install |

## Configuration

Default values are in `config/defaults.conf`. Key settings:

| Setting | Default | Description |
|---------|---------|-------------|
| `TIMEZONE` | `America/Denver` | System timezone |
| `DEFAULT_USER` | `admin` | Non-root user for GRD and services |
| `LOCAL_NETWORK` | `192.168.10.0/24` | LAN CIDR for RDP firewall rule |
| `TAILSCALE_SUBNET` | `100.64.0.0/10` | Tailscale CIDR for RDP firewall rule |
| `GNOME_SESSION` | `ubuntu` | `ubuntu` (Wayland) or `ubuntu-xorg` (Xorg) |
| `RDP_MODE` | `console` | `console` (share display) or `headless` (virtual) |

## Idempotency

Each module creates a sentinel file (`/etc/infrastructure-done-<name>`) on completion. Re-running `setup.sh` skips completed modules unless `--force` is used.

## Manual Steps

- **Tailscale**: First run of `tailscale up` requires browser authentication
- **RDP password**: Set during `configure.sh` — stored in `config/system.conf` (mode 600)
- **Reboot**: May be needed after display manager changes

## Remote Desktop: Why GRD over xrdp

GNOME Remote Desktop (GRD) natively shares the console session over RDP. This means you can use the physical display and RDP simultaneously — unlike xrdp, which creates a separate session. GRD is already included in Ubuntu 24.04 with GNOME.
