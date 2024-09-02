#!/bin/bash

BASE_PATH=/home/$USER/reComputer
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
cd $JETSON_REPO_PATH

# try stop old server
docker rm -f ollama
# run Front-end
./run.sh $(./autotag ollama)
# user only can access with http://ip:11434
