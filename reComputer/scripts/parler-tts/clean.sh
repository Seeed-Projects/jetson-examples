#!/bin/bash

# get image
source ./getVersion.sh

# remove docker image
sudo docker rmi feiticeir0/parler-tts:${TAG_IMAGE}
