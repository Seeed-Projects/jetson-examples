#!/bin/bash

CONTAINER_NAME="gpt-oss"
IMAGE_NAME="chenduola6/got-oss-20b:jp6"
SERVER_CMD="cd /root/gpt-oss/llama.cpp && ./build/bin/llama-server -m /root/gpt-oss/gguf/gpt-oss-20b-Q4_K.gguf -ngl 20 -c 1024 --host 0.0.0.0 --port 8080"
GPU_FLAGS=()

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

ensure_image() {
    if "${DOCKER_CMD[@]}" pull "$IMAGE_NAME"; then
        return 0
    fi

    echo "Warning: failed to pull image from Docker Hub."
    if "${DOCKER_CMD[@]}" image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        echo "Found local image cache: $IMAGE_NAME"
        echo "Continue with local image."
        return 0
    fi

    echo "No local image cache found. Please check network and retry."
    exit 1
}

create_container() {
    "${DOCKER_CMD[@]}" run -d \
        --name "$CONTAINER_NAME" \
        "${GPU_FLAGS[@]}" \
        --network host \
        --ipc=host \
        "$IMAGE_NAME" \
        /bin/bash -lc "$SERVER_CMD"
}

probe_gpu_mode() {
    if "${DOCKER_CMD[@]}" run --rm --runtime nvidia --network host --ipc=host "$IMAGE_NAME" /bin/sh -lc "exit 0" >/dev/null 2>&1; then
        GPU_FLAGS=(--runtime nvidia)
        echo "Using GPU mode: --runtime nvidia"
        return 0
    fi

    if "${DOCKER_CMD[@]}" run --rm --gpus all --network host --ipc=host "$IMAGE_NAME" /bin/sh -lc "exit 0" >/dev/null 2>&1; then
        GPU_FLAGS=(--gpus all)
        echo "Using GPU mode: --gpus all"
        return 0
    fi

    echo "Failed to detect a working Docker GPU mode."
    echo "Tried: --runtime nvidia and --gpus all"
    echo "Please check Docker + NVIDIA Container Runtime on this device."
    exit 1
}

ensure_image
probe_gpu_mode

# Check if the container with the specified name already exists
if [ "$("${DOCKER_CMD[@]}" ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Container $CONTAINER_NAME is already running."
elif [ "$("${DOCKER_CMD[@]}" ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Container $CONTAINER_NAME already exists. Starting..."
    if ! "${DOCKER_CMD[@]}" start "$CONTAINER_NAME"; then
        echo "Failed to start existing container. Recreating with current runtime settings..."
        "${DOCKER_CMD[@]}" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        if ! create_container >/dev/null; then
            echo "Failed to create container."
            exit 1
        fi
    fi
else
    echo "Container $CONTAINER_NAME does not exist. Creating and starting..."
    if ! create_container >/dev/null; then
        echo "Failed to create container."
        exit 1
    fi
fi

if [ -z "$("${DOCKER_CMD[@]}" ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Container failed to reach running state."
    echo "Inspect logs with: ${DOCKER_CMD[*]} logs $CONTAINER_NAME"
    exit 1
fi

echo "GPT-OSS server should be available at: http://127.0.0.1:8080"
echo "Check models:"
echo "curl http://127.0.0.1:8080/v1/models"
echo "Follow server logs:"
echo "${DOCKER_CMD[*]} logs -f $CONTAINER_NAME"
