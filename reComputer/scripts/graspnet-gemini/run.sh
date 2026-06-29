#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADER_SCRIPT="${SCRIPT_DIR}/../nvblox/onedrive_downloader.py"

CONTAINER_NAME="${GRASPNET_GEMINI_CONTAINER_NAME:-graspnet-gemini}"
IMAGE_NAME="${GRASPNET_GEMINI_IMAGE:-rebot-grasp:jp621-lowmem}"
IMAGE_ARCHIVE_URL="${GRASPNET_GEMINI_IMAGE_ARCHIVE_URL:-https://seeedstudio88-my.sharepoint.com/personal/youjiang_yu_seeedstudio88_onmicrosoft_com/_layouts/15/download.aspx?share=IQDAYs4omZPsQJNnTMLMwjlLAUxdjqSdw9z-cT5FuzwmS0E}"
CACHE_DIR="${GRASPNET_GEMINI_CACHE_DIR:-$HOME/.cache/jetson-examples/graspnet-gemini}"
ARCHIVE_NAME="${GRASPNET_GEMINI_ARCHIVE_NAME:-rebot-grasp-jp621-lowmem.tar}"
ARCHIVE_PATH="${CACHE_DIR%/}/${ARCHIVE_NAME}"

HOST_PORT="${GRASPNET_GEMINI_PORT:-8090}"
WIDTH="${GRASPNET_GEMINI_WIDTH:-640}"
HEIGHT="${GRASPNET_GEMINI_HEIGHT:-480}"
FPS="${GRASPNET_GEMINI_FPS:-15}"
NUM_POINT="${GRASPNET_GEMINI_NUM_POINT:-3000}"
CLOUD_CROP_NSAMPLE="${GRASPNET_GEMINI_CLOUD_CROP_NSAMPLE:-8}"
ENABLE_YOLO="${GRASPNET_GEMINI_ENABLE_YOLO:-0}"
YOLO_MODEL="${GRASPNET_GEMINI_YOLO_MODEL:-}"
STARTUP_TIMEOUT="${GRASPNET_GEMINI_STARTUP_TIMEOUT:-180}"
REQUIRE_CAMERA="${GRASPNET_GEMINI_REQUIRE_CAMERA:-0}"

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
            echo "reComputer run graspnet-gemini"
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

ensure_downloader() {
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

    ensure_downloader
    echo "Downloading GraspNet Gemini image archive from SharePoint..."
    python3 "${DOWNLOADER_SCRIPT}" "${IMAGE_ARCHIVE_URL}" --filename "${ARCHIVE_NAME}" --output-dir "${CACHE_DIR}"
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

probe_gpu_mode() {
    if docker run --rm --entrypoint /bin/sh --runtime nvidia "${IMAGE_NAME}" -lc "exit 0" >/dev/null 2>&1; then
        GPU_FLAGS=(--runtime nvidia)
        echo "Using GPU mode: --runtime nvidia"
        return 0
    fi

    if docker run --rm --entrypoint /bin/sh --gpus all "${IMAGE_NAME}" -lc "exit 0" >/dev/null 2>&1; then
        GPU_FLAGS=(--gpus all)
        echo "Using GPU mode: --gpus all"
        return 0
    fi

    echo "Failed to detect a working Docker GPU mode."
    echo "Tried: --runtime nvidia and --gpus all"
    echo "Please check Docker + NVIDIA Container Runtime on this device."
    exit 1
}

add_mount_if_exists() {
    local source_path="$1"
    local target_path="$2"
    local mode="${3:-ro}"

    if [[ -e "${source_path}" ]]; then
        LIB_MOUNTS+=(-v "${source_path}:${target_path}:${mode}")
    fi
}

collect_library_mounts() {
    add_mount_if_exists /usr/local/cuda-12.6 /usr/local/cuda-12.6 ro
    if [[ ! -e /usr/local/cuda-12.6 ]]; then
        add_mount_if_exists /usr/local/cuda /usr/local/cuda-12.6 ro
    fi

    add_mount_if_exists /usr/lib/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu ro
    add_mount_if_exists /usr/lib/python3.10/dist-packages /usr/lib/python3.10/dist-packages ro
    add_mount_if_exists /etc/nv_tegra_release /etc/nv_tegra_release ro
    add_mount_if_exists /run/udev /run/udev ro
    add_mount_if_exists /dev/bus/usb /dev/bus/usb rw
}

gemini_camera_usb_present() {
    local device_dir=""
    for device_dir in /sys/bus/usb/devices/*; do
        [[ -f "${device_dir}/idVendor" ]] || continue
        if [[ "$(tr '[:upper:]' '[:lower:]' < "${device_dir}/idVendor" | tr -d '[:space:]')" == "2bc5" ]]; then
            return 0
        fi
    done
    return 1
}

check_camera_hint() {
    if gemini_camera_usb_present; then
        echo "Detected an Orbbec USB camera."
        return 0
    fi

    if [[ "${REQUIRE_CAMERA}" == "1" ]]; then
        echo "No Orbbec USB camera was detected. Connect the Gemini camera and retry."
        exit 1
    fi

    echo "Warning: no Orbbec USB camera was detected. The Web UI can start, but live camera output may fail."
}

build_grasp_command() {
    GRASP_COMMAND=(
        python scripts/grasp_web.py
        --host 0.0.0.0
        --port "${HOST_PORT}"
        --width "${WIDTH}"
        --height "${HEIGHT}"
        --fps "${FPS}"
        --num-point "${NUM_POINT}"
        --cloud-crop-nsample "${CLOUD_CROP_NSAMPLE}"
    )

    if [[ "${ENABLE_YOLO}" != "1" ]]; then
        GRASP_COMMAND+=(--no-yolo)
    elif [[ -n "${YOLO_MODEL}" ]]; then
        GRASP_COMMAND+=(--yolo-model "${YOLO_MODEL}")
    fi
}

create_container() {
    build_grasp_command

    docker run -d \
        --name "${CONTAINER_NAME}" \
        "${GPU_FLAGS[@]}" \
        --network host \
        --ipc host \
        --privileged \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        -e NVIDIA_VISIBLE_DEVICES=all \
        -e NVIDIA_DRIVER_CAPABILITIES=all \
        -e CUDA_HOME=/usr/local/cuda \
        -e GRASP_PORT="${HOST_PORT}" \
        "${LIB_MOUNTS[@]}" \
        "${IMAGE_NAME}" \
        "${GRASP_COMMAND[@]}"
}

wait_for_web_ready() {
    local endpoint="http://127.0.0.1:${HOST_PORT}/"
    local elapsed=0
    local interval=3
    local http_code="000"

    if ! command -v curl >/dev/null 2>&1; then
        echo "curl not found, skip readiness probing."
        return 0
    fi

    echo "Waiting for GraspNet Gemini Web UI at ${endpoint} (timeout: ${STARTUP_TIMEOUT}s)..."
    while [[ "${elapsed}" -lt "${STARTUP_TIMEOUT}" ]]; do
        if [[ -z "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]]; then
            echo "Container exited before the Web UI became ready."
            echo "Recent logs:"
            docker logs --tail 120 "${CONTAINER_NAME}" || true
            return 1
        fi

        http_code="$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" "${endpoint}" 2>/dev/null || true)"
        if [[ "${http_code}" =~ ^(2|3)[0-9][0-9]$ ]]; then
            return 0
        fi

        if (( elapsed % 30 == 0 )); then
            echo "Waiting Web UI readiness... (${elapsed}s, http=${http_code})"
        fi
        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done

    echo "Web UI is still not ready after ${STARTUP_TIMEOUT}s."
    echo "Recent logs:"
    docker logs --tail 120 "${CONTAINER_NAME}" || true
    return 1
}

ensure_docker_access
ensure_image
probe_gpu_mode
collect_library_mounts
check_camera_hint

if [[ -n "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]]; then
    echo "Container ${CONTAINER_NAME} is already running."
elif [[ -n "$(docker ps -a -q -f name=^/${CONTAINER_NAME}$)" ]]; then
    echo "Container ${CONTAINER_NAME} already exists but is not running."
    echo "Recreating with current runtime settings..."
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    create_container >/dev/null
else
    echo "Creating and starting container ${CONTAINER_NAME}..."
    create_container >/dev/null
fi

if ! wait_for_web_ready; then
    exit 1
fi

echo "GraspNet Gemini demo is ready at: http://127.0.0.1:${HOST_PORT}"
echo "Open from another machine on the same network: http://<jetson-ip>:${HOST_PORT}"
echo "Follow logs:"
echo "docker logs -f ${CONTAINER_NAME}"
