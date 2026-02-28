#!/bin/bash

CONTAINER_NAME="depth-anything-v3"
IMAGE_NAME="chenduola6/depth-anything-v3:jp6.2"

# Prefer plain docker, fallback to sudo docker when user has no docker group permission
if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
else
    echo "Current user has no docker permission."
    echo "Please enter sudo password once for this run."
    if ! sudo -v; then
        echo "Failed to authenticate sudo. Exiting."
        exit 1
    fi
    # Keep sudo timestamp alive during long pulls/runs to avoid repeated prompts.
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill $SUDO_KEEPALIVE_PID >/dev/null 2>&1 || true' EXIT
    DOCKER_CMD=(sudo docker)
fi

# Pull the latest image
"${DOCKER_CMD[@]}" pull $IMAGE_NAME

# Enable local X11 access for docker GUI apps
xhost +local:docker

# Use default display when DISPLAY is not set
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

# Check if the container with the specified name already exists
if [ "$("${DOCKER_CMD[@]}" ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Container $CONTAINER_NAME already exists. Starting..."
    "${DOCKER_CMD[@]}" start $CONTAINER_NAME
else
    echo "Container $CONTAINER_NAME does not exist. Creating and starting..."
    "${DOCKER_CMD[@]}" run -it \
        --name $CONTAINER_NAME \
        --gpus all \
        --network host \
        --ipc host \
        --privileged \
        -e DISPLAY=$DISPLAY \
        -e QT_X11_NO_MITSHM=1 \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev:/dev \
        -v /etc/localtime:/etc/localtime:ro \
        $IMAGE_NAME
fi

echo "To run USB camera inference inside container:"
echo "1) ${DOCKER_CMD[*]} exec -it $CONTAINER_NAME /bin/bash"
echo "2) cd workspace/ros2-depth-anything-v3-trt"
echo "3) USB_SIMPLE=1 ./run_camera_depth.sh"
