#!/bin/bash

MODELS_DIR=/home/$USER/models

# TODO: Check JetPack version to pull correct image tag

# pull docker image
docker push feiticeir0/parler_tts:r36.2.0

docker run \
	--rm \
	-p 7860:7860 \
	--runtime=nvidia \
	-v $(MODELS_DIR):/app \
	feiticeir0/parler_tts:r36.2.0
