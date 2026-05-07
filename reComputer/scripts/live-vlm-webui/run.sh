#!/bin/bash

# Live VLM WebUI one-click deployment for NVIDIA Jetson
# Uses official GHCR pre-built images (no custom Dockerfile needed)

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

declare -A MODEL_MAP
MODEL_MAP=(
    [1]="gemma3:4b"
    [2]="gemma3:12b"
    [3]="qwen2.5-vl:3b"
    [4]="qwen2.5-vl:7b"
    [5]="llama3.2-vision:11b"
    [6]="phi3.5-vision:3.8b"
    [7]="nomic-embed-text"
)

detect_platform_and_image() {
    if [ -f "$L4T_VERSION_FILE" ]; then
        L4T_RELEASE=$(head -n 1 "$L4T_VERSION_FILE" | grep -oP '(?<=R)\d+' | head -1)
        L4T_REVISION=$(head -n 1 "$L4T_VERSION_FILE" | grep -oP '(?<=REVISION: )\d+' | head -1)
        L4T_VERSION="$L4T_RELEASE.$L4T_REVISION"
    else
        L4T_VERSION=$(dpkg-query --showformat='${Version}' --show nvidia-l4t-core 2>/dev/null \
            | grep -oP '\d+\.\d+' | head -1)
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
            echo "reComputer run live-vlm-webui"
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
        echo "Ollama container not found. Creating new one via docker compose..."
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
    printf "  %-3s %-28s %-12s %s\n" "3" "qwen2.5-vl:3b" "3B" "6GB (ultra-light)"
    printf "  %-3s %-28s %-12s %s\n" "4" "qwen2.5-vl:7b" "7B" "10GB (recommended)"
    printf "  %-3s %-28s %-12s %s\n" "5" "llama3.2-vision:11b" "11B" "14GB (medium)"
    printf "  %-3s %-28s %-12s %s\n" "6" "phi3.5-vision:3.8b" "3.8B" "6GB (ultra-light)"
    printf "  %-3s %-28s %-12s %s\n" "7" "nomic-embed-text" "(embedding)" "(optional)"
    printf "  %-3s %-28s %-12s %s\n" "0" "Skip (no model)" "—" "—"
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

    if ! docker ps --format '{{.Names}}' | grep -q "^${OLLAMA_CONTAINER}$"; then
        echo "${YELLOW}Ollama container is not running. Skipping model selection.${RESET}"
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
            y|Y) echo "Using existing model."; return 0 ;;
        esac
    fi

    interactive_model_selection
}

start_services() {
    if [ "$OLLAMA_STATE" = "new" ] || [ "$OLLAMA_STATE" = "restarted" ]; then
        echo "Starting Ollama via docker compose..."
        docker compose up -d ollama
        echo "Waiting for Ollama to be ready (max ${OLLAMA_START_PERIOD}s)..."
        local elapsed=0
        local interval=5
        while [ "$elapsed" -lt "$OLLAMA_START_PERIOD" ]; do
            if docker exec "$OLLAMA_CONTAINER" curl -s http://localhost:11434/ >/dev/null 2>&1; then
                echo "${GREEN}Ollama is ready.${RESET}"
                break
            fi
            if [ $((elapsed % 15)) -eq 0 ]; then
                echo "Waiting for Ollama startup... (${elapsed}s/${OLLAMA_START_PERIOD}s)"
            fi
            sleep "$interval"
            elapsed=$((elapsed + interval))
        done
        if [ "$elapsed" -ge "$OLLAMA_START_PERIOD" ]; then
            echo "${RED}Ollama failed to start within ${OLLAMA_START_PERIOD}s. Check logs with: docker logs ollama${RESET}"
            exit 1
        fi
    fi

    if [ "$WEBUI_STATE" = "new" ] || [ "$WEBUI_STATE" = "recreate" ]; then
        echo "Starting live-vlm-webui container..."
        sed -i "s|latest-jetson-orin|${IMAGE_TAG}|" "$SCRIPT_DIR/docker-compose.yml"
        if ! docker compose up -d live-vlm-webui; then
            echo "${RED}Failed to start live-vlm-webui container.${RESET}"
            exit 1
        fi
        echo "${GREEN}live-vlm-webui container started.${RESET}"
    fi
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
    smart_ollama_check
    smart_webui_check
    start_services
    handle_model_selection
    wait_for_webui_ready
    print_access_info
}

main
