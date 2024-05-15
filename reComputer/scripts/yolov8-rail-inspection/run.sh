#!/bin/bash

docker pull yaohui1998/bolt_inspection:1.0

if [ "$(docker ps -aq -f name=yolov8_rain_inspection)" ]; then
    echo "Found existing container named yolov8_rain_inspection. Executing Python script inside the container..."
    docker start yolov8_rain_inspection
    docker exec yolov8_rain_inspection python3 bolt_inspection.py
    docker cp yolov8_rain_inspection:/usr/src/ultralytics/Jetson-example/result/ ~/
else
    echo "No existing container named counter found. Pulling image and running container..."
    docker run -it --rm --network host \
    --ipc=host \
    --runtime=nvidia \
    -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
    -v /home:/home \
    -e DISPLAY=:0 \
    --privileged \
    --name yolov8_rain_inspection \
    --device=/dev/*:/dev/*  \
    yaohui1998/bolt_inspection:1.0
fi 