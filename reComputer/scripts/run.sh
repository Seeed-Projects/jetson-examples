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

check_disk_space() {
    directory="$1"  # a directory
    required_space_gb="$2"  # how many GB we need
    
    # get disk of directory
    device=$(df -P "$directory" | awk 'NR==2 {print $1}')
    echo $device
    
    # get free space in KB
    free_space=$(df -P "$device" | awk 'NR==2 {print $4}')
    echo $free_space
    
    # change unit to GB
    free_space_gb=$(echo "scale=2; $free_space / 1024 / 1024" | bc)
    echo $free_space_gb
    
    # check and fast-fail
    if (( $(echo "$free_space_gb >= $required_space_gb" | bc -l) )); then
        echo "disk space ($1) enough, keep going."
    else
        echo "disk space ($1) not enough!! we need $2 GB!!"
        exit 1
    fi
}

echo "run example：$1"
BASE_PATH=/home/$USER/reComputer

echo "----example init----"
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

echo "----example start----"
cd $JETSON_REPO_PATH
script_dir=$(dirname "$0")
start_script=$script_dir/$1/run.sh
if [ -f $start_script ]; then
    bash $start_script
else
    echo "ERROR: Example[$1] Not Found."
fi
echo "----example done----"
