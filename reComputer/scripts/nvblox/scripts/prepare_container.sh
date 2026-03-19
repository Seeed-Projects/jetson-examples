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
  die "Do not invoke prepare_container.sh with sudo directly. Run reComputer run nvblox instead."
fi
bootstrap_managed_root "${MANAGED_ROOT}"
ensure_docker_access

CONTAINER_WS="${MANAGED_ROOT}/isaac_ros-dev"
IMAGE_STAMP="${MANAGED_ROOT}/.stamps/derived_image.env"
DOCKERFILE_PATH="${PROJECT_ROOT}/docker/Dockerfile.nvblox_orbbec"
CONTEXT_HASH="$(container_image_context_hash)"
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

probe_gpu_runtime() {
  local image_ref="$1"
  local log_file="${2:-/dev/null}"
  local args=(run --rm --entrypoint /bin/bash)
  append_jetson_container_args args
  docker_cmd "${args[@]}" "${image_ref}" -lc 'echo runtime-ok >/dev/null' >"${log_file}" 2>&1
}

ensure_nvidia_runtime() {
  local base_image="$1"
  local config_file="/etc/nvidia-container-runtime/config.toml"
  local probe_log
  probe_log="$(mktemp)"
  trap 'rm -f "${probe_log}"' RETURN

  if probe_gpu_runtime "${base_image}" "${probe_log}"; then
    info "NVIDIA container runtime probe succeeded."
    return 0
  fi

  warn "Initial NVIDIA runtime probe output:"
  sed 's/^/[probe] /' "${probe_log}" >&2 || true
  warn "NVIDIA runtime probe failed. Trying to switch the runtime to csv mode."
  [[ -f "${config_file}" ]] || die "Runtime config file ${config_file} was not found."

  run_sudo sed -i -E 's/mode = "(auto|cdi)"/mode = "csv"/' "${config_file}"
  run_sudo systemctl restart docker

  : > "${probe_log}"
  if ! probe_gpu_runtime "${base_image}" "${probe_log}"; then
    sed 's/^/[probe] /' "${probe_log}" >&2 || true
    die "NVIDIA runtime probe still fails after switching to csv mode."
  fi
  info "NVIDIA container runtime is now working."
}

image_stamp_current() {
  [[ -f "${IMAGE_STAMP}" ]] || return 1
  # shellcheck disable=SC1090
  source "${IMAGE_STAMP}"
  [[ "${STAMP_BASE_IMAGE_REF:-}" == "${BASE_IMAGE_REF}" ]] || return 1
  [[ "${STAMP_BASE_IMAGE_ID:-}" == "${BASE_IMAGE_ID}" ]] || return 1
  [[ "${STAMP_CONTEXT_HASH:-}" == "${CONTEXT_HASH}" ]] || return 1
  docker_cmd image inspect "${DERIVED_IMAGE_TAG}" >/dev/null 2>&1
}

write_image_stamp() {
  {
    printf 'STAMP_BASE_IMAGE_REF=%q\n' "${BASE_IMAGE_REF}"
    printf 'STAMP_BASE_IMAGE_ID=%q\n' "${BASE_IMAGE_ID}"
    printf 'STAMP_CONTEXT_HASH=%q\n' "${CONTEXT_HASH}"
    printf 'STAMPED_AT=%q\n' "$(date -Is 2>/dev/null || date)"
  } > "${IMAGE_STAMP}"
}

build_derived_image() {
  info "Building derived image ${DERIVED_IMAGE_TAG} from ${BASE_IMAGE_REF}."
  docker_cmd build \
    --network host \
    --build-arg "BASE_IMAGE=${BASE_IMAGE_REF}" \
    --build-arg "ROS_DISTRO=${ROS_DISTRO_DEFAULT}" \
    -t "${DERIVED_IMAGE_TAG}" \
    -f "${DOCKERFILE_PATH}" \
    "${PROJECT_ROOT}"
}

prepare_container_workspace() {
  local args=(run --rm)

  mkdir -p "${CONTAINER_WS}/src" "${CONTAINER_WS}/.setup-nvbox"

  info "Preparing container workspace in ${CONTAINER_WS}."
  append_jetson_container_args args
  args+=(
    -e "ROS_DISTRO=${ROS_DISTRO_DEFAULT}" \
    -e "FORCE_REBUILD=${FORCE_REBUILD}" \
    -e "EXPECTED_WORKSPACE_SPEC_VERSION=${CONTAINER_WORKSPACE_SPEC_VERSION}" \
    -e "SETUP_IMAGE_ID=${DERIVED_IMAGE_ID}" \
    -e "SETUP_IMAGE_CONTEXT_HASH=${CONTEXT_HASH}" \
    -e "COMMUNITY_REPO_URL=${COMMUNITY_REPO_URL_DEFAULT}" \
    -e "COMMUNITY_REPO_BRANCH=${COMMUNITY_REPO_BRANCH_DEFAULT}" \
    -e "OFFICIAL_VSLAM_REPO_URL=${OFFICIAL_VSLAM_REPO_URL_DEFAULT}" \
    -e "OFFICIAL_VSLAM_REPO_BRANCH=${OFFICIAL_VSLAM_REPO_BRANCH_DEFAULT}" \
    -e "ORBBEC_LAUNCH_REPO_URL=${ORBBEC_LAUNCH_REPO_URL_DEFAULT}" \
    -e "ORBBEC_LAUNCH_REPO_BRANCH=${ORBBEC_LAUNCH_REPO_BRANCH_DEFAULT}" \
    -v "${CONTAINER_WS}:/workspaces/isaac_ros-dev" \
    "${DERIVED_IMAGE_TAG}" \
    /opt/nvblox/bin/prepare_container_workspace.sh
  )
  docker_cmd "${args[@]}"
}

validate_prepared_container_workspace() {
  local stamp_path="${CONTAINER_WS}/.setup-nvbox/container_workspace.env"
  local current_image_id=""

  [[ -f "${CONTAINER_WS}/install/setup.bash" ]] || die "Prepared container workspace is missing ${CONTAINER_WS}/install/setup.bash."
  [[ -f "${stamp_path}" ]] || die "Prepared container workspace stamp is missing at ${stamp_path}."

  current_image_id="$(docker_image_id "${DERIVED_IMAGE_TAG}")"

  # shellcheck disable=SC1090
  source "${stamp_path}"

  [[ "${STAMP_WORKSPACE_SPEC_VERSION:-}" == "${CONTAINER_WORKSPACE_SPEC_VERSION}" ]] || \
    die "Prepared container workspace spec is ${STAMP_WORKSPACE_SPEC_VERSION:-unknown}, expected ${CONTAINER_WORKSPACE_SPEC_VERSION}."
  [[ "${STAMP_IMAGE_CONTEXT_HASH:-}" == "${CONTEXT_HASH}" ]] || \
    die "Prepared container workspace context hash is stale. Expected ${CONTEXT_HASH}, got ${STAMP_IMAGE_CONTEXT_HASH:-unknown}."
  [[ "${STAMP_IMAGE_ID:-}" == "${current_image_id}" ]] || \
    die "Prepared container workspace was built against image ${STAMP_IMAGE_ID:-unknown}, expected ${current_image_id}."

  if ! validate_package_install_artifacts "${CONTAINER_WS}" "${PREPARED_CONTAINER_REQUIRED_PACKAGE}" "${PREPARED_CONTAINER_REQUIRED_PATHS[@]}"; then
    die "Prepared container install artifacts are missing or invalid inside the container workspace."
  fi

  info "Prepared container workspace spec: ${STAMP_WORKSPACE_SPEC_VERSION}"
  info "Prepared container workspace stamped at: ${STAMPED_AT:-unknown}"
  info "Verified prepared launch artifacts: ${PREPARED_CONTAINER_REQUIRED_PATHS[*]}"
}

BASE_IMAGE_REF="$(select_base_image || true)"
[[ -n "${BASE_IMAGE_REF}" ]] || die "No supported local base image found. Run reComputer run nvblox to download and load the OneDrive archive, or ensure $(acceptable_base_image_hint) already exists."
BASE_IMAGE_ID="$(docker_image_id "${BASE_IMAGE_REF}")"

ensure_nvidia_runtime "${BASE_IMAGE_REF}"

if (( FORCE_REBUILD )) || ! image_stamp_current; then
  build_derived_image
  write_image_stamp
else
  info "Derived image ${DERIVED_IMAGE_TAG} is current. Skipping rebuild."
fi

DERIVED_IMAGE_ID="$(docker_image_id "${DERIVED_IMAGE_TAG}")"
prepare_container_workspace
repair_managed_root_ownership "${MANAGED_ROOT}"
validate_prepared_container_workspace
info "Container preparation complete."
