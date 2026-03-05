#!/bin/bash

CONTAINER_NAME="gpt-oss"
IMAGE_NAME="chenduola6/got-oss-20b:jp6"
MODEL_PATH="/root/gpt-oss/gguf/gpt-oss-20b-Q4_K.gguf"
HOST="0.0.0.0"
PORT="${LLAMA_PORT:-8080}"
NGL="${LLAMA_NGL:-20}"
CTX="${LLAMA_CTX:-1024}"
STARTUP_TIMEOUT="${LLAMA_STARTUP_TIMEOUT:-600}"
SERVER_CMD="cd /root/gpt-oss/llama.cpp && ./build/bin/llama-server -m ${MODEL_PATH} -ngl ${NGL} -c ${CTX} --host ${HOST} --port ${PORT}"
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
    echo "Container $CONTAINER_NAME already exists but is not running."
    echo "Recreating with current runtime settings..."
    "${DOCKER_CMD[@]}" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    if ! create_container >/dev/null; then
        echo "Failed to create container."
        exit 1
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

wait_for_server_ready() {
    local endpoint="http://127.0.0.1:${PORT}/v1/models"
    local elapsed=0
    local interval=5
    local raw_response=""
    local response_body=""
    local http_code="000"
    local last_code="000"
    local last_body=""

    if ! command -v curl >/dev/null 2>&1; then
        echo "curl not found, skip readiness probing."
        return 0
    fi

    echo "Waiting for GPT-OSS to be ready at ${endpoint} (timeout: ${STARTUP_TIMEOUT}s)..."
    while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
        if [ -z "$("${DOCKER_CMD[@]}" ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
            echo "Container exited before model became ready."
            echo "Recent logs:"
            "${DOCKER_CMD[@]}" logs --tail 80 "$CONTAINER_NAME"
            return 1
        fi

        raw_response="$(curl -s --max-time 3 -w "\n%{http_code}" "$endpoint" 2>/dev/null || true)"
        http_code="$(printf '%s' "$raw_response" | tail -n 1)"
        response_body="$(printf '%s' "$raw_response" | sed '$d')"

        last_code="$http_code"
        last_body="$response_body"

        # Ready when endpoint returns model list payload.
        if [ "$http_code" = "200" ] && echo "$response_body" | grep -q "\"data\""; then
            return 0
        fi

        # Typical warm-up response from llama-server while loading weights.
        if [ "$http_code" = "503" ] && echo "$response_body" | grep -q "Loading model"; then
            if [ $((elapsed % 30)) -eq 0 ]; then
                echo "Model is still loading... (${elapsed}s)"
            fi
            sleep "$interval"
            elapsed=$((elapsed + interval))
            continue
        fi

        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "Waiting model readiness... (${elapsed}s, http=${http_code})"
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo "Model is still not ready after ${STARTUP_TIMEOUT}s."
    echo "Last endpoint status: ${last_code}"
    if [ -n "$last_body" ]; then
        echo "Last endpoint response: $last_body"
    fi
    echo "Recent logs:"
    "${DOCKER_CMD[@]}" logs --tail 80 "$CONTAINER_NAME"
    echo "You can try lower memory settings:"
    echo "LLAMA_CTX=512 LLAMA_NGL=16 reComputer run gpt-oss"
    return 1
}

if ! wait_for_server_ready; then
    exit 1
fi

echo "GPT-OSS server is ready at: http://127.0.0.1:${PORT}"
echo "Check models:"
echo "curl http://127.0.0.1:${PORT}/v1/models"
echo "Follow server logs:"
echo "${DOCKER_CMD[*]} logs -f $CONTAINER_NAME"
