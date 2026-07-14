#!/usr/bin/env bash
# Remove brltty — it grabs CH340 / CH341 USB-serial devices on Ubuntu,
# preventing the container from accessing the reBot Arm 102 leader.

set -euo pipefail

log()  { printf '[brltty] %s\n' "$*"; }
warn() { printf '[brltty][WARN] %s\n' "$*" >&2; }
die()  { printf '[brltty][FAIL] %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "run with sudo: sudo $0"

# Check if brltty is installed.
if ! dpkg -l brltty >/dev/null 2>&1; then
  log "brltty not installed — nothing to do"
  exit 0
fi

# Stop the service if it is running.
if systemctl is-active --quiet brltty.service 2>/dev/null; then
  log "stopping brltty.service"
  systemctl stop brltty.service \
    || warn "failed to stop brltty.service (non-fatal)"
fi

# Disable the service so it does not restart on next boot.
if systemctl is-enabled --quiet brltty.service 2>/dev/null; then
  log "disabling brltty.service"
  systemctl disable brltty.service \
    || warn "failed to disable brltty.service (non-fatal)"
fi

# Remove the package.
log "purging brltty"
apt-get remove --purge -y brltty \
  || warn "apt remove failed (non-fatal — may already be uninstalled)"

# Remove any leftover chardev nodes that brltty may have created.
rm -f /dev/ttyUSB* 2>/dev/null || true

log "brltty removed"
