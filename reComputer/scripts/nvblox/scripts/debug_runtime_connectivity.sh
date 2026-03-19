#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

MANAGED_ROOT="${MANAGED_ROOT_DEFAULT}"
LAUNCH_PACKAGE="isaac_orbbec_launch"
LAUNCH_FILE="recomputer_orbbec_dynamics.launch.py"
VSLAM_PROBE_LAUNCH_FILE="recomputer_orbbec_vslam_probe.launch.py"
HOST_CAMERA_LAUNCH_FILE="${ORBBEC_HOST_LAUNCH_PATH_DEFAULT}"
HOST_CAMERA_CONFIG_FILE="${ORBBEC_HOST_CONFIG_PATH_DEFAULT}"
HOST_CAMERA_CAPABILITY_CONFIG_FILE="${ORBBEC_HOST_STEREO_PROBE_CONFIG_PATH_DEFAULT}"
EXPECTED_COLOR_CAMERA_INFO_FRAME="camera_color_optical_frame"
HOST_STEREO_CAPABILITY_TIMEOUT_SEC=15
CAMERA_VISIBILITY_TIMEOUT_SEC=25
VSLAM_POSE_TIMEOUT_SEC=30
RUNTIME_OUTPUT_TIMEOUT_SEC=30
CURRENT_STAGE=""
HOST_CAMERA_PID=""
HOST_CAMERA_DEVICE_STATE_BEFORE_LAUNCH=""
HOST_CAMERA_READINESS_OUTPUT=""
HOST_CAMERA_CAPABILITY_OUTPUT=""

while (($#)); do
  case "$1" in
    --managed-root)
      shift
      MANAGED_ROOT="$1"
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

ensure_supported_user_context
if should_reexec_as_setup_user; then
  die "Do not invoke debug_runtime_connectivity.sh with sudo directly."
fi
require_bootstrapped_managed_root "${MANAGED_ROOT}"
ensure_docker_access

HOST_WS="${MANAGED_ROOT}/ros2_ws"
CONTAINER_WS="${MANAGED_ROOT}/isaac_ros-dev"
CONTAINER_STAMP="${CONTAINER_WS}/.setup-nvbox/container_workspace.env"
IMAGE_STAMP="${MANAGED_ROOT}/.stamps/derived_image.env"
HOST_STAMP="${MANAGED_ROOT}/.stamps/host_workspace.env"
LOG_DIR="${MANAGED_ROOT}/logs"
HOST_CAMERA_LOG="${LOG_DIR}/host-camera-debug-$(date '+%Y%m%d-%H%M%S').log"
HOST_CAMERA_CAPABILITY_LOG="${LOG_DIR}/host-camera-capability-debug-$(date '+%Y%m%d-%H%M%S').log"
PREPARED_CONTAINER_REQUIRED_PACKAGE="isaac_orbbec_launch"
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

begin_stage() {
  CURRENT_STAGE="$1"
  info "Stage ${CURRENT_STAGE}"
}

pass_stage() {
  info "PASS ${CURRENT_STAGE}"
}

fail_stage() {
  local message="${1:-failed}"
  die "FAIL ${CURRENT_STAGE}: ${message}"
}

validate_prepared_runtime_state() {
  local current_context_hash=""
  local current_image_id=""

  [[ -f "${HOST_WS}/install/setup.bash" ]] || die "Host workspace is missing at ${HOST_WS}."
  [[ -f "${CONTAINER_WS}/install/setup.bash" ]] || die "Container workspace is missing at ${CONTAINER_WS}."
  [[ -f "${CONTAINER_STAMP}" ]] || die "Container workspace stamp is missing at ${CONTAINER_STAMP}."
  [[ -f "${HOST_CAMERA_LAUNCH_FILE}" ]] || die "Missing host camera launch file ${HOST_CAMERA_LAUNCH_FILE}."
  [[ -f "${HOST_CAMERA_CONFIG_FILE}" ]] || die "Missing host camera config ${HOST_CAMERA_CONFIG_FILE}."
  [[ -f "${HOST_CAMERA_CAPABILITY_CONFIG_FILE}" ]] || die "Missing stereo capability probe config ${HOST_CAMERA_CAPABILITY_CONFIG_FILE}."
  [[ -f "${IMAGE_STAMP}" ]] || die "Derived image stamp is missing at ${IMAGE_STAMP}."
  [[ -f "${HOST_STAMP}" ]] || die "Host workspace stamp is missing at ${HOST_STAMP}."
  docker_cmd image inspect "${DERIVED_IMAGE_TAG}" >/dev/null 2>&1 || die "Derived image ${DERIVED_IMAGE_TAG} is missing."

  current_context_hash="$(container_image_context_hash)"
  current_image_id="$(docker_image_id "${DERIVED_IMAGE_TAG}")"

  # shellcheck disable=SC1090
  source "${IMAGE_STAMP}"
  [[ "${STAMP_CONTEXT_HASH:-}" == "${current_context_hash}" ]] || \
    die "Prepared derived image is stale for the current repo state."

  # shellcheck disable=SC1090
  source "${HOST_STAMP}"
  [[ "${HOST_ORBBEC_VERSION:-}" == "${ORBBEC_VERSION}" ]] || \
    die "Prepared host workspace version is ${HOST_ORBBEC_VERSION:-unknown}, expected ${ORBBEC_VERSION}."

  # shellcheck disable=SC1090
  source "${CONTAINER_STAMP}"
  [[ "${STAMP_WORKSPACE_SPEC_VERSION:-}" == "${CONTAINER_WORKSPACE_SPEC_VERSION}" ]] || \
    die "Prepared container workspace spec is ${STAMP_WORKSPACE_SPEC_VERSION:-unknown}, expected ${CONTAINER_WORKSPACE_SPEC_VERSION}."
  [[ "${STAMP_IMAGE_CONTEXT_HASH:-}" == "${current_context_hash}" ]] || \
    die "Prepared container workspace is stale for the current repo state."
  [[ "${STAMP_IMAGE_ID:-}" == "${current_image_id}" ]] || \
    die "Prepared container workspace was built against image ${STAMP_IMAGE_ID:-unknown}, expected ${current_image_id}."

  source_ros_setup "${HOST_WS}"
  ros2 pkg prefix orbbec_camera >/dev/null 2>&1 || die "Prepared host workspace cannot resolve orbbec_camera."

  if ! validate_package_install_artifacts "${CONTAINER_WS}" "${PREPARED_CONTAINER_REQUIRED_PACKAGE}" "${PREPARED_CONTAINER_REQUIRED_PATHS[@]}"; then
    die "Prepared container install artifacts are missing or invalid."
  fi

  info "Prepared derived image context hash: ${STAMP_CONTEXT_HASH}"
  info "Prepared host Orbbec version: ${HOST_ORBBEC_VERSION}"
  info "Prepared container workspace spec: ${STAMP_WORKSPACE_SPEC_VERSION}"
}

host_camera_stream_summary() {
  printf 'stereo, depth, and color'
}

ensure_gemini2_ready_for_debug() {
  local gemini2_state=""

  cleanup_residual_gemini2_processes "pre-debug Gemini2 cleanup" || true
  log_gemini2_device_state "Gemini2 device state before debug"

  gemini2_state="$(gemini2_device_state)"
  case "${gemini2_state}" in
    ready)
      return 0
      ;;
    usb_missing)
      return 1
      ;;
    usb_present_no_video)
      warn "Gemini2 USB device is present, but no /dev/video nodes were found. Attempting one automatic recovery."
      recover_gemini2_device "debug preflight" 0 1 1
      return $?
      ;;
    *)
      warn "Unexpected Gemini2 device state during debug preflight: ${gemini2_state}"
      return 1
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
  cleanup_residual_gemini2_processes "post-debug Gemini2 cleanup" || true
  log_gemini2_device_state "Gemini2 device state after debug cleanup"
}

trap stop_host_camera_driver EXIT INT TERM

launch_host_camera_process() {
  local config_file="$1"
  local log_path="$2"
  local purpose="$3"
  local launch_cmd=""

  HOST_CAMERA_DEVICE_STATE_BEFORE_LAUNCH="$(gemini2_device_state)"
  launch_cmd=$(
    cat <<EOF
source /opt/ros/${ROS_DISTRO_DEFAULT}/setup.bash
source "${HOST_WS}/install/setup.bash"
$(emit_ros_discovery_env_shell_exports)
exec ros2 launch "${HOST_CAMERA_LAUNCH_FILE}" "config_file_path:=${config_file}"
EOF
  )

  info "Launching Gemini2 ${purpose} on the host with config ${config_file}."
  bash -lc "${launch_cmd}" >>"${log_path}" 2>&1 &
  HOST_CAMERA_PID=$!
  info "Host camera log: ${log_path}"
}

launch_host_camera() {
  HOST_CAMERA_READINESS_OUTPUT=""
  launch_host_camera_process "${HOST_CAMERA_CONFIG_FILE}" "${HOST_CAMERA_LOG}" "mobile-mapping driver"
}

launch_host_camera_stereo_probe() {
  HOST_CAMERA_CAPABILITY_OUTPUT=""
  launch_host_camera_process "${HOST_CAMERA_CAPABILITY_CONFIG_FILE}" "${HOST_CAMERA_CAPABILITY_LOG}" "stereo capability probe"
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
    HOST_CAMERA_READINESS_OUTPUT="${readiness_output}"
    printf '%s\n' "${readiness_output}" >&2
    return 1
  }

  HOST_CAMERA_READINESS_OUTPUT="${readiness_output}"
  while IFS= read -r readiness_line; do
    [[ -n "${readiness_line}" ]] || continue
    info "${readiness_line}"
  done <<< "${readiness_output}"

  return 0
}

probe_host_stereo_capability() {
  local probe_output=""

  source_ros_setup "${HOST_WS}"

  launch_host_camera_stereo_probe
  probe_output="$(
    python3 - "${HOST_STEREO_CAPABILITY_TIMEOUT_SEC}" <<'PY' 2>&1
import sys
import time

import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, Image

timeout_seconds = float(sys.argv[1])


class StereoCapabilityProbe(Node):
    def __init__(self):
        super().__init__('orbbec_host_stereo_capability_probe')
        self.frames = {}
        self.received = {
            'depth_info': False,
            'left_ir_info': False,
            'right_ir_info': False,
            'depth_image': False,
            'infra_1': False,
            'infra_2': False,
        }
        self.create_subscription(CameraInfo, '/camera/depth/camera_info', self._info('depth_info'), qos_profile_sensor_data)
        self.create_subscription(CameraInfo, '/camera/left_ir/camera_info', self._info('left_ir_info'), qos_profile_sensor_data)
        self.create_subscription(CameraInfo, '/camera/right_ir/camera_info', self._info('right_ir_info'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/depth/image_raw', self._mark('depth_image'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/orbbec_camera_node/output/infra_1', self._mark('infra_1'), qos_profile_sensor_data)
        self.create_subscription(Image, '/camera/orbbec_camera_node/output/infra_2', self._mark('infra_2'), qos_profile_sensor_data)

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
    print('[stereo-probe] Waiting for host stereo IR and depth topics', flush=True)
    rclpy.init(args=None)
    node = StereoCapabilityProbe()
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
            print('[stereo-probe] Timed out waiting for: ' + ', '.join(missing), file=sys.stderr, flush=True)
            return 1

        for key in ('depth_info', 'left_ir_info', 'right_ir_info'):
            print(f'[stereo-probe] Observed {key} frame_id: {node.frames.get(key, "<empty>")}', flush=True)
        return 0
    finally:
        executor.remove_node(node)
        node.destroy_node()
        rclpy.shutdown()


sys.exit(main())
PY
  )" || {
    HOST_CAMERA_CAPABILITY_OUTPUT="${probe_output}"
    printf '%s\n' "${probe_output}" >&2
    return 1
  }

  HOST_CAMERA_CAPABILITY_OUTPUT="${probe_output}"
  while IFS= read -r probe_line; do
    [[ -n "${probe_line}" ]] || continue
    info "${probe_line}"
  done <<< "${probe_output}"

  return 0
}

handle_stereo_capability_failure() {
  local driver_exited=0
  local current_state=""
  local recovery_succeeded=0

  if ! kill -0 "${HOST_CAMERA_PID}" 2>/dev/null; then
    driver_exited=1
  fi
  current_state="$(gemini2_device_state)"

  log_host_camera_failure_diagnostics "${HOST_CAMERA_CAPABILITY_LOG}" "${HOST_CAMERA_CAPABILITY_OUTPUT}" "Host stereo capability debug failure"

  if (( driver_exited )) && recover_gemini2_after_host_camera_failure "host stereo capability debug probe" "${HOST_CAMERA_DEVICE_STATE_BEFORE_LAUNCH}"; then
    recovery_succeeded=1
    current_state="$(gemini2_device_state)"
  fi

  if (( driver_exited )) && [[ "${current_state}" == "usb_present_no_video" ]]; then
    fail_stage "The stereo capability probe failed and the camera lost its /dev/video nodes. Automatic recovery did not restore the device."
  fi

  if (( recovery_succeeded )); then
    fail_stage "The stereo capability probe recovered the device, but the current camera or connection still does not expose the stereo IR topics required by this Visual SLAM + NVBlox demo."
  fi

  fail_stage "The current Orbbec camera or connection does not expose the stereo IR + depth topics required by this Visual SLAM + NVBlox demo. Use a stereo-capable model such as Gemini 330 series, Gemini 2 XL, or Gemini 2 VL."
}

handle_host_camera_failure() {
  local driver_exited=0
  local current_state=""
  local recovery_succeeded=0

  if ! kill -0 "${HOST_CAMERA_PID}" 2>/dev/null; then
    driver_exited=1
  fi
  current_state="$(gemini2_device_state)"

  log_host_camera_failure_diagnostics "${HOST_CAMERA_LOG}" "${HOST_CAMERA_READINESS_OUTPUT}" "Host Gemini2 debug failure"

  if (( driver_exited )) && recover_gemini2_after_host_camera_failure "host camera debug failure" "${HOST_CAMERA_DEVICE_STATE_BEFORE_LAUNCH}"; then
    recovery_succeeded=1
    current_state="$(gemini2_device_state)"
  fi

  if (( driver_exited )); then
    if [[ "${current_state}" == "usb_present_no_video" ]]; then
      fail_stage "Host Gemini2 driver exited before camera streams became ready, and the device lost its /dev/video nodes. Automatic recovery did not restore the camera."
    fi
    if (( recovery_succeeded )); then
      fail_stage "Host Gemini2 driver exited before camera streams became ready. Automatic recovery restored the device, but the formal mobile-mapping stream set still did not stabilize."
    fi
    fail_stage "Host Gemini2 driver exited before camera streams became ready."
  fi

  fail_stage "Camera stream readiness probe failed while the host Gemini2 driver was still running."
}

probe_container_camera_visibility() {
  local probe_output=""
  local probe_args=(
    run
    --rm
    -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
    -e "EXPECTED_COLOR_FRAME=${EXPECTED_COLOR_CAMERA_INFO_FRAME}"
    -e "PROBE_TIMEOUT_SECONDS=${CAMERA_VISIBILITY_TIMEOUT_SEC}"
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
    -e "PROBE_TIMEOUT_SECONDS=${VSLAM_POSE_TIMEOUT_SEC}"
    -e "NVBLOX_GLOBAL_FRAME=odom"
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
LOG_FILE="/tmp/orbbec-vslam-probe.log"
LAUNCH_PID=""

cleanup() {
  if [[ -n "${LAUNCH_PID}" ]]; then
    kill -TERM "${LAUNCH_PID}" 2>/dev/null || true
    wait "${LAUNCH_PID}" 2>/dev/null || true
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

probe_full_demo_runtime_output() {
  local probe_output=""
  local probe_args=(
    run
    --rm
    -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
    -e "NVBLOX_LAUNCH_PACKAGE=${LAUNCH_PACKAGE}"
    -e "NVBLOX_LAUNCH_FILE=${LAUNCH_FILE}"
    -e "NVBLOX_GLOBAL_FRAME=odom"
    -e "RUNTIME_PROBE_TIMEOUT_SECONDS=${RUNTIME_OUTPUT_TIMEOUT_SEC}"
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
LAUNCH_LOG="/tmp/nvblox-full-demo-probe.log"
LAUNCH_PID=""
PROBE_PID=""

cleanup() {
  if [[ -n "${PROBE_PID}" ]]; then
    kill -TERM "${PROBE_PID}" 2>/dev/null || true
    wait "${PROBE_PID}" 2>/dev/null || true
  fi
  if [[ -n "${LAUNCH_PID}" ]]; then
    kill -TERM "${LAUNCH_PID}" 2>/dev/null || true
    wait "${LAUNCH_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

ros2 launch "${NVBLOX_LAUNCH_PACKAGE}" "${NVBLOX_LAUNCH_FILE}" run_rviz:=False global_frame:="${NVBLOX_GLOBAL_FRAME}" >"${LAUNCH_LOG}" 2>&1 &
LAUNCH_PID=$!

python3 - "${RUNTIME_PROBE_TIMEOUT_SECONDS}" <<'PY' &
import sys
import time

import rclpy
from nav_msgs.msg import OccupancyGrid, Odometry
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import PointCloud2

timeout_seconds = float(sys.argv[1])


class RuntimeProbe(Node):
    def __init__(self):
        super().__init__('nvblox_runtime_output_probe')
        self.odom_result = None
        self.map_result = None
        self.create_subscription(Odometry, '/visual_slam/tracking/odometry', self._odom_callback, 10)
        self.create_subscription(PointCloud2, '/nvblox_node/combined_esdf_pointcloud', self._map_callback, qos_profile_sensor_data)
        self.create_subscription(PointCloud2, '/nvblox_node/dynamic_esdf_pointcloud', self._map_callback, qos_profile_sensor_data)
        self.create_subscription(OccupancyGrid, '/nvblox_node/combined_map_slice', self._slice_callback, 10)

    def _odom_callback(self, msg: Odometry):
        self.odom_result = (
            '/visual_slam/tracking/odometry',
            f'frame_id={msg.header.frame_id or "<empty>"} child_frame_id={msg.child_frame_id or "<empty>"}')

    def _map_callback(self, msg: PointCloud2):
        self.map_result = (
            '/nvblox dynamic pointcloud',
            f'frame_id={msg.header.frame_id or "<empty>"} width={msg.width} height={msg.height}')

    def _slice_callback(self, msg: OccupancyGrid):
        self.map_result = (
            '/nvblox_node/combined_map_slice',
            f'frame_id={msg.header.frame_id or "<empty>"} width={msg.info.width} height={msg.info.height}')


def main() -> int:
    print('[full-demo-probe] Waiting for Visual SLAM odometry or dynamic NVBlox output', flush=True)
    rclpy.init(args=None)
    node = RuntimeProbe()
    executor = SingleThreadedExecutor()
    executor.add_node(node)
    deadline = time.monotonic() + timeout_seconds

    try:
        while time.monotonic() < deadline:
            executor.spin_once(timeout_sec=0.2)
            if node.map_result is not None:
                topic_name, details = node.map_result
                print(f'[full-demo-probe] Runtime output probe received {topic_name}: {details}', flush=True)
                return 0
            if node.odom_result is not None:
                topic_name, details = node.odom_result
                print(f'[full-demo-probe] Runtime output probe received {topic_name}: {details}', flush=True)
                return 0

        print('[full-demo-probe] Runtime output probe timed out waiting for Visual SLAM odometry or dynamic NVBlox output.', file=sys.stderr, flush=True)
        return 2
    finally:
        executor.remove_node(node)
        node.destroy_node()
        rclpy.shutdown()


sys.exit(main())
PY
PROBE_PID=$!

wait "${PROBE_PID}" || probe_status=$?
probe_status="${probe_status:-0}"
if (( probe_status != 0 )); then
  printf '[full-demo-probe] Relevant launch log tail:\n'
  tail -n 40 "${LAUNCH_LOG}" 2>/dev/null || true
  exit 1
fi
exit 0
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

enable_managed_fastdds_udp_runtime "${MANAGED_ROOT}"
export_effective_ros_discovery_env
validate_prepared_runtime_state

begin_stage "1/8 Gemini2 device state"
if ensure_gemini2_ready_for_debug; then
  pass_stage
else
  fail_stage "Gemini2 is not ready for runtime debugging."
fi

begin_stage "2/8 Host ROS discovery env"
log_ros_discovery_env "Host ROS discovery env"
pass_stage

begin_stage "3/8 Container ROS discovery env"
info "Container ROS discovery env: $(ros_discovery_env_summary)"
pass_stage

begin_stage "4/8 Host stereo capability probe"
if probe_host_stereo_capability; then
  info "Host stereo capability probe passed."
  stop_host_camera_driver
  pass_stage
else
  handle_stereo_capability_failure
fi

begin_stage "5/8 Host camera stream readiness"
launch_host_camera
if wait_for_camera_streams_ready; then
  pass_stage
else
  handle_host_camera_failure
fi

begin_stage "6/8 Container camera visibility probe"
if probe_container_camera_visibility; then
  pass_stage
else
  fail_stage "The container cannot discover the expected host camera topics with the current ROS discovery environment. The stereo capability probe already passed, so this is not a camera-capability issue."
fi

begin_stage "7/8 Container Visual SLAM pose probe"
if probe_container_visual_slam_pose; then
  pass_stage
else
  fail_stage "The container did not produce Visual SLAM odometry or TF output after the stereo capability and host stream probes passed."
fi

begin_stage "8/8 Full demo runtime output probe"
if probe_full_demo_runtime_output; then
  pass_stage
else
  fail_stage "The current prepared launch/runtime path did not reach Visual SLAM odometry or dynamic NVBlox output."
fi

info "Runtime connectivity debug completed successfully."
