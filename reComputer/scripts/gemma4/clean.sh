#!/bin/bash
set -euo pipefail

CONTAINER_NAME="${GEMMA4_CONTAINER_NAME:-gemma4-jetson}"

ensure_docker_access() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker command not found."
        exit 1
    fi

    if docker info >/dev/null 2>&1; then
        DOCKER_CMD=(docker)
        return 0
    fi

    if [[ "${EUID}" -ne 0 ]] && command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
        DOCKER_CMD=(sudo docker)
        return 0
    fi

    echo "Docker is not usable. Check the docker service and current user permissions."
    exit 1
}

ensure_docker_access

if [[ -n "$("${DOCKER_CMD[@]}" ps -q -f name="^/${CONTAINER_NAME}$")" ]]; then
    "${DOCKER_CMD[@]}" stop "${CONTAINER_NAME}" >/dev/null
fi

if [[ -n "$("${DOCKER_CMD[@]}" ps -a -q -f name="^/${CONTAINER_NAME}$")" ]]; then
    "${DOCKER_CMD[@]}" rm "${CONTAINER_NAME}" >/dev/null
    echo "Container ${CONTAINER_NAME} removed."
else
    echo "Container ${CONTAINER_NAME} does not exist."
fi

echo "Docker image, image archive, and model cache are kept locally for faster next startup."
