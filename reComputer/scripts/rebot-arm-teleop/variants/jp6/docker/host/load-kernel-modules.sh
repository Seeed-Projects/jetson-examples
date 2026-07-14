#!/usr/bin/env bash
# Load the kernel modules required by the reBot Arm teleop stack.
#
# Required modules (Jetson / kernel 5.15.148-tegra):
#   - can_dev      : SocketCAN core (usually built-in, but defensive)
#   - peak_usb     : PEAK-System USB-to-CAN adapter (loaded from
#                    /lib/modules/5.15.148-tegra/kernel/net/can/peak_usb.ko
#                    when not part of the running image)
#   - ch341 / ch34x: USB-serial bridge for the reBot Arm 102 leader arm
#                    (CH340/CH341 chipset)
#
# The script must be run with root privileges (sudo) because modprobe /
# insmod require CAP_SYS_MODULE.
#
# It is safe to run multiple times: `modprobe` and `insmod` are no-ops
# if the module is already loaded.

set -euo pipefail

KVER="$(uname -r)"
KMOD_ROOT="/lib/modules/${KVER}"

log() { printf '[kmod] %s\n' "$*"; }
warn() { printf '[kmod][WARN] %s\n' "$*" >&2; }
die() { printf '[kmod][FAIL] %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "run with sudo: sudo $0"

# Make sure kmod is callable.
command -v modprobe >/dev/null || die "modprobe not found; install kmod"
command -v insmod   >/dev/null || true

# -----------------------------------------------------------------------
# 1. SocketCAN core (can-dev). Normally built-in on Jetson; if missing
#    we try to load it.
# -----------------------------------------------------------------------
if ! grep -qw can_dev /proc/modules; then
  log "loading can_dev"
  if [[ -f "${KMOD_ROOT}/kernel/drivers/net/can/dev/can-dev.ko" ]]; then
    insmod "${KMOD_ROOT}/kernel/drivers/net/can/dev/can-dev.ko" \
      || warn "can-dev.ko insmod failed (may already be built-in)"
  else
    modprobe can_dev 2>/dev/null \
      || warn "can_dev module not available; assuming built-in"
  fi
else
  log "can_dev already loaded"
fi

# -----------------------------------------------------------------------
# 2. peak_usb - PEAK-System USB-CAN adapter.
# -----------------------------------------------------------------------
if ! grep -qw peak_usb /proc/modules; then
  PEAK_KO="${KMOD_ROOT}/kernel/net/can/peak_usb.ko"
  if [[ ! -f "${PEAK_KO}" ]]; then
    # Try the alternate path that shows up when the module was rebuilt.
    PEAK_KO="${KMOD_ROOT}/kernel/drivers/net/can/usb/peak_usb/peak_usb.ko"
  fi

  if [[ -f "${PEAK_KO}" ]]; then
    log "loading peak_usb from ${PEAK_KO}"
    insmod "${PEAK_KO}" || die "failed to insmod ${PEAK_KO}"
  else
    log "trying modprobe peak_usb (depends on /etc/modules-load.d)"
    modprobe peak_usb 2>/dev/null \
      || warn "peak_usb not found on this system; CAN bringup will fail"
  fi
else
  log "peak_usb already loaded"
fi

# -----------------------------------------------------------------------
# 3. CH340/CH341 USB-serial drivers for the leader arm.
# -----------------------------------------------------------------------
for mod in ch341 ch34x; do
  if grep -qw "${mod}" /proc/modules; then
    log "${mod} already loaded"
    continue
  fi

  KO_PATH="${KMOD_ROOT}/kernel/drivers/usb/serial/${mod}.ko"
  if [[ -f "${KO_PATH}" ]]; then
    log "loading ${mod} from ${KO_PATH}"
    insmod "${KO_PATH}" \
      || warn "${mod} insmod failed; reBot Arm 102 may not enumerate"
  else
    log "trying modprobe ${mod}"
    modprobe "${mod}" 2>/dev/null \
      || warn "${mod} not found; install linux-modules-extra-${KVER}"
  fi
done

# -----------------------------------------------------------------------
# 4. Persist across reboots (best-effort).
# -----------------------------------------------------------------------
MODULES_LOAD_D="/etc/modules-load.d/rebot-arm-teleop.conf"
if [[ -d /etc/modules-load.d ]] && [[ ! -f "${MODULES_LOAD_D}" ]]; then
  log "writing ${MODULES_LOAD_D} for persistent loading"
  cat > "${MODULES_LOAD_D}" <<'EOF'
# reBot Arm teleop — kernel modules loaded at boot.
can_dev
peak_usb
ch341
ch34x
EOF
fi

# -----------------------------------------------------------------------
# 5. udev: give non-root users read/write access to PEAK CAN / ttyUSB.
# -----------------------------------------------------------------------
UDEV_RULES_D="/etc/udev/rules.d/99-rebot-arm-teleop.rules"
if [[ -d /etc/udev/rules.d ]] && [[ ! -f "${UDEV_RULES_D}" ]]; then
  log "writing ${UDEV_RULES_D}"
  cat > "${UDEV_RULES_D}" <<'EOF'
# reBot Arm teleop — device access rules.
# PEAK-System PCAN-USB / PCAN-USB FD
SUBSYSTEM=="usb", ATTR{idVendor}=="0c72", MODE="0666"
# WCH CH340 / CH341
SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", MODE="0666"
# Generic ttyUSB / ttyACM for follower / leader serial arms
KERNEL=="ttyUSB[0-9]*", MODE="0666"
KERNEL=="ttyACM[0-9]*", MODE="0666"
# SocketCAN
KERNEL=="can[0-9]*", MODE="0666"
EOF
  udevadm control --reload-rules 2>/dev/null || true
  udevadm trigger                  2>/dev/null || true
fi

log "module summary:"
grep -E '^(peak_usb|ch341|ch34x|can_dev)\b' /proc/modules | awk '{printf "  %s  size=%s  refs=%s\n", $1, $2, $3}' || true
log "done"
