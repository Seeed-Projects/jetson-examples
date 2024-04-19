#!/bin/bash

# try stop old server
docker rm -f ollama
# run Front-end
./run.sh $(./autotag ollama)
# user only can access with http://ip:11434