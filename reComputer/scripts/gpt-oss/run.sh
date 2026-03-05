#!/bin/bash

CONTAINER_NAME="gpt-oss"
IMAGE_NAME="chenduola6/got-oss-20b:jp6.2"
SERVER_CMD="cd /root/gpt-oss/llama.cpp && ./build/bin/llama-server -m /root/gpt-oss/gguf/gpt-oss-20b-Q4_K.gguf -ngl 20 -c 1024 --host 0.0.0.0 --port 8080"

# Prefer plain docker, fallback to sudo docker when user has no docker group permission
if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
else
    echo "Current user has no docker permission."
    echo "Please enter sudo password once for this run."
    if ! sudo -v; then
        echo "Failed to authenticate sudo. Exiting."
        exit 1
    fi
    # Keep sudo timestamp alive during long pulls/runs to avoid repeated prompts.
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill $SUDO_KEEPALIVE_PID >/dev/null 2>&1 || true' EXIT
    DOCKER_CMD=(sudo docker)
fi

# Pull the latest image
"${DOCKER_CMD[@]}" pull "$IMAGE_NAME"

# Check if the container with the specified name already exists
if [ "$("${DOCKER_CMD[@]}" ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Container $CONTAINER_NAME is already running."
elif [ "$("${DOCKER_CMD[@]}" ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Container $CONTAINER_NAME already exists. Starting..."
    "${DOCKER_CMD[@]}" start "$CONTAINER_NAME"
else
    echo "Container $CONTAINER_NAME does not exist. Creating and starting..."
    "${DOCKER_CMD[@]}" run -d \
        --name "$CONTAINER_NAME" \
        --gpus all \
        --network host \
        --ipc=host \
        "$IMAGE_NAME" \
        /bin/bash -lc "$SERVER_CMD"
fi

echo "GPT-OSS server should be available at: http://127.0.0.1:8080"
echo "Check models:"
echo "curl http://127.0.0.1:8080/v1/models"
echo "Follow server logs:"
echo "${DOCKER_CMD[*]} logs -f $CONTAINER_NAME"
