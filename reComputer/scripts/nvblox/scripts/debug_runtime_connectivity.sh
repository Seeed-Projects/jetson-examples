#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

MANAGED_ROOT="${MANAGED_ROOT_DEFAULT}"
HEADLESS=0
USE_GUI=0
LAUNCH_FILE="orbbec_example.launch.py"
EXPECTED_CAMERA_INFO_FRAME="camera_color_optical_frame"
DEBUG_CAMERA_VISIBILITY_TIMEOUT_SEC=20
DEBUG_STATIC_TF_TIMEOUT_SEC=20
DEBUG_RUNTIME_OUTPUT_TIMEOUT_SEC=30
CURRENT_STAGE=""
XHOST_GRANTED=0
HOST_CAMERA_PID=""

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
  die "Do not invoke debug_runtime_connectivity.sh with sudo directly. Run it as the setup user from the nvblox example directory."
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

PREPARED_CONTAINER_REQUIRED_PATHS=(
  "launch/orbbec_transforms.launch.py"
  "launch/orbbec_example.launch.py"
  "launch/orbbec_debug.launch.py"
  "launch/orbbec_nvblox_standalone.launch.py"
  "config/nvblox/specializations/nvblox_orbbec_static.yaml"
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

build_base_container_args() {
  local docker_args_name="$1"
  local -n base_docker_args_ref="${docker_args_name}"

  base_docker_args_ref=(
    run
    --rm
    -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
    -v "${CONTAINER_WS}:/workspaces/isaac_ros-dev"
  )
  append_jetson_container_args "${docker_args_name}"
  append_ros_discovery_container_args "${docker_args_name}"
}

append_gui_container_args() {
  local gui_docker_args_name="$1"
  local -n gui_docker_args_ref="${gui_docker_args_name}"

  if (( USE_GUI )); then
    gui_docker_args_ref+=(
      -e "DISPLAY=${DISPLAY}"
      -e "QT_X11_NO_MITSHM=1"
      -v /tmp/.X11-unix:/tmp/.X11-unix:rw
    )
  fi
}

report_prepared_runtime_state() {
  local current_context_hash=""
  local current_image_id=""

  info "Using existing prepared artifacts only. This debug path does not rebuild the image or workspace."

  [[ -f "${HOST_WS}/install/setup.bash" ]] || die "Host workspace is missing at ${HOST_WS}."
  [[ -f "${CONTAINER_WS}/install/setup.bash" ]] || die "Container workspace is missing at ${CONTAINER_WS}."
  [[ -f "${CONTAINER_STAMP}" ]] || die "Container workspace stamp is missing at ${CONTAINER_STAMP}."
  docker_cmd image inspect "${DERIVED_IMAGE_TAG}" >/dev/null 2>&1 || die "Derived image ${DERIVED_IMAGE_TAG} is missing."

  current_context_hash="$(container_image_context_hash)"
  current_image_id="$(docker_image_id "${DERIVED_IMAGE_TAG}")"

  if [[ -f "${IMAGE_STAMP}" ]]; then
    # shellcheck disable=SC1090
    source "${IMAGE_STAMP}"
    info "Prepared derived image context hash: ${STAMP_CONTEXT_HASH:-unknown}"
    info "Prepared derived image stamped at: ${STAMPED_AT:-unknown}"
    if [[ "${STAMP_CONTEXT_HASH:-}" != "${current_context_hash}" ]]; then
      warn "Prepared derived image context hash differs from the current repo state. Continuing with the existing image for diagnosis."
    fi
  else
    warn "Derived image stamp is missing at ${IMAGE_STAMP}. Continuing with the existing image for diagnosis."
  fi

  if [[ -f "${HOST_STAMP}" ]]; then
    # shellcheck disable=SC1090
    source "${HOST_STAMP}"
    info "Prepared host Orbbec version: ${HOST_ORBBEC_VERSION:-unknown}"
    info "Prepared host workspace stamped at: ${HOST_STAMPED_AT:-unknown}"
    if [[ -n "${HOST_ORBBEC_VERSION:-}" && "${HOST_ORBBEC_VERSION:-}" != "${ORBBEC_VERSION}" ]]; then
      warn "Prepared host workspace version differs from the current repo target (${ORBBEC_VERSION}). Continuing with the prepared host workspace for diagnosis."
    fi
  else
    warn "Host workspace stamp is missing at ${HOST_STAMP}. Continuing with the prepared host workspace for diagnosis."
  fi

  source_ros_setup "${HOST_WS}"
  ros2 pkg prefix orbbec_camera >/dev/null 2>&1 || \
    die "Prepared host workspace cannot resolve orbbec_camera."

  # shellcheck disable=SC1090
  source "${CONTAINER_STAMP}"
  info "Prepared container workspace spec: ${STAMP_WORKSPACE_SPEC_VERSION:-unknown}"
  info "Prepared container workspace stamped at: ${STAMPED_AT:-unknown}"
  if [[ "${STAMP_WORKSPACE_SPEC_VERSION:-}" != "${CONTAINER_WORKSPACE_SPEC_VERSION}" ]]; then
    warn "Prepared container workspace spec differs from the current repo target (${CONTAINER_WORKSPACE_SPEC_VERSION}). Continuing with the prepared workspace for diagnosis."
  fi
  if [[ "${STAMP_IMAGE_CONTEXT_HASH:-}" != "${current_context_hash}" ]]; then
    warn "Prepared container workspace context hash differs from the current repo state. Continuing with the prepared workspace for diagnosis."
  fi
  if [[ "${STAMP_IMAGE_ID:-}" != "${current_image_id}" ]]; then
    warn "Prepared container workspace was built against a different derived image. Continuing with the current prepared workspace for diagnosis."
  fi

  if ! validate_nvblox_examples_bringup_install_artifacts "${CONTAINER_WS}" "${PREPARED_CONTAINER_REQUIRED_PATHS[@]}"; then
    die "Prepared container install artifacts are missing or invalid."
  fi

  info "Validated prepared container artifacts: ${PREPARED_CONTAINER_REQUIRED_PATHS[*]}"
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

cleanup() {
  stop_host_camera_driver

  if (( XHOST_GRANTED )); then
    xhost -si:localuser:root >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

launch_host_camera() {
  local launch_cmd=""

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

probe_container_camera_visibility() {
  local probe_output=""
  local probe_args=()

  build_base_container_args probe_args
  probe_args+=(
    -e "EXPECTED_CAMERA_INFO_FRAME=${EXPECTED_CAMERA_INFO_FRAME}"
    -e "PROBE_TIMEOUT_SECONDS=${DEBUG_CAMERA_VISIBILITY_TIMEOUT_SEC}"
  )

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

print_discovery_snapshot() {
  printf '[container-probe] Container ROS discovery env: ROS_DOMAIN_ID=%s, ROS_LOCALHOST_ONLY=%s, RMW_IMPLEMENTATION=%s, ROS_AUTOMATIC_DISCOVERY_RANGE=%s, ROS_STATIC_PEERS=%s, CYCLONEDDS_URI=%s, CYCLONEDDS_HOME=%s, FASTDDS_DEFAULT_PROFILES_FILE=%s, FASTRTPS_DEFAULT_PROFILES_FILE=%s\n' \
    "${ROS_DOMAIN_ID:-<unset>}" \
    "${ROS_LOCALHOST_ONLY:-<unset>}" \
    "${RMW_IMPLEMENTATION:-<unset>}" \
    "${ROS_AUTOMATIC_DISCOVERY_RANGE:-<unset>}" \
    "${ROS_STATIC_PEERS:-<unset>}" \
    "${CYCLONEDDS_URI:-<unset>}" \
    "${CYCLONEDDS_HOME:-<unset>}" \
    "${FASTDDS_DEFAULT_PROFILES_FILE:-<unset>}" \
    "${FASTRTPS_DEFAULT_PROFILES_FILE:-<unset>}"
  printf '[container-probe] ros2 topic list snapshot:\n'
  ros2 topic list 2>&1 | sed 's/^/[container-probe][topic] /'
  printf '[container-probe] ros2 node list snapshot:\n'
  ros2 node list 2>&1 | sed 's/^/[container-probe][node] /'
}

probe_status=0
set +e
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
probe_status=$?
set -e
if (( probe_status != 0 )); then
  print_discovery_snapshot
  exit "${probe_status}"
fi
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
  local probe_args=()

  build_base_container_args probe_args
  probe_args+=(-e "PROBE_TIMEOUT_SECONDS=${DEBUG_STATIC_TF_TIMEOUT_SEC}")

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

cleanup() {
  if [[ -n "${LAUNCH_PID}" ]] && kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    kill -INT "${LAUNCH_PID}" 2>/dev/null || true
    wait "${LAUNCH_PID}" 2>/dev/null || true
  fi
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
  local probe_args=()

  build_base_container_args probe_args
  probe_args+=(
    -e "NVBLOX_LAUNCH_FILE=${LAUNCH_FILE}"
    -e "RUNTIME_PROBE_TIMEOUT_SECONDS=${DEBUG_RUNTIME_OUTPUT_TIMEOUT_SEC}"
  )
  append_gui_container_args probe_args

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
source "/workspaces/isaac_ros-dev/.setup-nvbox/container_workspace.env"
if (( restore_nounset )); then
  set -u
fi

PACKAGE_PREFIX="$(ros2 pkg prefix nvblox_examples_bringup 2>/dev/null || true)"
[[ -n "${PACKAGE_PREFIX}" ]]
[[ -f "${PACKAGE_PREFIX}/share/nvblox_examples_bringup/launch/${NVBLOX_LAUNCH_FILE}" ]]

printf '[full-demo-probe] Workspace spec: %s\n' "${STAMP_WORKSPACE_SPEC_VERSION:-unknown}"
printf '[full-demo-probe] Launch file: %s\n' "${NVBLOX_LAUNCH_FILE}"
printf '[full-demo-probe] Managed static TF chain: odom -> base_link -> camera_link -> camera_color_optical_frame\n'

LAUNCH_LOG="/tmp/nvblox-full-demo-probe.log"
LAUNCH_PID=""
PROBE_PID=""

cleanup() {
  if [[ -n "${PROBE_PID}" ]] && kill -0 "${PROBE_PID}" 2>/dev/null; then
    kill -TERM "${PROBE_PID}" 2>/dev/null || true
    wait "${PROBE_PID}" 2>/dev/null || true
  fi
  if [[ -n "${LAUNCH_PID}" ]] && kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    kill -INT "${LAUNCH_PID}" 2>/dev/null || true
    wait "${LAUNCH_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

ros2 launch nvblox_examples_bringup "${NVBLOX_LAUNCH_FILE}" >"${LAUNCH_LOG}" 2>&1 &
LAUNCH_PID=$!

python3 - "${RUNTIME_PROBE_TIMEOUT_SECONDS}" <<'PY' &
import sys
import time

import rclpy
from nav_msgs.msg import OccupancyGrid
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import PointCloud2

timeout_seconds = float(sys.argv[1])


class NvbloxOutputProbe(Node):
    def __init__(self):
        super().__init__('nvblox_runtime_output_probe')
        self.result = None
        self.create_subscription(
            PointCloud2,
            '/nvblox_node/static_esdf_pointcloud',
            self._pointcloud_callback,
            qos_profile_sensor_data)
        self.create_subscription(
            OccupancyGrid,
            '/nvblox_node/static_map_slice',
            self._map_slice_callback,
            10)

    def _pointcloud_callback(self, msg: PointCloud2):
        self.result = (
            '/nvblox_node/static_esdf_pointcloud',
            f'frame_id={msg.header.frame_id or "<empty>"} width={msg.width} height={msg.height}')

    def _map_slice_callback(self, msg: OccupancyGrid):
        self.result = (
            '/nvblox_node/static_map_slice',
            f'frame_id={msg.header.frame_id or "<empty>"} width={msg.info.width} '
            f'height={msg.info.height} resolution={msg.info.resolution:.3f}')


def main() -> int:
    print(
        '[full-demo-probe] Waiting for /nvblox_node/static_esdf_pointcloud or '
        '/nvblox_node/static_map_slice',
        flush=True)
    rclpy.init(args=None)
    node = NvbloxOutputProbe()
    executor = SingleThreadedExecutor()
    executor.add_node(node)
    deadline = time.monotonic() + timeout_seconds

    try:
        while time.monotonic() < deadline and node.result is None:
            executor.spin_once(timeout_sec=0.2)

        if node.result is None:
            print(
                '[full-demo-probe] Runtime output probe timed out waiting for '
                '/nvblox_node/static_esdf_pointcloud or /nvblox_node/static_map_slice.',
                file=sys.stderr,
                flush=True)
            return 2

        topic_name, details = node.result
        print(f'[full-demo-probe] Runtime output probe received {topic_name}: {details}', flush=True)
        return 0
    finally:
        executor.remove_node(node)
        node.destroy_node()
        rclpy.shutdown()


sys.exit(main())
PY
PROBE_PID=$!

while true; do
  if ! kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    wait "${LAUNCH_PID}" || launch_status=$?
    launch_status="${launch_status:-0}"
    if kill -0 "${PROBE_PID}" 2>/dev/null; then
      kill -TERM "${PROBE_PID}" 2>/dev/null || true
      wait "${PROBE_PID}" 2>/dev/null || true
    fi

    if grep -q 'Camera info readiness probe timed out waiting for:' "${LAUNCH_LOG}"; then
      printf '[full-demo-probe] Launch failed during internal camera readiness probe.\n'
      grep 'Camera info readiness probe timed out waiting for:' "${LAUNCH_LOG}" | tail -n 1
      printf '[full-demo-probe] Relevant launch log tail:\n'
      tail -n 40 "${LAUNCH_LOG}" 2>/dev/null || true
      exit 1
    fi
    if grep -q 'TF readiness probe failed.' "${LAUNCH_LOG}"; then
      printf '[full-demo-probe] Launch failed during TF readiness.\n'
      grep 'TF readiness probe failed.' "${LAUNCH_LOG}" | tail -n 1
      printf '[full-demo-probe] Relevant launch log tail:\n'
      tail -n 40 "${LAUNCH_LOG}" 2>/dev/null || true
      exit 1
    fi

    printf '[full-demo-probe] Launch exited before runtime output probe succeeded (status=%s).\n' "${launch_status}"
    printf '[full-demo-probe] Relevant launch log tail:\n'
    tail -n 40 "${LAUNCH_LOG}" 2>/dev/null || true
    exit 1
  fi

  if ! kill -0 "${PROBE_PID}" 2>/dev/null; then
    wait "${PROBE_PID}" || probe_status=$?
    probe_status="${probe_status:-0}"
    if (( probe_status == 0 )); then
      printf '[full-demo-probe] Runtime output probe passed. Stopping demo launch.\n'
      exit 0
    fi

    printf '[full-demo-probe] Runtime output probe finished without observing map output.\n'
    printf '[full-demo-probe] Relevant launch log tail:\n'
    tail -n 40 "${LAUNCH_LOG}" 2>/dev/null || true
    exit 1
  fi

  sleep 1
done
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

configure_display() {
  if (( HEADLESS )); then
    LAUNCH_FILE="orbbec_debug.launch.py"
    return 0
  fi

  if [[ -z "${DISPLAY:-}" ]]; then
    warn "DISPLAY is not set. Falling back to headless launch probing."
    HEADLESS=1
    LAUNCH_FILE="orbbec_debug.launch.py"
    return 0
  fi

  if [[ ! -d /tmp/.X11-unix ]]; then
    warn "/tmp/.X11-unix is missing. Falling back to headless launch probing."
    HEADLESS=1
    LAUNCH_FILE="orbbec_debug.launch.py"
    return 0
  fi

  if ! command -v xhost >/dev/null 2>&1; then
    warn "xhost is not available. Falling back to headless launch probing."
    HEADLESS=1
    LAUNCH_FILE="orbbec_debug.launch.py"
    return 0
  fi

  if xhost +si:localuser:root >/dev/null 2>&1; then
    XHOST_GRANTED=1
    USE_GUI=1
    LAUNCH_FILE="orbbec_example.launch.py"
    return 0
  fi

  warn "Failed to grant X11 access for the container. Falling back to headless launch probing."
  HEADLESS=1
  LAUNCH_FILE="orbbec_debug.launch.py"
}

enable_managed_fastdds_udp_runtime "${MANAGED_ROOT}"
export_effective_ros_discovery_env
configure_display
report_prepared_runtime_state

begin_stage "1/7 Gemini2 device state"
if ensure_gemini2_ready_for_debug; then
  pass_stage
else
  fail_stage "Gemini2 is not ready for runtime debugging."
fi

begin_stage "2/7 Host ROS discovery env"
log_ros_discovery_env "Host ROS discovery env"
pass_stage

begin_stage "3/7 Container ROS discovery env"
info "Container ROS discovery env: $(ros_discovery_env_summary)"
pass_stage

begin_stage "4/7 Host camera stream readiness"
launch_host_camera
if wait_for_camera_streams_ready; then
  pass_stage
else
  if ! kill -0 "${HOST_CAMERA_PID}" 2>/dev/null; then
    fail_stage "Host Gemini2 driver exited before camera streams became ready. Check ${HOST_CAMERA_LOG}."
  fi
  fail_stage "Camera stream readiness probe failed. Check ${HOST_CAMERA_LOG}."
fi

begin_stage "5/7 Container camera visibility probe"
if probe_container_camera_visibility; then
  pass_stage
else
  fail_stage "The container cannot discover host camera_info topics with the current ROS discovery environment."
fi

begin_stage "6/7 Container static TF probe"
if probe_container_static_tf; then
  pass_stage
else
  fail_stage "The container managed static TF chain is not queryable."
fi

begin_stage "7/7 Full demo runtime output probe"
if probe_full_demo_runtime_output; then
  pass_stage
else
  fail_stage "The current prepared launch/runtime path did not reach stable map output."
fi

info "Runtime connectivity debug completed successfully."
