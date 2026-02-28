#!/bin/bash

CONTAINER_NAME="depth-anything-v3"

if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    docker stop $CONTAINER_NAME
fi

if [ "$(docker ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    docker rm $CONTAINER_NAME
    echo "Container $CONTAINER_NAME removed."
else
    echo "Container $CONTAINER_NAME does not exist."
fi
