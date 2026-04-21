#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADER_SCRIPT="${SCRIPT_DIR}/../nvblox/onedrive_downloader.py"
IMAGE_NAME="${ROS1_JP6_IMAGE:-ros:noetic}"
CONTAINER_NAME="${ROS1_JP6_CONTAINER_NAME:-ros1-jp6}"
SHARE_URL="${ROS1_JP6_SHARE_URL:-https://seeedstudio88-my.sharepoint.com/:u:/g/personal/youjiang_yu_seeedstudio88_onmicrosoft_com/IQCOgjRBDytqT4jKdktOzhdIAUf97NfnQJ4lk_DAHpLTaRY?e=Nw0RjJ}"
CACHE_DIR="${ROS1_JP6_CACHE_DIR:-$HOME/.cache/jetson-examples/ros1-jp6}"
ARCHIVE_NAME="${ROS1_JP6_ARCHIVE_NAME:-ros-noetic-jp6.tar}"
ARCHIVE_PATH="${CACHE_DIR%/}/${ARCHIVE_NAME}"
SAVE_PATH="${ROS1_JP6_SAVE_PATH:-}"
SKIP_RUN="${ROS1_JP6_SKIP_RUN:-0}"
CONTAINER_COMMAND="${ROS1_JP6_COMMAND:-bash}"
DOCKER_RUN_FLAGS=()

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
            echo "reComputer run ros1-jp6"
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

require_downloader() {
    if [[ ! -f "${DOWNLOADER_SCRIPT}" ]]; then
        echo "OneDrive downloader not found: ${DOWNLOADER_SCRIPT}"
        exit 1
    fi
}

ensure_archive() {
    mkdir -p "${CACHE_DIR}"
    if [[ -f "${ARCHIVE_PATH}" && -s "${ARCHIVE_PATH}" ]]; then
        echo "Using cached archive: ${ARCHIVE_PATH}"
        return 0
    fi

    require_downloader
    echo "Downloading ROS 1 archive from SharePoint..."
    python3 "${DOWNLOADER_SCRIPT}" "${SHARE_URL}" --filename "${ARCHIVE_NAME}" --output-dir "${CACHE_DIR}"
}

ensure_image() {
    if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        echo "Docker image already present: ${IMAGE_NAME}"
        return 0
    fi

    ensure_archive
    echo "Loading Docker image archive: ${ARCHIVE_PATH}"
    docker load -i "${ARCHIVE_PATH}"

    if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        echo "Expected image not found after docker load: ${IMAGE_NAME}"
        exit 1
    fi
}

maybe_save_image() {
    if [[ -z "${SAVE_PATH}" ]]; then
        return 0
    fi

    mkdir -p "$(dirname "${SAVE_PATH}")"
    echo "Saving image ${IMAGE_NAME} to ${SAVE_PATH}"
    docker save -o "${SAVE_PATH}" "${IMAGE_NAME}"
}

prepare_run_flags() {
    if docker run --rm --runtime nvidia "${IMAGE_NAME}" /bin/sh -lc "exit 0" >/dev/null 2>&1; then
        DOCKER_RUN_FLAGS+=(--runtime nvidia)
        echo "Using GPU mode: --runtime nvidia"
        return 0
    fi

    if docker run --rm --gpus all "${IMAGE_NAME}" /bin/sh -lc "exit 0" >/dev/null 2>&1; then
        DOCKER_RUN_FLAGS+=(--gpus all)
        echo "Using GPU mode: --gpus all"
        return 0
    fi

    echo "Warning: no GPU runtime detected. Falling back to CPU-only container start."
}

run_container() {
    local tty_args=()
    local docker_args=(
        --rm
        --name "${CONTAINER_NAME}"
        --network host
        --ipc host
        --privileged
        -v /dev:/dev
    )

    if [[ -t 0 && -t 1 ]]; then
        tty_args=(-it)
    fi

    if [[ -n "${DISPLAY:-}" ]]; then
        docker_args+=(
            -e "DISPLAY=${DISPLAY}"
            -e QT_X11_NO_MITSHM=1
            -v /tmp/.X11-unix:/tmp/.X11-unix
        )
    fi

    if [[ -n "${ROS_MASTER_URI:-}" ]]; then
        docker_args+=(-e "ROS_MASTER_URI=${ROS_MASTER_URI}")
    fi

    if [[ -n "${ROS_IP:-}" ]]; then
        docker_args+=(-e "ROS_IP=${ROS_IP}")
    fi

    if [[ -n "${ROS_HOSTNAME:-}" ]]; then
        docker_args+=(-e "ROS_HOSTNAME=${ROS_HOSTNAME}")
    fi

    if docker ps -a -q -f name="^/${CONTAINER_NAME}$" | grep -q .; then
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi

    echo "Starting ${IMAGE_NAME}"
    docker run "${tty_args[@]}" "${DOCKER_RUN_FLAGS[@]}" "${docker_args[@]}" "${IMAGE_NAME}" /bin/bash -lc "${CONTAINER_COMMAND}"
}

ensure_docker_access
ensure_image
maybe_save_image

if [[ "${SKIP_RUN}" == "1" ]]; then
    echo "ROS1_JP6_SKIP_RUN=1, image preparation finished."
    exit 0
fi

prepare_run_flags
run_container
