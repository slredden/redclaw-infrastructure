# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the `infrastructure` repository — repeatable setup scripts for preparing Ubuntu 24.04 LTS as an Openclaw server. OS/infrastructure only; per-bot provisioning is in `redbot-provision`.

## Architecture

**Two-step workflow:**
1. `configure.sh` (interactive) — detects state, asks questions, writes `config/system.conf`
2. `setup.sh` (non-interactive) — reads config, runs modules in order

**Shared libraries:**
- `lib/common.sh` — logging, preconditions, sentinels, package management, config loading
- `lib/detect.sh` — system state detection (display manager, firewall, tailscale, node)

**Modules** (`lib/01-*.sh` through `lib/05-*.sh`):
- Sourced by `setup.sh` via `run_module`, not executed directly
- Each module assumes `common.sh` is loaded and config variables are set
- Idempotency via sentinel files in `/etc/infrastructure-done-*`

## Conventions

- All scripts use `bash` with `set -euo pipefail`
- Modules are sourced (not executed as subprocesses) so they share the config namespace
- `config/system.conf` is git-ignored (per-machine, contains RDP password)
- `config/defaults.conf` is committed (shipped defaults)
- Use `log_info`/`log_warn`/`log_error` for output, not raw `echo`
- Use `ensure_pkg` instead of raw `apt-get install`
- Use `backup_config` before modifying system config files
- Both scripts require root (`sudo`)

## Testing

```bash
# Syntax check all scripts
bash -n configure.sh setup.sh lib/*.sh

# Dry run (requires config/system.conf)
sudo ./setup.sh --dry-run

# Full run
sudo ./setup.sh

# Re-run ignoring sentinels
sudo ./setup.sh --force
```
