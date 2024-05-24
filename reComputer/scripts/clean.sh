#!/bin/bash

check_is_jetson_or_not() {
    model_file="/proc/device-tree/model"
    
    if [ -f "/proc/device-tree/model" ]; then
        model=$(tr -d '\0' < /proc/device-tree/model | tr '[:upper:]' '[:lower:]')
        if [[ $model =~ jetson|orin|nv|agx ]]; then
            echo "INFO: machine[$model] confirmed..."
        else
            echo "WARNING: machine[$model] maybe not support..."
            exit 1
        fi
    else
        echo "ERROR: machine[$model] not support this..."
        exit 1
    fi
}
check_is_jetson_or_not

echo "clean example：$1"
BASE_PATH=/home/$USER/reComputer
# TODO: 要一个二次确认
echo "----clean example start----"
cd $JETSON_REPO_PATH
script_dir=$(dirname "$0")
start_script=$script_dir/$1/clean.sh
if [ -f $start_script ]; then
    bash $start_script
else
    echo "ERROR: Example[$1]/clean.sh Not Found."
fi
echo "----clean example done----"
