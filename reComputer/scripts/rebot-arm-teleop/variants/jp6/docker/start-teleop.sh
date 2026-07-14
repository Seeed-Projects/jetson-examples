#!/usr/bin/env bash
# One-command launcher for the reBot Arm LeRobot teleop session.
#
# What this script does (in order):
#   1. Removes `brltty` (it grabs CH340 / ttyUSB on Ubuntu).
#   2. Loads kernel modules: can_dev, peak_usb, ch341, ch34x.
#   3. Brings up the SocketCAN interface produced by peak_usb at 1 Mbps
#      (auto-detects whether the adapter shows up as can0 / can1 / ...).
#   4. Runs the rebot-lerobot-teleop image with the host's CUDA stack
#      bind-mounted in (NOT bundled inside the image).
#   5. Inside the container, `teleop.sh` exec's `lerobot-teleoperate`
#      with the Seeed B601 RS follower + reBot Arm 102 leader pair.
#
# Usage:
#   sudo ./docker/start-teleop.sh
#   LEADER_PORT=/dev/ttyUSB1 sudo ./docker/start-teleop.sh
#   BITRATE=500000 TELEOP_FPS=60 sudo ./docker/start-teleop.sh
#
# Run with --build first if you haven't built the image yet.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOST_DIR="${PROJECT_ROOT}/docker/host"

IMAGE_TAG="${IMAGE_TAG:-rebot-lerobot-teleop:latest}"
# Default to empty → auto-detect by CH340/CH341 (VID 0x1a86) vid/pid walk.
# Override with LEADER_PORT=/dev/ttyUSB1 if you want a specific device.
LEADER_PORT="${LEADER_PORT:-}"
LEADER_PORT_STATE="/tmp/.rebot-arm-leader-port"
FOLLOWER_PORT="${FOLLOWER_PORT:-}"      # auto-detect if empty
BITRATE="${BITRATE:-1000000}"
RESTART_MS="${RESTART_MS:-100}"
CUDA_DIR="${CUDA_DIR:-/usr/local/cuda-12.6}"
NVTEGRA_RELEASE="${NVTEGRA_RELEASE:-/etc/nv_tegra_release}"
NVIDIA_LIB_DIR="${NVIDIA_LIB_DIR:-/usr/lib/aarch64-linux-gnu/nvidia}"
TEGRA_LIB_DIR="${TEGRA_LIB_DIR:-/usr/lib/aarch64-linux-gnu/tegrasupport}"
CUDNN_LIB_DIR="${CUDNN_LIB_DIR:-/usr/lib/aarch64-linux-gnu}"
DOCKER_SOCKET="${DOCKER_SOCKET:-/var/run/docker.sock}"

TELEOP_FPS="${TELEOP_FPS:-30}"
TELEOP_DURATION="${TELEOP_DURATION:-}"
TELEOP_DISPLAY="${TELEOP_DISPLAY:-false}"
TELEOP_DISPLAY_IP="${TELEOP_DISPLAY_IP:-}"
TELEOP_DISPLAY_PORT="${TELEOP_DISPLAY_PORT:-}"
TELEOP_EXTRA_ARGS="${TELEOP_EXTRA_ARGS:-}"

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
  die "image ${IMAGE_TAG} not found. Run: sudo ./docker/build-image.sh"
fi

# -----------------------------------------------------------------------
# 2. Root is required for kmod + can + brltty steps.
# -----------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "run with sudo: sudo $0"
fi

# -----------------------------------------------------------------------
# 3. brltty must go.
# -----------------------------------------------------------------------
log "step 1/5: removing brltty"
bash "${HOST_DIR}/remove-brltty.sh" || warn "brltty cleanup had warnings"

# -----------------------------------------------------------------------
# 4. Kernel modules.
# -----------------------------------------------------------------------
log "step 2/5: loading kernel modules"
bash "${HOST_DIR}/load-kernel-modules.sh" \
  || die "kernel module loader failed"

# -----------------------------------------------------------------------
# 5. SocketCAN.
# -----------------------------------------------------------------------
log "step 3/5: bringing up SocketCAN at ${BITRATE} bps"
: "${FOLLOWER_PORT:=}"
export CAN_IFACE_HINT="${FOLLOWER_PORT}"
export BITRATE
export RESTART_MS

CAN_LOG="$(bash "${HOST_DIR}/setup-can.sh" 2>&1)" \
  || { printf '%s\n' "${CAN_LOG}" >&2; die "CAN bringup failed"; }
printf '%s\n' "${CAN_LOG}"

# Re-read whichever interface setup-can.sh actually selected.
if [[ -z "${FOLLOWER_PORT}" ]]; then
  if [[ -r /tmp/.rebot-arm-can-iface ]]; then
    FOLLOWER_PORT="$(cat /tmp/.rebot-arm-can-iface)"
    log "auto-detected CAN iface: ${FOLLOWER_PORT}"
  else
    die "could not determine CAN interface (FOLLOWER_PORT is empty)"
  fi
fi

# -----------------------------------------------------------------------
# 6. Resolve the leader USB-serial port (auto-detect by CH340/CH341 VID).
# -----------------------------------------------------------------------
log "step 4/5: resolving leader serial port"
export LEADER_PORT
bash "${HOST_DIR}/setup-leader-port.sh" \
  || die "leader port auto-detect failed; set LEADER_PORT=/dev/ttyUSBn explicitly"

# setup-leader-port.sh writes the resolved path to a state file we can
# re-read even if the user only set LEADER_PORT as a hint.
if [[ -r "${LEADER_PORT_STATE}" ]]; then
  RESOLVED_LEADER="$(cat "${LEADER_PORT_STATE}")"
  if [[ -n "${RESOLVED_LEADER}" ]] && [[ -e "${RESOLVED_LEADER}" ]]; then
    if [[ -z "${LEADER_PORT}" ]] || [[ "${LEADER_PORT}" != "${RESOLVED_LEADER}" ]]; then
      log "leader port auto-detected: ${RESOLVED_LEADER}"
    fi
    LEADER_PORT="${RESOLVED_LEADER}"
  else
    die "leader state file ${LEADER_PORT_STATE} points at ${RESOLVED_LEADER:-<empty>} which does not exist"
  fi
else
  die "leader port resolver did not write ${LEADER_PORT_STATE}"
fi

# -----------------------------------------------------------------------
# 7. Build the docker run command.
# -----------------------------------------------------------------------
log "step 5/5: launching teleop container"

# We always need privileged + network host so the CAN interface and
# USB devices are visible to the container exactly as on the host.
#
# --device /dev/ttyUSB*: pass every present leader/follower serial port
# --device-cgroup-rule 'a *:* rwm': needed when using --device for
#                                    devices that may not exist yet
# -v /usr/local/cuda-12.6, nvidia/, tegrasupport/, nv_tegra_release:
#                                    host CUDA / Tegra user-space stack
# -e NVIDIA_VISIBLE_DEVICES=all:    enables the nvidia runtime to enumerate

DOCKER_RUN_ARGS=(
  --rm
  -it
  --name rebot-lerobot-teleop
  --hostname rebot-lerobot-teleop
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

# Host CUDA toolkit (libcudart / libcurand / ...).
if [[ -d "${CUDA_DIR}" ]]; then
  DOCKER_RUN_ARGS+=( -v "${CUDA_DIR}:${CUDA_DIR}:ro" )
else
  warn "CUDA_DIR ${CUDA_DIR} not found; skipping mount"
fi

# Host NVIDIA user-space libs (libcuda.so etc.).
if [[ -d "${NVIDIA_LIB_DIR}" ]]; then
  DOCKER_RUN_ARGS+=( -v "${NVIDIA_LIB_DIR}:${NVIDIA_LIB_DIR}:ro" )
else
  warn "NVIDIA_LIB_DIR ${NVIDIA_LIB_DIR} not found; skipping mount"
fi

# Jetson tegrasupport libs (libnvbuf_*, etc.).
if [[ -d "${TEGRA_LIB_DIR}" ]]; then
  DOCKER_RUN_ARGS+=( -v "${TEGRA_LIB_DIR}:${TEGRA_LIB_DIR}:ro" )
fi

# Jetson libcudnn (Debian package). libcudnn.so.9 lives at
# /usr/lib/aarch64-linux-gnu/ on the host and is NOT in cuda-12.6/lib64.
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

# Pass every present USB serial port through to the container. If no
# ports exist yet, fall back to a permissive cgroup rule so hot-plug
# also works.
DOCKER_RUN_ARGS+=( --device-cgroup-rule 'a *:* rwm' )
for d in /dev/ttyUSB* /dev/ttyACM*; do
  [[ -e "$d" ]] || continue
  DOCKER_RUN_ARGS+=( --device "$d" )
done

# Mount the host SocketCAN interface into the container's network
# namespace. We are already running with --network host, so it should
# be visible as ${FOLLOWER_PORT} inside, but explicit /dev mount helps
# on kernels that hide socket nodes from non-init net namespaces.
if [[ -e "/dev/${FOLLOWER_PORT}" ]]; then
  DOCKER_RUN_ARGS+=( --device "/dev/${FOLLOWER_PORT}" )
fi

log "docker run ${DOCKER_RUN_ARGS[*]} ${IMAGE_TAG}"

exec "${DOCKER[@]}" run "${DOCKER_RUN_ARGS[@]}" "${IMAGE_TAG}"
