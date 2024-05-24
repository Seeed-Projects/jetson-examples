#!/bin/bash

BASE_PATH=/home/$USER/reComputer
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
cd $JETSON_REPO_PATH

./run.sh $(./autotag whisper)
