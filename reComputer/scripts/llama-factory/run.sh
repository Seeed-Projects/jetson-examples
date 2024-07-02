#!/bin/bash


DATA_PATH="/home/$USER/reComputer/jetson-containers/data"

sudo docker run -it --rm --network host --runtime nvidia \
    --volume $DATA_PATH:/data \
    --name llama-factory \
    youjiang9977/llama-factory:r35.4.1

