#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${NVBLOX_MODE:-all}"
START_ARGS=()

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|Yes|on|ON|On)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

case "${MODE}" in
  ""|all)
    ;;
  prepare|prepare-only)
    START_ARGS+=(--prepare-only)
    ;;
  run|run-only)
    START_ARGS+=(--run-only)
    ;;
  *)
    echo "Invalid NVBLOX_MODE='${MODE}'. Use all, prepare, or run." >&2
    exit 1
    ;;
esac

if is_truthy "${NVBLOX_FORCE_REBUILD:-0}"; then
  START_ARGS+=(--force-rebuild)
fi

if is_truthy "${NVBLOX_HEADLESS:-0}"; then
  START_ARGS+=(--headless)
fi

bash "${SCRIPT_DIR}/start_nvblox_demo.sh" "${START_ARGS[@]}"
