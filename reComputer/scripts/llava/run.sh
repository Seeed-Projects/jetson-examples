#!/bin/bash

BASE_PATH=/home/$USER/reComputer
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
cd $JETSON_REPO_PATH

./run.sh $(./autotag llava) \
python3 -m llava.serve.cli \
--model-path liuhaotian/llava-v1.5-7b \
--image-file /data/images/hoover.jpg