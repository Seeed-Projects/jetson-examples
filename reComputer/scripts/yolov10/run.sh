#!/bin/bash

sudo docker run -it --rm --net=host --runtime nvidia \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /home/$USER/reComputer/yolov10/weights:/opt/yolov10/weights \
    -v /home/$USER/reComputer/yolov10/runs:/opt/yolov10/runs \
    youjiang9977/yolov10-jetson:5.1.1
