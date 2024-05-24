#!/bin/bash

BASE_PATH=/home/$USER/reComputer
mkdir -p $BASE_PATH/
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
BASE_JETSON_LAB_GIT="https://github.com/dusty-nv/jetson-containers/tree/d1573a3e8d7ba3fef36ebb23a7391e60eaf64db7"
if [ -d $JETSON_REPO_PATH ]; then
    echo "jetson-ai-lab existed."
else
    echo "jetson-ai-lab does not installed. start init..."
    cd $BASE_PATH/
    git clone --depth=1 $BASE_JETSON_LAB_GIT
    cd $JETSON_REPO_PATH
    sudo apt update; sudo apt install -y python3-pip
    pip3 install -r requirements.txt
fi
