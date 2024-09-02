#!/bin/bash


# check the runtime environment.
source $(dirname "$(realpath "$0")")/../utils.sh
check_base_env "$(dirname "$(realpath "$0")")/config.yaml"

BASE_PATH=/home/$USER/reComputer
mkdir -p $BASE_PATH/
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
BASE_JETSON_LAB_GIT="https://github.com/dusty-nv/jetson-containers"
if [ -d $JETSON_REPO_PATH ]; then
    echo "jetson-ai-lab existed."
else
    echo "jetson-ai-lab does not installed. start init..."
    cd $BASE_PATH/
    git clone --depth=1 $BASE_JETSON_LAB_GIT
    cd $JETSON_REPO_PATH
    bash install.sh
fi
