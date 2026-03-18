#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

MODE_PREPARE=1
MODE_RUN=1
FORCE_REBUILD=0
HEADLESS=0
MANAGED_ROOT="${MANAGED_ROOT:-${MANAGED_ROOT_DEFAULT}}"
ORIGINAL_ARGS=("$@")

ensure_base_image() {
  local base_image=""
  local share_url=""
  local archive_name=""
  local cache_dir=""
  local archive_path=""

  assert_command python3
  ensure_docker_access

  base_image="$(select_base_image || true)"
  if [[ -n "${base_image}" ]]; then
    info "Base image already present: ${base_image}. Skipping OneDrive download and docker load."
    return 0
  fi

  install_packages_if_missing python3-requests

  share_url="$(resolve_nvblox_image_share_url)"
  archive_name="$(resolve_nvblox_image_archive_name)"
  cache_dir="$(resolve_nvblox_image_cache_dir)"
  archive_path="$(resolve_nvblox_image_archive_path "${cache_dir}" "${archive_name}")"

  mkdir -p "${cache_dir}"
  cleanup_nvblox_partial_downloads "${cache_dir}"

  info "Ensuring NVBlox base image archive at ${archive_path}"
  python3 "${SCRIPT_DIR}/onedrive_downloader.py" "${share_url}" "${archive_name}" --download-dir "${cache_dir}"
  [[ -f "${archive_path}" ]] || die "Base image archive was not created at ${archive_path}."

  info "Loading Docker image archive ${archive_path}"
  docker_cmd load -i "${archive_path}"

  base_image="$(select_base_image || true)"
  [[ -n "${base_image}" ]] || die "docker load finished, but no supported local base image was detected. Expected $(acceptable_base_image_hint)."
  info "Base image ready: ${base_image}"
}

usage() {
  cat <<'EOF'
Usage:
  ./start_nvblox_demo.sh
  ./start_nvblox_demo.sh --prepare-only
  ./start_nvblox_demo.sh --run-only
  ./start_nvblox_demo.sh --force-rebuild
  ./start_nvblox_demo.sh --headless

Environment:
  MANAGED_ROOT                Override managed workspace root. Default: ~/nvblox_demo
  NVBLOX_IMAGE_SHARE_URL      Override the default OneDrive share link
  NVBLOX_IMAGE_ARCHIVE_NAME   Override the downloaded archive filename
  NVBLOX_IMAGE_CACHE_DIR      Override the Docker archive cache directory
EOF
}

while (($#)); do
  case "$1" in
    --prepare-only)
      MODE_PREPARE=1
      MODE_RUN=0
      ;;
    --run-only)
      MODE_PREPARE=0
      MODE_RUN=1
      ;;
    --force-rebuild)
      FORCE_REBUILD=1
      ;;
    --headless)
      HEADLESS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

if (( MODE_PREPARE == 0 && MODE_RUN == 0 )); then
  die "Nothing to do. Use the default mode, --prepare-only, or --run-only."
fi

ensure_supported_user_context
if should_reexec_as_setup_user; then
  printf '[reComputer][nvblox] Re-entering as %s.\n' "${SETUP_USER_NAME}" >&2
  reexec_as_setup_user "${SCRIPT_DIR}/start_nvblox_demo.sh" "${ORIGINAL_ARGS[@]}"
fi

guard_managed_root_path "${MANAGED_ROOT}"
if (( MODE_PREPARE )); then
  repair_managed_root_ownership "${MANAGED_ROOT}"
  bootstrap_managed_root "${MANAGED_ROOT}"
else
  require_bootstrapped_managed_root "${MANAGED_ROOT}"
fi

mkdir -p "${MANAGED_ROOT}/logs"
RUN_LOG="${MANAGED_ROOT}/logs/run-$(date '+%Y%m%d-%H%M%S').log"
exec > >(tee -a "${RUN_LOG}") 2>&1

info "Managed root: ${MANAGED_ROOT}"
info "Run log: ${RUN_LOG}"
info "Mode: prepare=${MODE_PREPARE} run=${MODE_RUN} force_rebuild=${FORCE_REBUILD} headless=${HEADLESS}"

if (( MODE_PREPARE )); then
  ensure_base_image
fi

PREFLIGHT_ARGS=(--managed-root "${MANAGED_ROOT}")
if (( MODE_PREPARE )); then
  PREFLIGHT_ARGS+=(--prepare)
fi
if (( MODE_RUN )); then
  PREFLIGHT_ARGS+=(--run)
fi
bash "${SCRIPT_DIR}/scripts/preflight.sh" "${PREFLIGHT_ARGS[@]}"

if (( MODE_PREPARE )); then
  PREPARE_ARGS=(--managed-root "${MANAGED_ROOT}")
  if (( FORCE_REBUILD )); then
    PREPARE_ARGS+=(--force-rebuild)
  fi

  bash "${SCRIPT_DIR}/scripts/prepare_host.sh" "${PREPARE_ARGS[@]}"
  bash "${SCRIPT_DIR}/scripts/prepare_container.sh" "${PREPARE_ARGS[@]}"
fi

if (( MODE_RUN )); then
  RUN_ARGS=(--managed-root "${MANAGED_ROOT}")
  if (( HEADLESS )); then
    RUN_ARGS+=(--headless)
  fi

  bash "${SCRIPT_DIR}/scripts/run_demo.sh" "${RUN_ARGS[@]}"
fi

info "Done."
