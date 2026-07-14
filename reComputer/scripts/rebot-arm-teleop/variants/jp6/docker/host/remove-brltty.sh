#!/usr/bin/env bash
# Remove brltty so it stops grabbing CH340 / ttyUSB devices.
#
# `brltty` is a braille-display daemon that, on Ubuntu / Debian, installs
# a udev rule claiming several USB-serial chipsets (including the
# WCH CH340/CH341 used by the reBot Arm 102 leader). Until it is
# removed, the leader arm will not appear as /dev/ttyUSB* and the
# teleop session will fail with "port not found".
#
# Must be run with sudo. Idempotent: a no-op if brltty is not installed.

set -euo pipefail

log()  { printf '[brltty] %s\n' "$*"; }
warn() { printf '[brltty][WARN] %s\n' "$*" >&2; }

[[ "${EUID}" -eq 0 ]] || { echo 'run with sudo' >&2; exit 1; }

if ! dpkg -s brltty >/dev/null 2>&1 && ! rpm -q brltty >/dev/null 2>&1; then
  log "brltty is not installed; nothing to do"
  exit 0
fi

if command -v apt-get >/dev/null 2>&1; then
  log "removing brltty via apt-get autoremove"
  apt-get -y autoremove brltty \
    || warn "apt-get autoremove brltty failed (continuing)"
elif command -v dnf >/dev/null 2>&1; then
  log "removing brltty via dnf"
  dnf -y remove brltty \
    || warn "dnf remove brltty failed (continuing)"
elif command -v yum >/dev/null 2>&1; then
  log "removing brltty via yum"
  yum -y remove brltty \
    || warn "yum remove brltty failed (continuing)"
fi

# Defensive: some distributions leave the udev rule behind even after
# the package is gone. Drop any rule that mentions brltty.
if [[ -d /etc/udev/rules.d ]]; then
  found=0
  for f in /etc/udev/rules.d/*brltty*; do
    [[ -e "$f" ]] || continue
    log "removing leftover udev rule: ${f}"
    rm -f "$f"
    found=1
  done
  if [[ "${found}" -eq 1 ]]; then
    udevadm control --reload-rules || true
    udevadm trigger              || true
  fi
fi

# Defensive: kill any running brltty processes and reload udev.
pkill -f brltty 2>/dev/null || true
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

log "done"

# -----------------------------------------------------------------------
# Helper: list available ttyUSB / ttyACM nodes so the operator can
# sanity-check that the leader / follower arms are visible.
# -----------------------------------------------------------------------
if [[ "${1:-}" == "--list" ]]; then
  echo "available serial ports after brltty cleanup:"
  for d in /sys/class/tty/ttyUSB* /sys/class/tty/ttyACM*; do
    [[ -e "$d" ]] || continue
    echo "  /dev/$(basename "$d")"
  done
fi
