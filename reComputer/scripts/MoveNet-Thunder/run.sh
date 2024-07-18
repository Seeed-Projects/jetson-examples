#!/bin/bash

# get L4T version
# it exports a variable IMAGE_TAG
source ./getVersion.sh

# pull docker image
docker pull feiticeir0/movenet-thunder:tf2-${IMAGE_TAG}

docker run \
	-e DISPLAY=$DISPLAY \
	--runtime=nvidia \
	--rm \
	--device /dev/video0 \
	-v /tmp/.X11-unix:/tmp/.X11-unix \
	feiticeir0/movenet-thunder:tf2-${IMAGE_TAG}


