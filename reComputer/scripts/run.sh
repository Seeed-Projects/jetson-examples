#!/bin/bash
handle_error() {
    echo "An error occurred. Exiting..."
    exit 1
}
trap 'handle_error' ERR

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

echo "run example：$1"
BASE_PATH=/home/$USER/reComputer


cd $JETSON_REPO_PATH
script_dir=$(dirname "$0")

init_script=$script_dir/$1/init.sh
if [ -f $init_script ]; then
    echo "----example init----"
    bash $init_script
else
    echo "WARN: Example[$1] init.sh Not Found."
fi

start_script=$script_dir/$1/run.sh
if [ -f $start_script ]; then
    echo "----example start----"
    bash $start_script
else
    echo "ERROR: Example[$1] run.sh Not Found."
fi
echo "----example done----"
