#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${REBOT_CACHE_DIR:-${HOME}/.cache/jetson-examples/rebot-arm-teleop}"

JP6_URL="https://seeedstudio88-my.sharepoint.com/:u:/g/personal/youjiang_yu_seeedstudio88_onmicrosoft_com/IQDX-g96oIidTbT5ZXKKG144AWVQg-MRC_saM_m0LxNr7Nc?download=1"
JP72_URL="https://seeedstudio88-my.sharepoint.com/:u:/g/personal/youjiang_yu_seeedstudio88_onmicrosoft_com/IQDTev5stkImSqn8uhlp5H1FAYkBrlqzfz_-3-vybPvmwB8?download=1"

log() { printf '[rebot-arm-teleop] %s\n' "$*"; }
die() { printf '[rebot-arm-teleop][FAIL] %s\n' "$*" >&2; exit 1; }

normalize_variant() {
  case "${1,,}" in
    6|6.1|6.2|jp6|jetpack6|jetpack6.1|jetpack6.2)
      printf 'jp6\n'
      ;;
    7.2|jp7.2|jp72|jetpack7.2)
      printf 'jp72\n'
      ;;
    *)
      return 1
      ;;
  esac
}

detect_variant() {
  local package_version=""
  local l4t_version=""

  if [[ -n "${REBOT_JETPACK:-}" ]]; then
    normalize_variant "${REBOT_JETPACK}" || die "invalid REBOT_JETPACK='${REBOT_JETPACK}'; use jp6 or jp72"
    return
  fi

  if command -v dpkg-query >/dev/null 2>&1; then
    package_version="$(dpkg-query -W -f='${Version}' nvidia-jetpack 2>/dev/null || true)"
  fi
  if [[ "${package_version}" =~ ^6\.(1|2)([^0-9]|$) ]]; then
    printf 'jp6\n'
    return
  fi
  if [[ "${package_version}" =~ ^7\.2([^0-9]|$) ]]; then
    printf 'jp72\n'
    return
  fi

  if [[ -r /etc/nv_tegra_release ]]; then
    l4t_version="$(sed -n 's/^# R\([0-9][0-9]*\).*REVISION: \([0-9][0-9.]*\).*/\1.\2/p' /etc/nv_tegra_release | head -n 1)"
  elif command -v dpkg-query >/dev/null 2>&1; then
    l4t_version="$(dpkg-query -W -f='${Version}' nvidia-l4t-core 2>/dev/null | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9.]*\).*/\1/p' || true)"
  fi
  case "${l4t_version}" in
    36.4|36.4.*)
      printf 'jp6\n'
      ;;
    38.2|38.2.*)
      printf 'jp72\n'
      ;;
    *)
      die "supported systems are JetPack 6.1, 6.2, and 7.2 (detected nvidia-jetpack='${package_version:-unknown}', L4T='${l4t_version:-unknown}'); set REBOT_JETPACK only if detection is unavailable"
      ;;
  esac
}

docker_command() {
  if docker info >/dev/null 2>&1; then
    printf 'docker\n'
  elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    printf 'sudo docker\n'
  else
    die "Docker daemon is unavailable; install Docker and NVIDIA Container Toolkit first"
  fi
}

download_image() {
  local url="$1"
  local archive="$2"
  local cookie_jar="${archive}.cookies"

  command -v curl >/dev/null 2>&1 || die "curl is required"
  mkdir -p "$(dirname "${archive}")"
  touch "${cookie_jar}"

  log "downloading image (resumable): ${archive}"
  curl --location --fail --show-error \
    --retry 5 --retry-all-errors --connect-timeout 20 \
    --continue-at - --cookie-jar "${cookie_jar}" --cookie "${cookie_jar}" \
    --output "${archive}" "${url}"

  gzip -t "${archive}" || die "downloaded image archive is incomplete or corrupt: ${archive}"
}

VARIANT="$(detect_variant)"
case "${VARIANT}" in
  jp6)
    IMAGE_TAG="rebot-lerobot-teleop:latest"
    IMAGE_URL="${REBOT_JP6_IMAGE_URL:-${JP6_URL}}"
    ARCHIVE="${CACHE_DIR}/Jetpack6-rebot-lerobot-teleop.tar.gz"
    ;;
  jp72)
    IMAGE_TAG="rebot-lerobot-teleop-jp72:latest"
    IMAGE_URL="${REBOT_JP72_IMAGE_URL:-${JP72_URL}}"
    ARCHIVE="${CACHE_DIR}/rebot-lerobot-teleop-jp72.tar.gz"
    ;;
esac

read -r -a DOCKER <<< "$(docker_command)"
log "selected ${VARIANT}; Docker image ${IMAGE_TAG}"

if ! "${DOCKER[@]}" image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
  if [[ ! -f "${ARCHIVE}" ]] || ! gzip -t "${ARCHIVE}" 2>/dev/null; then
    download_image "${IMAGE_URL}" "${ARCHIVE}"
  else
    log "using cached image archive: ${ARCHIVE}"
  fi
  log "loading Docker image; this may take several minutes"
  gzip -dc "${ARCHIVE}" | "${DOCKER[@]}" load
  "${DOCKER[@]}" image inspect "${IMAGE_TAG}" >/dev/null 2>&1 \
    || die "archive loaded but expected image ${IMAGE_TAG} was not found"
fi

LAUNCHER="${SCRIPT_DIR}/variants/${VARIANT}/docker/start-teleop.sh"
[[ -f "${LAUNCHER}" ]] || die "missing launcher: ${LAUNCHER}"
if [[ "${REBOT_DRY_RUN:-0}" == "1" ]]; then
  log "dry run complete; launcher=${LAUNCHER}"
  exit 0
fi
log "starting the reBot Arm teleoperation session"
if [[ "${EUID}" -eq 0 ]]; then
  exec env IMAGE_TAG="${IMAGE_TAG}" bash "${LAUNCHER}"
fi

command -v sudo >/dev/null 2>&1 || die "root access is required to configure CAN and serial devices"
exec sudo --preserve-env=LEADER_PORT,FOLLOWER_PORT,BITRATE,RESTART_MS,TELEOP_FPS,TELEOP_DURATION,TELEOP_DISPLAY,TELEOP_DISPLAY_IP,TELEOP_DISPLAY_PORT,TELEOP_EXTRA_ARGS \
  env IMAGE_TAG="${IMAGE_TAG}" bash "${LAUNCHER}"
