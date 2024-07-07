#!/bin/bash

# pull docker image

docker pull feiticeir0/movenet-thunder:tf2-r36.2.0

docker run \
	-e DISPLAY=$DISPLAY \
	--runtime=nvidia \
	--rm \
	--device /dev/video0 \
	-v /tmp/.X11-unix:/tmp/.X11-unix \
	feiticeir0/movenet-thunder:tf2-r36.2.0


