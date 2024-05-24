#!/bin/bash

BASE_PATH=/home/$USER/reComputer
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
cd $JETSON_REPO_PATH
# try stop old server
docker rm -f ollama
# start new server
./run.sh -d --name ollama $(./autotag ollama)
# run a client
./run.sh $(./autotag ollama) /bin/ollama run llama3
# clean new server
docker rm -f ollama
