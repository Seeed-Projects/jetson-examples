#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

MANAGED_ROOT="${MANAGED_ROOT_DEFAULT}"
MODE_PREPARE=0
MODE_RUN=0

while (($#)); do
  case "$1" in
    --managed-root)
      shift
      MANAGED_ROOT="$1"
      ;;
    --prepare)
      MODE_PREPARE=1
      ;;
    --run)
      MODE_RUN=1
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

(( MODE_PREPARE || MODE_RUN )) || die "preflight.sh requires --prepare, --run, or both."

ensure_supported_user_context
if should_reexec_as_setup_user; then
  die "Do not invoke preflight.sh with sudo directly. Run reComputer run nvblox instead."
fi

guard_managed_root_path "${MANAGED_ROOT}"
if (( MODE_PREPARE )); then
  bootstrap_managed_root "${MANAGED_ROOT}"
else
  require_bootstrapped_managed_root "${MANAGED_ROOT}"
fi

assert_command sudo
assert_command git
assert_command bash
assert_supported_platform
check_apt_locks
ensure_docker_access

if (( MODE_PREPARE )); then
  warn_on_unreachable_endpoints "https://github.com" "https://packages.ros.org" "https://raw.githubusercontent.com/ros/rosdistro/master/ros.key"
  if ! base_image="$(select_base_image)"; then
    die "No supported local base image found. Run reComputer run nvblox to download and load the OneDrive archive, or ensure $(acceptable_base_image_hint) already exists."
  fi
  info "Selected base image: ${base_image}"
fi

if (( MODE_RUN )); then
  gemini2_state="$(gemini2_device_state)"
  log_gemini2_device_state "Gemini2 device state during preflight"

  case "${gemini2_state}" in
    ready)
      ;;
    usb_missing)
      die "Gemini2 is not connected. Current device state: usb_missing."
      ;;
    usb_present_no_video)
      warn "Gemini2 USB device is present, but no /dev/video nodes were found. Attempting one automatic recovery."
      if ! recover_gemini2_device "run preflight" 1 1 1; then
        gemini2_state="$(gemini2_device_state)"
        die "Gemini2 USB device is present, but video nodes were not recovered. Current device state: ${gemini2_state}. Reconnect the camera if this persists."
      fi
      ;;
    *)
      die "Unexpected Gemini2 device state during preflight: ${gemini2_state}"
      ;;
  esac

  if (( ! MODE_PREPARE )) && ! docker_cmd image inspect "${DERIVED_IMAGE_TAG}" >/dev/null 2>&1; then
    die "Derived image ${DERIVED_IMAGE_TAG} does not exist. Run with --prepare-only or the default mode first."
  fi
fi

info "Preflight checks passed."
