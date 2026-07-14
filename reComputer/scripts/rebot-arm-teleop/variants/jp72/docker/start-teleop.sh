#!/usr/bin/env bash
# One-command launcher for the reBot Arm LeRobot teleop session.
# Adapted for Jetpack 7.2 with CUDA 13.2
#
# What this script does (in order):
#   1. Removes `brltty` (it grabs CH340 / ttyUSB on Ubuntu).
#   2. Loads kernel modules: can_dev, peak_usb, ch341, ch34x.
#   3. Enumerates /sys/class/net/can*, picks the peak_usb-backed one, brings
#      it up at 1 Mbps. Falls back to the first can* if peak_usb is missing.
#      Sets /dev/<canX> mode 0666 so the container's non-root user can read.
#   4. Enumerates /sys/class/tty/ttyUSB* / ttyACM*, finds the CH340/CH341
#      (VID 0x1a86) leader. Sets /dev/<ttyUSBn> mode 0666 so the container's
#      non-root user can read.
#   5. Runs the rebot-lerobot-teleop-jp72 image with the host's CUDA stack
#      bind-mounted in (NOT bundled inside the image).
#   6. Passes every present /dev/ttyUSB*, /dev/ttyACM*, /dev/can* through to
#      the container with --device.
#
# Usage:
#   sudo ./start-teleop.sh
#   sudo LEADER_PORT=/dev/ttyUSB1 ./start-teleop.sh
#   sudo BITRATE=500000 TELEOP_FPS=60 ./start-teleop.sh
#
# Run with --build first if you haven't built the image yet.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOST_DIR="${SCRIPT_DIR}/host"

IMAGE_TAG="${IMAGE_TAG:-rebot-lerobot-teleop-jp72:latest}"
# Default to empty → auto-detect by CH340/CH341 (VID 0x1a86) vid/pid walk.
# Override with LEADER_PORT=/dev/ttyUSB1 if you want a specific device.
LEADER_PORT="${LEADER_PORT:-}"
LEADER_PORT_STATE="/tmp/.rebot-arm-leader-port-jp72"
FOLLOWER_PORT="${FOLLOWER_PORT:-}"      # auto-detect if empty
BITRATE="${BITRATE:-1000000}"
RESTART_MS="${RESTART_MS:-100}"
# Jetpack 7.2 paths (CUDA 13.2)
CUDA_DIR="${CUDA_DIR:-/usr/local/cuda-13.2}"
NVTEGRA_RELEASE="${NVTEGRA_RELEASE:-/etc/nv_tegra_release}"
NVIDIA_LIB_DIR="${NVIDIA_LIB_DIR:-/usr/lib/aarch64-linux-gnu/nvidia}"
CUDNN_LIB_DIR="${CUDNN_LIB_DIR:-/usr/lib/aarch64-linux-gnu}"

TELEOP_FPS="${TELEOP_FPS:-30}"
TELEOP_DURATION="${TELEOP_DURATION:-}"
TELEOP_DISPLAY="${TELEOP_DISPLAY:-false}"
TELEOP_DISPLAY_IP="${TELEOP_DISPLAY_IP:-}"
TELEOP_DISPLAY_PORT="${TELEOP_DISPLAY_PORT:-}"
TELEOP_EXTRA_ARGS="${TELEOP_EXTRA_ARGS:-}"

# CH340/CH341 (reBot Arm 102 leader arm) VID.
REBOT_VID="${REBOT_VID:-1a86}"

DOCKER=(docker)
if ! docker ps >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    echo "[start][FAIL] docker daemon not reachable" >&2
    exit 1
  fi
fi

log()  { printf '[start] %s\n' "$*"; }
warn() { printf '[start][WARN] %s\n' "$*" >&2; }
die()  { printf '[start][FAIL] %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------
# 0. Optional: build the image first.
# -----------------------------------------------------------------------
if [[ "${1:-}" == "--build" ]]; then
  log "--build: building image ${IMAGE_TAG}"
  "${SCRIPT_DIR}/build-image.sh"
fi

# -----------------------------------------------------------------------
# 1. Image must exist.
# -----------------------------------------------------------------------
if ! "${DOCKER[@]}" image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
  die "image ${IMAGE_TAG} not found. Run: sudo ./build-image.sh"
fi

# -----------------------------------------------------------------------
# 2. Root is required for kmod + can + brltty + chmod steps.
# -----------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "run with sudo: sudo $0"
fi

# -----------------------------------------------------------------------
# 3. brltty must go.
# -----------------------------------------------------------------------
log "step 1/7: removing brltty"
bash "${HOST_DIR}/remove-brltty.sh" || warn "brltty cleanup had warnings"

# -----------------------------------------------------------------------
# 4. Kernel modules.
# -----------------------------------------------------------------------
log "step 2/7: loading kernel modules"
bash "${HOST_DIR}/load-kernel-modules.sh" \
  || die "kernel module loader failed"

# -----------------------------------------------------------------------
# 5. Enumerate + configure SocketCAN.
#
# JP6 logic, inlined: scan /sys/class/net/can*, prefer peak_usb-backed
# interfaces, fall back to the first can* node if no peak_usb match.
# Then bring it up at ${BITRATE} bps with restart-ms=${RESTART_MS}.
# Finally chmod 0666 /dev/${SELECTED} so the container's non-root user
# (uid 1000) can open the raw socket.
# -----------------------------------------------------------------------
log "step 3/7: enumerating SocketCAN interfaces"
command -v ip >/dev/null || die "iproute2 'ip' command not found"

mapfile -t CAN_IFACES < <(ls /sys/class/net/ 2>/dev/null | grep -E '^can[0-9]+$' || true)
if [[ "${#CAN_IFACES[@]}" -eq 0 ]]; then
  die "no /sys/class/net/can* interfaces found; is peak_usb loaded? is the PEAK USB-CAN adapter plugged in?"
fi

CAN_IFACE=""
if [[ -n "${FOLLOWER_PORT}" ]] && [[ -d "/sys/class/net/${FOLLOWER_PORT}" ]]; then
  CAN_IFACE="${FOLLOWER_PORT}"
  log "  using FOLLOWER_PORT hint: ${CAN_IFACE}"
fi

if [[ -z "${CAN_IFACE}" ]]; then
  for iface in "${CAN_IFACES[@]}"; do
    driver_link="/sys/class/net/${iface}/device/driver"
    if [[ -L "${driver_link}" ]]; then
      driver_name="$(basename "$(readlink "${driver_link}")")"
      if [[ "${driver_name}" == "peak_usb" ]]; then
        CAN_IFACE="${iface}"
        log "  found peak_usb-backed interface: ${CAN_IFACE}"
        break
      fi
    fi
  done
fi

if [[ -z "${CAN_IFACE}" ]]; then
  CAN_IFACE="${CAN_IFACES[0]}"
  warn "no peak_usb-backed interface found; falling back to ${CAN_IFACE}"
fi

log "step 4/7: bringing up ${CAN_IFACE} at ${BITRATE} bps (restart-ms=${RESTART_MS})"
ip link set "${CAN_IFACE}" down 2>/dev/null || true
ip link set "${CAN_IFACE}" type can bitrate "${BITRATE}" restart-ms "${RESTART_MS}"
ip link set "${CAN_IFACE}" up

if ! ip link show "${CAN_IFACE}" | grep -qw UP; then
  die "interface ${CAN_IFACE} is NOT up; check physical wiring"
fi
log "  ${CAN_IFACE} is UP at ${BITRATE} bps"

# Permissions: the container's entrypoint runs as uid 1000 (non-root).
# Set /dev/<canX> to 0666 so it can open the CAN_RAW socket.
if [[ -e "/dev/${CAN_IFACE}" ]]; then
  chmod 0666 "/dev/${CAN_IFACE}" \
    && log "  chmod 0666 /dev/${CAN_IFACE}" \
    || warn "  failed to chmod /dev/${CAN_IFACE}"
else
  warn "  /dev/${CAN_IFACE} does not exist; skipping chmod"
fi

printf '%s\n' "${CAN_IFACE}" > /tmp/.rebot-arm-can-iface
chmod 0644 /tmp/.rebot-arm-can-iface

# FOLLOWER_PORT is consumed downstream as a plain device name (e.g. "can0").
FOLLOWER_PORT="${CAN_IFACE}"

# -----------------------------------------------------------------------
# 6. Enumerate + configure the leader USB-serial port.
#
# JP6 logic, inlined: if LEADER_PORT is set and exists, use it; otherwise
# scan /sys/class/tty/ttyUSB* / ttyACM* and pick the one whose parent USB
# device reports idVendor=0x${REBOT_VID} (default 1a86 = CH340/CH341).
# Then chmod 0666 so the container's non-root user can read/write the
# port.
# -----------------------------------------------------------------------
log "step 5/7: enumerating USB serial ports for leader (vid=0x${REBOT_VID})"

# Drop CH340 from ModemManager's udev filter (permanent).
# ModemManager cannot scan /dev/ttyUSB* — it claims the bus-level port via
# ModemManager modem probing rules. Stopping the service + writing a udev
# ignore rule prevents it from re-claiming on hotplug.
MM_WAS_ACTIVE=0
if systemctl is-active --quiet ModemManager 2>/dev/null; then
  MM_WAS_ACTIVE=1
  warn "  ModemManager is running; stopping it for this session"
  systemctl stop ModemManager 2>/dev/null \
    || warn "  systemctl stop ModemManager failed; continue and hope for the best"
fi
mkdir -p /etc/ModemManager/filter.d
# Only write the rules file if it doesn't already exist, so repeated
# runs do not churn the file's mtime and trigger pam_modmotd/etc.
# to do unnecessary work.
RULES_FILE="/etc/ModemManager/filter.d/99-block-ch340.rules"
if [[ ! -f "${RULES_FILE}" ]]; then
  cat >"${RULES_FILE}" <<'UDEV'
# reBot Arm leader is a CH340; never let ModemManager claim it.
ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", ENV{ID_MM_DEVICE_IGNORE}="1"
ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="5523", ENV{ID_MM_DEVICE_IGNORE}="1"
ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="5512", ENV{ID_MM_DEVICE_IGNORE}="1"
UDEV
fi
# Only `udevadm control --reload-rules` if the rules file is actually new
# or just changed.
if [[ "${MM_WAS_ACTIVE}" -eq 1 ]]; then
  udevadm control --reload-rules 2>/dev/null || true
  # Trigger a fresh enumeration now that the rules are in place. This
  # is required because ModemManager was just stopped; otherwise the
  # kernel-side udev state is still pointing to the now-gone filters
  # and will re-attach the CH340 to MM on the next plug event.
  udevadm trigger --subsystem-match=tty --action=add 2>/dev/null || true
  sleep 0.3
else
  # ModemManager was not running. Do NOT re-trigger tty enumeration
  # here — synthesizing 'add' events races with the kernel's own
  # ch341 hotplug worker and can briefly delete /dev/ttyUSB*.
  # Just settle whatever in-flight udev events already exist.
  udevadm settle --timeout=2 2>/dev/null || true
fi

# 6a. Explicit override (if user gave us a port, trust it and chmod+return).
if [[ -n "${LEADER_PORT}" ]]; then
  if [[ ! -e "${LEADER_PORT}" ]]; then
    # Hint was given but the node isn't here; fall through to scan and let
    # the user override again if the scan finds nothing usable.
    warn "  LEADER_PORT=${LEADER_PORT} not present; rescanning"
  fi
fi

# 6b. Walk /sys/class/tty and look at the parent's idVendor / idProduct.
#     Do discovery + chmod in one pass to avoid the
#     "found then vanished" race caused by udev re-enumeration.
#
# Helper: ensure the /dev/<tty> node exists. On this Jetson kernel the
# ch341 driver sometimes creates the tty class device but udev never
# gets to run the /lib/udev/rules.d/60-serial.rules on it (because the
# add event is delivered during a window where systemd-udevd's worker
# is busy). The fix is to fall back to `mknod` against the sysfs
# `dev` attribute (major:minor) when /dev/ttyUSB* is missing.
ensure_devnode() {
  local tty_name="$1"   # e.g. "ttyUSB0"
  local dev_path="/dev/${tty_name}"
  if [[ -e "${dev_path}" ]]; then
    return 0
  fi
  # Find the sysfs tty device and its 'dev' attribute.
  local sys_class="/sys/class/tty/${tty_name}"
  if [[ ! -L "${sys_class}" ]]; then
    return 1
  fi
  local sysfs_real
  sysfs_real="$(readlink -f "${sys_class}")"
  # On ch341/CH34x, the dev attribute lives at the leaf tty device
  # (the one readlink gives us), not one directory up.
  local dev_attr="${sysfs_real}/dev"
  if [[ ! -f "${dev_attr}" ]]; then
    dev_attr="${sysfs_real}/../dev"
  fi
  if [[ ! -f "${dev_attr}" ]]; then
    return 1
  fi
  local devnum
  devnum="$(cat "${dev_attr}" 2>/dev/null || true)"
  if [[ ! "${devnum}" =~ ^[0-9]+:[0-9]+$ ]]; then
    return 1
  fi
  local major="${devnum%%:*}"
  local minor="${devnum##*:}"
  warn "  ${dev_path} missing on disk; recreating via mknod ${major} ${minor} (udev missed event)"
  mknod "${dev_path}" c "${major}" "${minor}" 2>/dev/null \
    || return 1
  chmod 0666 "${dev_path}" 2>/dev/null || true
  return 0
}

probe_and_chmod_port() {
  local tty="$1"
  local dev_path="/dev/$(basename "${tty}")"
  local parent_bus="$(realpath "${tty}/../..")"
  local vid=""
  local d="${parent_bus}"
  for _ in 1 2 3 4 5; do
    if [[ -f "${d}/idVendor" ]]; then
      vid="$(cat "${d}/idVendor" 2>/dev/null || true)"
      break
    fi
    d="$(dirname "${d}")"
  done
  if [[ "${vid}" == "${REBOT_VID}" ]]; then
    # The /dev/<tty> node may briefly disappear during a re-enumeration,
    # but the caller already filtered out missing nodes. If the dev
    # node genuinely isn't here right now, just skip — the outer rescan
    # loop will pick it up on the next pass.
    [[ -e "${dev_path}" ]] || {
      warn "  candidate ${dev_path} not present (mid re-enumeration); will rescan"
      return 1
    }
    # chmod right now while we still hold a reference to the sysfs path.
    chmod 0666 "${dev_path}" 2>/dev/null || true
    CANDIDATES+=( "${dev_path}" )
    log "  candidate: ${dev_path} (vid=0x${vid})"
  fi
  return 0
}

# Walk every ch341 / ch34x / cdc_acm sysfs port and make sure its
# /dev/<tty> node is materialized. This is a pre-scan pass that runs
# before the VID-filtered probe loop, because udev occasionally
# silently drops the synthetic 'add' event for tty devices (the
# symptom: sysfs has the tty class link, but /dev/ttyUSB* doesn't).
# Returns nothing; mutates /dev/ttyUSB* in place via mknod when needed.
ensure_all_devnodes() {
  for class_link in /sys/class/tty/ttyUSB* /sys/class/tty/ttyACM*; do
    [[ -L "${class_link}" ]] || continue
    local tty_name
    tty_name="$(basename "${class_link}")"
    ensure_devnode "${tty_name}" || true
  done
}

RESCAN_ATTEMPTS=5
RESCAN_DELAY=0.2
attempt=0
CANDIDATES=()
# One udev settle wait up front so a freshly-inserted CH340 finishes
# registering before we start scanning.
udevadm settle --timeout=5 2>/dev/null || true
# Belt-and-suspenders: pre-scan /dev/ttyUSB* and mknod anything that
# the kernel has registered in sysfs but udev failed to materialize.
# This handles the case where /sys/class/tty/ttyUSB0 exists but
# /dev/ttyUSB0 does not.
ensure_all_devnodes
while [[ ${attempt} -lt ${RESCAN_ATTEMPTS} ]]; do
  attempt=$((attempt + 1))
  CANDIDATES=()
  found_one=0
  # Re-run ensure_devnode at the start of each attempt in case udev
  # is still catching up.
  ensure_all_devnodes
  for tty in /sys/class/tty/ttyUSB* /sys/class/tty/ttyACM*; do
    [[ -e "${tty}" ]] || continue
    # Only consider ports that actually exist as a dev node. udev
    # occasionally tears the node down/recreates it during the early
    # moments after a fresh add; treat that as a transient absence.
    [[ -e "/dev/$(basename "${tty}")" ]] || continue
    if probe_and_chmod_port "${tty}"; then
      :
    fi
  done
  found_one="${#CANDIDATES[@]}"
  if [[ "${found_one}" -gt 0 ]]; then
    break
  fi
  warn "  no CH340/CH341 (vid=0x${REBOT_VID}) found at /dev/ttyUSB* on attempt ${attempt}/${RESCAN_ATTEMPTS}"
  warn "  available serial ports:"
  for tty in /sys/class/tty/ttyUSB* /sys/class/tty/ttyACM*; do
    [[ -e "/dev/$(basename "${tty}")" ]] || continue
    warn "    /dev/$(basename "${tty}")"
  done
  if [[ ${attempt} -lt ${RESCAN_ATTEMPTS} ]]; then
    sleep "${RESCAN_DELAY}"
    RESCAN_DELAY=$(awk -v d="${RESCAN_DELAY}" 'BEGIN { print d * 1.7 }')
    # NOTE: do NOT call `udevadm trigger` here. Triggering causes the very
    # re-enumeration race we're trying to avoid (briefly deletes
    # /dev/ttyUSB*). Just wait — the kernel will finish settling on its own.
    udevadm settle --timeout=2 2>/dev/null || true
  fi
done

# If we still found nothing AND user already gave LEADER_PORT, try to
# materialize it (mknod) before accepting it as a candidate. This is
# the explicit-override path: when the operator knows which port is
# the leader, we should never require a hotplug just to satisfy udev.
if [[ "${#CANDIDATES[@]}" -eq 0 ]] && [[ -n "${LEADER_PORT}" ]]; then
  if [[ ! -e "${LEADER_PORT}" ]]; then
    tty_name="$(basename "${LEADER_PORT}")"
    if ensure_devnode "${tty_name}"; then
      log "  LEADER_PORT=${LEADER_PORT} missing; mknod restored it from sysfs"
    fi
  fi
  if [[ -e "${LEADER_PORT}" ]]; then
    log "  no CH340 found by VID scan, but LEADER_PORT=${LEADER_PORT} exists; using it as-is"
    CANDIDATES=( "${LEADER_PORT}" )
  fi
fi

if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
  {
    echo
    echo "summary:"
    echo "  no CH340/CH341 (vid=0x${REBOT_VID}) available after ${RESCAN_ATTEMPTS} attempts"
    echo "  kernelside:"
    echo "    lsusb | grep -i 1a86                              # device visible on USB?"
    echo "    lsmod | grep ch34                                  # ch341 driver loaded?"
    echo "    dmesg | grep -iE 'ttyUSB|ch34|cp210x|ftdi'        # kernel log for this VID"
    echo "    journalctl -u ModemManager -n 20                   # is ModemManager attach?"
    echo "  physical:"
    echo "    re-seat the USB-C cable on the reBot leader arm"
    echo "  bypass:"
    echo "    sudo LEADER_PORT=/dev/ttyUSBn ./start-teleop.sh  # explicit override"
  } >&2
  die "plug the reBot Arm 102 leader in and re-run"
fi

case "${#CANDIDATES[@]}" in
  1)
    LEADER_PORT="${CANDIDATES[0]}"
    log "  auto-selected leader port: ${LEADER_PORT}"
    ;;
  *)
    warn "multiple CH340/CH341 devices found; please disambiguate:"
    for c in "${CANDIDATES[@]}"; do warn "  ${c}"; done
    die "set LEADER_PORT explicitly, e.g. sudo LEADER_PORT=${CANDIDATES[0]} $0"
    ;;
esac

# Re-chmod one more time right before docker runs, in case the chmod
# inside the probe loop happened during an early enumeration.
chmod 0666 "${LEADER_PORT}" 2>/dev/null \
  && log "  chmod 0666 ${LEADER_PORT}" \
  || warn "  failed to chmod ${LEADER_PORT}"
[[ -e "${LEADER_PORT}" ]] \
  || die "leader port ${LEADER_PORT} disappeared between discovery and docker run"

# Also chmod 0666 every other present ttyUSB / ttyACM so the container can
# fall back if LEADER_PORT was overridden.
for d in /dev/ttyUSB* /dev/ttyACM*; do
  [[ -e "$d" ]] || continue
  [[ "$d" == "${LEADER_PORT}" ]] && continue
  chmod 0666 "$d" 2>/dev/null || true
done

printf '%s\n' "${LEADER_PORT}" > "${LEADER_PORT_STATE}"
chmod 0644 "${LEADER_PORT_STATE}"

# -----------------------------------------------------------------------
# 7. Build the docker run command.
# -----------------------------------------------------------------------
log "step 6/7: launching teleop container"

# We always need privileged + network host so the CAN interface and
# USB devices are visible to the container exactly as on the host.
#
# --device /dev/ttyUSB*, /dev/ttyACM*, /dev/can*: pass every present port
# --device-cgroup-rule 'a *:* rwm': needed when using --device for
#                                    devices that may not exist yet
# -v /usr/local/cuda-13.2, nvidia/, nv_tegra_release:
#                                    host CUDA / Tegra user-space stack
# -e NVIDIA_VISIBLE_DEVICES=all:    enables the nvidia runtime to enumerate

DOCKER_RUN_ARGS=(
  --rm
  -it
  --name rebot-lerobot-teleop-jp72
  --hostname rebot-lerobot-teleop-jp72
  --network host
  --ipc host
  --privileged
  --ulimit memlock=-1
  --ulimit stack=67108864
  --runtime nvidia
  -e "NVIDIA_VISIBLE_DEVICES=all"
  -e "NVIDIA_DRIVER_CAPABILITIES=all"
  -e "CUDA_HOME=/usr/local/cuda"
  -e "LEADER_PORT=${LEADER_PORT}"
  -e "FOLLOWER_PORT=${FOLLOWER_PORT}"
  -e "TELEOP_FPS=${TELEOP_FPS}"
  -e "TELEOP_DURATION=${TELEOP_DURATION}"
  -e "TELEOP_DISPLAY=${TELEOP_DISPLAY}"
  -e "TELEOP_DISPLAY_IP=${TELEOP_DISPLAY_IP}"
  -e "TELEOP_DISPLAY_PORT=${TELEOP_DISPLAY_PORT}"
  -e "TELEOP_EXTRA_ARGS=${TELEOP_EXTRA_ARGS}"
)

# Host CUDA toolkit (libcudart / libcurand / ...) for Jetpack 7.2 (CUDA 13.2)
if [[ -d "${CUDA_DIR}" ]]; then
  DOCKER_RUN_ARGS+=( -v "${CUDA_DIR}:${CUDA_DIR}:ro" )
else
  warn "CUDA_DIR ${CUDA_DIR} not found; trying /usr/local/cuda"
  if [[ -d /usr/local/cuda ]]; then
    DOCKER_RUN_ARGS+=( -v /usr/local/cuda:/usr/local/cuda:ro )
  fi
fi

# Host NVIDIA user-space libs (libnvidia-*, libnvrm_*, libnvargus*, etc.).
# Jetpack 7.2: most of these live in /usr/lib/aarch64-linux-gnu/nvidia.
# The closed-source GPU driver (libcuda.so, libcuda_instrumentation.so)
# lives in /opt/nvidia/l4t-gpu-libs/nvgpu and /opt/nvidia/l4t-gpu-libs/openrm.
#
# IMPORTANT: do NOT bind-mount /opt/nvidia/l4t-gpu-libs here. The
# nvidia-container-toolkit already bind-mounts it (and creates an internal
# libcuda.so -> libcuda.so.1.1 symlink in its rootfs), so mounting the host
# path read-only would make that internal symlink step fail with
# "read-only file system".
if [[ -d "${NVIDIA_LIB_DIR}" ]]; then
  DOCKER_RUN_ARGS+=( -v "${NVIDIA_LIB_DIR}:${NVIDIA_LIB_DIR}:ro" )
else
  warn "NVIDIA_LIB_DIR ${NVIDIA_LIB_DIR} not found; skipping mount"
fi

# /usr/lib/aarch64-linux-gnu/tegrasupport was a Jetpack 6 path and
# does not exist on JP7.2. Removed.

# Jetson libcudnn (Debian package). libcudnn.so.9 lives at
# /usr/lib/aarch64-linux-gnu/ on the host and is NOT in cuda-13.2/lib64.
if [[ -d "${CUDNN_LIB_DIR}" ]]; then
  DOCKER_RUN_ARGS+=( -v "${CUDNN_LIB_DIR}:${CUDNN_LIB_DIR}:ro" )
fi

# /etc/alternatives: required so that apt-managed symlinks like
# libopenblas.so.0 -> /etc/alternatives/libopenblas.so.0-aarch64-linux-gnu
# resolve inside the container.
if [[ -d /etc/alternatives ]]; then
  DOCKER_RUN_ARGS+=( -v /etc/alternatives:/etc/alternatives:ro )
fi

# Tegra version marker (PyTorch reads this on Jetson).
if [[ -f "${NVTEGRA_RELEASE}" ]]; then
  DOCKER_RUN_ARGS+=( -v "${NVTEGRA_RELEASE}:${NVTEGRA_RELEASE}:ro" )
fi

# Pass every present USB serial port and CAN socket through to the
# container. If no ports exist yet, fall back to a permissive cgroup
# rule so hot-plug also works.
DOCKER_RUN_ARGS+=( --device-cgroup-rule 'a *:* rwm' )
for d in /dev/ttyUSB* /dev/ttyACM* /dev/can*; do
  [[ -e "$d" ]] || continue
  DOCKER_RUN_ARGS+=( --device "$d" )
done

# Also explicitly --device the resolved leader and follower so that
# --device-cgroup-rule alone is not the only path to them.
if [[ -e "${LEADER_PORT}" ]]; then
  DOCKER_RUN_ARGS+=( --device "${LEADER_PORT}" )
fi
if [[ -e "/dev/${FOLLOWER_PORT}" ]]; then
  DOCKER_RUN_ARGS+=( --device "/dev/${FOLLOWER_PORT}" )
fi

log "step 7/7: docker run ${DOCKER_RUN_ARGS[*]} ${IMAGE_TAG}"
exec "${DOCKER[@]}" run "${DOCKER_RUN_ARGS[@]}" "${IMAGE_TAG}"
