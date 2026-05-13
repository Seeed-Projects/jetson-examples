#!/bin/bash
set -euo pipefail

CONTAINER_NAME="${GEMMA4_CONTAINER_NAME:-gemma4-jetson}"
IMAGE_NAME="${GEMMA4_IMAGE_NAME:-llama-jetson}"
IMAGE_SHARE_URL="${GEMMA4_IMAGE_SHARE_URL:-https://seeedstudio88-my.sharepoint.com/:u:/g/personal/youjiang_yu_seeedstudio88_onmicrosoft_com/IQBGgzrQX-wrSogvNhhCauP7AZF7ALXGs25MyW8vswV7PE4?e=3jI1o6}"
IMAGE_ARCHIVE_NAME="${GEMMA4_IMAGE_ARCHIVE_NAME:-gemma4-jetson.tar}"
MODEL_URL="${GEMMA4_MODEL_URL:-https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf}"
MODELS_DIR="${GEMMA4_MODELS_DIR:-$HOME/models}"
MODEL_FILE="${GEMMA4_MODEL_FILE:-$MODELS_DIR/gemma-4-E4B-it-Q4_K_M.gguf}"
CACHE_DIR="${GEMMA4_CACHE_DIR:-$HOME/.cache/jetson-examples/gemma4}"
HOST_PORT="${GEMMA4_PORT:-8080}"
CONTAINER_PORT="${GEMMA4_CONTAINER_PORT:-8080}"
STARTUP_TIMEOUT="${GEMMA4_STARTUP_TIMEOUT:-600}"
CTX_SIZE="${GEMMA4_CTX_SIZE:-8192}"
DOCKER_CMD=()
GPU_FLAGS=()
LIB_MOUNTS=()
APT_UPDATED=0

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

die() {
    echo "Error: $*" >&2
    exit 1
}

run_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    else
        command -v sudo >/dev/null 2>&1 || die "sudo is required to install missing dependencies."
        sudo "$@"
    fi
}

apt_update_once() {
    if [[ "${APT_UPDATED}" -eq 0 ]]; then
        log "Updating apt package index..."
        run_root apt-get update
        APT_UPDATED=1
    fi
}

install_apt_packages() {
    local packages=("$@")
    if [[ "${#packages[@]}" -eq 0 ]]; then
        return 0
    fi

    apt_update_once
    log "Installing missing packages: ${packages[*]}"
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

ensure_base_dependencies() {
    local packages=()

    command -v python3 >/dev/null 2>&1 || packages+=(python3)
    command -v aria2c >/dev/null 2>&1 || packages+=(aria2)
    command -v docker >/dev/null 2>&1 || packages+=(docker.io)

    install_apt_packages "${packages[@]}"
}

ensure_docker_ready() {
    if docker info >/dev/null 2>&1; then
        DOCKER_CMD=(docker)
        return 0
    fi

    if command -v systemctl >/dev/null 2>&1; then
        run_root systemctl enable --now docker >/dev/null 2>&1 || true
    fi

    if docker info >/dev/null 2>&1; then
        DOCKER_CMD=(docker)
        return 0
    fi

    if [[ "${EUID}" -ne 0 ]] && command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
        DOCKER_CMD=(sudo docker)
        return 0
    fi

    die "Docker is installed but not usable. Check that the docker service is running and the current user has permission."
}

package_available() {
    apt-cache show "$1" >/dev/null 2>&1
}

ensure_nvidia_runtime_package() {
    if "${DOCKER_CMD[@]}" info 2>/dev/null | grep -qi "nvidia"; then
        return 0
    fi

    apt_update_once
    if package_available nvidia-container-toolkit; then
        install_apt_packages nvidia-container-toolkit
    elif package_available nvidia-container-runtime; then
        install_apt_packages nvidia-container-runtime
    else
        log "NVIDIA container runtime package is not available from current apt sources."
        return 0
    fi

    if command -v nvidia-ctk >/dev/null 2>&1; then
        run_root nvidia-ctk runtime configure --runtime=docker >/dev/null 2>&1 || true
    fi

    if command -v systemctl >/dev/null 2>&1; then
        run_root systemctl restart docker >/dev/null 2>&1 || true
    fi

    ensure_docker_ready
}

sharepoint_download_url() {
    local url="$1"
    local separator

    if [[ "${url}" == *"/_layouts/15/download.aspx"* ]]; then
        printf '%s\n' "${url}"
        return 0
    fi

    if [[ "${url}" =~ ^(https?://[^/]+)/:[A-Za-z]:/g/(personal/[^/?#]+)/([^/?#]+) ]]; then
        printf '%s/%s/_layouts/15/download.aspx?share=%s\n' \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}"
        return 0
    fi

    if [[ "${url}" == *"download=1"* ]]; then
        printf '%s\n' "${url}"
        return 0
    fi

    separator="?"
    [[ "${url}" == *"?"* ]] && separator="&"
    printf '%s%sdownload=1\n' "${url}" "${separator}"
}

download_with_aria2() {
    local url="$1"
    local output_dir="$2"
    local output_name="$3"

    mkdir -p "${output_dir}"
    aria2c \
        --continue=true \
        --max-connection-per-server=8 \
        --split=8 \
        --min-split-size=10M \
        --retry-wait=5 \
        --max-tries=0 \
        --timeout=60 \
        --connect-timeout=15 \
        --allow-overwrite=true \
        --auto-file-renaming=false \
        --dir="${output_dir}" \
        --out="${output_name}" \
        "${url}"
}

ensure_image() {
    local archive_path="${CACHE_DIR%/}/${IMAGE_ARCHIVE_NAME}"
    local image_url="${GEMMA4_IMAGE_ARCHIVE_URL:-$(sharepoint_download_url "${IMAGE_SHARE_URL}")}"
    local load_output
    local loaded_image

    if "${DOCKER_CMD[@]}" image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        log "Docker image already exists locally: ${IMAGE_NAME}"
        return 0
    fi

    if [[ ! -s "${archive_path}" ]]; then
        log "Downloading Docker image archive from OneDrive/SharePoint..."
        log "Resolved download URL: ${image_url}"
        download_with_aria2 "${image_url}" "${CACHE_DIR}" "${IMAGE_ARCHIVE_NAME}"
    else
        log "Using cached Docker archive: ${archive_path}"
    fi

    log "Loading Docker image archive: ${archive_path}"
    load_output="$("${DOCKER_CMD[@]}" load -i "${archive_path}")"
    printf '%s\n' "${load_output}"

    if "${DOCKER_CMD[@]}" image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        return 0
    fi

    loaded_image="$(printf '%s\n' "${load_output}" | awk -F': ' '/Loaded image:/{print $2; exit}')"
    if [[ -n "${loaded_image}" ]] && "${DOCKER_CMD[@]}" image inspect "${loaded_image}" >/dev/null 2>&1; then
        IMAGE_NAME="${loaded_image}"
        log "Using loaded Docker image: ${IMAGE_NAME}"
        return 0
    fi

    die "Expected image was not found after docker load: ${IMAGE_NAME}. Set GEMMA4_IMAGE_NAME if the archive uses a different image tag."
}

ensure_model() {
    mkdir -p "${MODELS_DIR}"
    if [[ -s "${MODEL_FILE}" ]]; then
        log "Model already exists locally: ${MODEL_FILE}"
        return 0
    fi

    log "Downloading Gemma4 model..."
    download_with_aria2 "${MODEL_URL}" "${MODELS_DIR}" "$(basename "${MODEL_FILE}")"
}

select_gpu_layers() {
    local total_mem_mb
    total_mem_mb="$(free -m | awk '/^Mem:/{print $2}')"

    if [[ "${total_mem_mb}" -ge 60000 ]]; then
        echo 99
    elif [[ "${total_mem_mb}" -ge 14000 ]]; then
        echo 80
    elif [[ "${total_mem_mb}" -ge 7000 ]]; then
        echo 40
    else
        echo 20
    fi
}

probe_gpu_mode_once() {
    if "${DOCKER_CMD[@]}" run --rm --entrypoint /bin/sh --runtime nvidia "${IMAGE_NAME}" -lc "exit 0" >/dev/null 2>&1; then
        GPU_FLAGS=(--runtime nvidia)
        log "Using GPU mode: --runtime nvidia"
        return 0
    fi

    if "${DOCKER_CMD[@]}" run --rm --entrypoint /bin/sh --gpus all "${IMAGE_NAME}" -lc "exit 0" >/dev/null 2>&1; then
        GPU_FLAGS=(--gpus all)
        log "Using GPU mode: --gpus all"
        return 0
    fi

    return 1
}

probe_gpu_mode() {
    if probe_gpu_mode_once; then
        return 0
    fi

    log "NVIDIA Docker runtime was not detected. Trying to install/configure it..."
    ensure_nvidia_runtime_package

    if probe_gpu_mode_once; then
        return 0
    fi

    die "Failed to detect a working Docker GPU mode. Check NVIDIA Container Runtime on this Jetson."
}

collect_library_mounts() {
    local candidate
    local candidates=(
        "/usr/local/cuda/lib64:/usr/local/cuda/lib64:ro"
        "/usr/lib/aarch64-linux-gnu/nvidia:/usr/lib/aarch64-linux-gnu/nvidia:ro"
        "/usr/lib/aarch64-linux-gnu/libcuda.so.1:/usr/lib/aarch64-linux-gnu/libcuda.so.1:ro"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -e "${candidate%%:*}" ]]; then
            LIB_MOUNTS+=(-v "${candidate}")
        fi
    done
}

probe_http() {
    python3 - "$1" <<'PY'
import sys
import urllib.error
import urllib.request

url = sys.argv[1]
try:
    with urllib.request.urlopen(url, timeout=3) as response:
        body = response.read(4096).decode("utf-8", errors="ignore")
        print(f"{response.status}\t{body}")
except urllib.error.HTTPError as exc:
    body = exc.read(4096).decode("utf-8", errors="ignore")
    print(f"{exc.code}\t{body}")
except Exception as exc:
    print(f"000\t{exc}")
PY
}

wait_for_server_ready() {
    local endpoint="http://127.0.0.1:${HOST_PORT}/v1/models"
    local elapsed=0
    local interval=5
    local raw_response
    local http_code
    local response_body

    log "Waiting for Gemma4 server at ${endpoint} (timeout: ${STARTUP_TIMEOUT}s)..."
    while [[ "${elapsed}" -lt "${STARTUP_TIMEOUT}" ]]; do
        if [[ -z "$("${DOCKER_CMD[@]}" ps -q -f name="^/${CONTAINER_NAME}$")" ]]; then
            echo "Container exited before the model became ready."
            echo "Recent logs:"
            "${DOCKER_CMD[@]}" logs --tail 80 "${CONTAINER_NAME}" || true
            return 1
        fi

        raw_response="$(probe_http "${endpoint}" || true)"
        http_code="${raw_response%%$'\t'*}"
        response_body="${raw_response#*$'\t'}"

        if [[ "${http_code}" == "200" && "${response_body}" == *'"data"'* ]]; then
            return 0
        fi

        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log "Waiting for model readiness... (${elapsed}s, http=${http_code})"
        fi

        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done

    echo "Model is still not ready after ${STARTUP_TIMEOUT}s."
    echo "Recent logs:"
    "${DOCKER_CMD[@]}" logs --tail 80 "${CONTAINER_NAME}" || true
    return 1
}

run_container() {
    local gpu_layers="${GEMMA4_GPU_LAYERS:-$(select_gpu_layers)}"
    local model_basename
    model_basename="$(basename "${MODEL_FILE}")"

    log "Using --n-gpu-layers ${gpu_layers}"

    if [[ -n "$("${DOCKER_CMD[@]}" ps -q -f name="^/${CONTAINER_NAME}$")" ]]; then
        log "Container is already running: ${CONTAINER_NAME}"
        return 0
    fi

    if [[ -n "$("${DOCKER_CMD[@]}" ps -a -q -f name="^/${CONTAINER_NAME}$")" ]]; then
        log "Removing stopped container: ${CONTAINER_NAME}"
        "${DOCKER_CMD[@]}" rm -f "${CONTAINER_NAME}" >/dev/null
    fi

    log "Creating and starting container: ${CONTAINER_NAME}"
    "${DOCKER_CMD[@]}" run -d \
        --name "${CONTAINER_NAME}" \
        "${GPU_FLAGS[@]}" \
        -p "${HOST_PORT}:${CONTAINER_PORT}" \
        -v "${MODELS_DIR}":/models \
        "${LIB_MOUNTS[@]}" \
        -e LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/aarch64-linux-gnu/nvidia:/usr/lib/aarch64-linux-gnu:/usr/local/lib/llama \
        "${IMAGE_NAME}" \
        --model "/models/${model_basename}" \
        --ctx-size "${CTX_SIZE}" \
        --host 0.0.0.0 \
        --port "${CONTAINER_PORT}" \
        --n-gpu-layers "${gpu_layers}" >/dev/null
}

main() {
    ensure_base_dependencies
    ensure_docker_ready
    ensure_image
    ensure_model
    probe_gpu_mode
    collect_library_mounts
    run_container
    wait_for_server_ready

    log "Gemma4 server is ready: http://127.0.0.1:${HOST_PORT}"
    log "Follow logs with: ${DOCKER_CMD[*]} logs -f ${CONTAINER_NAME}"
}

main "$@"
