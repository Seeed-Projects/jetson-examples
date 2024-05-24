#!/bin/bash

BASE_PATH=/home/$USER/reComputer
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
cd $JETSON_REPO_PATH

# download llm model
./run.sh --workdir=/opt/text-generation-webui $(./autotag text-generation-webui) /bin/bash -c \
'python3 download-model.py --output=/data/models/text-generation-webui TheBloke/Llama-2-7b-Chat-GPTQ'

# run text-generation-webui
./run.sh $(./autotag text-generation-webui)