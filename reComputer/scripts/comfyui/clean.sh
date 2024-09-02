#!/bin/bash
CONTAINER_NAME="comfyui"
IMAGE_NAME="yaohui1998/comfyui"

sudo docker stop $CONTAINER_NAME
sudo docker rm $CONTAINER_NAME
sudo docker rmi $IMAGE_NAME

sudo rm -r /home/$USER/reComputer/ComfyUI
