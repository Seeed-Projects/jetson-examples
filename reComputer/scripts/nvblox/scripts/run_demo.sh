#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

MANAGED_ROOT="${MANAGED_ROOT_DEFAULT}"
HEADLESS=0

while (($#)); do
  case "$1" in
    --managed-root)
      shift
      MANAGED_ROOT="$1"
      ;;
    --headless)
      HEADLESS=1
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

ensure_supported_user_context
if should_reexec_as_setup_user; then
  die "Do not invoke run_demo.sh with sudo directly. Run reComputer run nvblox instead."
fi
require_bootstrapped_managed_root "${MANAGED_ROOT}"
ensure_docker_access

HOST_WS="${MANAGED_ROOT}/ros2_ws"
CONTAINER_WS="${MANAGED_ROOT}/isaac_ros-dev"
CONTAINER_STAMP="${CONTAINER_WS}/.setup-nvbox/container_workspace.env"
IMAGE_STAMP="${MANAGED_ROOT}/.stamps/derived_image.env"
HOST_STAMP="${MANAGED_ROOT}/.stamps/host_workspace.env"
LOG_DIR="${MANAGED_ROOT}/logs"
CONTAINER_NAME="${CONTAINER_NAME_DEFAULT}"
HOST_CAMERA_LOG="${LOG_DIR}/host-camera-$(date '+%Y%m%d-%H%M%S').log"
HOST_CAMERA_PID=""
XHOST_GRANTED=0
LAUNCH_FILE="orbbec_example.launch.py"
USE_GUI=0
EXPECTED_CAMERA_INFO_FRAME="camera_color_optical_frame"
PREPARE_HINT="Run NVBLOX_MODE=prepare NVBLOX_FORCE_REBUILD=1 reComputer run nvblox."
CONTAINER_PREPARE_HINT="Prepared container workspace is invalid. ${PREPARE_HINT}"

[[ -f "${HOST_WS}/install/setup.bash" ]] || die "Host workspace is missing at ${HOST_WS}. ${PREPARE_HINT}"
[[ -f "${CONTAINER_WS}/install/setup.bash" ]] || die "Container workspace is missing at ${CONTAINER_WS}. ${PREPARE_HINT}"
[[ -f "${CONTAINER_STAMP}" ]] || die "Container workspace stamp is missing at ${CONTAINER_STAMP}. ${PREPARE_HINT}"
docker_cmd image inspect "${DERIVED_IMAGE_TAG}" >/dev/null 2>&1 || die "Derived image ${DERIVED_IMAGE_TAG} is missing. ${PREPARE_HINT}"

PREPARED_CONTAINER_REQUIRED_PACKAGE="nvblox_examples_bringup"
PREPARED_CONTAINER_REQUIRED_PATHS=(
  "launch/orbbec_transforms.launch.py"
  "launch/orbbec_example.launch.py"
  "launch/orbbec_debug.launch.py"
  "launch/orbbec_nvblox_standalone.launch.py"
  "config/nvblox/specializations/nvblox_orbbec_static.yaml"
)
CONTAINER_STATIC_TF_TIMEOUT_SEC=20

validate_prepared_image_state() {
  local current_context_hash=""

  [[ -f "${IMAGE_STAMP}" ]] || die "Derived image stamp is missing at ${IMAGE_STAMP}. ${PREPARE_HINT}"
  docker_cmd image inspect "${DERIVED_IMAGE_TAG}" >/dev/null 2>&1 || die "Derived image ${DERIVED_IMAGE_TAG} is missing. ${PREPARE_HINT}"

  current_context_hash="$(container_image_context_hash)"

  # shellcheck disable=SC1090
  source "${IMAGE_STAMP}"

  [[ "${STAMP_CONTEXT_HASH:-}" == "${current_context_hash}" ]] || \
    die "Derived image ${DERIVED_IMAGE_TAG} is stale for the current repo state. ${PREPARE_HINT}"

  info "Prepared derived image context hash: ${STAMP_CONTEXT_HASH}"
  info "Prepared derived image stamped at: ${STAMPED_AT:-unknown}"
}

validate_prepared_host_workspace() {
  [[ -f "${HOST_STAMP}" ]] || die "Host workspace stamp is missing at ${HOST_STAMP}. ${PREPARE_HINT}"
  [[ -f "${HOST_WS}/install/setup.bash" ]] || die "Host workspace is missing at ${HOST_WS}. ${PREPARE_HINT}"

  # shellcheck disable=SC1090
  source "${HOST_STAMP}"

  [[ "${HOST_ORBBEC_VERSION:-}" == "${ORBBEC_VERSION}" ]] || \
    die "Prepared host workspace version is ${HOST_ORBBEC_VERSION:-unknown}, expected ${ORBBEC_VERSION}. ${PREPARE_HINT}"

  source_ros_setup "${HOST_WS}"
  ros2 pkg prefix orbbec_camera >/dev/null 2>&1 || \
    die "Prepared host workspace cannot resolve orbbec_camera. ${PREPARE_HINT}"

  info "Prepared host Orbbec version: ${HOST_ORBBEC_VERSION}"
  info "Prepared host workspace stamped at: ${HOST_STAMPED_AT:-unknown}"
}

validate_prepared_container_workspace_state() {
  local current_context_hash=""
  local current_image_id=""

  [[ -f "${CONTAINER_WS}/install/setup.bash" ]] || die "Container workspace is missing at ${CONTAINER_WS}. ${PREPARE_HINT}"
  [[ -f "${CONTAINER_STAMP}" ]] || die "Container workspace stamp is missing at ${CONTAINER_STAMP}. ${PREPARE_HINT}"

  current_context_hash="$(container_image_context_hash)"
  current_image_id="$(docker_image_id "${DERIVED_IMAGE_TAG}")"

  # shellcheck disable=SC1090
  source "${CONTAINER_STAMP}"

  [[ "${STAMP_WORKSPACE_SPEC_VERSION:-}" == "${CONTAINER_WORKSPACE_SPEC_VERSION}" ]] || \
    die "Prepared container workspace spec is ${STAMP_WORKSPACE_SPEC_VERSION:-unknown}, expected ${CONTAINER_WORKSPACE_SPEC_VERSION}. ${PREPARE_HINT}"
  [[ "${STAMP_IMAGE_CONTEXT_HASH:-}" == "${current_context_hash}" ]] || \
    die "Prepared container workspace is stale for the current repo state. ${PREPARE_HINT}"
  [[ "${STAMP_IMAGE_ID:-}" == "${current_image_id}" ]] || \
    die "Prepared container workspace was built against image ${STAMP_IMAGE_ID:-unknown}, expected ${current_image_id}. ${PREPARE_HINT}"

  if ! validate_package_install_artifacts "${CONTAINER_WS}" "${PREPARED_CONTAINER_REQUIRED_PACKAGE}" "${PREPARED_CONTAINER_REQUIRED_PATHS[@]}"; then
    die "Prepared container install artifacts are missing or invalid. ${PREPARE_HINT}"
  fi

  info "Prepared container workspace spec: ${STAMP_WORKSPACE_SPEC_VERSION}"
  info "Prepared container workspace stamped at: ${STAMPED_AT:-unknown}"
  info "Validated prepared container artifacts: ${PREPARED_CONTAINER_REQUIRED_PATHS[*]}"
}

probe_container_camera_visibility() {
  local probe_output=""
  local probe_args=(
    run
    --rm
    -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
    -e "EXPECTED_CAMERA_INFO_FRAME=${EXPECTED_CAMERA_INFO_FRAME}"
    -e "PROBE_TIMEOUT_SECONDS=20"
    -v "${CONTAINER_WS}:/workspaces/isaac_ros-dev"
  )

  append_jetson_container_args probe_args
  append_ros_discovery_container_args probe_args

  probe_output="$(
    docker_cmd "${probe_args[@]}" "${DERIVED_IMAGE_TAG}" bash -lc "$(cat <<'EOF'
set -euo pipefail
restore_nounset=0
if [[ $- == *u* ]]; then
  restore_nounset=1
  set +u
fi
source "/opt/ros/${ROS_DISTRO}/setup.bash"
source "/workspaces/isaac_ros-dev/install/setup.bash"
if (( restore_nounset )); then
  set -u
fi
python3 - "${EXPECTED_CAMERA_INFO_FRAME}" "${PROBE_TIMEOUT_SECONDS}" <<'PY'
import sys
import time

import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo

expected_frame = sys.argv[1]
timeout_seconds = float(sys.argv[2])


class CameraVisibilityProbe(Node):
    def __init__(self):
        super().__init__('orbbec_container_camera_visibility_probe')
        self.frames = {}
        self.create_subscription(
            CameraInfo,
            '/camera/color/camera_info',
            self._color_info_callback,
            qos_profile_sensor_data)
        self.create_subscription(
            CameraInfo,
            '/camera/depth/camera_info',
            self._depth_info_callback,
            qos_profile_sensor_data)

    def _color_info_callback(self, msg: CameraInfo):
        self.frames['color'] = msg.header.frame_id

    def _depth_info_callback(self, msg: CameraInfo):
        self.frames['depth'] = msg.header.frame_id


def main() -> int:
    print('[container-probe] Waiting for host camera_info topics inside the container', flush=True)
    rclpy.init(args=None)
    node = CameraVisibilityProbe()
    executor = SingleThreadedExecutor()
    executor.add_node(node)
    deadline = time.monotonic() + timeout_seconds

    try:
        while time.monotonic() < deadline:
            executor.spin_once(timeout_sec=0.2)
            if 'color' in node.frames and 'depth' in node.frames:
                break

        missing = []
        if 'color' not in node.frames:
            missing.append('/camera/color/camera_info')
        if 'depth' not in node.frames:
            missing.append('/camera/depth/camera_info')
        if missing:
            print(
                '[container-probe] Timed out waiting for: ' + ', '.join(missing),
                file=sys.stderr,
                flush=True)
            return 1

        print(f'[container-probe] Observed /camera/color/camera_info frame_id: {node.frames["color"]}', flush=True)
        print(f'[container-probe] Observed /camera/depth/camera_info frame_id: {node.frames["depth"]}', flush=True)

        if node.frames['color'] != expected_frame:
            print(
                f'[container-probe] Unexpected /camera/color/camera_info frame_id: {node.frames["color"]} '
                f'(expected {expected_frame})',
                file=sys.stderr,
                flush=True)
            return 1
        if node.frames['depth'] != expected_frame:
            print(
                f'[container-probe] Unexpected /camera/depth/camera_info frame_id: {node.frames["depth"]} '
                f'(expected {expected_frame})',
                file=sys.stderr,
                flush=True)
            return 1

        print('[container-probe] Container camera visibility probe passed.', flush=True)
        return 0
    finally:
        executor.remove_node(node)
        node.destroy_node()
        rclpy.shutdown()


sys.exit(main())
PY
EOF
)" 2>&1
  )" || {
    printf '%s\n' "${probe_output}" >&2
    return 1
  }

  while IFS= read -r probe_line; do
    [[ -n "${probe_line}" ]] || continue
    info "${probe_line}"
  done <<< "${probe_output}"

  return 0
}

probe_container_static_tf() {
  local probe_output=""
  local probe_args=(
    run
    --rm
    -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
    -e "PROBE_TIMEOUT_SECONDS=${CONTAINER_STATIC_TF_TIMEOUT_SEC}"
    -v "${CONTAINER_WS}:/workspaces/isaac_ros-dev"
  )

  append_jetson_container_args probe_args
  append_ros_discovery_container_args probe_args

  probe_output="$(
    docker_cmd "${probe_args[@]}" "${DERIVED_IMAGE_TAG}" bash -lc "$(cat <<'EOF'
set -euo pipefail
restore_nounset=0
if [[ $- == *u* ]]; then
  restore_nounset=1
  set +u
fi
source "/opt/ros/${ROS_DISTRO}/setup.bash"
source "/workspaces/isaac_ros-dev/install/setup.bash"
if (( restore_nounset )); then
  set -u
fi

LOG_FILE="/tmp/orbbec-tf-probe.log"
LAUNCH_PID=""
LAUNCH_STOP_TIMEOUT=8

terminate_launch() {
  local signal=""
  local deadline=0

  if [[ -z "${LAUNCH_PID}" ]] || ! kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    LAUNCH_PID=""
    return 0
  fi

  for signal in INT TERM KILL; do
    kill "-${signal}" "${LAUNCH_PID}" 2>/dev/null || true
    deadline=$((SECONDS + LAUNCH_STOP_TIMEOUT))
    while ((SECONDS < deadline)); do
      if ! kill -0 "${LAUNCH_PID}" 2>/dev/null; then
        wait "${LAUNCH_PID}" 2>/dev/null || true
        LAUNCH_PID=""
        return 0
      fi
      sleep 1
    done
  done

  wait "${LAUNCH_PID}" 2>/dev/null || true
  LAUNCH_PID=""
}

cleanup() {
  terminate_launch
}
trap cleanup EXIT INT TERM

ros2 launch nvblox_examples_bringup orbbec_transforms.launch.py >"${LOG_FILE}" 2>&1 &
LAUNCH_PID=$!

status=0
python3 - "${PROBE_TIMEOUT_SECONDS}" <<'PY' || status=$?
import sys
import time

import rclpy
from rclpy.duration import Duration
from rclpy.time import Time
from tf2_ros import Buffer, TransformListener

timeout_seconds = float(sys.argv[1])
required_transforms = [
    ('odom', 'base_link'),
    ('odom', 'camera_link'),
    ('odom', 'camera_color_optical_frame'),
]


def main() -> int:
    print('[container-tf-probe] Waiting for managed static TF chain inside the container', flush=True)
    rclpy.init(args=None)
    node = rclpy.create_node('orbbec_container_tf_probe')
    tf_buffer = Buffer(cache_time=Duration(seconds=timeout_seconds))
    tf_listener = TransformListener(tf_buffer, node, spin_thread=False)
    deadline = time.monotonic() + timeout_seconds
    last_missing = []

    try:
        while time.monotonic() < deadline:
            rclpy.spin_once(node, timeout_sec=0.2)
            last_missing = []
            for target_frame, source_frame in required_transforms:
                if not tf_buffer.can_transform(
                        target_frame,
                        source_frame,
                        Time(),
                        timeout=Duration(seconds=0.1)):
                    last_missing.append(f'{target_frame} <- {source_frame}')

            if not last_missing:
                print(
                    '[container-tf-probe] TF probe passed for odom <- base_link, '
                    'odom <- camera_link, odom <- camera_color_optical_frame',
                    flush=True)
                return 0

        print(
            '[container-tf-probe] TF probe failed. Missing transforms: '
            + ', '.join(last_missing or ['unknown']),
            file=sys.stderr,
            flush=True)
        return 1
    finally:
        del tf_listener
        node.destroy_node()
        rclpy.shutdown()


sys.exit(main())
PY

if (( status != 0 )); then
  printf '[container-tf-probe] Relevant launch log tail:\n'
  tail -n 40 "${LOG_FILE}" 2>/dev/null || true
fi

terminate_launch
exit "${status}"
EOF
)" 2>&1
  )" || {
    printf '%s\n' "${probe_output}" >&2
    return 1
  }

  while IFS= read -r probe_line; do
    [[ -n "${probe_line}" ]] || continue
    info "${probe_line}"
  done <<< "${probe_output}"

  return 0
}

ensure_gemini2_ready_for_run() {
  local gemini2_state=""

  cleanup_residual_gemini2_processes "pre-run Gemini2 cleanup" || true
  log_gemini2_device_state "Gemini2 device state before host launch"

  gemini2_state="$(gemini2_device_state)"
  case "${gemini2_state}" in
    ready)
      return 0
      ;;
    usb_missing)
      die "Gemini2 is not connected. Current device state: usb_missing."
      ;;
    usb_present_no_video)
      warn "Gemini2 USB device is present, but no /dev/video nodes were found before host launch. Attempting one automatic recovery."
      if ! recover_gemini2_device "pre-run host launch" 0 1 1; then
        gemini2_state="$(gemini2_device_state)"
        die "Gemini2 USB device is present, but video nodes were not recovered before launch. Current device state: ${gemini2_state}."
      fi
      ;;
    *)
      die "Unexpected Gemini2 device state before host launch: ${gemini2_state}"
      ;;
  esac
}

stop_host_camera_driver() {
  local signal=""
  local deadline=0

  if [[ -n "${HOST_CAMERA_PID}" ]] && kill -0 "${HOST_CAMERA_PID}" 2>/dev/null; then
    info "Stopping host Gemini2 driver (pid=${HOST_CAMERA_PID})."
    for signal in INT TERM KILL; do
      kill "-${signal}" "${HOST_CAMERA_PID}" 2>/dev/null || true
      deadline=$((SECONDS + GEMINI2_SIGNAL_TIMEOUT_SECONDS))
      while ((SECONDS < deadline)); do
        if ! kill -0 "${HOST_CAMERA_PID}" 2>/dev/null; then
          break 2
        fi
        sleep 1
      done
    done
  fi

  HOST_CAMERA_PID=""
  cleanup_residual_gemini2_processes "post-run Gemini2 cleanup" || true

  if [[ "$(gemini2_device_state)" == "usb_present_no_video" ]]; then
    warn "Gemini2 USB device is still present, but /dev/video nodes are missing after cleanup. Attempting full recovery."
    if ! recover_gemini2_device "post-run cleanup" 0 1 0; then
      warn "Gemini2 full recovery did not restore /dev/video nodes after cleanup."
    fi
  fi

  log_gemini2_device_state "Gemini2 device state after cleanup"
}

cleanup() {
  stop_host_camera_driver

  if (( XHOST_GRANTED )); then
    xhost -si:localuser:root >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

launch_host_camera() {
  local launch_cmd

  ensure_gemini2_ready_for_run
  launch_cmd=$(
    cat <<EOF
source /opt/ros/${ROS_DISTRO_DEFAULT}/setup.bash
source "${HOST_WS}/install/setup.bash"
$(emit_ros_discovery_env_shell_exports)
exec ros2 launch orbbec_camera gemini2.launch.py publish_tf:=false tf_publish_rate:=0.0
EOF
  )

  info "Launching Gemini2 driver on the host."
  bash -lc "${launch_cmd}" >>"${HOST_CAMERA_LOG}" 2>&1 &
  HOST_CAMERA_PID=$!
  info "Host camera log: ${HOST_CAMERA_LOG}"
}

wait_for_camera_streams_ready() {
  local readiness_output=""

  source_ros_setup "${HOST_WS}"

  readiness_output="$(
    python3 - "${EXPECTED_CAMERA_INFO_FRAME}" <<'PY' 2>&1
import sys
import time

import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, Image

expected_frame = sys.argv[1]
timeout_seconds = 90.0


class CameraReadinessProbe(Node):
    def __init__(self):
        super().__init__('orbbec_host_readiness_probe')
        self.frames = {}
        self.received = {
            'color_info': False,
            'depth_info': False,
            'color_image': False,
            'depth_image': False,
        }
        self.create_subscription(
            CameraInfo,
            '/camera/color/camera_info',
            self._color_info_callback,
            qos_profile_sensor_data)
        self.create_subscription(
            CameraInfo,
            '/camera/depth/camera_info',
            self._depth_info_callback,
            qos_profile_sensor_data)
        self.create_subscription(
            Image,
            '/camera/color/image_raw',
            self._color_image_callback,
            qos_profile_sensor_data)
        self.create_subscription(
            Image,
            '/camera/depth/image_raw',
            self._depth_image_callback,
            qos_profile_sensor_data)

    def _color_info_callback(self, msg: CameraInfo):
        self.received['color_info'] = True
        self.frames['color_info'] = msg.header.frame_id

    def _depth_info_callback(self, msg: CameraInfo):
        self.received['depth_info'] = True
        self.frames['depth_info'] = msg.header.frame_id

    def _color_image_callback(self, msg: Image):
        self.received['color_image'] = True

    def _depth_image_callback(self, msg: Image):
        self.received['depth_image'] = True


def main():
    rclpy.init(args=None)
    node = CameraReadinessProbe()
    executor = SingleThreadedExecutor()
    executor.add_node(node)
    deadline = time.monotonic() + timeout_seconds

    try:
        while time.monotonic() < deadline:
            executor.spin_once(timeout_sec=0.2)
            if all(node.received.values()):
                break

        missing = [name for name, received in node.received.items() if not received]
        if missing:
            print(
                'Host stream readiness probe timed out waiting for: ' + ', '.join(missing),
                file=sys.stderr)
            return 1

        color_frame = node.frames.get('color_info', '')
        depth_frame = node.frames.get('depth_info', '')
        print(f'/camera/color/camera_info frame_id={color_frame}')
        print(f'/camera/depth/camera_info frame_id={depth_frame}')

        if color_frame != expected_frame:
            print(
                f'Unexpected /camera/color/camera_info frame_id: {color_frame} '
                f'(expected {expected_frame})',
                file=sys.stderr)
            return 1
        if depth_frame != expected_frame:
            print(
                f'Unexpected /camera/depth/camera_info frame_id: {depth_frame} '
                f'(expected {expected_frame})',
                file=sys.stderr)
            return 1
        return 0
    finally:
        executor.remove_node(node)
        node.destroy_node()
        rclpy.shutdown()


sys.exit(main())
PY
  )" || {
    printf '%s\n' "${readiness_output}" >&2
    return 1
  }

  while IFS= read -r readiness_line; do
    [[ -n "${readiness_line}" ]] || continue
    info "${readiness_line}"
  done <<< "${readiness_output}"

  return 0
}

validate_container_launch_artifact() {
  local validate_cmd=""
  local validate_args=(
    run
    --rm
    -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
    -e "NVBLOX_LAUNCH_FILE=${LAUNCH_FILE}"
    -e "EXPECTED_WORKSPACE_SPEC_VERSION=${CONTAINER_WORKSPACE_SPEC_VERSION}"
    -v "${CONTAINER_WS}:/workspaces/isaac_ros-dev"
  )

  append_jetson_container_args validate_args
  append_ros_discovery_container_args validate_args
  validate_cmd=$(
    cat <<'EOF'
set -euo pipefail
restore_nounset=0
if [[ $- == *u* ]]; then
  restore_nounset=1
  set +u
fi
source "/opt/ros/${ROS_DISTRO}/setup.bash"
source "/workspaces/isaac_ros-dev/install/setup.bash"
source "/workspaces/isaac_ros-dev/.setup-nvbox/container_workspace.env"
if (( restore_nounset )); then
  set -u
fi
PACKAGE_PREFIX="$(ros2 pkg prefix nvblox_examples_bringup 2>/dev/null || true)"
[[ -n "${PACKAGE_PREFIX}" ]]
[[ "${STAMP_WORKSPACE_SPEC_VERSION:-}" == "${EXPECTED_WORKSPACE_SPEC_VERSION}" ]]
[[ -f "${PACKAGE_PREFIX}/share/nvblox_examples_bringup/launch/${NVBLOX_LAUNCH_FILE}" ]]
EOF
  )

  info "Validating prepared launch artifact inside the container."
  docker_cmd "${validate_args[@]}" "${DERIVED_IMAGE_TAG}" bash -lc "${validate_cmd}" >/dev/null 2>&1
}

configure_display() {
  if (( HEADLESS )); then
    return 0
  fi

  if [[ -z "${DISPLAY:-}" ]]; then
    warn "DISPLAY is not set. Falling back to headless mode."
    HEADLESS=1
    return 0
  fi

  if [[ ! -d /tmp/.X11-unix ]]; then
    warn "/tmp/.X11-unix is missing. Falling back to headless mode."
    HEADLESS=1
    return 0
  fi

  if ! command -v xhost >/dev/null 2>&1; then
    warn "xhost is not available. Falling back to headless mode."
    HEADLESS=1
    return 0
  fi

  if xhost +si:localuser:root >/dev/null 2>&1; then
    XHOST_GRANTED=1
    USE_GUI=1
    LAUNCH_FILE="orbbec_example.launch.py"
    return 0
  fi

  warn "Failed to grant X11 access for the container. Falling back to headless mode."
  HEADLESS=1
}

if (( HEADLESS )); then
  LAUNCH_FILE="orbbec_debug.launch.py"
fi

configure_display
if (( HEADLESS )); then
  LAUNCH_FILE="orbbec_debug.launch.py"
fi

enable_managed_fastdds_udp_runtime "${MANAGED_ROOT}"
export_effective_ros_discovery_env
log_ros_discovery_env "Host ROS discovery env"
info "Container ROS discovery env: $(ros_discovery_env_summary)"

validate_prepared_image_state
validate_prepared_host_workspace
validate_prepared_container_workspace_state

if ! validate_container_launch_artifact; then
  die "${CONTAINER_PREPARE_HINT}"
fi

launch_host_camera
if ! wait_for_camera_streams_ready; then
  if ! kill -0 "${HOST_CAMERA_PID}" 2>/dev/null; then
    die "Host Gemini2 driver exited before camera streams became ready. Check ${HOST_CAMERA_LOG}."
  fi
  die "Camera stream readiness probe failed. Check ${HOST_CAMERA_LOG}."
fi
info "Camera streams and frame IDs are ready."

if ! probe_container_camera_visibility; then
  die "Host camera streams are ready, but the container cannot discover host camera topics. Check the ROS discovery environment shown above, or run bash reComputer/scripts/nvblox/scripts/debug_runtime_connectivity.sh for a discovery snapshot."
fi

if ! probe_container_static_tf; then
  die "Host camera streams and container camera visibility are ready, but the managed static TF chain is not queryable inside the container."
fi

docker_cmd rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

DOCKER_ARGS=(
  run
  --rm
  --name "${CONTAINER_NAME}"
  -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
  -e "NVBLOX_LAUNCH_FILE=${LAUNCH_FILE}"
  -e "EXPECTED_WORKSPACE_SPEC_VERSION=${CONTAINER_WORKSPACE_SPEC_VERSION}"
  -v "${CONTAINER_WS}:/workspaces/isaac_ros-dev"
  -v "${PROJECT_ROOT}/docker/launch_nvblox.sh:/opt/nvblox/bin/launch_nvblox.sh:ro"
)
append_jetson_container_args DOCKER_ARGS
append_ros_discovery_container_args DOCKER_ARGS

if [[ -t 0 && -t 1 ]]; then
  DOCKER_ARGS+=(-it)
else
  DOCKER_ARGS+=(-i)
fi

if (( USE_GUI )); then
  DOCKER_ARGS+=(
    -e "DISPLAY=${DISPLAY}"
    -e "QT_X11_NO_MITSHM=1"
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw
  )
else
  info "Starting in headless mode with ${LAUNCH_FILE}."
fi

info "Launching NVBlox demo in container ${CONTAINER_NAME}."
docker_cmd "${DOCKER_ARGS[@]}" "${DERIVED_IMAGE_TAG}" bash /opt/nvblox/bin/launch_nvblox.sh
