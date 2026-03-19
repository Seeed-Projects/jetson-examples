#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

MANAGED_ROOT="${MANAGED_ROOT_DEFAULT}"
FORCE_REBUILD=0

while (($#)); do
  case "$1" in
    --managed-root)
      shift
      MANAGED_ROOT="$1"
      ;;
    --force-rebuild)
      FORCE_REBUILD=1
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

ensure_supported_user_context
if should_reexec_as_setup_user; then
  die "Do not invoke prepare_host.sh with sudo directly. Run reComputer run nvblox instead."
fi
bootstrap_managed_root "${MANAGED_ROOT}"

HOST_WS="${MANAGED_ROOT}/ros2_ws"
HOST_REPO="${HOST_WS}/src/OrbbecSDK_ROS2"
HOST_STAMP="${MANAGED_ROOT}/.stamps/host_workspace.env"

ensure_locale() {
  install_packages_if_missing locales
  if ! locale -a 2>/dev/null | grep -qi '^en_US\.utf-8$'; then
    info "Generating en_US.UTF-8 locale."
    printf 'en_US.UTF-8 UTF-8\n' | run_sudo tee -a /etc/locale.gen >/dev/null
    run_sudo locale-gen en_US.UTF-8
  fi

  run_sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
}

ensure_ros2_repository() {
  local ros_keyring="/usr/share/keyrings/ros-archive-keyring.gpg"
  local ros_source="/etc/apt/sources.list.d/ros2.list"
  local repo_line=""

  if [[ -f "/opt/ros/${ROS_DISTRO_DEFAULT}/setup.bash" ]]; then
    return 0
  fi

  info "Installing ROS 2 apt repository."
  install_packages_if_missing curl gnupg lsb-release ca-certificates software-properties-common
  run_sudo add-apt-repository universe -y

  if [[ ! -f "${ros_keyring}" ]]; then
    run_sudo curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o "${ros_keyring}"
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  repo_line="deb [arch=$(dpkg --print-architecture) signed-by=${ros_keyring}] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main"
  if [[ ! -f "${ros_source}" ]] || ! grep -Fqx "${repo_line}" "${ros_source}" 2>/dev/null; then
    printf '%s\n' "${repo_line}" | run_sudo tee "${ros_source}" >/dev/null
  fi
}

ensure_ros2_humble() {
  if [[ -f "/opt/ros/${ROS_DISTRO_DEFAULT}/setup.bash" ]]; then
    info "ROS 2 ${ROS_DISTRO_DEFAULT} already installed."
    return 0
  fi

  ensure_locale
  ensure_ros2_repository
  install_packages_if_missing "ros-${ROS_DISTRO_DEFAULT}-desktop" python3-rosdep python3-vcstool python3-colcon-common-extensions
}

ensure_rosdep_ready() {
  install_packages_if_missing python3-rosdep python3-vcstool python3-colcon-common-extensions python3-pip build-essential git curl

  if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    info "Initializing rosdep."
    run_sudo rosdep init
  fi

  info "Updating rosdep."
  rosdep update
}

sync_orbbec_repo() {
  mkdir -p "${HOST_WS}/src"

  if [[ ! -d "${HOST_REPO}/.git" ]]; then
    info "Cloning OrbbecSDK_ROS2 ${ORBBEC_VERSION}."
    git clone --branch "${ORBBEC_VERSION}" --depth 1 "${ORBBEC_REPO_URL}" "${HOST_REPO}"
    return 0
  fi

  if [[ -n "$(git -C "${HOST_REPO}" status --porcelain)" ]]; then
    die "Managed Orbbec repo at ${HOST_REPO} has local changes. Clean it or remove ${MANAGED_ROOT} before retrying."
  fi

  info "Refreshing OrbbecSDK_ROS2 checkout."
  git -C "${HOST_REPO}" fetch --depth 1 origin "refs/tags/${ORBBEC_VERSION}:refs/tags/${ORBBEC_VERSION}"
  git -C "${HOST_REPO}" checkout -f "${ORBBEC_VERSION}"
}

install_orbbec_udev_rules() {
  info "Installing Orbbec udev rules."
  (
    cd "${HOST_REPO}/orbbec_camera/scripts"
    run_sudo bash install_udev_rules.sh
  )
  run_sudo udevadm control --reload-rules
  run_sudo udevadm trigger
}

verify_host_workspace() {
  local pkg_prefix=""

  [[ -f "${HOST_WS}/install/setup.bash" ]] || return 1

  source_ros_setup "${HOST_WS}"
  pkg_prefix="$(ros2 pkg prefix orbbec_camera 2>/dev/null || true)"
  [[ -n "${pkg_prefix}" ]] || return 1
  [[ -d "${pkg_prefix}/share/orbbec_camera" ]] || return 1
}

host_stamp_current() {
  [[ -f "${HOST_STAMP}" ]] || return 1
  # shellcheck disable=SC1090
  source "${HOST_STAMP}"
  [[ "${HOST_ORBBEC_VERSION:-}" == "${ORBBEC_VERSION}" ]] || return 1
  verify_host_workspace
}

write_host_stamp() {
  {
    printf 'HOST_ORBBEC_VERSION=%q\n' "${ORBBEC_VERSION}"
    printf 'HOST_STAMPED_AT=%q\n' "$(date -Is 2>/dev/null || date)"
  } > "${HOST_STAMP}"
}

ensure_locale
ensure_ros2_humble
ensure_rosdep_ready

install_packages_if_missing \
  libgflags-dev \
  nlohmann-json3-dev \
  libdw-dev \
  libssl-dev \
  mesa-utils \
  libgl1 \
  libgoogle-glog-dev \
  "ros-${ROS_DISTRO_DEFAULT}-image-transport" \
  "ros-${ROS_DISTRO_DEFAULT}-image-transport-plugins" \
  "ros-${ROS_DISTRO_DEFAULT}-compressed-image-transport" \
  "ros-${ROS_DISTRO_DEFAULT}-image-publisher" \
  "ros-${ROS_DISTRO_DEFAULT}-camera-info-manager" \
  "ros-${ROS_DISTRO_DEFAULT}-diagnostic-updater" \
  "ros-${ROS_DISTRO_DEFAULT}-diagnostic-msgs" \
  "ros-${ROS_DISTRO_DEFAULT}-statistics-msgs" \
  "ros-${ROS_DISTRO_DEFAULT}-xacro" \
  "ros-${ROS_DISTRO_DEFAULT}-backward-ros"

sync_orbbec_repo
install_orbbec_udev_rules

if (( FORCE_REBUILD == 0 )) && host_stamp_current; then
  info "Host Orbbec workspace is already prepared. Skipping rebuild."
  exit 0
fi

source_ros_setup

info "Installing host workspace rosdep dependencies."
(
  cd "${HOST_WS}"
  rosdep install --from-paths src --ignore-src -r -y --rosdistro "${ROS_DISTRO_DEFAULT}"
)

info "Building host Orbbec workspace."
(
  cd "${HOST_WS}"
  if (( FORCE_REBUILD )); then
    rm -rf build install log
  fi
  colcon build --event-handlers console_direct+ --cmake-args -DCMAKE_BUILD_TYPE=Release
)

verify_host_workspace || die "Host Orbbec workspace verification failed."
write_host_stamp
info "Host preparation complete."
