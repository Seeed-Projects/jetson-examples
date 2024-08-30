#!/bin/bash

source $(dirname "$(realpath "$0")")/../utils.sh
check_base_env "$(dirname "$(realpath "$0")")/config.yaml"

# make dirs
BASE_PATH=/home/$USER/reComputer
sudo mkdir -p $BASE_PATH/yolov10/weights
sudo mkdir -p $BASE_PATH/yolov10/run
echo "create workspace at $BASE_PATH/yolov10"

# download models
echo "download yolov10 models"
WEIGHTS_FILE=$BASE_PATH/yolov10/weights/yolov10s.pt
if [ ! -f $WEIGHTS_FILE ]; then
    sudo wget -P $BASE_PATH/yolov10/weights https://github.com/THU-MIG/yolov10/releases/download/v1.1/yolov10s.pt
else
    echo "Weights file already exists: $WEIGHTS_FILE"
fi

