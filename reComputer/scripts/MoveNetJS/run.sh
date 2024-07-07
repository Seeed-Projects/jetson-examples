#!/bin/bash

# pull docker image

docker push feiticeir0/movenetjs:latest

docker run \
	--rm \
	-p 5000:5000 \
	feiticeir0/movenetjs:latest



