#!/usr/bin/env bash

if [[ "${SETUP_NVBOX_COMMON_SH:-0}" == "1" ]]; then
  return 0
fi
readonly SETUP_NVBOX_COMMON_SH=1

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT

common_fatal() {
  printf '[setup-nvbox][ERROR] %s\n' "$*" >&2
  exit 1
}

resolve_setup_user_name() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "${SUDO_USER}"
    return 0
  fi

  id -un
}

lookup_user_passwd_entry() {
  local user_name="$1"
  getent passwd "${user_name}" 2>/dev/null | head -n 1
}

resolve_user_home() {
  local user_name="$1"
  local passwd_entry=""

  passwd_entry="$(lookup_user_passwd_entry "${user_name}")"
  [[ -n "${passwd_entry}" ]] || common_fatal "Cannot resolve passwd entry for user ${user_name}."
  printf '%s\n' "$(cut -d: -f6 <<<"${passwd_entry}")"
}

readonly SETUP_USER_NAME="$(resolve_setup_user_name)"
readonly SETUP_USER_HOME="$(resolve_user_home "${SETUP_USER_NAME}")"
readonly SETUP_USER_UID="$(id -u "${SETUP_USER_NAME}")"
readonly SETUP_USER_GID="$(id -g "${SETUP_USER_NAME}")"
readonly MANAGED_ROOT_DEFAULT="${SETUP_USER_HOME}/nvblox_demo"
readonly MANAGED_SENTINEL_NAME=".managed-by-setup-nvbox"
readonly ROS_DISTRO_DEFAULT="humble"
readonly ORBBEC_VERSION="v2.3.4"
readonly ORBBEC_REPO_URL="https://github.com/orbbec/OrbbecSDK_ROS2.git"
readonly GEMINI2_USB_VENDOR_ID="2bc5"
readonly GEMINI2_USB_PRODUCT_ID="0670"
readonly GEMINI2_READY_TIMEOUT_SECONDS=15
readonly GEMINI2_SIGNAL_TIMEOUT_SECONDS=5
readonly COMMUNITY_REPO_URL_DEFAULT="https://github.com/jjjadand/isaac-NVblox-Orbbec.git"
readonly COMMUNITY_REPO_BRANCH_DEFAULT="main"
readonly BASE_IMAGE_PREFERRED="isaac_ros_dev-aarch64:latest"
readonly DERIVED_IMAGE_TAG="local/isaac_ros_nvblox_orbbec:jp6-humble"
readonly CONTAINER_NAME_DEFAULT="isaac_ros_nvblox_orbbec"
readonly CONTAINER_WORKSPACE_SPEC_VERSION="static-demo-final-v3"
readonly NVBLOX_IMAGE_SHARE_URL_DEFAULT="https://seeedstudio88-my.sharepoint.com/:u:/g/personal/youjiang_yu_seeedstudio88_onmicrosoft_com/IQCCDToomY6WSaRZdfsTs9vXAengb-SCEvNfSUgq0cipP6w?e=z9axor"
readonly NVBLOX_IMAGE_ARCHIVE_NAME_DEFAULT="nvblox_images.tar"
readonly NVBLOX_IMAGE_CACHE_DIR_DEFAULT="${SETUP_USER_HOME}/.cache/jetson-examples/nvblox"
readonly FASTDDS_RUNTIME_DIR_RELATIVE=".runtime/fastdds"
readonly FASTDDS_UDP_ONLY_PROFILE_FILENAME="udp_only.xml"
readonly ROS_DISCOVERY_ENV_VARS=(
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
readonly ROS_DISCOVERY_PATH_ENV_VARS=(
  "CYCLONEDDS_URI"
  "CYCLONEDDS_HOME"
  "FASTDDS_DEFAULT_PROFILES_FILE"
  "FASTRTPS_DEFAULT_PROFILES_FILE"
)

DOCKER_PREFIX=()

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(timestamp)" "${level}" "$*"
}

info() {
  log INFO "$@"
}

warn() {
  log WARN "$@"
}

error() {
  log ERROR "$@" >&2
}

die() {
  error "$@"
  exit 1
}

resolve_nvblox_image_share_url() {
  printf '%s\n' "${NVBLOX_IMAGE_SHARE_URL:-${NVBLOX_IMAGE_SHARE_URL_DEFAULT}}"
}

resolve_nvblox_image_archive_name() {
  printf '%s\n' "${NVBLOX_IMAGE_ARCHIVE_NAME:-${NVBLOX_IMAGE_ARCHIVE_NAME_DEFAULT}}"
}

resolve_nvblox_image_cache_dir() {
  printf '%s\n' "${NVBLOX_IMAGE_CACHE_DIR:-${NVBLOX_IMAGE_CACHE_DIR_DEFAULT}}"
}

resolve_nvblox_image_archive_path() {
  local cache_dir="${1:-$(resolve_nvblox_image_cache_dir)}"
  local archive_name="${2:-$(resolve_nvblox_image_archive_name)}"

  printf '%s/%s\n' "${cache_dir%/}" "${archive_name}"
}

cleanup_nvblox_partial_downloads() {
  local cache_dir="${1:-$(resolve_nvblox_image_cache_dir)}"
  local partial_file=""

  [[ -d "${cache_dir}" ]] || return 0

  while IFS= read -r partial_file; do
    [[ -n "${partial_file}" ]] || continue
    rm -f "${partial_file}"
    info "Removed partial NVBlox download ${partial_file}"
  done < <(find "${cache_dir}" -maxdepth 1 -type f -name '*.part' 2>/dev/null | sort)
}

ensure_supported_user_context() {
  if [[ "${EUID}" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    die "Running from a root login shell is not supported. Use your normal user account, or invoke this script with sudo from that account."
  fi

  if [[ "${EUID}" -eq 0 && "${SETUP_USER_NAME}" == "root" ]]; then
    die "Cannot determine a non-root setup user from sudo context."
  fi
}

should_reexec_as_setup_user() {
  [[ "${EUID}" -eq 0 ]] || return 1
  [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]] || return 1
  [[ "${SETUP_NVBOX_REEXECED:-0}" != "1" ]]
}

reexec_as_setup_user() {
  local script_path="$1"
  shift
  local env_args=("SETUP_NVBOX_REEXECED=1")

  if [[ -n "${MANAGED_ROOT:-}" ]]; then
    env_args+=("MANAGED_ROOT=${MANAGED_ROOT}")
  fi

  exec sudo -H -u "${SETUP_USER_NAME}" env "${env_args[@]}" bash "${script_path}" "$@"
}

run_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_sudo_noninteractive() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return 0
  fi

  sudo -n "$@"
}

guard_managed_root_path() {
  local root="$1"
  local sentinel="${root}/${MANAGED_SENTINEL_NAME}"

  if [[ -e "${root}" && ! -e "${sentinel}" ]]; then
    die "Managed root ${root} exists but is not owned by this project. Refusing to continue."
  fi
}

bootstrap_managed_root() {
  local root="$1"
  local sentinel="${root}/${MANAGED_SENTINEL_NAME}"

  guard_managed_root_path "${root}"
  mkdir -p "${root}/logs" "${root}/.stamps"
  if [[ ! -f "${sentinel}" ]]; then
    {
      printf 'managed_root=%s\n' "${root}"
      printf 'created_at=%s\n' "$(date -Is 2>/dev/null || date)"
      printf 'project_root=%s\n' "${PROJECT_ROOT}"
    } > "${sentinel}"
  fi
}

repair_managed_root_ownership() {
  local root="$1"
  local sentinel="${root}/${MANAGED_SENTINEL_NAME}"

  [[ -d "${root}" ]] || return 0
  [[ -f "${sentinel}" ]] || return 0

  if find "${root}" \( ! -uid "${SETUP_USER_UID}" -o ! -gid "${SETUP_USER_GID}" \) -print -quit 2>/dev/null | grep -q .; then
    info "Repairing managed root ownership under ${root}."
    run_sudo chown -R "${SETUP_USER_UID}:${SETUP_USER_GID}" "${root}"
  fi
}

require_bootstrapped_managed_root() {
  local root="$1"
  local sentinel="${root}/${MANAGED_SENTINEL_NAME}"

  if [[ ! -f "${sentinel}" ]]; then
    die "Managed root ${root} is not prepared. Run with --prepare-only or the default mode first."
  fi
}

package_installed() {
  local package_name="$1"
  dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | grep -q 'install ok installed'
}

install_packages_if_missing() {
  local missing=()
  local package_name

  for package_name in "$@"; do
    if ! package_installed "${package_name}"; then
      missing+=("${package_name}")
    fi
  done

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  info "Installing apt packages: ${missing[*]}"
  run_sudo apt-get update
  run_sudo apt-get install -y --no-install-recommends "${missing[@]}"
}

assert_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || die "Required command not found: ${command_name}"
}

read_file_lower_trimmed() {
  local file_path="$1"
  tr '[:upper:]' '[:lower:]' < "${file_path}" | tr -d '[:space:]'
}

find_usb_device_with_ids() {
  local start_path="$1"
  local current_path=""

  current_path="$(readlink -f "${start_path}" 2>/dev/null || true)"
  [[ -n "${current_path}" ]] || return 1

  while [[ "${current_path}" != "/" ]]; do
    if [[ -f "${current_path}/idVendor" && -f "${current_path}/idProduct" ]]; then
      if [[ "$(read_file_lower_trimmed "${current_path}/idVendor")" == "${GEMINI2_USB_VENDOR_ID}" ]] && \
         [[ "$(read_file_lower_trimmed "${current_path}/idProduct")" == "${GEMINI2_USB_PRODUCT_ID}" ]]; then
        printf '%s\n' "${current_path}"
        return 0
      fi
    fi
    current_path="$(dirname "${current_path}")"
  done

  return 1
}

gemini2_usb_device_dirs() {
  local device_dir

  for device_dir in /sys/bus/usb/devices/*; do
    [[ -f "${device_dir}/idVendor" && -f "${device_dir}/idProduct" ]] || continue
    if [[ "$(read_file_lower_trimmed "${device_dir}/idVendor")" == "${GEMINI2_USB_VENDOR_ID}" ]] && \
       [[ "$(read_file_lower_trimmed "${device_dir}/idProduct")" == "${GEMINI2_USB_PRODUCT_ID}" ]]; then
      printf '%s\n' "${device_dir}"
    fi
  done
}

gemini2_usb_present() {
  local usb_device=""
  usb_device="$(gemini2_usb_device_dirs | head -n 1 || true)"
  [[ -n "${usb_device}" ]]
}

gemini2_video_nodes() {
  local video_sysfs_path=""
  local video_name=""

  for video_sysfs_path in /sys/class/video4linux/video*; do
    [[ -e "${video_sysfs_path}" ]] || continue
    if find_usb_device_with_ids "${video_sysfs_path}/device" >/dev/null 2>&1; then
      video_name="$(basename "${video_sysfs_path}")"
      [[ -e "/dev/${video_name}" ]] || continue
      printf '/dev/%s\n' "${video_name}"
    fi
  done | sort -u
}

gemini2_video_nodes_joined() {
  local video_nodes=()

  mapfile -t video_nodes < <(gemini2_video_nodes)
  if ((${#video_nodes[@]} == 0)); then
    return 0
  fi

  printf '%s\n' "${video_nodes[*]}"
}

gemini2_device_state() {
  local video_nodes=""

  if ! gemini2_usb_present; then
    printf 'usb_missing\n'
    return 0
  fi

  video_nodes="$(gemini2_video_nodes_joined)"
  if [[ -n "${video_nodes}" ]]; then
    printf 'ready\n'
  else
    printf 'usb_present_no_video\n'
  fi
}

log_gemini2_device_state() {
  local prefix="${1:-Gemini2 device state}"
  local state=""
  local video_nodes=""

  state="$(gemini2_device_state)"
  video_nodes="$(gemini2_video_nodes_joined)"

  if [[ -n "${video_nodes}" ]]; then
    info "${prefix}: ${state} (video nodes: ${video_nodes})"
  else
    info "${prefix}: ${state}"
  fi
}

gemini2_detected() {
  [[ "$(gemini2_device_state)" == "ready" ]]
}

wait_for_gemini2_ready() {
  local timeout_seconds="${1:-${GEMINI2_READY_TIMEOUT_SECONDS}}"
  local deadline=$((SECONDS + timeout_seconds))

  while ((SECONDS < deadline)); do
    if [[ "$(gemini2_device_state)" == "ready" ]]; then
      return 0
    fi
    sleep 1
  done

  return 1
}

collect_live_pids() {
  local pid=""

  for pid in "$@"; do
    if kill -0 "${pid}" 2>/dev/null; then
      printf '%s\n' "${pid}"
    fi
  done
}

cleanup_residual_gemini2_processes() {
  local context="${1:-Gemini2 cleanup}"
  local patterns=(
    'ros2 launch orbbec_camera gemini2.launch.py'
    'camera_container'
    'orbbec_camera_node'
  )
  local pattern=""
  local pid=""
  local signal=""
  local deadline=0
  local pids=()
  local live_pids=()
  declare -A seen_pids=()

  command -v pgrep >/dev/null 2>&1 || return 0

  for pattern in "${patterns[@]}"; do
    while IFS= read -r pid; do
      [[ -n "${pid}" ]] || continue
      [[ -n "${seen_pids[${pid}]:-}" ]] && continue
      seen_pids["${pid}"]=1
      pids+=("${pid}")
    done < <(pgrep -f -- "${pattern}" || true)
  done

  if ((${#pids[@]} == 0)); then
    return 0
  fi

  for pid in "${pids[@]}"; do
    info "${context}: found residual Gemini2 host process ${pid}: $(ps -p "${pid}" -o args= 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
  done

  for signal in INT TERM KILL; do
    live_pids=()
    mapfile -t live_pids < <(collect_live_pids "${pids[@]}")
    ((${#live_pids[@]} == 0)) && return 0

    info "${context}: sending SIG${signal} to Gemini2 host processes: ${live_pids[*]}"
    kill "-${signal}" "${live_pids[@]}" 2>/dev/null || true

    deadline=$((SECONDS + GEMINI2_SIGNAL_TIMEOUT_SECONDS))
    while ((SECONDS < deadline)); do
      mapfile -t live_pids < <(collect_live_pids "${pids[@]}")
      ((${#live_pids[@]} == 0)) && return 0
      sleep 1
    done
  done

  mapfile -t live_pids < <(collect_live_pids "${pids[@]}")
  if ((${#live_pids[@]} != 0)); then
    warn "${context}: Gemini2 host processes are still alive after SIGKILL: ${live_pids[*]}"
    return 1
  fi

  return 0
}

gemini2_refresh_udev() {
  local interactive_sudo="${1:-1}"

  if ! command -v udevadm >/dev/null 2>&1; then
    warn "udevadm is not available; skipping Gemini2 udev refresh."
    return 1
  fi

  info "Refreshing udev rules for Gemini2."
  if (( interactive_sudo )); then
    run_sudo udevadm control --reload-rules
    run_sudo udevadm trigger
  else
    if ! run_sudo_noninteractive udevadm control --reload-rules; then
      warn "Skipping Gemini2 udev refresh because passwordless sudo is not available."
      return 1
    fi
    run_sudo_noninteractive udevadm trigger || return 1
  fi

  return 0
}

write_sysfs_value_with_sudo() {
  local file_path="$1"
  local value="$2"
  local interactive_sudo="${3:-1}"

  if (( interactive_sudo )); then
    run_sudo bash -lc "printf '%s' '${value}' > '${file_path}'"
  else
    if ! run_sudo_noninteractive bash -lc "printf '%s' '${value}' > '${file_path}'"; then
      warn "Skipping Gemini2 sysfs write to ${file_path} because passwordless sudo is not available."
      return 1
    fi
  fi
}

rebind_gemini2_usb_devices() {
  local interactive_sudo="${1:-1}"
  local device_dir=""
  local device_name=""
  local found_device=0

  while IFS= read -r device_dir; do
    [[ -n "${device_dir}" ]] || continue
    found_device=1
    device_name="$(basename "${device_dir}")"
    info "Rebinding Gemini2 USB device ${device_name}."
    write_sysfs_value_with_sudo "/sys/bus/usb/drivers/usb/unbind" "${device_name}" "${interactive_sudo}" || return 1
    sleep 1
    write_sysfs_value_with_sudo "/sys/bus/usb/drivers/usb/bind" "${device_name}" "${interactive_sudo}" || return 1
  done < <(gemini2_usb_device_dirs)

  (( found_device )) || return 1
  return 0
}

recover_gemini2_device() {
  local context="${1:-Gemini2 recovery}"
  local cleanup_processes="${2:-1}"
  local allow_usb_rebind="${3:-1}"
  local interactive_sudo="${4:-1}"

  log_gemini2_device_state "Gemini2 device state before ${context}"
  if [[ "$(gemini2_device_state)" == "ready" ]]; then
    return 0
  fi

  if [[ "$(gemini2_device_state)" == "usb_missing" ]]; then
    return 1
  fi

  if (( cleanup_processes )); then
    cleanup_residual_gemini2_processes "${context}" || true
  fi

  if gemini2_refresh_udev "${interactive_sudo}"; then
    if wait_for_gemini2_ready "${GEMINI2_READY_TIMEOUT_SECONDS}"; then
      info "Gemini2 recovery succeeded after udev refresh (${context})."
      log_gemini2_device_state "Gemini2 device state after ${context}"
      return 0
    fi
  fi

  if (( allow_usb_rebind )) && gemini2_usb_present; then
    if rebind_gemini2_usb_devices "${interactive_sudo}"; then
      if wait_for_gemini2_ready "${GEMINI2_READY_TIMEOUT_SECONDS}"; then
        info "Gemini2 recovery succeeded after USB rebind (${context})."
        log_gemini2_device_state "Gemini2 device state after ${context}"
        return 0
      fi
    fi
  fi

  log_gemini2_device_state "Gemini2 device state after ${context}"
  return 1
}

assert_supported_platform() {
  local arch=""
  local model=""
  local jetpack_version=""
  local jetpack_major=""

  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  if [[ "${arch}" != "arm64" && "${arch}" != "aarch64" ]]; then
    die "Unsupported architecture: ${arch}. This script only supports Jetson Orin arm64."
  fi

  [[ -f /etc/os-release ]] || die "Cannot detect OS version because /etc/os-release is missing."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Unsupported OS: ${ID:-unknown}. Ubuntu 22.04 is required."
  [[ "${VERSION_ID:-}" == "22.04" ]] || die "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Ubuntu 22.04 is required."

  [[ -f /proc/device-tree/model ]] || die "Cannot detect Jetson model from /proc/device-tree/model."
  model="$(tr -d '\0' < /proc/device-tree/model)"
  [[ "${model}" == *"Jetson"* ]] || die "Unsupported Jetson model: ${model}. A Jetson Orin device is required."
  [[ "${model}" == *"Orin"* ]] || die "Unsupported Jetson model: ${model}. A Jetson Orin device is required."

  jetpack_version="$(dpkg-query -W -f='${Version}' nvidia-jetpack 2>/dev/null || true)"
  [[ -n "${jetpack_version}" ]] || die "nvidia-jetpack is not installed. JetPack 6.x is required."
  if [[ "${jetpack_version}" =~ ^([0-9]+) ]]; then
    jetpack_major="${BASH_REMATCH[1]}"
  else
    die "Unable to parse nvidia-jetpack version: ${jetpack_version}"
  fi

  [[ "${jetpack_major}" == "6" ]] || die "Unsupported JetPack version: ${jetpack_version}. JetPack 6.x is required."
  info "Platform OK: ${model}, Ubuntu ${VERSION_ID}, JetPack ${jetpack_version}"
}

check_apt_locks() {
  local lock_path
  local pids

  if ! command -v fuser >/dev/null 2>&1; then
    warn "fuser is not available; skipping apt lock inspection."
    return 0
  fi

  for lock_path in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock; do
    pids="$(fuser "${lock_path}" 2>/dev/null || true)"
    if [[ -n "${pids}" ]]; then
      die "apt/dpkg lock detected on ${lock_path} (pids: ${pids}). Resolve it before continuing."
    fi
  done
}

check_network_endpoints() {
  local endpoint

  assert_command curl
  for endpoint in "$@"; do
    if ! curl -fsSI --max-time 10 "${endpoint}" >/dev/null 2>&1; then
      die "Cannot reach ${endpoint}. Network access is required for prepare mode."
    fi
  done
}

warn_on_unreachable_endpoints() {
  local endpoint

  assert_command curl
  for endpoint in "$@"; do
    if curl -fsSI --max-time 10 "${endpoint}" >/dev/null 2>&1; then
      info "Network probe OK: ${endpoint}"
    else
      warn "Network probe failed for ${endpoint}. Continuing; the real install steps will fail later if access is actually required."
    fi
  done
}

ensure_docker_access() {
  if docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=()
    return 0
  fi

  if sudo docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=(sudo)
    return 0
  fi

  die "Cannot access the Docker daemon with docker or sudo docker."
}

docker_cmd() {
  if ((${#DOCKER_PREFIX[@]})); then
    "${DOCKER_PREFIX[@]}" docker "$@"
  else
    docker "$@"
  fi
}

append_jetson_container_args() {
  local -n jetson_docker_args_ref="$1"

  jetson_docker_args_ref+=(
    --runtime=nvidia
    --privileged
    --network host
    --ipc host
    --pid host
    --ulimit memlock=-1
    --ulimit stack=67108864
    -e "NVIDIA_VISIBLE_DEVICES=nvidia.com/gpu=all,nvidia.com/pva=all"
    -e "NVIDIA_DRIVER_CAPABILITIES=all"
    -e "ISAAC_ROS_WS=/workspaces/isaac_ros-dev"
    -v /etc/localtime:/etc/localtime:ro
    -v /tmp:/tmp
  )

  if [[ -f /usr/bin/tegrastats ]]; then
    jetson_docker_args_ref+=(-v /usr/bin/tegrastats:/usr/bin/tegrastats)
  fi
  if [[ -d /usr/lib/aarch64-linux-gnu/tegra ]]; then
    jetson_docker_args_ref+=(-v /usr/lib/aarch64-linux-gnu/tegra:/usr/lib/aarch64-linux-gnu/tegra)
  fi
  if [[ -d /usr/src/jetson_multimedia_api ]]; then
    jetson_docker_args_ref+=(-v /usr/src/jetson_multimedia_api:/usr/src/jetson_multimedia_api)
  fi
  if [[ -d /usr/share/vpi3 ]]; then
    jetson_docker_args_ref+=(-v /usr/share/vpi3:/usr/share/vpi3)
  fi
  if [[ -d /dev/input ]]; then
    jetson_docker_args_ref+=(-v /dev/input:/dev/input)
  fi
  if getent group jtop >/dev/null 2>&1 && [[ -S /run/jtop.sock ]]; then
    jetson_docker_args_ref+=(-v /run/jtop.sock:/run/jtop.sock:ro)
  fi
}

resolve_ros_discovery_env_value() {
  local var_name="$1"
  local value=""

  case "${var_name}" in
    RMW_IMPLEMENTATION)
      value="${RMW_IMPLEMENTATION:-}"
      if [[ -z "${value}" ]]; then
        value="rmw_fastrtps_cpp"
      fi
      ;;
    *)
      value="${!var_name-}"
      ;;
  esac

  printf '%s\n' "${value}"
}

export_effective_ros_discovery_env() {
  local var_name=""
  local value=""

  for var_name in "${ROS_DISCOVERY_ENV_VARS[@]}"; do
    value="$(resolve_ros_discovery_env_value "${var_name}")"
    if [[ -n "${value}" ]]; then
      export "${var_name}=${value}"
    else
      unset "${var_name}" || true
    fi
  done
}

ros_discovery_env_summary() {
  local parts=()
  local var_name=""
  local value=""
  local old_ifs="${IFS}"

  for var_name in "${ROS_DISCOVERY_ENV_VARS[@]}"; do
    value="$(resolve_ros_discovery_env_value "${var_name}")"
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

log_ros_discovery_env() {
  local prefix="${1:-ROS discovery env}"
  info "${prefix}: $(ros_discovery_env_summary)"
}

emit_ros_discovery_env_shell_exports() {
  local var_name=""
  local value=""

  for var_name in "${ROS_DISCOVERY_ENV_VARS[@]}"; do
    value="$(resolve_ros_discovery_env_value "${var_name}")"
    if [[ -n "${value}" ]]; then
      printf 'export %s=%q\n' "${var_name}" "${value}"
    else
      printf 'unset %s\n' "${var_name}"
    fi
  done
}

managed_fastdds_profile_path() {
  local managed_root="$1"
  printf '%s/%s/%s\n' "${managed_root}" "${FASTDDS_RUNTIME_DIR_RELATIVE}" "${FASTDDS_UDP_ONLY_PROFILE_FILENAME}"
}

write_managed_fastdds_udp_profile() {
  local managed_root="$1"
  local profile_path=""
  local profile_dir=""

  profile_path="$(managed_fastdds_profile_path "${managed_root}")"
  profile_dir="$(dirname "${profile_path}")"
  mkdir -p "${profile_dir}"

  cat > "${profile_path}" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<dds xmlns="http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles">
  <profiles>
    <transport_descriptors>
      <transport_descriptor>
        <transport_id>udp_transport</transport_id>
        <type>UDPv4</type>
      </transport_descriptor>
    </transport_descriptors>
    <participant profile_name="udp_only_participant" is_default_profile="true">
      <rtps>
        <useBuiltinTransports>false</useBuiltinTransports>
        <userTransports>
          <transport_id>udp_transport</transport_id>
        </userTransports>
      </rtps>
    </participant>
  </profiles>
</dds>
EOF

  printf '%s\n' "${profile_path}"
}

enable_managed_fastdds_udp_runtime() {
  local managed_root="$1"
  local profile_path=""

  profile_path="$(write_managed_fastdds_udp_profile "${managed_root}")"
  export FASTDDS_DEFAULT_PROFILES_FILE="${profile_path}"
  export FASTRTPS_DEFAULT_PROFILES_FILE="${profile_path}"
  info "Managed Fast DDS UDP-only profile: ${profile_path}"
}

append_ros_discovery_env_args() {
  local -n ros_discovery_env_args_ref="$1"
  local var_name=""
  local value=""

  for var_name in "${ROS_DISCOVERY_ENV_VARS[@]}"; do
    value="$(resolve_ros_discovery_env_value "${var_name}")"
    if [[ -n "${value}" ]]; then
      ros_discovery_env_args_ref+=(-e "${var_name}=${value}")
    fi
  done
}

resolve_ros_discovery_mount_source() {
  local var_name="$1"
  local value=""

  value="$(resolve_ros_discovery_env_value "${var_name}")"
  [[ -n "${value}" ]] || return 1

  case "${var_name}" in
    CYCLONEDDS_URI)
      if [[ "${value}" == file://* ]]; then
        value="${value#file://}"
      fi
      ;;
  esac

  [[ "${value}" = /* ]] || return 1
  [[ -e "${value}" ]] || return 1
  printf '%s\n' "${value}"
}

append_ros_discovery_mount_args() {
  local -n ros_discovery_mount_args_ref="$1"
  local var_name=""
  local mount_source=""
  local mount_mode="ro"
  declare -A seen_mounts=()

  for var_name in "${ROS_DISCOVERY_PATH_ENV_VARS[@]}"; do
    mount_source="$(resolve_ros_discovery_mount_source "${var_name}" || true)"
    [[ -n "${mount_source}" ]] || continue
    [[ -z "${seen_mounts[${mount_source}]:-}" ]] || continue
    seen_mounts["${mount_source}"]=1

    if [[ -d "${mount_source}" && "${var_name}" == "CYCLONEDDS_HOME" ]]; then
      mount_mode="rw"
    else
      mount_mode="ro"
    fi

    ros_discovery_mount_args_ref+=(-v "${mount_source}:${mount_source}:${mount_mode}")
  done
}

append_ros_discovery_container_args() {
  local docker_args_name="$1"
  append_ros_discovery_env_args "${docker_args_name}"
  append_ros_discovery_mount_args "${docker_args_name}"
}

validate_nvblox_examples_bringup_install_artifacts() {
  local workspace_root="$1"
  shift
  local required_paths=("$@")
  local required_artifact_list=""
  local validate_cmd=""
  local validate_args=(
    run
    --rm
    -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}"
    -v "${workspace_root}:/workspaces/isaac_ros-dev"
  )

  ((${#required_paths[@]} != 0)) || return 0
  required_artifact_list="$(printf '%s\n' "${required_paths[@]}")"
  append_jetson_container_args validate_args
  append_ros_discovery_container_args validate_args
  validate_args+=(-e "REQUIRED_ARTIFACT_LIST=${required_artifact_list}")

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
if (( restore_nounset )); then
  set -u
fi
PACKAGE_PREFIX="$(ros2 pkg prefix nvblox_examples_bringup 2>/dev/null || true)"
[[ -n "${PACKAGE_PREFIX}" ]]
INSTALL_ROOT="${PACKAGE_PREFIX}/share/nvblox_examples_bringup"

while IFS= read -r relative_path; do
  [[ -n "${relative_path}" ]] || continue
  [[ -f "${INSTALL_ROOT}/${relative_path}" ]] || {
    printf '%s\n' "${INSTALL_ROOT}/${relative_path}" >&2
    exit 10
  }
done <<< "${REQUIRED_ARTIFACT_LIST}"
EOF
  )

  docker_cmd "${validate_args[@]}" "${DERIVED_IMAGE_TAG}" bash -lc "${validate_cmd}"
}

select_base_image() {
  local candidate=""

  if docker_cmd image inspect "${BASE_IMAGE_PREFERRED}" >/dev/null 2>&1; then
    printf '%s\n' "${BASE_IMAGE_PREFERRED}"
    return 0
  fi

  candidate="$(docker_cmd image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^nvcr\.io/nvidia/isaac/ros:.*aarch64-ros2_humble' | head -n 1 || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  return 1
}

acceptable_base_image_hint() {
  printf '%s\n' "${BASE_IMAGE_PREFERRED} or nvcr.io/nvidia/isaac/ros:*aarch64-ros2_humble*"
}

docker_image_id() {
  local image_ref="$1"
  docker_cmd image inspect --format '{{.Id}}' "${image_ref}"
}

compute_tree_hash() {
  local combined=""
  local file_path

  assert_command sha256sum

  for file_path in "$@"; do
    [[ -f "${file_path}" ]] || die "Cannot hash missing file: ${file_path}"
    combined+=$(sha256sum "${file_path}")
  done

  printf '%s' "${combined}" | sha256sum | awk '{print $1}'
}

container_image_context_hash() {
  compute_tree_hash \
    "${PROJECT_ROOT}/docker/Dockerfile.nvblox_orbbec" \
    "${PROJECT_ROOT}/docker/prepare_container_workspace.sh" \
    "${PROJECT_ROOT}/docker/launch_nvblox.sh"
}

source_ros_setup() {
  local workspace_root="${1:-}"
  local restore_nounset=0

  if [[ $- == *u* ]]; then
    restore_nounset=1
    set +u
  fi

  # shellcheck disable=SC1091
  source "/opt/ros/${ROS_DISTRO_DEFAULT}/setup.bash"
  if [[ -n "${workspace_root}" && -f "${workspace_root}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090
    source "${workspace_root}/install/setup.bash"
  fi

  if (( restore_nounset )); then
    set -u
  fi
}
