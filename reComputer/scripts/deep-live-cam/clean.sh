#!/bin/bash

CONTAINER_NAME="deep-live-cam"
IMAGE_NAME="yaohui1998/deep-live-cam:1.0"

sudo docker stop $CONTAINER_NAME
sudo docker rm $CONTAINER_NAME
sudo docker rmi $IMAGE_NAMEs
sudo rm -r ~/images