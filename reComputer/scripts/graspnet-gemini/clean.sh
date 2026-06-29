#!/bin/bash
set -euo pipefail

CONTAINER_NAME="${GRASPNET_GEMINI_CONTAINER_NAME:-graspnet-gemini}"

ensure_docker_access() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker command not found."
        echo "Please install Docker first, then rerun this command."
        exit 1
    fi

    if docker info >/dev/null 2>&1; then
        return 0
    fi

    if id -nG "$USER" | grep -qw docker; then
        echo "Current user is already in docker group, but docker is still unavailable."
        echo "Please make sure Docker daemon is running, for example:"
        echo "sudo systemctl enable --now docker"
        exit 1
    fi

    echo "Current user has no docker permission."
    echo "You can run this manually:"
    echo "sudo usermod -aG docker $USER"
    exit 1
}

ensure_docker_access

if [[ -n "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]]; then
    docker stop "${CONTAINER_NAME}" >/dev/null
fi

if [[ -n "$(docker ps -a -q -f name=^/${CONTAINER_NAME}$)" ]]; then
    docker rm "${CONTAINER_NAME}" >/dev/null
    echo "Container ${CONTAINER_NAME} removed."
else
    echo "Container ${CONTAINER_NAME} does not exist."
fi

echo "Image and downloaded archive are kept locally for faster next startup."
