#!/bin/bash

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
L4T_VERSION_FILE="/etc/nv_tegra_release"
OLLAMA_CONTAINER="ollama"
WEBUI_CONTAINER="live-vlm-webui"
OLLAMA_PORT=11434
WEBUI_PORT=8090
STARTUP_TIMEOUT=120
OLLAMA_START_PERIOD=60
GPU_FLAGS=()

declare -A MODEL_MAP
MODEL_MAP=(
    [1]="gemma3:4b"
    [2]="gemma3:12b"
    [3]="llava:7b"
    [4]="llama3.2-vision:11b"
    [5]="moondream:latest"
    [6]="gemma3:4b"
    [7]="nomic-embed-text:latest"
)

detect_platform_and_image() {
    if [ -f "$L4T_VERSION_FILE" ]; then
        L4T_RELEASE=$(head -n 1 "$L4T_VERSION_FILE" | grep -o 'R[0-9]*' | head -1 | cut -dR -f2)
        L4T_REVISION=$(head -n 1 "$L4T_VERSION_FILE" | grep -o 'REVISION: [0-9]*' | awk '{print $2}')
        L4T_VERSION="$L4T_RELEASE.$L4T_REVISION"
    else
        L4T_VERSION=$(dpkg-query --showformat='${Version}' --show nvidia-l4t-core 2>/dev/null \
            | grep -o '[0-9]*\.[0-9]*' | head -1)
    fi

    echo "Detected L4T version: $L4T_VERSION"

    case "$L4T_VERSION" in
        36.*) IMAGE_TAG="latest-jetson-orin" ;;
        38.*) IMAGE_TAG="latest-jetson-thor" ;;
        *)   echo "${YELLOW}Unknown L4T version $L4T_VERSION, defaulting to jetson-orin image.${RESET}"
             IMAGE_TAG="latest-jetson-orin" ;;
    esac
    echo "Using image tag: $IMAGE_TAG"
}

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
        echo "Please make sure Docker daemon is running."
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
            echo "Please log out and log back in, then rerun: reComputer run live-vlm-webui"
            exit 1
            ;;
        *)
            echo "Skipped docker group setup."
            echo "You can run this manually: sudo usermod -aG docker $USER"
            exit 1
            ;;
    esac
}

probe_gpu_mode() {
    local test_image="nvidia/cuda:12.6.0-base-ubuntu22.04"
    if docker run --rm --runtime nvidia --network host "$test_image" /bin/sh -lc "exit 0" >/dev/null 2>&1; then
        GPU_FLAGS=(--runtime nvidia)
        echo "GPU mode: --runtime nvidia"
        return 0
    fi
    if docker run --rm --gpus all --network host "$test_image" /bin/sh -lc "exit 0" >/dev/null 2>&1; then
        GPU_FLAGS=(--gpus all)
        echo "GPU mode: --gpus all"
        return 0
    fi
    echo "${RED}Failed to detect a working Docker GPU mode.${RESET}"
    echo "Please check Docker + NVIDIA Container Runtime on this device."
    exit 1
}

pull_image() {
    local image="$1"
    echo "Pulling image: $image"
    if ! docker pull "$image"; then
        if docker image inspect "$image" >/dev/null 2>&1; then
            echo "Using local image cache: $image"
            return 0
        fi
        echo "${RED}Failed to pull image $image.${RESET}"
        return 1
    fi
}

smart_ollama_check() {
    if docker ps --format '{{.Names}}' | grep -q "^${OLLAMA_CONTAINER}$"; then
        echo "${GREEN}Ollama container is already running.${RESET}"
        OLLAMA_STATE="running"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${OLLAMA_CONTAINER}$"; then
        echo "${YELLOW}Ollama container exists but is stopped.${RESET}"
        read -r -p "Start the existing Ollama container? (y/n): " choice
        case "$choice" in
            y|Y) docker start "$OLLAMA_CONTAINER"; OLLAMA_STATE="restarted" ;;
            *)   echo "Skipping Ollama start. Will not be able to pull/run models."
                 OLLAMA_STATE="skipped"
                 return 0
                 ;;
        esac
    else
        echo "Ollama container not found. Creating new one..."
        OLLAMA_STATE="new"
    fi
}

smart_webui_check() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${WEBUI_CONTAINER}$"; then
        echo "${YELLOW}WebUI container already exists.${RESET}"
        read -r -p "Remove and recreate the WebUI container? (y/n): " choice
        case "$choice" in
            y|Y)
                docker rm -f "$WEBUI_CONTAINER" >/dev/null 2>&1
                echo "Existing WebUI container removed."
                WEBUI_STATE="recreate"
                ;;
            *)
                echo "Skipping WebUI container creation."
                WEBUI_STATE="skipped"
                ;;
        esac
    else
        WEBUI_STATE="new"
    fi
}

start_ollama() {
    local ollama_image="ollama/ollama:latest"
    if [ "$OLLAMA_STATE" = "new" ]; then
        pull_image "$ollama_image"
        docker run -d \
            --name "$OLLAMA_CONTAINER" \
            "${GPU_FLAGS[@]}" \
            --network host \
            --runtime nvidia \
            -v ollama-data:/root/.ollama \
            "$ollama_image"
    fi
    if [ "$OLLAMA_STATE" = "restarted" ]; then
        docker start "$OLLAMA_CONTAINER"
    fi

    echo "Waiting for Ollama to be ready (max ${OLLAMA_START_PERIOD}s)..."
    local elapsed=0
    local interval=5
    while [ "$elapsed" -lt "$OLLAMA_START_PERIOD" ]; do
        if docker exec "$OLLAMA_CONTAINER" curl -s http://localhost:11434/ >/dev/null 2>&1; then
            echo "${GREEN}Ollama is ready.${RESET}"
            return 0
        fi
        if [ $((elapsed % 15)) -eq 0 ]; then
            echo "Waiting for Ollama startup... (${elapsed}s/${OLLAMA_START_PERIOD}s)"
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    echo "${RED}Ollama failed to start within ${OLLAMA_START_PERIOD}s.${RESET}"
    echo "Check logs with: docker logs ollama"
    return 1
}

start_webui() {
    local webui_image="ghcr.io/nvidia-ai-iot/live-vlm-webui:${IMAGE_TAG}"

    # If model is selected but container creation was skipped, force recreate
    if [ "$WEBUI_STATE" = "skipped" ] && [ -n "$SELECTED_MODEL" ]; then
        echo "${YELLOW}Model selected but container creation was skipped. Forcing recreation...${RESET}"
        docker rm -f "$WEBUI_CONTAINER" >/dev/null 2>&1
        WEBUI_STATE="recreate"
    fi

    if [ "$WEBUI_STATE" = "new" ] || [ "$WEBUI_STATE" = "recreate" ]; then
        pull_image "$webui_image"

        # Build command arguments for Ollama configuration
        local cmd_args="-m live_vlm_webui.server --host 0.0.0.0 --port 8090"
        if [ -n "$SELECTED_MODEL" ]; then
            cmd_args="$cmd_args --model $SELECTED_MODEL"
        fi
        # Use Ollama's local API (--api-key EMPTY for no auth)
        cmd_args="$cmd_args --api-base http://localhost:11434/v1 --api-key EMPTY"

        docker run -d \
            --name "$WEBUI_CONTAINER" \
            "${GPU_FLAGS[@]}" \
            --network host \
            --privileged \
            -v /run/jtop.sock:/run/jtop.sock:ro \
            -e PYTHONUNBUFFERED=1 \
            --entrypoint python \
            "$webui_image" \
            $cmd_args
        echo "${GREEN}live-vlm-webui container started with Ollama config.${RESET}"
    fi
}

model_ollama_list() {
    docker exec "$OLLAMA_CONTAINER" ollama list 2>/dev/null
}

is_model_pulled() {
    local model="$1"
    model_ollama_list | grep -q "^${model}" 2>/dev/null
}

pull_model() {
    local model="$1"
    echo "Pulling model: ${CYAN}${model}${RESET}"
    echo "This may take several minutes depending on model size and network speed..."
    if docker exec "$OLLAMA_CONTAINER" ollama pull "$model"; then
        echo "${GREEN}Model $model pulled successfully.${RESET}"
        return 0
    else
        echo "${RED}Failed to pull model $model.${RESET}"
        return 1
    fi
}

interactive_model_selection() {
    echo ""
    echo "========================================"
    echo "  Select a VLM model to use"
    echo "========================================"
    echo ""
    printf "  %-3s %-28s %-12s %s\n" "#" "Model" "Parameters" "VRAM"
    printf "  %-3s %-28s %-12s %s\n" "---" "--------------------------" "------------" "----"
    printf "  %-3s %-28s %-12s %s\n" "1" "gemma3:4b" "4B" "6GB (entry)"
    printf "  %-3s %-28s %-12s %s\n" "2" "gemma3:12b" "12B" "10GB (balanced)"
    printf "  %-3s %-28s %-12s %s\n" "3" "llava:7b" "7B" "6GB (vision)"
    printf "  %-3s %-28s %-12s %s\n" "4" "llama3.2-vision:11b" "11B" "14GB (vision)"
    printf "  %-3s %-28s %-12s %s\n" "5" "moondream:latest" "~1B" "1GB (ultra-light vision)"
    printf "  %-3s %-28s %-12s %s\n" "6" "gemma3:4b" "4B" "6GB (entry)"
    printf "  %-3s %-28s %-12s %s\n" "7" "nomic-embed-text:latest" "(embedding)" "(optional)"
    printf "  %-3s %-28s %-12s %s\n" "0" "Skip (no model)" "-" "-"
    echo ""

    while true; do
        read -r -p "Select model [0-7, default 0]: " choice
        choice="${choice:-0}"
        case "$choice" in
            0) echo "Skipping model pull."; return 0 ;;
            1|2|3|4|5|6|7)
                SELECTED_MODEL="${MODEL_MAP[$choice]}"
                break
                ;;
            *) echo "Invalid choice. Please enter 0-7." ;;
        esac
    done

    if is_model_pulled "$SELECTED_MODEL"; then
        echo "${GREEN}Model $SELECTED_MODEL is already pulled.${RESET}"
        model_ollama_list | grep "^${SELECTED_MODEL}"
        read -r -p "Skip pulling and use existing model? (y/n, default y): " confirm
        confirm="${confirm:-y}"
        case "$confirm" in
            y|Y) return 0 ;;
        esac
    fi

    pull_model "$SELECTED_MODEL"
}

is_ollama_ready() {
    docker exec "$OLLAMA_CONTAINER" curl -s http://localhost:11434/ >/dev/null 2>&1
}

wait_for_ollama_ready() {
    local max_wait=60
    local elapsed=0
    local interval=5

    echo "Waiting for Ollama service to be ready..."

    while [ "$elapsed" -lt "$max_wait" ]; do
        if is_ollama_ready; then
            echo "${GREEN}Ollama service is ready.${RESET}"
            return 0
        fi
        if [ $((elapsed % 15)) -eq 0 ]; then
            echo "Waiting for Ollama... (${elapsed}s/${max_wait}s)"
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo "${RED}Ollama service is not responding after ${max_wait}s.${RESET}"
    echo "Check logs with: docker logs ollama"
    return 1
}

handle_model_selection() {
    if [ -n "$OLLAMA_MODEL" ]; then
        SELECTED_MODEL="$OLLAMA_MODEL"
        echo "${CYAN}OLLAMA_MODEL is set: using $SELECTED_MODEL${RESET}"
        if is_model_pulled "$SELECTED_MODEL"; then
            echo "${GREEN}Model $SELECTED_MODEL is already pulled. Skipping pull.${RESET}"
        else
            pull_model "$SELECTED_MODEL"
        fi
        return 0
    fi

    if ! is_ollama_ready; then
        echo "${YELLOW}Ollama service is not ready. Skipping model selection.${RESET}"
        return 0
    fi

    local existing_models
    existing_models=$(model_ollama_list 2>/dev/null | grep -v "^NAME" | grep -v "^$" | wc -l)
    if [ "$existing_models" -gt 0 ]; then
        echo "${GREEN}Found installed models:${RESET}"
        model_ollama_list | grep -v "^$"
        echo ""
        read -r -p "Use an existing model without pulling a new one? (y/n, default y): " confirm
        confirm="${confirm:-y}"
        case "$confirm" in
            y|Y)
                echo "Using existing model."
                # Set first available model as default
                SELECTED_MODEL=$(model_ollama_list 2>/dev/null | grep -v "^NAME" | grep -v "^$" | head -1 | awk '{print $1}')
                if [ -n "$SELECTED_MODEL" ]; then
                    echo "${CYAN}Auto-selected model: $SELECTED_MODEL${RESET}"
                fi
                return 0
                ;;
        esac
    fi

    interactive_model_selection
}

wait_for_webui_ready() {
    local endpoint="https://localhost:${WEBUI_PORT}"
    local elapsed=0
    local interval=5

    if ! command -v curl >/dev/null 2>&1; then
        echo "curl not found, skipping readiness check."
        return 0
    fi

    echo "Waiting for Live VLM WebUI to be ready at ${endpoint} (timeout: ${STARTUP_TIMEOUT}s)..."

    while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${WEBUI_CONTAINER}$"; then
            echo "${RED}WebUI container exited unexpectedly.${RESET}"
            echo "Recent logs:"
            docker logs --tail 50 "$WEBUI_CONTAINER" 2>&1
            return 1
        fi

        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -k --max-time 3 "$endpoint" 2>/dev/null || echo "000")

        if [ "$http_code" = "200" ]; then
            echo "${GREEN}Live VLM WebUI is ready!${RESET}"
            return 0
        fi

        if [ $((elapsed % 20)) -eq 0 ]; then
            echo "Waiting for WebUI readiness... (${elapsed}s, http=${http_code})"
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo "${RED}WebUI is still not ready after ${STARTUP_TIMEOUT}s.${RESET}"
    echo "Last HTTP status: ${http_code}"
    echo "Recent logs:"
    docker logs --tail 50 "$WEBUI_CONTAINER" 2>&1
    echo ""
    echo "You can still access the WebUI at: ${endpoint}"
    echo "It may still be loading. Check status with: docker logs -f ${WEBUI_CONTAINER}"
    return 0
}

print_access_info() {
    echo ""
    echo "========================================"
    echo "  Live VLM WebUI is ready!"
    echo "========================================"
    echo ""
    echo "  Access URLs:"
    echo "  - Local:   ${CYAN}https://localhost:${WEBUI_PORT}${RESET}"
    echo "  - Network: https://$(hostname -I | awk '{print $1}'):${WEBUI_PORT}"
    echo ""
    echo "  Ollama API: http://localhost:${OLLAMA_PORT}"
    if [ -n "$SELECTED_MODEL" ]; then
        echo "  Model: ${GREEN}${SELECTED_MODEL}${RESET}"
    fi
    echo ""
    echo "  View logs:"
    echo "  docker logs -f ${WEBUI_CONTAINER}"
    echo ""
    echo "  Model management:"
    echo "  docker exec ${OLLAMA_CONTAINER} ollama list"
    echo "  docker exec ${OLLAMA_CONTAINER} ollama pull <model>"
    echo ""
}

main() {
    echo "========================================"
    echo "  Live VLM WebUI - One-Click Deployment"
    echo "========================================"
    echo ""

    ensure_docker_access
    detect_platform_and_image
    probe_gpu_mode
    smart_ollama_check
    smart_webui_check

    if [ "$OLLAMA_STATE" != "skipped" ] && [ "$OLLAMA_STATE" != "running" ]; then
        start_ollama
    fi

    if [ "$OLLAMA_STATE" != "skipped" ]; then
        if ! wait_for_ollama_ready; then
            echo "${YELLOW}Warning: Ollama may not be ready. WebUI might not function properly.${RESET}"
        fi
    fi

    # Start WebUI first so it's available even if model pull takes time or fails
    if [ "$WEBUI_STATE" != "skipped" ]; then
        start_webui
    fi

    # Handle model selection - only pull if model doesn't exist
    handle_model_selection

    # If model pull failed, warn but continue - WebUI is still usable
    # User can pull model later via: docker exec ollama ollama pull <model>
    wait_for_webui_ready
    print_access_info
}

main
