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

WORKSPACE_SPEC_VERSION="${EXPECTED_WORKSPACE_SPEC_VERSION:-static-demo-final-v4}"

ISAAC_WS="/workspaces/isaac_ros-dev"
SRC_DIR="${ISAAC_WS}/src"
SETUP_DIR="${ISAAC_WS}/.setup-nvbox"
STAMP_PATH="${SETUP_DIR}/container_workspace.env"
COMMUNITY_REPO_PATH="${SETUP_DIR}/isaac-NVblox-Orbbec"
OFFICIAL_NVBLOX_REPO_PATH="${SETUP_DIR}/isaac_ros_nvblox"

COMMUNITY_COMMON_ROOT="${COMMUNITY_REPO_PATH}/src/isaac_ros_common"
COMMUNITY_NITROS_ROOT="${COMMUNITY_REPO_PATH}/src/isaac_ros_nitros"
COMMUNITY_NVBLOX_ROOT="${COMMUNITY_REPO_PATH}/src/isaac_ros_nvblox"
OFFICIAL_NVBLOX_ROOT="${OFFICIAL_NVBLOX_REPO_PATH}"

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

STATIC_DEMO_OVERLAY_FILE_PATHS=(
  "nvblox_examples/nvblox_examples_bringup/config/visualization/orbbec_example.rviz"
)

GENERATED_LAUNCH_FILE_PATHS=(
  "nvblox_examples/nvblox_examples_bringup/launch/orbbec_transforms.launch.py"
  "nvblox_examples/nvblox_examples_bringup/launch/orbbec_example.launch.py"
  "nvblox_examples/nvblox_examples_bringup/launch/orbbec_debug.launch.py"
  "nvblox_examples/nvblox_examples_bringup/launch/orbbec_nvblox_standalone.launch.py"
)

GENERATED_CONFIG_FILE_PATHS=(
  "nvblox_examples/nvblox_examples_bringup/config/nvblox/specializations/nvblox_orbbec_static.yaml"
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
  "nvblox_msgs"
  "nvblox_ros_common"
  "nvblox_ros_python_utils"
  "nvblox_ros"
  "nvblox_rviz_plugin"
  "nvblox_examples/nvblox_examples_bringup"
)

REQUIRED_SRC_FILE_PATHS=(
  "nvblox_ros/CMakeLists.txt"
  "nvblox_ros/nvblox_core/CMakeLists.txt"
  "nvblox_ros/nvblox_core/cmake/cuda/setup_compute_capability.cmake"
  "nvblox_examples/nvblox_examples_bringup/launch/orbbec_transforms.launch.py"
  "nvblox_examples/nvblox_examples_bringup/config/visualization/orbbec_example.rviz"
  "nvblox_examples/nvblox_examples_bringup/launch/orbbec_example.launch.py"
  "nvblox_examples/nvblox_examples_bringup/launch/orbbec_debug.launch.py"
  "nvblox_examples/nvblox_examples_bringup/launch/orbbec_nvblox_standalone.launch.py"
  "nvblox_examples/nvblox_examples_bringup/config/nvblox/specializations/nvblox_orbbec_static.yaml"
)

EXCLUDED_SRC_PATHS=(
  "isaac_ros_pynitros"
  "isaac_ros_managed_nitros_examples"
  "isaac_ros_nitros_bridge"
  "isaac_ros_nitros_topic_tools"
  "isaac_ros_visual_slam"
  "isaac_ros_visual_slam_interfaces"
  "nvblox_nav2"
  "nvblox_examples/nvblox_image_padding"
  "nvblox_examples/semantic_label_conversion"
)

STATIC_DEMO_REMOVED_DEPENDENCIES=(
  "nova_carter_navigation"
  "isaac_ros_visual_slam"
  "isaac_ros_visual_slam_interfaces"
  "isaac_ros_peoplenet_models_install"
  "isaac_ros_detectnet"
  "isaac_ros_peoplesemseg_models_install"
  "isaac_ros_dnn_image_encoder"
  "isaac_ros_triton"
  "isaac_ros_unet"
  "semantic_label_conversion"
  "nvblox_image_padding"
)

ROSDEP_SKIP_KEYS=(
  "isaac_ros_peoplenet_models_install"
  "isaac_ros_detectnet"
  "isaac_ros_image_proc"
)

COLCON_TARGETS=(
  "nvblox_examples_bringup"
)

RUNTIME_REQUIRED_PACKAGES=(
  "nvblox_examples_bringup"
  "nvblox_ros"
)

INSTALL_REQUIRED_FILE_PATHS=(
  "install/nvblox_examples_bringup/share/nvblox_examples_bringup/launch/orbbec_transforms.launch.py"
  "install/nvblox_examples_bringup/share/nvblox_examples_bringup/launch/orbbec_example.launch.py"
  "install/nvblox_examples_bringup/share/nvblox_examples_bringup/launch/orbbec_debug.launch.py"
  "install/nvblox_examples_bringup/share/nvblox_examples_bringup/launch/orbbec_nvblox_standalone.launch.py"
  "install/nvblox_examples_bringup/share/nvblox_examples_bringup/config/nvblox/specializations/nvblox_orbbec_static.yaml"
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
}

verify_managed_git_cache_state() {
  assert_git_repo_accessible "${COMMUNITY_REPO_PATH}" "community repo"
  assert_git_repo_accessible "${OFFICIAL_NVBLOX_REPO_PATH}" "official Isaac ROS Nvblox repo"
  assert_git_repo_accessible "${OFFICIAL_NVBLOX_REPO_PATH}/nvblox_ros/nvblox_core" "official Isaac ROS Nvblox submodule"
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

sync_package_group() {
  local source_root="$1"
  shift
  local package_path=""

  for package_path in "$@"; do
    copy_package_path "${source_root}" "${package_path}"
  done
}

copy_overlay_file() {
  local source_root="$1"
  local relative_path="$2"
  local src_path="${source_root}/${relative_path}"
  local dest_path="${SRC_DIR}/${relative_path}"

  [[ -f "${src_path}" ]] || die "Expected overlay file is missing: ${src_path}"
  mkdir -p "$(dirname "${dest_path}")"
  cp -f "${src_path}" "${dest_path}"
}

apply_overlay_files() {
  local source_root="$1"
  shift
  local relative_path=""

  for relative_path in "$@"; do
    copy_overlay_file "${source_root}" "${relative_path}"
  done
}

write_orbbec_transforms_launch() {
  cat > "${SRC_DIR}/nvblox_examples/nvblox_examples_bringup/launch/orbbec_transforms.launch.py" <<'EOF'
from isaac_ros_launch_utils.all_types import *
import isaac_ros_launch_utils as lu


def static_tf(parent: str, child: str, xyz: tuple[float, float, float], rpy: tuple[float, float, float]) -> Node:
    return Node(
        package='tf2_ros',
        executable='static_transform_publisher',
        arguments=[
            '--x', str(xyz[0]),
            '--y', str(xyz[1]),
            '--z', str(xyz[2]),
            '--roll', str(rpy[0]),
            '--pitch', str(rpy[1]),
            '--yaw', str(rpy[2]),
            '--frame-id', parent,
            '--child-frame-id', child,
        ],
        output='screen')


def generate_launch_description() -> LaunchDescription:
    args = lu.ArgumentContainer()
    actions = args.get_launch_actions()

    actions.append(static_tf('odom', 'base_link', (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)))
    actions.append(static_tf('base_link', 'camera_link', (0.1, 0.0, 0.2), (0.0, 0.0, 0.0)))
    actions.append(static_tf('camera_link', 'camera0_link', (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)))
    actions.append(static_tf(
        'camera_link',
        'camera_color_optical_frame',
        (0.0, 0.0, 0.0),
        (-1.57079632679, 0.0, -1.57079632679)))
    actions.append(static_tf(
        'camera_color_optical_frame',
        'camera_depth_optical_frame',
        (0.0, 0.0, 0.0),
        (0.0, 0.0, 0.0)))

    return LaunchDescription(actions)
EOF
}

write_orbbec_static_config() {
  cat > "${SRC_DIR}/nvblox_examples/nvblox_examples_bringup/config/nvblox/specializations/nvblox_orbbec_static.yaml" <<'EOF'
/**:
  ros__parameters:
    use_lidar: false
    input_qos: "SENSOR_DATA"
    map_clearing_frame_id: "base_link"
    esdf_slice_bounds_visualization_attachment_frame_id: "base_link"
    static_mapper:
      esdf_slice_height: 0.0
      esdf_slice_min_height: -0.1
      esdf_slice_max_height: 0.3
EOF
}

write_orbbec_example_launch() {
  cat > "${SRC_DIR}/nvblox_examples/nvblox_examples_bringup/launch/orbbec_example.launch.py" <<'EOF'
from isaac_ros_launch_utils.all_types import *
import isaac_ros_launch_utils as lu

from nvblox_ros_python_utils.nvblox_constants import NVBLOX_CONTAINER_NAME


def generate_launch_description() -> LaunchDescription:
    args = lu.ArgumentContainer()
    args.add_arg('log_level', 'info', choices=['debug', 'info', 'warn'], cli=True)
    actions = args.get_launch_actions()

    actions.append(
        lu.include(
            'nvblox_examples_bringup',
            'launch/orbbec_transforms.launch.py'))

    actions.append(lu.component_container(NVBLOX_CONTAINER_NAME, log_level=args.log_level))

    base_config = lu.get_path('nvblox_examples_bringup', 'config/nvblox/nvblox_base.yaml')
    realsense_config = lu.get_path(
        'nvblox_examples_bringup',
        'config/nvblox/specializations/nvblox_realsense.yaml')
    orbbec_static_config = lu.get_path(
        'nvblox_examples_bringup',
        'config/nvblox/specializations/nvblox_orbbec_static.yaml')

    nvblox_node = ComposableNode(
        name='nvblox_node',
        package='nvblox_ros',
        plugin='nvblox::NvbloxNode',
        remappings=[
            ('camera_0/depth/image', '/camera/depth/image_raw'),
            ('camera_0/depth/camera_info', '/camera/depth/camera_info'),
            ('camera_0/color/image', '/camera/color/image_raw'),
            ('camera_0/color/camera_info', '/camera/color/camera_info'),
        ],
        parameters=[
            base_config,
            realsense_config,
            orbbec_static_config,
            {'num_cameras': 1},
            {'use_lidar': False},
        ],
    )

    actions.append(lu.load_composable_nodes(NVBLOX_CONTAINER_NAME, [nvblox_node]))

    rviz_config_path = lu.get_path(
        'nvblox_examples_bringup',
        'config/visualization/orbbec_example.rviz')
    actions.append(
        Node(
            package='rviz2',
            executable='rviz2',
            arguments=['-d', str(rviz_config_path)],
            output='screen'))

    return LaunchDescription(actions)
EOF
}

write_orbbec_debug_launch() {
  cat > "${SRC_DIR}/nvblox_examples/nvblox_examples_bringup/launch/orbbec_debug.launch.py" <<'EOF'
from isaac_ros_launch_utils.all_types import *
import isaac_ros_launch_utils as lu

from nvblox_ros_python_utils.nvblox_constants import NVBLOX_CONTAINER_NAME


def generate_launch_description() -> LaunchDescription:
    args = lu.ArgumentContainer()
    args.add_arg('log_level', 'debug', choices=['debug', 'info', 'warn'], cli=True)
    actions = args.get_launch_actions()

    actions.append(
        lu.include(
            'nvblox_examples_bringup',
            'launch/orbbec_transforms.launch.py'))

    actions.append(lu.component_container(NVBLOX_CONTAINER_NAME, log_level=args.log_level))

    base_config = lu.get_path('nvblox_examples_bringup', 'config/nvblox/nvblox_base.yaml')
    realsense_config = lu.get_path(
        'nvblox_examples_bringup',
        'config/nvblox/specializations/nvblox_realsense.yaml')
    orbbec_static_config = lu.get_path(
        'nvblox_examples_bringup',
        'config/nvblox/specializations/nvblox_orbbec_static.yaml')

    nvblox_node = ComposableNode(
        name='nvblox_node',
        package='nvblox_ros',
        plugin='nvblox::NvbloxNode',
        remappings=[
            ('camera_0/depth/image', '/camera/depth/image_raw'),
            ('camera_0/depth/camera_info', '/camera/depth/camera_info'),
            ('camera_0/color/image', '/camera/color/image_raw'),
            ('camera_0/color/camera_info', '/camera/color/camera_info'),
        ],
        parameters=[
            base_config,
            realsense_config,
            orbbec_static_config,
            {'num_cameras': 1},
            {'use_lidar': False},
        ],
    )

    actions.append(lu.load_composable_nodes(NVBLOX_CONTAINER_NAME, [nvblox_node]))
    return LaunchDescription(actions)
EOF
}

write_orbbec_standalone_launch() {
  cat > "${SRC_DIR}/nvblox_examples/nvblox_examples_bringup/launch/orbbec_nvblox_standalone.launch.py" <<'EOF'
from isaac_ros_launch_utils.all_types import *
import isaac_ros_launch_utils as lu

from nvblox_ros_python_utils.nvblox_constants import NVBLOX_CONTAINER_NAME


def generate_launch_description() -> LaunchDescription:
    args = lu.ArgumentContainer()
    args.add_arg('log_level', 'info', choices=['debug', 'info', 'warn'], cli=True)
    actions = args.get_launch_actions()

    actions.append(
        lu.include(
            'nvblox_examples_bringup',
            'launch/orbbec_transforms.launch.py'))

    actions.append(lu.component_container(NVBLOX_CONTAINER_NAME, log_level=args.log_level))

    base_config = lu.get_path('nvblox_examples_bringup', 'config/nvblox/nvblox_base.yaml')
    realsense_config = lu.get_path(
        'nvblox_examples_bringup',
        'config/nvblox/specializations/nvblox_realsense.yaml')
    orbbec_static_config = lu.get_path(
        'nvblox_examples_bringup',
        'config/nvblox/specializations/nvblox_orbbec_static.yaml')

    nvblox_node = ComposableNode(
        name='nvblox_node',
        package='nvblox_ros',
        plugin='nvblox::NvbloxNode',
        remappings=[
            ('camera_0/depth/image', '/camera/depth/image_raw'),
            ('camera_0/depth/camera_info', '/camera/depth/camera_info'),
            ('camera_0/color/image', '/camera/color/image_raw'),
            ('camera_0/color/camera_info', '/camera/color/camera_info'),
        ],
        parameters=[
            base_config,
            realsense_config,
            orbbec_static_config,
            {'num_cameras': 1},
            {'use_lidar': False},
        ],
    )

    actions.append(lu.load_composable_nodes(NVBLOX_CONTAINER_NAME, [nvblox_node]))
    return LaunchDescription(actions)
EOF
}

generate_static_demo_launches() {
  log "Generating managed static demo launch files."
  mkdir -p \
    "${SRC_DIR}/nvblox_examples/nvblox_examples_bringup/launch" \
    "${SRC_DIR}/nvblox_examples/nvblox_examples_bringup/config/nvblox/specializations"
  write_orbbec_transforms_launch
  write_orbbec_static_config
  write_orbbec_example_launch
  write_orbbec_debug_launch
  write_orbbec_standalone_launch
}

patch_manifest_remove_dependencies() {
  local manifest_path="$1"
  shift
  local dependency_name=""

  [[ -f "${manifest_path}" ]] || die "Expected manifest does not exist: ${manifest_path}"

  for dependency_name in "$@"; do
    sed -i "/>${dependency_name}</d" "${manifest_path}"
  done
}

patch_static_demo_manifests() {
  local bringup_manifest="${SRC_DIR}/nvblox_examples/nvblox_examples_bringup/package.xml"

  log "Patching synced manifests for the static demo workspace."
  patch_manifest_remove_dependencies "${bringup_manifest}" "${STATIC_DEMO_REMOVED_DEPENDENCIES[@]}"
}

verify_synced_workspace_layout() {
  local path_name=""
  local file_path=""
  local bringup_manifest="${SRC_DIR}/nvblox_examples/nvblox_examples_bringup/package.xml"
  local dependency_name=""

  for path_name in "${REQUIRED_SRC_PATHS[@]}"; do
    [[ -d "${SRC_DIR}/${path_name}" ]] || die "Required synced package path is missing: ${SRC_DIR}/${path_name}"
  done

  for path_name in "${EXCLUDED_SRC_PATHS[@]}"; do
    [[ ! -e "${SRC_DIR}/${path_name}" ]] || die "Excluded package path should not exist in the managed workspace: ${SRC_DIR}/${path_name}"
  done

  for file_path in "${REQUIRED_SRC_FILE_PATHS[@]}"; do
    [[ -f "${SRC_DIR}/${file_path}" ]] || die "Required synced file is missing: ${SRC_DIR}/${file_path}"
  done

  [[ -f "${bringup_manifest}" ]] || die "Expected bringup manifest is missing: ${bringup_manifest}"
  for dependency_name in "${STATIC_DEMO_REMOVED_DEPENDENCIES[@]}"; do
    if grep -q ">${dependency_name}<" "${bringup_manifest}"; then
      die "Static demo manifest still declares excluded dependency ${dependency_name}."
    fi
  done
}

sync_static_demo_workspace() {
  log "Syncing package whitelist into the managed workspace."
  clear_managed_src_dir
  sync_package_group "${COMMUNITY_COMMON_ROOT}" "${COMMUNITY_COMMON_PACKAGE_PATHS[@]}"
  sync_package_group "${COMMUNITY_NITROS_ROOT}" "${COMMUNITY_NITROS_PACKAGE_PATHS[@]}"
  sync_package_group "${OFFICIAL_NVBLOX_ROOT}" "${OFFICIAL_NVBLOX_PACKAGE_PATHS[@]}"
  apply_overlay_files "${COMMUNITY_NVBLOX_ROOT}" "${STATIC_DEMO_OVERLAY_FILE_PATHS[@]}"
  generate_static_demo_launches
  patch_static_demo_manifests
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
sync_git_submodule "${OFFICIAL_NVBLOX_REPO_PATH}" "nvblox_ros/nvblox_core" "official Isaac ROS Nvblox"
assert_git_repo_accessible "${COMMUNITY_REPO_PATH}" "community repo"
assert_git_repo_accessible "${OFFICIAL_NVBLOX_REPO_PATH}" "official Isaac ROS Nvblox repo"
assert_git_repo_accessible "${OFFICIAL_NVBLOX_REPO_PATH}/nvblox_ros/nvblox_core" "official Isaac ROS Nvblox submodule"
COMMUNITY_COMMIT="$(git -C "${COMMUNITY_REPO_PATH}" rev-parse HEAD)"
OFFICIAL_NVBLOX_COMMIT="$(git -C "${OFFICIAL_NVBLOX_REPO_PATH}" rev-parse HEAD)"
OFFICIAL_NVBLOX_CORE_COMMIT="$(git -C "${OFFICIAL_NVBLOX_REPO_PATH}/nvblox_ros/nvblox_core" rev-parse HEAD)"

if [[ "${FORCE_REBUILD}" != "1" ]] && stamp_current; then
  log "Container workspace is already current. Skipping rebuild."
  exit 0
fi

sync_static_demo_workspace
rebuild_workspace
verify_synced_workspace_layout
verify_workspace_install || die "Container workspace verification failed."
write_stamp
log "Container workspace preparation complete."
