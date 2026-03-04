#!/bin/bash

CONTAINER_NAME="depth_anything_v3"

# Prefer plain docker, fallback to sudo docker when user has no docker group permission
if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
else
    DOCKER_CMD=(sudo docker)
fi

if [ "$("${DOCKER_CMD[@]}" ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    "${DOCKER_CMD[@]}" stop $CONTAINER_NAME
fi

if [ "$("${DOCKER_CMD[@]}" ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    "${DOCKER_CMD[@]}" rm $CONTAINER_NAME
    echo "Container $CONTAINER_NAME removed."
else
    echo "Container $CONTAINER_NAME does not exist."
fi
