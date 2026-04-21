#!/bin/bash
set -euo pipefail

CONTAINER_NAME="${ROS1_JP6_CONTAINER_NAME:-ros1-jp6}"

ensure_docker_access() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker command not found."
        echo "Please install Docker first, then rerun this command."
        exit 1
    fi

    if docker info >/dev/null 2>&1; then
        return 0
    fi

    echo "Docker daemon is not available to the current user."
    echo "Please make sure Docker is running and your user can access /var/run/docker.sock."
    exit 1
}

ensure_docker_access

if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    docker stop "${CONTAINER_NAME}"
fi

if [ "$(docker ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    docker rm "${CONTAINER_NAME}"
    echo "Container ${CONTAINER_NAME} removed."
else
    echo "Container ${CONTAINER_NAME} does not exist."
fi

echo "Image cache and downloaded archive are kept locally."
