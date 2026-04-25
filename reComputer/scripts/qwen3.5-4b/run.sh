#!/bin/bash
set -euo pipefail

CONTAINER_NAME="qwen3.5-4b"
IMAGE_NAME="${QWEN35_IMAGE_NAME:-llama-jetson}"
IMAGE_ARCHIVE_URL="${QWEN35_IMAGE_ARCHIVE_URL:-https://seeedstudio88-my.sharepoint.com/personal/youjiang_yu_seeedstudio88_onmicrosoft_com/_layouts/15/download.aspx?share=IQBA2papRoneTrRhf5DQ_dOnAV3EvVgvJ3LKb1q8qltMlSM}"
MODEL_URL="${QWEN35_MODEL_URL:-https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf}"
MODELS_DIR="${QWEN35_MODELS_DIR:-$HOME/models}"
MODEL_FILE="${QWEN35_MODEL_FILE:-$MODELS_DIR/Qwen3.5-4B-Q4_K_M.gguf}"
HOST_PORT="${QWEN35_PORT:-8080}"
CONTAINER_PORT=8080
STARTUP_TIMEOUT="${QWEN35_STARTUP_TIMEOUT:-600}"
GPU_FLAGS=()
LIB_MOUNTS=()

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
            echo "reComputer run qwen3.5-4b"
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
    if "${DOCKER_CMD[@]}" image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        echo "Docker image already exists locally: $IMAGE_NAME"
        return 0
    fi

    local archive_path
    archive_path="$(mktemp /tmp/qwen3.5-4b-image.XXXXXX.tar.gz)"

    echo "Downloading Docker image archive..."
    aria2c \
        --continue=true \
        --max-connection-per-server=8 \
        --split=8 \
        --min-split-size=10M \
        --retry-wait=5 \
        --max-tries=0 \
        --dir="$(dirname "$archive_path")" \
        --out="$(basename "$archive_path")" \
        "$IMAGE_ARCHIVE_URL"

    echo "Importing Docker image..."
    "${DOCKER_CMD[@]}" load -i "$archive_path"
    rm -f "$archive_path"
}

ensure_model() {
    mkdir -p "$MODELS_DIR"
    if [ -f "$MODEL_FILE" ]; then
        echo "Model already exists locally: $MODEL_FILE"
        return 0
    fi

    echo "Downloading model..."
    aria2c \
        --continue=true \
        --max-connection-per-server=8 \
        --split=8 \
        --min-split-size=10M \
        --retry-wait=5 \
        --max-tries=0 \
        --dir="$MODELS_DIR" \
        --out="$(basename "$MODEL_FILE")" \
        "$MODEL_URL"
}

select_gpu_layers() {
    local total_mem_mb
    total_mem_mb="$(free -m | awk '/^Mem:/{print $2}')"

    if [ "$total_mem_mb" -ge 60000 ]; then
        echo 99
    elif [ "$total_mem_mb" -ge 14000 ]; then
        echo 80
    elif [ "$total_mem_mb" -ge 7000 ]; then
        echo 40
    else
        echo 20
    fi
}

probe_gpu_mode() {
    if "${DOCKER_CMD[@]}" run --rm --runtime nvidia "$IMAGE_NAME" --help >/dev/null 2>&1; then
        GPU_FLAGS=(--runtime nvidia)
        echo "Using GPU mode: --runtime nvidia"
        return 0
    fi

    if "${DOCKER_CMD[@]}" run --rm --gpus all "$IMAGE_NAME" --help >/dev/null 2>&1; then
        GPU_FLAGS=(--gpus all)
        echo "Using GPU mode: --gpus all"
        return 0
    fi

    echo "Failed to detect a working Docker GPU mode."
    echo "Tried: --runtime nvidia and --gpus all"
    echo "Please check Docker + NVIDIA Container Runtime on this device."
    exit 1
}

collect_library_mounts() {
    local candidate
    local candidates=(
        "/usr/local/cuda/lib64:/usr/local/cuda/lib64:ro"
        "/usr/lib/aarch64-linux-gnu/nvidia:/usr/lib/aarch64-linux-gnu/nvidia:ro"
        "/usr/lib/aarch64-linux-gnu/libcuda.so.1:/usr/lib/aarch64-linux-gnu/libcuda.so.1:ro"
    )

    for candidate in "${candidates[@]}"; do
        if [ -e "${candidate%%:*}" ]; then
            LIB_MOUNTS+=(-v "$candidate")
        fi
    done
}

wait_for_server_ready() {
    local endpoint="http://127.0.0.1:${HOST_PORT}/v1/models"
    local elapsed=0
    local interval=5
    local raw_response=""
    local response_body=""
    local http_code="000"

    if ! command -v curl >/dev/null 2>&1; then
        echo "curl not found, skip readiness probing."
        return 0
    fi

    echo "Waiting for Qwen server to be ready at ${endpoint} (timeout: ${STARTUP_TIMEOUT}s)..."
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

        if [ "$http_code" = "200" ] && echo "$response_body" | grep -q "\"data\""; then
            return 0
        fi

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
    echo "Recent logs:"
    "${DOCKER_CMD[@]}" logs --tail 80 "$CONTAINER_NAME"
    return 1
}

ensure_image
ensure_model
probe_gpu_mode
collect_library_mounts

GPU_LAYERS="${QWEN35_GPU_LAYERS:-$(select_gpu_layers)}"
echo "Using --n-gpu-layers ${GPU_LAYERS}"

if [ "$("${DOCKER_CMD[@]}" ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Container $CONTAINER_NAME is already running."
elif [ "$("${DOCKER_CMD[@]}" ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Container $CONTAINER_NAME already exists but is not running."
    echo "Recreating with current settings..."
    "${DOCKER_CMD[@]}" rm -f "$CONTAINER_NAME" >/dev/null
    "${DOCKER_CMD[@]}" run -d \
        --name "$CONTAINER_NAME" \
        "${GPU_FLAGS[@]}" \
        -p "${HOST_PORT}:${CONTAINER_PORT}" \
        -v "$MODELS_DIR":/models \
        "${LIB_MOUNTS[@]}" \
        -e LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/aarch64-linux-gnu/nvidia:/usr/lib/aarch64-linux-gnu:/usr/local/lib/llama \
        "$IMAGE_NAME" \
        --model "/models/$(basename "$MODEL_FILE")" \
        --ctx-size "${QWEN35_CTX_SIZE:-8192}" \
        --host 0.0.0.0 \
        --port "${CONTAINER_PORT}" \
        --n-gpu-layers "${GPU_LAYERS}" >/dev/null
else
    echo "Creating and starting container $CONTAINER_NAME..."
    "${DOCKER_CMD[@]}" run -d \
        --name "$CONTAINER_NAME" \
        "${GPU_FLAGS[@]}" \
        -p "${HOST_PORT}:${CONTAINER_PORT}" \
        -v "$MODELS_DIR":/models \
        "${LIB_MOUNTS[@]}" \
        -e LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/aarch64-linux-gnu/nvidia:/usr/lib/aarch64-linux-gnu:/usr/local/lib/llama \
        "$IMAGE_NAME" \
        --model "/models/$(basename "$MODEL_FILE")" \
        --ctx-size "${QWEN35_CTX_SIZE:-8192}" \
        --host 0.0.0.0 \
        --port "${CONTAINER_PORT}" \
        --n-gpu-layers "${GPU_LAYERS}" >/dev/null
fi

if ! wait_for_server_ready; then
    exit 1
fi

echo "Qwen3.5-4B server is ready at: http://127.0.0.1:${HOST_PORT}"
echo "Check models:"
echo "curl http://127.0.0.1:${HOST_PORT}/v1/models"
echo "Chat API example:"
echo "curl http://127.0.0.1:${HOST_PORT}/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'"
echo "Follow server logs:"
echo "${DOCKER_CMD[*]} logs -f $CONTAINER_NAME"
