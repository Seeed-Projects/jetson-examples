#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${REBOT_CACHE_DIR:-${HOME}/.cache/jetson-examples/rebot-arm-teleop}"
DOCKER=(docker)
if ! docker info >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
  DOCKER=(sudo docker)
fi

for image in rebot-lerobot-teleop:latest rebot-lerobot-teleop-jp72:latest; do
  if "${DOCKER[@]}" image inspect "${image}" >/dev/null 2>&1; then
    "${DOCKER[@]}" image rm "${image}"
  fi
done

rm -rf "${CACHE_DIR}"
echo "Removed reBot Arm teleop images and cache: ${CACHE_DIR}"
