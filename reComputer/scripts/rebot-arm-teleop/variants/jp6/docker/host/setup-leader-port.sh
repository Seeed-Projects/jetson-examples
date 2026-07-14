#!/usr/bin/env bash
# Pick the serial port for the reBot Arm 102 leader arm.
#
# The leader is wired through a CH340 / CH341 USB-serial bridge
# (idVendor 0x1a86). Ubuntu enumerates it as /dev/ttyUSB0, ttyUSB1, ...
# but the index is not stable — another CH340 (debug probe, Arduino, ...)
# plugged in first can bump the leader to ttyUSB1 or ttyUSB2.
#
# This script:
#   1. If LEADER_PORT is set explicitly and exists, trust it.
#   2. Otherwise enumerate /sys/class/tty/ttyUSB* and look at the
#      parent's USB idVendor. Prefer any node whose VID/PID matches the
#      reBot Arm 102 (currently a generic CH340/CH341 — VID 0x1a86).
#      Multiple matches → fail loudly so the operator picks one.
#   3. Writes the resolved path to /tmp/.rebot-arm-leader-port so the
#      parent launcher (start-teleop.sh) and the container can read it.
#
# Usage:
#   sudo ./docker/host/setup-leader-port.sh
#   sudo LEADER_PORT=/dev/ttyUSB1 ./docker/host/setup-leader-port.sh
#
# Env vars:
#   LEADER_PORT    : explicit override; if it exists, used as-is
#   REBOT_VID      : USB vendor id of the leader (default 1a86 = WCH)
#   REBOT_PID      : USB product id(s), comma-sep; default blank = any CH340/CH341

set -euo pipefail

log()  { printf '[leader] %s\n' "$*"; }
warn() { printf '[leader][WARN] %s\n' "$*" >&2; }
die()  { printf '[leader][FAIL] %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || true  # allow non-root; udev 0666 rules cover device access

# Note: we deliberately do NOT default LEADER_PORT here. An empty string
# must mean "auto-detect", while an unset variable should also mean
# "auto-detect" by virtue of bash's empty string semantics. Both cases
# are handled identically by the empty-check below.
LEADER_PORT="${LEADER_PORT-}"
REBOT_VID="${REBOT_VID:-1a86}"
REBOT_PID="${REBOT_PID:-}"

STATE_FILE="/tmp/.rebot-arm-leader-port"

# -----------------------------------------------------------------------
# 1. Explicit override.
# -----------------------------------------------------------------------
if [[ -n "${LEADER_PORT:-}" ]] && [[ -e "${LEADER_PORT}" ]]; then
  log "using explicit LEADER_PORT=${LEADER_PORT}"
  printf '%s\n' "${LEADER_PORT}" > "${STATE_FILE}"
  chmod 0644 "${STATE_FILE}"
  exit 0
fi

# -----------------------------------------------------------------------
# 2. Enumerate /sys/class/tty/ttyUSB* / ttyACM* and inspect the parent
#    USB device's idVendor / idProduct.
# -----------------------------------------------------------------------
list_serial_ports() {
  for tty in /sys/class/tty/ttyUSB* /sys/class/tty/ttyACM*; do
    [[ -e "${tty}" ]] || continue
    printf '%s\n' "${tty}"
  done
}

log "scanning for CH340/CH341 (vid=0x${REBOT_VID}) candidates"
CANDIDATES=()
while IFS= read -r tty; do
  dev_path="/dev/$(basename "${tty}")"
  # /sys/class/tty/ttyUSB0 → /sys/devices/.../<usb-iface>/ttyUSB0
  # We want the USB interface dir, then walk up to the USB device
  # (which carries idVendor / idProduct).
  iface_dir="$(realpath "${tty}/../..")"
  vid=""
  pid=""
  d="${iface_dir}"
  for _ in 1 2 3 4; do
    if [[ -f "${d}/idVendor" ]]; then
      vid="$(cat "${d}/idVendor" 2>/dev/null || true)"
      pid="$(cat "${d}/idProduct" 2>/dev/null || true)"
      break
    fi
    d="$(dirname "${d}")"
  done
  if [[ "${vid}" == "${REBOT_VID}" ]]; then
    if [[ -z "${REBOT_PID}" ]] || [[ ",${REBOT_PID}," == *",${pid},"* ]]; then
      CANDIDATES+=( "${dev_path}" )
      log "  candidate: ${dev_path} (vid=0x${vid} pid=0x${pid:-????})"
    fi
  fi
done < <(list_serial_ports)

# -----------------------------------------------------------------------
# 3. Resolve.
# -----------------------------------------------------------------------
case "${#CANDIDATES[@]}" in
  0)
    warn "no CH340/CH341 device found at /dev/ttyUSB* / ttyACM*"
    warn "available serial ports:"
    for tty in /sys/class/tty/ttyUSB* /sys/class/tty/ttyACM*; do
      [[ -e "${tty}" ]] || continue
      warn "  /dev/$(basename "${tty}")"
    done
    die "plug the reBot Arm 102 leader in (or set LEADER_PORT explicitly)"
    ;;
  1)
    SELECTED="${CANDIDATES[0]}"
    log "auto-selected leader port: ${SELECTED}"
    ;;
  *)
    warn "multiple CH340/CH341 devices found; please disambiguate:"
    for c in "${CANDIDATES[@]}"; do warn "  ${c}"; done
    die "set LEADER_PORT explicitly, e.g. sudo LEADER_PORT=${CANDIDATES[0]} $0"
    ;;
esac

printf '%s\n' "${SELECTED}" > "${STATE_FILE}"
chmod 0644 "${STATE_FILE}"
log "wrote ${STATE_FILE}"
