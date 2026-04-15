#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

MANAGED_ROOT="${MANAGED_ROOT:-${MANAGED_ROOT_DEFAULT}}"
CACHE_DIR="$(resolve_nvblox_image_cache_dir)"

maybe_enable_docker_access() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker command not found. Skipping container and image cleanup."
    return 1
  fi

  if docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=()
    return 0
  fi

  if sudo docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=(sudo)
    return 0
  fi

  warn "Cannot access the Docker daemon. Skipping container and image cleanup."
  return 1
}

remove_managed_root() {
  local sentinel_path="${MANAGED_ROOT}/${MANAGED_SENTINEL_NAME}"

  if [[ ! -e "${MANAGED_ROOT}" ]]; then
    info "Managed root ${MANAGED_ROOT} does not exist."
    return 0
  fi

  if [[ ! -f "${sentinel_path}" ]]; then
    die "Managed root ${MANAGED_ROOT} exists but is not owned by the NVBlox example. Refusing to remove it."
  fi

  run_sudo rm -rf "${MANAGED_ROOT}"
  info "Removed managed root ${MANAGED_ROOT}"
}

ensure_supported_user_context
if should_reexec_as_setup_user; then
  printf '[reComputer][nvblox] Re-entering as %s.\n' "${SETUP_USER_NAME}" >&2
  reexec_as_setup_user "${SCRIPT_DIR}/clean.sh"
fi

cleanup_residual_gemini2_processes "nvblox clean" || true

if maybe_enable_docker_access; then
  if docker_cmd ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME_DEFAULT}"; then
    info "Removing container ${CONTAINER_NAME_DEFAULT}"
    docker_cmd rm -f "${CONTAINER_NAME_DEFAULT}" >/dev/null
  else
    info "Container ${CONTAINER_NAME_DEFAULT} does not exist."
  fi

  if docker_cmd image inspect "${DERIVED_IMAGE_TAG}" >/dev/null 2>&1; then
    info "Removing derived image ${DERIVED_IMAGE_TAG}"
    docker_cmd image rm -f "${DERIVED_IMAGE_TAG}" >/dev/null
  else
    info "Derived image ${DERIVED_IMAGE_TAG} does not exist."
  fi
fi

remove_managed_root
cleanup_nvblox_partial_downloads "${CACHE_DIR}"

info "NVBlox clean complete. Cached base archive is kept in ${CACHE_DIR}"
