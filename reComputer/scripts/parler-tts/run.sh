#!/bin/bash

MODELS_DIR=/home/$USER/models

# get L4T version
# it exports a variable IMAGE_TAG
source ./getVersion.sh

# pull docker image
echo "docker push feiticeir0/parler_tts:${IMAGE_TAG}"

docker run \
	--rm \
	-p 7860:7860 \
	--runtime=nvidia \
	-v $(MODELS_DIR):/app \
	feiticeir0/parler_tts:${IMAGE_TAG}
