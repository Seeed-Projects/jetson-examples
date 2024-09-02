#!/bin/bash

CONTAINER_NAME="depth-anything"
IMAGE_NAME="yaohui1998/depthanything-on-jetson-orin:latest"

sudo docker stop $CONTAINER_NAME
sudo docker rm $CONTAINER_NAME
sudo docker rmi $IMAGE_NAMEs
