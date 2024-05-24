#!/bin/bash

BASE_PATH=/home/$USER/reComputer
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
cd $JETSON_REPO_PATH

./run.sh $(./autotag nanoowl) bash -c "ls /dev/video* && cd examples/tree_demo && python3 tree_demo.py ../../data/owl_image_encoder_patch32.engine"
