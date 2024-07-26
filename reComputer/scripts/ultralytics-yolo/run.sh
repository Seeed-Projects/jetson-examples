#!/bin/bash

docker pull yaohui1998/ultralytics-yolo:v2

docker run --rm -it \
    --privileged \
    --network host \
    -v /tmp/.X11-unix:/tmp/.X11-unix[@] \
    -v /dev/*:/dev/* \
    -v /etc/localtime:/etc/localtime:ro \
    --runtime nvidia \
    yaohui1998/ultralytics-yolo:v2