#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${1:-}" ]]; then
  export REBOT_JETPACK="${1}"
fi

exec bash "${SCRIPT_DIR}/start-teleop.sh"
