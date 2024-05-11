#!/bin/bash

docker pull yaohui1998/yolov8_counter

if [ "$(docker ps -aq -f name=counter)" ]; then
    echo "Found existing container named counter. Executing Python script inside the container..."
    docker start counter
    docker exec counter python3 yolo_counting.py
    docker cp counter:/usr/src/ultralytics/result/ ~/
else
    echo "No existing container named counter found. Pulling image and running container..."
    docker run -it -d --network host \
    --ipc=host \
    --runtime=nvidia \
    -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
    -v /home:/home \
    -e DISPLAY=:0 \
    --privileged \
    --name yolov8_counter \
    --device=/dev/*:/dev/*  \
    yaohui1998/yolov8_counter
    docker exec yolov8_counter python3 yolo_counting.py
    docker cp -r yolov8_counter:/usr/src/ultralytics/result/ ~/

fi