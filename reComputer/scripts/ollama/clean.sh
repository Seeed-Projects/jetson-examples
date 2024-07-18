#!/bin/bash
BASE_PATH=/home/$USER/reComputer
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
# search local image
img_tag=$($JETSON_REPO_PATH/autotag -p local ollama)
# 检查返回值
if [ $? -eq 0 ]; then
    echo "Found Image successfully."
    sudo docker rmi $img_tag
else
    echo "[warn] Found Image failed with error code $?. skip delete Image."
fi
# 
# 4 build whl
read -p "Delete all data for ollama? (y/n): " choice
if [[ $choice == "y" || $choice == "Y" ]]; then
    echo "Delete=> $JETSON_REPO_PATH/data/models/ollama/"
    sudo rm -rf $JETSON_REPO_PATH/data/models/ollama/
    echo "Clean Data Done."
else
    echo "[warn] Skip Clean Data."
fi
