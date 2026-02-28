#!/bin/bash

CONTAINER_NAME="depth-anything-v3"
IMAGE_NAME="chenduola6/depth-anything-v3:jp6.2"

# Pull the latest image
docker pull $IMAGE_NAME

# Enable local X11 access for docker GUI apps
xhost +local:docker

# Use default display when DISPLAY is not set
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

# Check if the container with the specified name already exists
if [ "$(docker ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Container $CONTAINER_NAME already exists. Starting..."
    docker start $CONTAINER_NAME
else
    echo "Container $CONTAINER_NAME does not exist. Creating and starting..."
    docker run -it \
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
echo "1) docker exec -it $CONTAINER_NAME /bin/bash"
echo "2) cd workspace/ros2-depth-anything-v3-trt"
echo "3) USB_SIMPLE=1 ./run_camera_depth.sh"
