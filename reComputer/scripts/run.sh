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
if [ -d $JETSON_REPO_PATH ]; then
    echo "jetson-ai-lab existed."
else
    echo "jetson-ai-lab does not installed. start init..."
    cd $BASE_PATH/
    git clone --depth=1 https://github.com/dusty-nv/jetson-containers
    cd $JETSON_REPO_PATH
    sudo apt update; sudo apt install -y python3-pip
    pip3 install -r requirements.txt
fi
echo "----example start----"
cd $JETSON_REPO_PATH
case "$1" in
    "llava")
        ./run.sh $(./autotag llava) \
        python3 -m llava.serve.cli \
        --model-path liuhaotian/llava-v1.5-7b \
        --image-file /data/images/hoover.jpg
    ;;
    "llava-v1.5-7b")
        ./run.sh $(./autotag llava) \
        python3 -m llava.serve.cli \
        --model-path liuhaotian/llava-v1.5-7b \
        --image-file /data/images/hoover.jpg
    ;;
    "llava-v1.6-vicuna-7b")
        ./run.sh $(./autotag local_llm) \
        python3 -m local_llm --api=mlc \
        --model liuhaotian/llava-v1.6-vicuna-7b \
        --max-context-len 768 \
        --max-new-tokens 128
    ;;
    "Sheared-LLaMA-2.7B-ShareGPT")
        ./run.sh $(./autotag local_llm) \
        python3 -m local_llm.chat --api=mlc \
        --model princeton-nlp/Sheared-LLaMA-2.7B-ShareGPT
    ;;
    "text-generation-webui")
        # download llm model
        ./run.sh --workdir=/opt/text-generation-webui $(./autotag text-generation-webui) /bin/bash -c \
        'python3 download-model.py --output=/data/models/text-generation-webui TheBloke/Llama-2-7b-Chat-GPTQ'
        # run text-generation-webui
        ./run.sh $(./autotag text-generation-webui)
    ;;
    "stable-diffusion-webui")
        ./run.sh $(./autotag stable-diffusion-webui)
    ;;
    "nanoowl")
        ./run.sh $(./autotag nanoowl) bash -c "ls /dev/video* && cd examples/tree_demo && python3 tree_demo.py ../../data/owl_image_encoder_patch32.engine"
    ;;
    "whisper")
        ./run.sh $(./autotag whisper)
    ;;
    "nanodb")
        script_dir=$(dirname "$0")
        bash $script_dir/nanodb.sh
    ;;
    "live-llava")
        script_dir=$(dirname "$0")
        bash $script_dir/live-llava.sh
    ;;
    *)
        echo "Unknown example"
        # handle unknown
    ;;
esac
echo "----example done----"
