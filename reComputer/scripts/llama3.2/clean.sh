#!/bin/bash

IMAGE_NAME="youjiang9977/ollama:r35.3.1"

if [ "$(docker images -q "$IMAGE_NAME")" ]; then
    echo "Deleting $IMAGE_NAME..."
    docker rmi "$IMAGE_NAME"
    echo "Image $IMAGE_NAME has been successfully deleted."
else
    echo "No image named $IMAGE_NAME was found."
fi

