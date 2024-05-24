#!/bin/bash

BASE_PATH=/home/$USER/reComputer
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
cd $JETSON_REPO_PATH

./run.sh $(./autotag local_llm) \
python3 -m local_llm.chat --api=mlc \
--model princeton-nlp/Sheared-LLaMA-2.7B-ShareGPT