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

check_disk_space() {
    local example_name=$1
    local config_file="$script_dir/$example_name/config.yaml"
    
    if [ -f "$config_file" ]; then
        # Check if yq is installed
        if command -v yq &> /dev/null; then
            required_space=$(yq -r '.REQUIRED_DISK_SPACE' "$config_file" 2>/dev/null || echo "10")
        else
            # Default to 10GB if yq not available
            required_space=10
        fi
    else
        # Default requirement if no config
        required_space=10
    fi
    
    # Get available disk space in GB
    available_space=$(df -BG --output=avail / | tail -1 | sed 's/[^0-9]*//g')
    
    echo "Disk space check:"
    echo "  Required: ${required_space}GB"
    echo "  Available: ${available_space}GB"
    
    if [ "$available_space" -lt "$required_space" ]; then
        echo ""
        echo "ERROR: Insufficient disk space!"
        echo "This example requires at least ${required_space}GB of free disk space."
        echo "You only have ${available_space}GB available."
        echo ""
        echo "Please free up disk space and try again."
        exit 1
    else
        echo "  Status: ✓ OK"
    fi
}

check_is_jetson_or_not

echo "run example：$1"
BASE_PATH=/home/$USER/reComputer


script_dir=$(dirname "$0")

# Check disk space before proceeding
check_disk_space "$1"

cd $JETSON_REPO_PATH

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
