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
USE_GUI=0
RUN_RVIZ=1
LAUNCH_PACKAGE="isaac_orbbec_launch"
LAUNCH_FILE="recomputer_orbbec_dynamics.launch.py"
VSLAM_PROBE_LAUNCH_FILE="recomputer_orbbec_vslam_probe.launch.py"
EXPECTED_COLOR_CAMERA_INFO_FRAME="camera_color_optical_frame"
VSLAM_POSE_PROBE_TIMEOUT_SEC=30
PREPARE_HINT="Run NVBLOX_MODE=prepare NVBLOX_FORCE_REBUILD=1 reComputer run nvblox."
CONTAINER_PREPARE_HINT="Prepared container workspace is invalid. ${PREPARE_HINT}"
HOST_CAMERA_LAUNCH_FILE="${ORBBEC_HOST_LAUNCH_PATH_DEFAULT}"
HOST_CAMERA_CONFIG_FILE="${ORBBEC_HOST_CONFIG_PATH_DEFAULT}"
PREPARED_CONTAINER_REQUIRED_PACKAGE="isaac_orbbec_launch"

[[ -f "${HOST_WS}/install/setup.bash" ]] || die "Host workspace is missing at ${HOST_WS}. ${PREPARE_HINT}"
[[ -f "${CONTAINER_WS}/install/setup.bash" ]] || die "Container workspace is missing at ${CONTAINER_WS}. ${PREPARE_HINT}"
[[ -f "${CONTAINER_STAMP}" ]] || die "Container workspace stamp is missing at ${CONTAINER_STAMP}. ${PREPARE_HINT}"
[[ -f "${HOST_CAMERA_LAUNCH_FILE}" ]] || die "Missing host camera launch file ${HOST_CAMERA_LAUNCH_FILE}."
[[ -f "${HOST_CAMERA_CONFIG_FILE}" ]] || die "Missing host camera config ${HOST_CAMERA_CONFIG_FILE}."
docker_cmd image inspect "${DERIVED_IMAGE_TAG}" >/dev/null 2>&1 || die "Derived image ${DERIVED_IMAGE_TAG} is missing. ${PREPARE_HINT}"

PREPARED_CONTAINER_REQUIRED_PATHS=(
  "launch/perception/vslam.launch.py"
  "launch/nvblox/nvblox.launch.py"
  "launch/rviz/rviz.launch.py"
  "launch/recomputer_orbbec_dynamics.launch.py"
  "launch/recomputer_orbbec_vslam_probe.launch.py"
  "config/sensors/orbbec.yaml"
  "config/nvblox/nvblox_base.yaml"
  "config/nvblox/specializations/nvblox_dynamics.yaml"
  "config/nvblox/specializations/nvblox_realsense.yaml"
  "config/rviz/realsense_dynamics_example.rviz"
)

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
    -e "EXPECTED_COLOR_FRAME=${EXPECTED_COLOR_CAMERA_INFO_FRAME}"
    -e "PROBE_TIMEOUT_SECONDS=25"
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
python3 - "${EXPECTED_COLOR_FRAME}" "${PROBE_TIMEOUT_SECONDS}" <<'PY'
import sys
import time

import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, Image

expected_color_frame = sys.argv[1]
timeout_seconds = float(sys.argv[2])


class CameraVisibilityProbe(Node):
    def __init__(self):
        super().__init__('orbbec_container_camera_visibility_probe')
        self.frames = {}
        self.received = {
            'color_info': False,
            'depth_info': False,
            'left_ir_info': False,
            'right_ir_info': False,
            'infra_1': False,
            'infra_2': False,
            'depth_output': False,
        }
        self.create_subscription(CameraInfo, '/camera/color/camera_info', self._info('color_info'), qos_profile_sensor_data)
        self.create_subscription(CameraInfo, '/camera/depth/camera_info', self._info('depth_info'), qos_profile_sensor_data)
        self.create_subscription(CameraInfo, '/camera/left_ir/camera_info', self._info('left_ir_info'), qos_profile_sensor_data)
        self.create_subscription(CameraInfo, '/camera/right_ir/camera_info', self._info('right_ir_info'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/orbbec_camera_node/output/infra_1', self._mark('infra_1'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/orbbec_camera_node/output/infra_2', self._mark('infra_2'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/orbbec_camera_node/output/depth', self._mark('depth_output'), qos_profile_sensor_data)

    def _mark(self, key):
        def callback(_msg):
            self.received[key] = True
        return callback

    def _info(self, key):
        def callback(msg: CameraInfo):
            self.received[key] = True
            self.frames[key] = msg.header.frame_id
        return callback


def main() -> int:
    print('[container-probe] Waiting for host stereo, depth, and color topics inside the container', flush=True)
    rclpy.init(args=None)
    node = CameraVisibilityProbe()
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
            print('[container-probe] Timed out waiting for: ' + ', '.join(missing), file=sys.stderr, flush=True)
            return 1

        for key in ('color_info', 'depth_info', 'left_ir_info', 'right_ir_info'):
            print(f'[container-probe] Observed {key} frame_id: {node.frames.get(key, "<empty>")}', flush=True)

        if node.frames['color_info'] != expected_color_frame:
            print(
                f'[container-probe] Unexpected /camera/color/camera_info frame_id: {node.frames["color_info"]} '
                f'(expected {expected_color_frame})',
                file=sys.stderr,
                flush=True)
            return 1
        if not node.frames['depth_info']:
            print('[container-probe] /camera/depth/camera_info frame_id is empty', file=sys.stderr, flush=True)
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

probe_container_visual_slam_pose() {
  local probe_output=""
  local probe_args=(
    run
    --rm
    -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
    -e "NVBLOX_LAUNCH_PACKAGE=${LAUNCH_PACKAGE}"
    -e "NVBLOX_VSLAM_PROBE_LAUNCH_FILE=${VSLAM_PROBE_LAUNCH_FILE}"
    -e "PROBE_TIMEOUT_SECONDS=${VSLAM_POSE_PROBE_TIMEOUT_SEC}"
    -e "NVBLOX_GLOBAL_FRAME=odom"
    -v "${CONTAINER_WS}:/workspaces/isaac_ros-dev"
  )

  append_jetson_container_args probe_args
  append_ros_discovery_container_args probe_args

  info "Probing container Visual SLAM pose output in a short-lived container."

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

LOG_FILE="/tmp/orbbec-vslam-probe.log"
LAUNCH_PID=""

terminate_pid() {
  local pid="${1:-}"
  local signal=""
  local deadline=0

  [[ -n "${pid}" ]] || return 0
  if ! kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi

  for signal in INT TERM KILL; do
    kill "-${signal}" "${pid}" 2>/dev/null || true
    deadline=$((SECONDS + 2))
    while ((SECONDS < deadline)); do
      if ! kill -0 "${pid}" 2>/dev/null; then
        return 0
      fi
      sleep 1
    done
  done

  return 0
}

cleanup() {
  if [[ -n "${LAUNCH_PID}" ]] && kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    terminate_pid "${LAUNCH_PID}" || true
  fi
}
trap cleanup EXIT INT TERM

ros2 launch "${NVBLOX_LAUNCH_PACKAGE}" "${NVBLOX_VSLAM_PROBE_LAUNCH_FILE}" global_frame:="${NVBLOX_GLOBAL_FRAME}" >"${LOG_FILE}" 2>&1 &
LAUNCH_PID=$!

status=0
python3 - "${PROBE_TIMEOUT_SECONDS}" "${NVBLOX_GLOBAL_FRAME}" <<'PY' || status=$?
import sys
import time

import rclpy
from nav_msgs.msg import Odometry
from rclpy.duration import Duration
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.time import Time
from tf2_ros import Buffer, TransformListener

timeout_seconds = float(sys.argv[1])
global_frame = sys.argv[2]


class VisualSlamProbe(Node):
    def __init__(self):
        super().__init__('orbbec_container_vslam_probe')
        self.odom_frame_id = None
        self.child_frame_id = None
        self.create_subscription(Odometry, '/visual_slam/tracking/odometry', self._odom_callback, 10)

    def _odom_callback(self, msg: Odometry):
        self.odom_frame_id = msg.header.frame_id
        self.child_frame_id = msg.child_frame_id


def main() -> int:
    print('[container-vslam-probe] Waiting for Visual SLAM odometry and TF output', flush=True)
    rclpy.init(args=None)
    node = VisualSlamProbe()
    executor = SingleThreadedExecutor()
    executor.add_node(node)
    tf_buffer = Buffer(cache_time=Duration(seconds=timeout_seconds))
    tf_listener = TransformListener(tf_buffer, node, spin_thread=False)
    deadline = time.monotonic() + timeout_seconds

    try:
      while time.monotonic() < deadline:
        executor.spin_once(timeout_sec=0.2)
        has_tf = tf_buffer.can_transform(global_frame, 'camera_link', Time(), timeout=Duration(seconds=0.1))
        has_odom = node.odom_frame_id is not None
        if has_tf and has_odom:
          print(
              f'[container-vslam-probe] Observed /visual_slam/tracking/odometry frame_id={node.odom_frame_id} '
              f'child_frame_id={node.child_frame_id}',
              flush=True)
          print(f'[container-vslam-probe] TF probe passed for {global_frame} <- camera_link', flush=True)
          return 0

      print(
          f'[container-vslam-probe] Timed out waiting for Visual SLAM odometry and TF {global_frame} <- camera_link.',
          file=sys.stderr,
          flush=True)
      return 1
    finally:
      del tf_listener
      executor.remove_node(node)
      node.destroy_node()
      rclpy.shutdown()


sys.exit(main())
PY

if (( status != 0 )); then
  printf '[container-vslam-probe] Relevant launch log tail:\n'
  tail -n 40 "${LOG_FILE}" 2>/dev/null || true
fi

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
    warn "Gemini2 USB device is still present, but /dev/video nodes are missing after cleanup. Attempting light recovery."
    if ! recover_gemini2_device "post-run cleanup" 0 0 0; then
      warn "Gemini2 light recovery did not restore /dev/video nodes after cleanup."
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
  local launch_cmd=""

  ensure_gemini2_ready_for_run
  launch_cmd=$(
    cat <<EOF
source /opt/ros/${ROS_DISTRO_DEFAULT}/setup.bash
source "${HOST_WS}/install/setup.bash"
$(emit_ros_discovery_env_shell_exports)
exec ros2 launch "${HOST_CAMERA_LAUNCH_FILE}" "config_file_path:=${HOST_CAMERA_CONFIG_FILE}"
EOF
  )

  info "Launching Gemini2 mobile-mapping driver on the host."
  bash -lc "${launch_cmd}" >>"${HOST_CAMERA_LOG}" 2>&1 &
  HOST_CAMERA_PID=$!
  info "Host camera log: ${HOST_CAMERA_LOG}"
}

wait_for_camera_streams_ready() {
  local readiness_output=""

  source_ros_setup "${HOST_WS}"

  readiness_output="$(
    python3 - "${EXPECTED_COLOR_CAMERA_INFO_FRAME}" <<'PY' 2>&1
import sys
import time

import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, Image

expected_color_frame = sys.argv[1]
timeout_seconds = 90.0


class CameraReadinessProbe(Node):
    def __init__(self):
        super().__init__('orbbec_host_readiness_probe')
        self.frames = {}
        self.received = {
            'color_info': False,
            'depth_info': False,
            'left_ir_info': False,
            'right_ir_info': False,
            'color_image': False,
            'depth_image': False,
            'infra_1': False,
            'infra_2': False,
            'depth_output': False,
        }
        self.create_subscription(CameraInfo, '/camera/color/camera_info', self._info('color_info'), qos_profile_sensor_data)
        self.create_subscription(CameraInfo, '/camera/depth/camera_info', self._info('depth_info'), qos_profile_sensor_data)
        self.create_subscription(CameraInfo, '/camera/left_ir/camera_info', self._info('left_ir_info'), qos_profile_sensor_data)
        self.create_subscription(CameraInfo, '/camera/right_ir/camera_info', self._info('right_ir_info'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/color/image_raw', self._mark('color_image'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/depth/image_raw', self._mark('depth_image'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/orbbec_camera_node/output/infra_1', self._mark('infra_1'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/orbbec_camera_node/output/infra_2', self._mark('infra_2'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/orbbec_camera_node/output/depth', self._mark('depth_output'), qos_profile_sensor_data)

    def _mark(self, key):
        def callback(_msg):
            self.received[key] = True
        return callback

    def _info(self, key):
        def callback(msg: CameraInfo):
            self.received[key] = True
            self.frames[key] = msg.header.frame_id
        return callback


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
            print('Host stream readiness probe timed out waiting for: ' + ', '.join(missing), file=sys.stderr)
            return 1

        for key in ('color_info', 'depth_info', 'left_ir_info', 'right_ir_info'):
            print(f'{key} frame_id={node.frames.get(key, "<empty>")}')

        if node.frames.get('color_info') != expected_color_frame:
            print(
                f'Unexpected /camera/color/camera_info frame_id: {node.frames.get("color_info", "")} '
                f'(expected {expected_color_frame})',
                file=sys.stderr)
            return 1
        if not node.frames.get('depth_info'):
            print('Unexpected empty /camera/depth/camera_info frame_id', file=sys.stderr)
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
    -e "NVBLOX_LAUNCH_PACKAGE=${LAUNCH_PACKAGE}"
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
PACKAGE_PREFIX="$(ros2 pkg prefix "${NVBLOX_LAUNCH_PACKAGE}" 2>/dev/null || true)"
[[ -n "${PACKAGE_PREFIX}" ]]
[[ "${STAMP_WORKSPACE_SPEC_VERSION:-}" == "${EXPECTED_WORKSPACE_SPEC_VERSION}" ]]
[[ -f "${PACKAGE_PREFIX}/share/${NVBLOX_LAUNCH_PACKAGE}/launch/${NVBLOX_LAUNCH_FILE}" ]]
EOF
  )

  info "Validating prepared launch artifact inside the container."
  docker_cmd "${validate_args[@]}" "${DERIVED_IMAGE_TAG}" bash -lc "${validate_cmd}" >/dev/null 2>&1
}

configure_display() {
  if (( HEADLESS )); then
    RUN_RVIZ=0
    return 0
  fi

  if [[ -z "${DISPLAY:-}" ]]; then
    warn "DISPLAY is not set. Falling back to headless mode."
    HEADLESS=1
    RUN_RVIZ=0
    return 0
  fi

  if [[ ! -d /tmp/.X11-unix ]]; then
    warn "/tmp/.X11-unix is missing. Falling back to headless mode."
    HEADLESS=1
    RUN_RVIZ=0
    return 0
  fi

  if ! command -v xhost >/dev/null 2>&1; then
    warn "xhost is not available. Falling back to headless mode."
    HEADLESS=1
    RUN_RVIZ=0
    return 0
  fi

  if xhost +si:localuser:root >/dev/null 2>&1; then
    XHOST_GRANTED=1
    USE_GUI=1
    RUN_RVIZ=1
    return 0
  fi

  warn "Failed to grant X11 access for the container. Falling back to headless mode."
  HEADLESS=1
  RUN_RVIZ=0
}

configure_display

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
info "Host stereo, depth, and color streams are ready for mobile mapping."

if ! probe_container_camera_visibility; then
  die "Host camera streams are ready, but the container cannot discover host stereo/depth/color topics. Check the ROS discovery environment shown above."
fi

if ! probe_container_visual_slam_pose; then
  die "Host camera streams are ready, but the container did not produce Visual SLAM odometry. Check the launch log tail above."
fi

docker_cmd rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

DOCKER_ARGS=(
  run
  --rm
  --name "${CONTAINER_NAME}"
  -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
  -e "NVBLOX_LAUNCH_PACKAGE=${LAUNCH_PACKAGE}"
  -e "NVBLOX_LAUNCH_FILE=${LAUNCH_FILE}"
  -e "NVBLOX_RUN_RVIZ=${RUN_RVIZ}"
  -e "NVBLOX_GLOBAL_FRAME=odom"
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
  info "Starting in headless mode with ${LAUNCH_PACKAGE}/${LAUNCH_FILE}."
fi

info "Launching NVBlox mobile mapping demo in container ${CONTAINER_NAME}."
docker_cmd "${DOCKER_ARGS[@]}" "${DERIVED_IMAGE_TAG}" bash /opt/nvblox/bin/launch_nvblox.sh
