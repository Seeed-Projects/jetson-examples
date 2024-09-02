#!/bin/bash

CONTAINER_NAME="comfyui"
IMAGE_NAME="yaohui1998/comfyui"

# Pull the latest image
docker pull $IMAGE_NAME

cd /home/$USER/reComputer/
git clone https://github.com/comfyanonymous/ComfyUI.git


# Check if the container with the specified name already exists
if [ $(docker ps -a -q -f name=^/${CONTAINER_NAME}$) ]; then
    echo "Container $CONTAINER_NAME already exists. Starting and attaching..."
    docker start $CONTAINER_NAME
    docker exec -it $CONTAINER_NAME /bin/bash
else
    echo "Container $CONTAINER_NAME does not exist. Creating and starting..."
    docker run -it --rm \
        --name $CONTAINER_NAME \
        --privileged \
        --network host \
        -v /home/$USER/reComputer/ComfyUI:/usr/src/ComfyUI-Seeed \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/*:/dev/* \
        -v /etc/localtime:/etc/localtime:ro \
        --runtime nvidia \
        $IMAGE_NAME
fi
