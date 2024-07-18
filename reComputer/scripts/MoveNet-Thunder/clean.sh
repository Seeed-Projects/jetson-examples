#!/bin/bash

# get image
source ./getVersion.sh

# remove docker image
sudo docker rmi feiticeir0/movenet:tf2-${TAG_IMAGE}
