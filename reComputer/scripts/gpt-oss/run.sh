#!/bin/bash

CONTAINER_NAME="gpt-oss"
IMAGE_NAME="chenduola6/got-oss-20b:jp6"
SERVER_CMD="cd /root/gpt-oss/llama.cpp && ./build/bin/llama-server -m /root/gpt-oss/gguf/gpt-oss-20b-Q4_K.gguf -ngl 20 -c 1024 --host 0.0.0.0 --port 8080"

ensure_docker_access() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker command not found."
        echo "Please install Docker first, then rerun this command."
        exit 1
    fi

    if docker info >/dev/null 2>&1; then
        return 0
    fi

    if id -nG "$USER" | grep -qw docker; then
        echo "Current user is already in docker group, but docker is still unavailable."
        echo "Please make sure Docker daemon is running, for example:"
        echo "sudo systemctl enable --now docker"
        exit 1
    fi

    echo "Current user has no docker permission."
    read -r -p "Add current user ($USER) to docker group now? (y/n): " choice
    case "$choice" in
        y|Y)
            if ! sudo -v; then
                echo "Failed to authenticate sudo. Exiting."
                exit 1
            fi
            if ! getent group docker >/dev/null 2>&1; then
                sudo groupadd docker
            fi
            sudo usermod -aG docker "$USER"
            echo "Added $USER to docker group."
            echo "Please log out and log back in (or reboot), then rerun:"
            echo "reComputer run gpt-oss"
            exit 1
            ;;
        *)
            echo "Skipped docker group setup."
            echo "You can run this manually:"
            echo "sudo usermod -aG docker $USER"
            exit 1
            ;;
    esac
}

ensure_docker_access
DOCKER_CMD=(docker)

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
