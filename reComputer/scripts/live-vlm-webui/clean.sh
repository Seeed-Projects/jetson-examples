#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"

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
            echo "reComputer clean live-vlm-webui"
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

cd "$SCRIPT_DIR"

if docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
    docker stop ollama
fi

if docker ps --format '{{.Names}}' | grep -q "^live-vlm-webui$"; then
    docker stop live-vlm-webui
fi

if docker ps -a --format '{{.Names}}' | grep -q "^ollama$"; then
    docker rm ollama
    echo "Container ollama removed."
else
    echo "Container ollama does not exist."
fi

if docker ps -a --format '{{.Names}}' | grep -q "^live-vlm-webui$"; then
    docker rm live-vlm-webui
    echo "Container live-vlm-webui removed."
else
    echo "Container live-vlm-webui does not exist."
fi

echo "Containers removed. Images kept locally for faster next startup."
