#!/usr/bin/env bash
# Bring up a SocketCAN interface produced by peak_usb.
#
# The reBot Arm CAN bus usually shows up as can0, but the index is not
# guaranteed - other CAN adapters or hot-plug events may renumber it.
# This script enumerates /sys/class/net/can*, picks the first one whose
# driver is peak_usb, and brings it up at 1 Mbps with restart-ms=100.
#
# Required host state:
#   - peak_usb kernel module loaded (see load-kernel-modules.sh)
#   - PEAK USB-CAN adapter physically connected
#
# Usage:
#   sudo ./docker/host/setup-can.sh            # default 1Mbps, restart-ms 100
#   BITRATE=500000 ./docker/host/setup-can.sh  # override bitrate
#
# Env vars:
#   BITRATE       : CAN bitrate in bps       (default 1000000)
#   RESTART_MS    : restart-ms on bus error  (default 100)
#   CAN_IFACE_HINT: if non-empty, prefer this interface name when present
#                   (e.g. "can1" if the user already knows it).

set -euo pipefail

log()  { printf '[can] %s\n' "$*"; }
warn() { printf '[can][WARN] %s\n' "$*" >&2; }
die()  { printf '[can][FAIL] %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "run with sudo: sudo $0"
command -v ip >/dev/null || die "iproute2 'ip' command not found"

BITRATE="${BITRATE:-1000000}"
RESTART_MS="${RESTART_MS:-100}"

# -----------------------------------------------------------------------
# 1. Find candidate CAN interfaces.
# -----------------------------------------------------------------------
mapfile -t CAN_IFACES < <(ls /sys/class/net/ 2>/dev/null | grep -E '^can[0-9]+$' || true)
if [[ "${#CAN_IFACES[@]}" -eq 0 ]]; then
  warn "no /sys/class/net/can* interfaces found"
  warn "is peak_usb loaded? is the PEAK USB-CAN adapter plugged in?"
  exit 1
fi

# If the user gave a hint, try that one first if it exists.
SELECTED=""
if [[ -n "${CAN_IFACE_HINT:-}" ]] && [[ -d "/sys/class/net/${CAN_IFACE_HINT}" ]]; then
  SELECTED="${CAN_IFACE_HINT}"
  log "using hint interface: ${SELECTED}"
fi

if [[ -z "${SELECTED}" ]]; then
  # Prefer interfaces whose driver is peak_usb.
  for iface in "${CAN_IFACES[@]}"; do
    driver_link="/sys/class/net/${iface}/device/driver"
    if [[ -L "${driver_link}" ]]; then
      driver_name="$(basename "$(readlink "${driver_link}")")"
      if [[ "${driver_name}" == "peak_usb" ]]; then
        SELECTED="${iface}"
        log "found peak_usb-backed interface: ${iface}"
        break
      fi
    fi
  done
fi

if [[ -z "${SELECTED}" ]]; then
  # Fall back to the first can* interface, even if driver unknown.
  SELECTED="${CAN_IFACES[0]}"
  warn "no peak_usb-backed interface found; falling back to ${SELECTED}"
fi

log "selected CAN interface: ${SELECTED}"

# -----------------------------------------------------------------------
# 2. Bring the interface up at the requested bitrate.
# -----------------------------------------------------------------------
ip link set "${SELECTED}" down 2>/dev/null || true
ip link set "${SELECTED}" type can bitrate "${BITRATE}" restart-ms "${RESTART_MS}"
ip link set "${SELECTED}" up

# -----------------------------------------------------------------------
# 3. Verify.
# -----------------------------------------------------------------------
state="$(ip -details link show "${SELECTED}" 2>/dev/null | head -n1 || true)"
log "link state: ${state}"

if ip link show "${SELECTED}" | grep -qw UP; then
  log "OK: ${SELECTED} is UP at ${BITRATE} bps (restart-ms=${RESTART_MS})"
  printf '%s\n' "${SELECTED}" > /tmp/.rebot-arm-can-iface
  chmod 0644 /tmp/.rebot-arm-can-iface
  exit 0
else
  die "interface ${SELECTED} is NOT up; check physical wiring"
fi
