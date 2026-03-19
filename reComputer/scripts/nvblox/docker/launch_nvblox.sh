#!/usr/bin/env bash
set -euo pipefail

ROS_DISTRO="${ROS_DISTRO:-humble}"
NVBLOX_LAUNCH_PACKAGE="${NVBLOX_LAUNCH_PACKAGE:-isaac_orbbec_launch}"
NVBLOX_LAUNCH_FILE="${NVBLOX_LAUNCH_FILE:-recomputer_orbbec_dynamics.launch.py}"
NVBLOX_RUN_RVIZ="${NVBLOX_RUN_RVIZ:-1}"
NVBLOX_GLOBAL_FRAME="${NVBLOX_GLOBAL_FRAME:-odom}"
EXPECTED_WORKSPACE_SPEC_VERSION="${EXPECTED_WORKSPACE_SPEC_VERSION:-}"
NVBLOX_OUTPUT_PROBE_TIMEOUT_SEC="${NVBLOX_OUTPUT_PROBE_TIMEOUT_SEC:-45}"
ISAAC_WS="/workspaces/isaac_ros-dev"
STAMP_PATH="${ISAAC_WS}/.setup-nvbox/container_workspace.env"
LAUNCH_PID=""
OUTPUT_PROBE_PID=""
ROS_DISCOVERY_ENV_VARS=(
  "ROS_DOMAIN_ID"
  "ROS_LOCALHOST_ONLY"
  "RMW_IMPLEMENTATION"
  "ROS_AUTOMATIC_DISCOVERY_RANGE"
  "ROS_STATIC_PEERS"
  "CYCLONEDDS_URI"
  "CYCLONEDDS_HOME"
  "FASTDDS_DEFAULT_PROFILES_FILE"
  "FASTRTPS_DEFAULT_PROFILES_FILE"
)

[[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]] || {
  printf '[container][ERROR] Missing ROS setup at /opt/ros/%s/setup.bash\n' "${ROS_DISTRO}" >&2
  exit 1
}
[[ -f "${ISAAC_WS}/install/setup.bash" ]] || {
  printf '[container][ERROR] Missing workspace setup at %s/install/setup.bash\n' "${ISAAC_WS}" >&2
  exit 1
}
[[ -f "${STAMP_PATH}" ]] || {
  printf '[container][ERROR] Missing workspace stamp at %s\n' "${STAMP_PATH}" >&2
  exit 1
}

restore_nounset=0
if [[ $- == *u* ]]; then
  restore_nounset=1
  set +u
fi

# shellcheck disable=SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# shellcheck disable=SC1090
source "${ISAAC_WS}/install/setup.bash"
# shellcheck disable=SC1090
source "${STAMP_PATH}"

if (( restore_nounset )); then
  set -u
fi

if [[ -n "${EXPECTED_WORKSPACE_SPEC_VERSION}" ]] && \
   [[ "${STAMP_WORKSPACE_SPEC_VERSION:-}" != "${EXPECTED_WORKSPACE_SPEC_VERSION}" ]]; then
  printf '[container][ERROR] Workspace spec mismatch. Expected %s, found %s\n' \
    "${EXPECTED_WORKSPACE_SPEC_VERSION}" "${STAMP_WORKSPACE_SPEC_VERSION:-unknown}" >&2
  exit 1
fi

PACKAGE_PREFIX="$(ros2 pkg prefix "${NVBLOX_LAUNCH_PACKAGE}" 2>/dev/null || true)"
[[ -n "${PACKAGE_PREFIX}" ]] || {
  printf '[container][ERROR] Cannot resolve %s in the prepared workspace.\n' "${NVBLOX_LAUNCH_PACKAGE}" >&2
  exit 1
}

LAUNCH_PATH="${PACKAGE_PREFIX}/share/${NVBLOX_LAUNCH_PACKAGE}/launch/${NVBLOX_LAUNCH_FILE}"
[[ -f "${LAUNCH_PATH}" ]] || {
  printf '[container][ERROR] Prepared launch file is missing: %s\n' "${LAUNCH_PATH}" >&2
  exit 1
}

format_ros_discovery_env() {
  local parts=()
  local var_name=""
  local value=""
  local old_ifs="${IFS}"

  for var_name in "${ROS_DISCOVERY_ENV_VARS[@]}"; do
    value="${!var_name-}"
    if [[ -n "${value}" ]]; then
      parts+=("${var_name}=${value}")
    else
      parts+=("${var_name}=<unset>")
    fi
  done

  IFS=', '
  printf '%s\n' "${parts[*]}"
  IFS="${old_ifs}"
}

if [[ "${NVBLOX_RUN_RVIZ}" == "1" ]]; then
  RUN_RVIZ_VALUE="True"
else
  RUN_RVIZ_VALUE="False"
fi

printf '[container][INFO] Workspace spec: %s\n' "${STAMP_WORKSPACE_SPEC_VERSION:-unknown}"
printf '[container][INFO] Workspace stamped at: %s\n' "${STAMPED_AT:-unknown}"
printf '[container][INFO] Launching mobile mapping file: %s/%s\n' "${NVBLOX_LAUNCH_PACKAGE}" "${NVBLOX_LAUNCH_FILE}"
printf '[container][INFO] Visual SLAM global frame: %s\n' "${NVBLOX_GLOBAL_FRAME}"
printf '[container][INFO] RViz enabled: %s\n' "${RUN_RVIZ_VALUE}"
printf '[container][INFO] Container ROS discovery env: %s\n' "$(format_ros_discovery_env)"

probe_nvblox_runtime_output() {
  python3 - "${NVBLOX_OUTPUT_PROBE_TIMEOUT_SEC}" <<'PY'
import sys
import time

import rclpy
from nav_msgs.msg import OccupancyGrid, Odometry
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import PointCloud2

timeout_seconds = float(sys.argv[1])


class NvbloxOutputProbe(Node):
    def __init__(self):
        super().__init__('nvblox_runtime_output_probe')
        self.odom_result = None
        self.map_result = None
        self.create_subscription(Odometry, '/visual_slam/tracking/odometry', self._odom_callback, 10)
        self.create_subscription(PointCloud2, '/nvblox_node/combined_esdf_pointcloud', self._combined_esdf_callback, qos_profile_sensor_data)
        self.create_subscription(PointCloud2, '/nvblox_node/dynamic_esdf_pointcloud', self._dynamic_esdf_callback, qos_profile_sensor_data)
        self.create_subscription(OccupancyGrid, '/nvblox_node/combined_map_slice', self._combined_map_slice_callback, 10)

    def _odom_callback(self, msg: Odometry):
        self.odom_result = (
            '/visual_slam/tracking/odometry',
            f'frame_id={msg.header.frame_id or "<empty>"} child_frame_id={msg.child_frame_id or "<empty>"}')

    def _combined_esdf_callback(self, msg: PointCloud2):
        self.map_result = (
            '/nvblox_node/combined_esdf_pointcloud',
            f'frame_id={msg.header.frame_id or "<empty>"} width={msg.width} height={msg.height}')

    def _dynamic_esdf_callback(self, msg: PointCloud2):
        self.map_result = (
            '/nvblox_node/dynamic_esdf_pointcloud',
            f'frame_id={msg.header.frame_id or "<empty>"} width={msg.width} height={msg.height}')

    def _combined_map_slice_callback(self, msg: OccupancyGrid):
        self.map_result = (
            '/nvblox_node/combined_map_slice',
            f'frame_id={msg.header.frame_id or "<empty>"} width={msg.info.width} '
            f'height={msg.info.height} resolution={msg.info.resolution:.3f}')


def main() -> int:
    print(
        '[container][INFO] Starting runtime output probe for '
        '/visual_slam/tracking/odometry and dynamic NVBlox map topics '
        f'({timeout_seconds:.0f}s timeout)',
        flush=True)
    rclpy.init(args=None)
    node = NvbloxOutputProbe()
    executor = SingleThreadedExecutor()
    executor.add_node(node)
    deadline = time.monotonic() + timeout_seconds

    try:
        while time.monotonic() < deadline:
            executor.spin_once(timeout_sec=0.2)
            if node.map_result is not None:
                topic_name, details = node.map_result
                print(f'[container][INFO] Runtime output probe received {topic_name}: {details}', flush=True)
                return 0
            if node.odom_result is not None:
                topic_name, details = node.odom_result
                print(f'[container][INFO] Runtime output probe received {topic_name}: {details}', flush=True)
                print('[container][INFO] Visual SLAM odometry is active. Move the camera to accumulate live NVBlox map output.', flush=True)
                return 0

        print(
            '[container][WARN] Runtime output probe timed out waiting for Visual SLAM odometry or dynamic NVBlox map output.',
            flush=True)
        return 1
    finally:
        executor.remove_node(node)
        node.destroy_node()
        rclpy.shutdown()


sys.exit(main())
PY
}

forward_signal() {
  local signal="$1"

  [[ -n "${LAUNCH_PID}" ]] && kill "-${signal}" "${LAUNCH_PID}" 2>/dev/null || true
  [[ -n "${OUTPUT_PROBE_PID}" ]] && kill "-${signal}" "${OUTPUT_PROBE_PID}" 2>/dev/null || true
}

trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM

ros2 launch "${NVBLOX_LAUNCH_PACKAGE}" "${NVBLOX_LAUNCH_FILE}" \
  "run_rviz:=${RUN_RVIZ_VALUE}" \
  "global_frame:=${NVBLOX_GLOBAL_FRAME}" &
LAUNCH_PID=$!

probe_nvblox_runtime_output &
OUTPUT_PROBE_PID=$!

set +e
wait "${LAUNCH_PID}"
launch_status=$?
set -e

if [[ -n "${OUTPUT_PROBE_PID}" ]] && kill -0 "${OUTPUT_PROBE_PID}" 2>/dev/null; then
  kill -TERM "${OUTPUT_PROBE_PID}" 2>/dev/null || true
fi
wait "${OUTPUT_PROBE_PID}" 2>/dev/null || true

exit "${launch_status}"
