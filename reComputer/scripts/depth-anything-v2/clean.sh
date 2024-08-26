#!/bin/bash

CONTAINER_NAME="depth-anything-v2"
IMAGE_NAME="yaohui1998/depthanything-v2-on-jetson-orin:latest"

sudo docker stop $CONTAINER_NAME
sudo docker rm $CONTAINER_NAME
sudo docker rmi $IMAGE_NAMEs