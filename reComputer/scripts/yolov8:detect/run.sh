#!/bin/bash

sudo docker run -it --rm --network host --ipc=host --runtime=nvidia --device=/dev/video0  youjiang9977/yolov8:detect
