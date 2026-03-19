#!/usr/bin/env bash
set -euo pipefail

ROS_DISTRO="${ROS_DISTRO:-humble}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
SETUP_IMAGE_ID="${SETUP_IMAGE_ID:-}"
SETUP_IMAGE_CONTEXT_HASH="${SETUP_IMAGE_CONTEXT_HASH:-}"
COMMUNITY_REPO_URL="${COMMUNITY_REPO_URL:-https://github.com/jjjadand/isaac-NVblox-Orbbec.git}"
COMMUNITY_REPO_BRANCH="${COMMUNITY_REPO_BRANCH:-main}"
OFFICIAL_NVBLOX_REPO_URL="${OFFICIAL_NVBLOX_REPO_URL:-https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nvblox.git}"
OFFICIAL_NVBLOX_REPO_BRANCH="${OFFICIAL_NVBLOX_REPO_BRANCH:-release-3.2}"
OFFICIAL_VSLAM_REPO_URL="${OFFICIAL_VSLAM_REPO_URL:-https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_visual_slam.git}"
OFFICIAL_VSLAM_REPO_BRANCH="${OFFICIAL_VSLAM_REPO_BRANCH:-release-3.2}"
ORBBEC_LAUNCH_REPO_URL="${ORBBEC_LAUNCH_REPO_URL:-https://github.com/orbbec/isaac_orbbec_launch.git}"
ORBBEC_LAUNCH_REPO_BRANCH="${ORBBEC_LAUNCH_REPO_BRANCH:-main}"

WORKSPACE_SPEC_VERSION="${EXPECTED_WORKSPACE_SPEC_VERSION:-mobile-vslam-dynamics-v1}"

ISAAC_WS="/workspaces/isaac_ros-dev"
SRC_DIR="${ISAAC_WS}/src"
SETUP_DIR="${ISAAC_WS}/.setup-nvbox"
STAMP_PATH="${SETUP_DIR}/container_workspace.env"
COMMUNITY_REPO_PATH="${SETUP_DIR}/isaac-NVblox-Orbbec"
OFFICIAL_NVBLOX_REPO_PATH="${SETUP_DIR}/isaac_ros_nvblox"
OFFICIAL_VSLAM_REPO_PATH="${SETUP_DIR}/isaac_ros_visual_slam"
ORBBEC_LAUNCH_REPO_PATH="${SETUP_DIR}/isaac_orbbec_launch"

COMMUNITY_COMMON_ROOT="${COMMUNITY_REPO_PATH}/src/isaac_ros_common"
COMMUNITY_NITROS_ROOT="${COMMUNITY_REPO_PATH}/src/isaac_ros_nitros"
OFFICIAL_NVBLOX_ROOT="${OFFICIAL_NVBLOX_REPO_PATH}"
OFFICIAL_VSLAM_ROOT="${OFFICIAL_VSLAM_REPO_PATH}"
ORBBEC_LAUNCH_ROOT="${ORBBEC_LAUNCH_REPO_PATH}"

COMMUNITY_COMMON_PACKAGE_PATHS=(
  "isaac_common"
  "isaac_ros_common"
  "isaac_ros_launch_utils"
  "isaac_ros_tensor_list_interfaces"
)

COMMUNITY_NITROS_PACKAGE_PATHS=(
  "isaac_ros_gxf"
  "isaac_ros_nitros"
  "isaac_ros_managed_nitros"
  "isaac_ros_nitros_type/isaac_ros_nitros_camera_info_type"
  "isaac_ros_nitros_type/isaac_ros_nitros_image_type"
  "isaac_ros_nitros_type/isaac_ros_nitros_tensor_list_type"
  "isaac_ros_gxf_extensions/gxf_isaac_message_compositor"
  "isaac_ros_gxf_extensions/gxf_isaac_optimizer"
  "isaac_ros_gxf_extensions/gxf_isaac_gxf_helpers"
  "isaac_ros_gxf_extensions/gxf_isaac_sight"
  "isaac_ros_gxf_extensions/gxf_isaac_atlas"
  "isaac_ros_gxf_extensions/gxf_isaac_gems"
)

OFFICIAL_NVBLOX_PACKAGE_PATHS=(
  "nvblox_msgs"
  "nvblox_ros_common"
  "nvblox_ros_python_utils"
  "nvblox_ros"
  "nvblox_rviz_plugin"
  "nvblox_examples/nvblox_examples_bringup"
)

OFFICIAL_VSLAM_PACKAGE_PATHS=(
  "isaac_ros_visual_slam"
  "isaac_ros_visual_slam_interfaces"
)

GENERATED_LAUNCH_FILE_PATHS=(
  "isaac_orbbec_launch/launch/recomputer_orbbec_dynamics.launch.py"
  "isaac_orbbec_launch/launch/recomputer_orbbec_vslam_probe.launch.py"
)

REQUIRED_SRC_PATHS=(
  "isaac_common"
  "isaac_ros_common"
  "isaac_ros_launch_utils"
  "isaac_ros_tensor_list_interfaces"
  "isaac_ros_gxf"
  "isaac_ros_nitros"
  "isaac_ros_managed_nitros"
  "isaac_ros_nitros_type/isaac_ros_nitros_camera_info_type"
  "isaac_ros_nitros_type/isaac_ros_nitros_image_type"
  "isaac_ros_nitros_type/isaac_ros_nitros_tensor_list_type"
  "isaac_ros_gxf_extensions/gxf_isaac_message_compositor"
  "isaac_ros_gxf_extensions/gxf_isaac_optimizer"
  "isaac_ros_gxf_extensions/gxf_isaac_gxf_helpers"
  "isaac_ros_gxf_extensions/gxf_isaac_sight"
  "isaac_ros_gxf_extensions/gxf_isaac_atlas"
  "isaac_ros_gxf_extensions/gxf_isaac_gems"
  "isaac_ros_visual_slam"
  "isaac_ros_visual_slam_interfaces"
  "isaac_orbbec_launch"
  "nvblox_msgs"
  "nvblox_ros_common"
  "nvblox_ros_python_utils"
  "nvblox_ros"
  "nvblox_rviz_plugin"
  "nvblox_examples/nvblox_examples_bringup"
)

REQUIRED_SRC_FILE_PATHS=(
  "isaac_ros_visual_slam/package.xml"
  "isaac_ros_visual_slam_interfaces/package.xml"
  "isaac_orbbec_launch/package.xml"
  "isaac_orbbec_launch/launch/perception/vslam.launch.py"
  "isaac_orbbec_launch/launch/nvblox/nvblox.launch.py"
  "isaac_orbbec_launch/launch/rviz/rviz.launch.py"
  "isaac_orbbec_launch/config/sensors/orbbec.yaml"
  "isaac_orbbec_launch/config/nvblox/nvblox_base.yaml"
  "isaac_orbbec_launch/config/nvblox/specializations/nvblox_dynamics.yaml"
  "isaac_orbbec_launch/config/nvblox/specializations/nvblox_realsense.yaml"
  "isaac_orbbec_launch/config/rviz/realsense_dynamics_example.rviz"
  "isaac_orbbec_launch/launch/recomputer_orbbec_dynamics.launch.py"
  "isaac_orbbec_launch/launch/recomputer_orbbec_vslam_probe.launch.py"
  "nvblox_ros/CMakeLists.txt"
  "nvblox_ros/nvblox_core/CMakeLists.txt"
  "nvblox_ros/nvblox_core/cmake/cuda/setup_compute_capability.cmake"
)

EXCLUDED_SRC_PATHS=(
  "isaac_ros_pynitros"
  "isaac_ros_managed_nitros_examples"
  "isaac_ros_nitros_bridge"
  "isaac_ros_nitros_topic_tools"
  "nvblox_nav2"
  "nvblox_examples/nvblox_image_padding"
  "nvblox_examples/semantic_label_conversion"
)

ROSDEP_SKIP_KEYS=(
  "isaac_ros_peoplenet_models_install"
  "isaac_ros_detectnet"
  "isaac_ros_image_proc"
)

COLCON_TARGETS=(
  "isaac_orbbec_launch"
  "isaac_ros_visual_slam"
  "nvblox_examples_bringup"
)

RUNTIME_REQUIRED_PACKAGES=(
  "isaac_orbbec_launch"
  "isaac_ros_visual_slam"
  "nvblox_ros"
)

INSTALL_REQUIRED_FILE_PATHS=(
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/launch/perception/vslam.launch.py"
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/launch/nvblox/nvblox.launch.py"
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/launch/rviz/rviz.launch.py"
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/launch/recomputer_orbbec_dynamics.launch.py"
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/launch/recomputer_orbbec_vslam_probe.launch.py"
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/config/sensors/orbbec.yaml"
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/config/nvblox/nvblox_base.yaml"
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/config/nvblox/specializations/nvblox_dynamics.yaml"
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/config/nvblox/specializations/nvblox_realsense.yaml"
  "install/isaac_orbbec_launch/share/isaac_orbbec_launch/config/rviz/realsense_dynamics_example.rviz"
)

log() {
  printf '[container][%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  printf '[container][ERROR] %s\n' "$*" >&2
  exit 1
}

source_ros() {
  local restore_nounset=0

  if [[ $- == *u* ]]; then
    restore_nounset=1
    set +u
  fi

  # shellcheck disable=SC1091
  source "/opt/ros/${ROS_DISTRO}/setup.bash"
  if [[ -f "${ISAAC_WS}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090
    source "${ISAAC_WS}/install/setup.bash"
  fi

  if (( restore_nounset )); then
    set -u
  fi
}

ensure_rosdep_ready() {
  if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    log "Initializing rosdep."
    rosdep init || true
  fi

  log "Updating rosdep."
  rosdep update
}

ensure_git_safe_directory() {
  local repo_path="$1"

  [[ -n "${repo_path}" ]] || return 0
  [[ -e "${repo_path}" ]] || return 0

  if git config --global --get-all safe.directory 2>/dev/null | grep -Fqx "${repo_path}"; then
    return 0
  fi

  git config --global --add safe.directory "${repo_path}"
}

resolve_gitdir_path() {
  local repo_path="$1"
  local dot_git_path="${repo_path}/.git"
  local gitdir_value=""

  if [[ -d "${dot_git_path}" ]]; then
    printf '%s\n' "${dot_git_path}"
    return 0
  fi

  if [[ -f "${dot_git_path}" ]]; then
    gitdir_value="$(sed -n 's/^gitdir: //p' "${dot_git_path}" | head -n 1)"
    [[ -n "${gitdir_value}" ]] || return 1

    if [[ "${gitdir_value}" = /* ]]; then
      printf '%s\n' "${gitdir_value}"
    else
      printf '%s\n' "$(cd "${repo_path}" && cd "${gitdir_value}" && pwd)"
    fi
    return 0
  fi

  return 1
}

ensure_repo_safe_directories() {
  local repo_path="$1"
  local gitdir_path=""

  ensure_git_safe_directory "${repo_path}"

  if gitdir_path="$(resolve_gitdir_path "${repo_path}" 2>/dev/null)"; then
    ensure_git_safe_directory "${gitdir_path}"
  fi
}

extract_dubious_ownership_paths() {
  local log_path="$1"
  sed -n "s/.*detected dubious ownership in repository at '\(.*\)'/\1/p" "${log_path}" | sort -u
}

ensure_paths_from_ownership_log() {
  local log_path="$1"
  local repo_path=""

  while IFS= read -r repo_path; do
    [[ -n "${repo_path}" ]] || continue
    ensure_repo_safe_directories "${repo_path}"
  done < <(extract_dubious_ownership_paths "${log_path}")
}

assert_git_repo_metadata() {
  local repo_path="$1"
  local label="$2"

  [[ ! -e "${repo_path}" ]] && return 0
  [[ -e "${repo_path}/.git" ]] && return 0
  die "Managed ${label} cache at ${repo_path} is missing Git metadata. Delete ${repo_path} and rerun prepare."
}

assert_git_repo_accessible() {
  local repo_path="$1"
  local label="$2"
  local git_log

  [[ -e "${repo_path}" ]] || return 0
  assert_git_repo_metadata "${repo_path}" "${label}"
  ensure_repo_safe_directories "${repo_path}"

  git_log="$(mktemp)"
  if git -C "${repo_path}" rev-parse --is-inside-work-tree >/dev/null 2>"${git_log}"; then
    rm -f "${git_log}"
    return 0
  fi

  if grep -q "detected dubious ownership" "${git_log}"; then
    ensure_paths_from_ownership_log "${git_log}"
    if git -C "${repo_path}" rev-parse --is-inside-work-tree >/dev/null 2>"${git_log}"; then
      rm -f "${git_log}"
      return 0
    fi
  fi

  cat "${git_log}" >&2 || true
  rm -f "${git_log}"
  die "Managed ${label} cache at ${repo_path} is not usable. Delete ${repo_path} and rerun prepare."
}

initialize_managed_git_access() {
  mkdir -p "${HOME}" >/dev/null 2>&1 || true
  touch "${HOME}/.gitconfig" >/dev/null 2>&1 || true

  ensure_repo_safe_directories "${COMMUNITY_REPO_PATH}"
  ensure_repo_safe_directories "${OFFICIAL_NVBLOX_REPO_PATH}"
  ensure_repo_safe_directories "${OFFICIAL_NVBLOX_REPO_PATH}/nvblox_ros/nvblox_core"
  ensure_repo_safe_directories "${OFFICIAL_VSLAM_REPO_PATH}"
  ensure_repo_safe_directories "${ORBBEC_LAUNCH_REPO_PATH}"
}

verify_managed_git_cache_state() {
  assert_git_repo_accessible "${COMMUNITY_REPO_PATH}" "community repo"
  assert_git_repo_accessible "${OFFICIAL_NVBLOX_REPO_PATH}" "official Isaac ROS Nvblox repo"
  assert_git_repo_accessible "${OFFICIAL_NVBLOX_REPO_PATH}/nvblox_ros/nvblox_core" "official Isaac ROS Nvblox submodule"
  assert_git_repo_accessible "${OFFICIAL_VSLAM_REPO_PATH}" "official Isaac ROS Visual SLAM repo"
  assert_git_repo_accessible "${ORBBEC_LAUNCH_REPO_PATH}" "Orbbec Isaac launch repo"
}

clone_or_update_repo() {
  local repo_url="$1"
  local repo_branch="$2"
  local repo_path="$3"
  local repo_name="$4"

  mkdir -p "${SRC_DIR}" "${SETUP_DIR}"

  if [[ ! -d "${repo_path}/.git" ]]; then
    log "Cloning ${repo_name} from ${repo_url}."
    git clone --branch "${repo_branch}" --depth 1 "${repo_url}" "${repo_path}"
    ensure_repo_safe_directories "${repo_path}"
    return 0
  fi

  assert_git_repo_accessible "${repo_path}" "${repo_name}"
  if [[ -n "$(git -C "${repo_path}" status --porcelain)" ]]; then
    die "Managed repo has local changes at ${repo_path}."
  fi

  log "Refreshing ${repo_name}."
  git -C "${repo_path}" fetch --depth 1 origin "${repo_branch}"
  git -C "${repo_path}" checkout -B "${repo_branch}" "origin/${repo_branch}"
}

sync_git_submodule() {
  local repo_path="$1"
  local submodule_path="$2"
  local label="$3"
  local submodule_repo_path="${repo_path}/${submodule_path}"
  local git_log=""

  assert_git_repo_accessible "${repo_path}" "${label}"
  ensure_repo_safe_directories "${submodule_repo_path}"
  log "Syncing ${label} submodule ${submodule_path}."
  git -C "${repo_path}" submodule sync -- "${submodule_path}"
  git_log="$(mktemp)"
  if ! git -C "${repo_path}" submodule update --init --depth 1 -- "${submodule_path}" 2>"${git_log}"; then
    if grep -q "detected dubious ownership" "${git_log}"; then
      ensure_paths_from_ownership_log "${git_log}"
      ensure_repo_safe_directories "${repo_path}"
      ensure_repo_safe_directories "${submodule_repo_path}"
      : > "${git_log}"
      if ! git -C "${repo_path}" submodule update --init --depth 1 -- "${submodule_path}" 2>"${git_log}"; then
        cat "${git_log}" >&2 || true
        rm -f "${git_log}"
        die "Failed to sync ${label} submodule ${submodule_path} after refreshing Git safe.directory entries."
      fi
    else
      cat "${git_log}" >&2 || true
      rm -f "${git_log}"
      die "Failed to sync ${label} submodule ${submodule_path}."
    fi
  fi

  rm -f "${git_log}"
  assert_git_repo_accessible "${submodule_repo_path}" "${label} submodule"
}

verify_workspace_install() {
  local package_name=""
  local file_path=""

  [[ -f "${ISAAC_WS}/install/setup.bash" ]] || return 1

  source_ros
  for package_name in "${RUNTIME_REQUIRED_PACKAGES[@]}"; do
    ros2 pkg prefix "${package_name}" >/dev/null 2>&1 || return 1
  done

  for file_path in "${INSTALL_REQUIRED_FILE_PATHS[@]}"; do
    [[ -f "${ISAAC_WS}/${file_path}" ]] || return 1
  done
}

stamp_current() {
  [[ -f "${STAMP_PATH}" ]] || return 1
  # shellcheck disable=SC1090
  source "${STAMP_PATH}"
  [[ "${STAMP_IMAGE_ID:-}" == "${SETUP_IMAGE_ID}" ]] || return 1
  [[ "${STAMP_IMAGE_CONTEXT_HASH:-}" == "${SETUP_IMAGE_CONTEXT_HASH}" ]] || return 1
  [[ "${STAMP_COMMUNITY_COMMIT:-}" == "${COMMUNITY_COMMIT}" ]] || return 1
  [[ "${STAMP_OFFICIAL_NVBLOX_COMMIT:-}" == "${OFFICIAL_NVBLOX_COMMIT}" ]] || return 1
  [[ "${STAMP_OFFICIAL_NVBLOX_CORE_COMMIT:-}" == "${OFFICIAL_NVBLOX_CORE_COMMIT}" ]] || return 1
  [[ "${STAMP_OFFICIAL_VSLAM_COMMIT:-}" == "${OFFICIAL_VSLAM_COMMIT}" ]] || return 1
  [[ "${STAMP_ORBBEC_LAUNCH_COMMIT:-}" == "${ORBBEC_LAUNCH_COMMIT}" ]] || return 1
  [[ "${STAMP_WORKSPACE_SPEC_VERSION:-}" == "${WORKSPACE_SPEC_VERSION}" ]] || return 1
  verify_synced_workspace_layout
  verify_workspace_install
}

write_stamp() {
  {
    printf 'STAMP_IMAGE_ID=%q\n' "${SETUP_IMAGE_ID}"
    printf 'STAMP_IMAGE_CONTEXT_HASH=%q\n' "${SETUP_IMAGE_CONTEXT_HASH}"
    printf 'STAMP_COMMUNITY_COMMIT=%q\n' "${COMMUNITY_COMMIT}"
    printf 'STAMP_OFFICIAL_NVBLOX_COMMIT=%q\n' "${OFFICIAL_NVBLOX_COMMIT}"
    printf 'STAMP_OFFICIAL_NVBLOX_CORE_COMMIT=%q\n' "${OFFICIAL_NVBLOX_CORE_COMMIT}"
    printf 'STAMP_OFFICIAL_VSLAM_COMMIT=%q\n' "${OFFICIAL_VSLAM_COMMIT}"
    printf 'STAMP_ORBBEC_LAUNCH_COMMIT=%q\n' "${ORBBEC_LAUNCH_COMMIT}"
    printf 'STAMP_WORKSPACE_SPEC_VERSION=%q\n' "${WORKSPACE_SPEC_VERSION}"
    printf 'STAMPED_AT=%q\n' "$(date -Is 2>/dev/null || date)"
  } > "${STAMP_PATH}"
}

clear_managed_src_dir() {
  mkdir -p "${SRC_DIR}"
  find "${SRC_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
}

copy_package_path() {
  local source_root="$1"
  local package_path="$2"
  local src_path="${source_root}/${package_path}"
  local dest_path="${SRC_DIR}/${package_path}"

  [[ -d "${src_path}" ]] || die "Expected package path ${package_path} is missing from ${source_root}."
  mkdir -p "$(dirname "${dest_path}")"
  rm -rf "${dest_path}"
  cp -a "${src_path}" "${dest_path}"
}

copy_package_root() {
  local source_root="$1"
  local package_name="$2"
  local dest_path="${SRC_DIR}/${package_name}"

  [[ -f "${source_root}/package.xml" ]] || die "Expected root package.xml is missing from ${source_root}."
  mkdir -p "${dest_path}"
  rm -rf "${dest_path}"
  mkdir -p "${dest_path}"
  find "${source_root}" -mindepth 1 -maxdepth 1 ! -name '.git' -exec cp -a {} "${dest_path}/" \;
}

sync_package_group() {
  local source_root="$1"
  shift
  local package_path=""

  for package_path in "$@"; do
    copy_package_path "${source_root}" "${package_path}"
  done
}

write_recomputer_dynamics_launch() {
  cat > "${SRC_DIR}/isaac_orbbec_launch/launch/recomputer_orbbec_dynamics.launch.py" <<'EOF'
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    bringup_dir = get_package_share_directory('isaac_orbbec_launch')
    run_rviz = LaunchConfiguration('run_rviz', default='True')
    global_frame = LaunchConfiguration('global_frame', default='odom')
    flatten_odometry = LaunchConfiguration('flatten_odometry_to_2d', default='False')
    shared_container_name = 'shared_nvblox_container'

    shared_container = Node(
        name=shared_container_name,
        package='rclcpp_components',
        executable='component_container_mt',
        output='screen')

    vslam_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            os.path.join(bringup_dir, 'launch', 'perception', 'vslam.launch.py')]),
        launch_arguments={
            'output_odom_frame_name': global_frame,
            'setup_for_orbbec': 'True',
            'run_odometry_flattening': flatten_odometry,
            'attach_to_shared_component_container': 'True',
            'component_container_name': shared_container_name,
        }.items())

    nvblox_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            os.path.join(bringup_dir, 'launch', 'nvblox', 'nvblox.launch.py')]),
        launch_arguments={
            'global_frame': global_frame,
            'setup_for_dynamics': 'True',
            'setup_for_orbbec': 'True',
            'attach_to_shared_component_container': 'True',
            'component_container_name': shared_container_name,
        }.items())

    rviz_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            os.path.join(bringup_dir, 'launch', 'rviz', 'rviz.launch.py')]),
        launch_arguments={
            'config_name': 'realsense_dynamics_example.rviz',
            'global_frame': global_frame,
        }.items(),
        condition=IfCondition(run_rviz))

    return LaunchDescription([
        DeclareLaunchArgument('run_rviz', default_value='True'),
        DeclareLaunchArgument('global_frame', default_value='odom'),
        DeclareLaunchArgument('flatten_odometry_to_2d', default_value='False'),
        shared_container,
        vslam_launch,
        nvblox_launch,
        rviz_launch,
    ])
EOF
}

write_recomputer_vslam_probe_launch() {
  cat > "${SRC_DIR}/isaac_orbbec_launch/launch/recomputer_orbbec_vslam_probe.launch.py" <<'EOF'
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    bringup_dir = get_package_share_directory('isaac_orbbec_launch')
    global_frame = LaunchConfiguration('global_frame', default='odom')
    shared_container_name = 'shared_vslam_probe_container'

    shared_container = Node(
        name=shared_container_name,
        package='rclcpp_components',
        executable='component_container_mt',
        output='screen')

    vslam_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            os.path.join(bringup_dir, 'launch', 'perception', 'vslam.launch.py')]),
        launch_arguments={
            'output_odom_frame_name': global_frame,
            'setup_for_orbbec': 'True',
            'attach_to_shared_component_container': 'True',
            'component_container_name': shared_container_name,
        }.items())

    return LaunchDescription([
        DeclareLaunchArgument('global_frame', default_value='odom'),
        shared_container,
        vslam_launch,
    ])
EOF
}

generate_mobile_demo_launches() {
  log "Generating managed mobile mapping launch files."
  mkdir -p "${SRC_DIR}/isaac_orbbec_launch/launch"
  write_recomputer_dynamics_launch
  write_recomputer_vslam_probe_launch
}

verify_synced_workspace_layout() {
  local path_name=""
  local file_path=""

  for path_name in "${REQUIRED_SRC_PATHS[@]}"; do
    [[ -d "${SRC_DIR}/${path_name}" ]] || die "Required synced package path is missing: ${SRC_DIR}/${path_name}"
  done

  for path_name in "${EXCLUDED_SRC_PATHS[@]}"; do
    [[ ! -e "${SRC_DIR}/${path_name}" ]] || die "Excluded package path should not exist in the managed workspace: ${SRC_DIR}/${path_name}"
  done

  for file_path in "${REQUIRED_SRC_FILE_PATHS[@]}"; do
    [[ -f "${SRC_DIR}/${file_path}" ]] || die "Required synced file is missing: ${SRC_DIR}/${file_path}"
  done
}

sync_mobile_demo_workspace() {
  log "Syncing package whitelist into the managed workspace."
  clear_managed_src_dir
  sync_package_group "${COMMUNITY_COMMON_ROOT}" "${COMMUNITY_COMMON_PACKAGE_PATHS[@]}"
  sync_package_group "${COMMUNITY_NITROS_ROOT}" "${COMMUNITY_NITROS_PACKAGE_PATHS[@]}"
  sync_package_group "${OFFICIAL_NVBLOX_ROOT}" "${OFFICIAL_NVBLOX_PACKAGE_PATHS[@]}"
  sync_package_group "${OFFICIAL_VSLAM_ROOT}" "${OFFICIAL_VSLAM_PACKAGE_PATHS[@]}"
  copy_package_root "${ORBBEC_LAUNCH_ROOT}" "isaac_orbbec_launch"
  generate_mobile_demo_launches
  verify_synced_workspace_layout
}

rebuild_workspace() {
  local rosdep_dependency_args=(
    --dependency-types buildtool
    --dependency-types buildtool_export
    --dependency-types build
    --dependency-types build_export
    --dependency-types exec
  )
  local rosdep_skip_args=()
  local skip_key=""

  source_ros
  ensure_rosdep_ready

  for skip_key in "${ROSDEP_SKIP_KEYS[@]}"; do
    rosdep_skip_args+=(--skip-keys "${skip_key}")
  done

  log "Installing workspace dependencies with rosdep."
  (
    cd "${ISAAC_WS}"
    rosdep install \
      --from-paths src \
      --ignore-src \
      -r \
      -y \
      --rosdistro "${ROS_DISTRO}" \
      "${rosdep_dependency_args[@]}" \
      "${rosdep_skip_args[@]}"
  )

  run_colcon_build() {
    (
      cd "${ISAAC_WS}"
      colcon build \
        --packages-up-to "${COLCON_TARGETS[@]}" \
        --symlink-install \
        --event-handlers console_direct+ \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
    )
  }

  patch_ext_stdgpu_cuda_compat() {
    local ext_stdgpu_root=""
    local memory_detail_path=""
    local unordered_base_path=""
    local patched_any=1

    while IFS= read -r ext_stdgpu_root; do
      memory_detail_path="${ext_stdgpu_root}/src/stdgpu/impl/memory_detail.h"
      unordered_base_path="${ext_stdgpu_root}/src/stdgpu/impl/unordered_base_detail.cuh"

      if [[ -f "${memory_detail_path}" ]]; then
        if python3 - "${memory_detail_path}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    "construct_at(p, forward<Args>(args)...);": "stdgpu::construct_at(p, stdgpu::forward<Args>(args)...);",
    "destroy_at(p);": "stdgpu::destroy_at(p);",
    "return to_address(pointer_traits<Ptr>::to_address(p));": "return stdgpu::to_address(pointer_traits<Ptr>::to_address(p));",
}
changed = False
for old, new in replacements.items():
    if old in text:
        text = text.replace(old, new)
        changed = True

if changed:
    path.write_text(text)

sys.exit(0 if changed else 1)
PY
        then
          log "Applied CUDA 12.6 stdgpu compatibility patch to ${memory_detail_path}."
          patched_any=0
        fi
      fi

      if [[ -f "${unordered_base_path}" ]]; then
        if python3 - "${unordered_base_path}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    "_base.insert(*to_address(_begin + i));": "_base.insert(*stdgpu::to_address(_begin + i));",
}
changed = False
for old, new in replacements.items():
    if old in text:
        text = text.replace(old, new)
        changed = True

if changed:
    path.write_text(text)

sys.exit(0 if changed else 1)
PY
        then
          log "Applied CUDA 12.6 stdgpu compatibility patch to ${unordered_base_path}."
          patched_any=0
        fi
      fi
    done < <(find "${ISAAC_WS}/build" -type d -path '*/_deps/ext_stdgpu-src' 2>/dev/null | sort)

    return "${patched_any}"
  }

  log "Building container workspace."
  rm -rf "${ISAAC_WS}/build" "${ISAAC_WS}/install" "${ISAAC_WS}/log"

  if run_colcon_build; then
    return 0
  fi

  if patch_ext_stdgpu_cuda_compat; then
    log "Retrying container workspace build after applying stdgpu CUDA compatibility patches."
    run_colcon_build
    return 0
  fi

  die "Container workspace build failed before the compatibility patch could be applied."
}

initialize_managed_git_access
verify_managed_git_cache_state

clone_or_update_repo "${COMMUNITY_REPO_URL}" "${COMMUNITY_REPO_BRANCH}" "${COMMUNITY_REPO_PATH}" "community repo"
clone_or_update_repo "${OFFICIAL_NVBLOX_REPO_URL}" "${OFFICIAL_NVBLOX_REPO_BRANCH}" "${OFFICIAL_NVBLOX_REPO_PATH}" "official Isaac ROS Nvblox repo"
clone_or_update_repo "${OFFICIAL_VSLAM_REPO_URL}" "${OFFICIAL_VSLAM_REPO_BRANCH}" "${OFFICIAL_VSLAM_REPO_PATH}" "official Isaac ROS Visual SLAM repo"
clone_or_update_repo "${ORBBEC_LAUNCH_REPO_URL}" "${ORBBEC_LAUNCH_REPO_BRANCH}" "${ORBBEC_LAUNCH_REPO_PATH}" "Orbbec Isaac launch repo"
sync_git_submodule "${OFFICIAL_NVBLOX_REPO_PATH}" "nvblox_ros/nvblox_core" "official Isaac ROS Nvblox"
assert_git_repo_accessible "${COMMUNITY_REPO_PATH}" "community repo"
assert_git_repo_accessible "${OFFICIAL_NVBLOX_REPO_PATH}" "official Isaac ROS Nvblox repo"
assert_git_repo_accessible "${OFFICIAL_NVBLOX_REPO_PATH}/nvblox_ros/nvblox_core" "official Isaac ROS Nvblox submodule"
assert_git_repo_accessible "${OFFICIAL_VSLAM_REPO_PATH}" "official Isaac ROS Visual SLAM repo"
assert_git_repo_accessible "${ORBBEC_LAUNCH_REPO_PATH}" "Orbbec Isaac launch repo"
COMMUNITY_COMMIT="$(git -C "${COMMUNITY_REPO_PATH}" rev-parse HEAD)"
OFFICIAL_NVBLOX_COMMIT="$(git -C "${OFFICIAL_NVBLOX_REPO_PATH}" rev-parse HEAD)"
OFFICIAL_NVBLOX_CORE_COMMIT="$(git -C "${OFFICIAL_NVBLOX_REPO_PATH}/nvblox_ros/nvblox_core" rev-parse HEAD)"
OFFICIAL_VSLAM_COMMIT="$(git -C "${OFFICIAL_VSLAM_REPO_PATH}" rev-parse HEAD)"
ORBBEC_LAUNCH_COMMIT="$(git -C "${ORBBEC_LAUNCH_REPO_PATH}" rev-parse HEAD)"

if [[ "${FORCE_REBUILD}" != "1" ]] && stamp_current; then
  log "Container workspace is already current. Skipping rebuild."
  exit 0
fi

sync_mobile_demo_workspace
rebuild_workspace
verify_synced_workspace_layout
verify_workspace_install || die "Container workspace verification failed."
write_stamp
log "Container workspace preparation complete."
