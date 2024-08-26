#!/bin/bash
CONTAINER_NAME="ultralytics-yolo"
IMAGE_NAME="yaohui1998/ultralytics-yolo:latest"

sudo docker stop $CONTAINER_NAME
sudo docker rm $CONTAINER_NAME
sudo docker rmi $IMAGE_NAME