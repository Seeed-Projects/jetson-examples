#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}"
ONNX_URL="${YOLO26_TENSORRT_ONNX_URL:-https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo26n.onnx}"
ONNX_SHA256="${YOLO26_TENSORRT_ONNX_SHA256:-2e947b787d9e787b93a16772a5f55b1d4d8c4d86f53146149c5d6a642442d6f7}"
CAMERA_ID="${YOLO26_TENSORRT_CAMERA:-auto}"
PORT="${YOLO26_TENSORRT_PORT:-8080}"
BUILD_ONLY=0

log() { echo "[$(date '+%H:%M:%S')] $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-only) BUILD_ONLY=1; shift ;;
        --camera) CAMERA_ID="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

cd "${WORK_DIR}"

# ------------------------------------------------------------------
# 1. Ensure ONNX model is present
# ------------------------------------------------------------------
if [[ ! -s "yolo26n.onnx" ]]; then
    if [[ "${YOLO26_TENSORRT_SKIP_DOWNLOAD:-0}" == "1" ]]; then
        log "ERROR: yolo26n.onnx is missing and YOLO26_TENSORRT_SKIP_DOWNLOAD=1"
        exit 1
    fi
    log "Downloading yolo26n.onnx..."
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "${ONNX_URL}" -O yolo26n.onnx
    elif command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar "${ONNX_URL}" -o yolo26n.onnx
    else
        log "ERROR: wget or curl required to download model"
        exit 1
    fi
fi
ACTUAL_ONNX_SHA256="$(sha256sum yolo26n.onnx | awk '{print $1}')"
if [[ "${ACTUAL_ONNX_SHA256}" != "${ONNX_SHA256}" ]]; then
    log "ERROR: yolo26n.onnx SHA256 mismatch"
    log "Expected: ${ONNX_SHA256}"
    log "Actual:   ${ACTUAL_ONNX_SHA256}"
    exit 1
fi
log "ONNX model ready: yolo26n.onnx"

# ------------------------------------------------------------------
# 2. Build TensorRT engine on the target Jetson (device-specific)
# ------------------------------------------------------------------
TRTEXEC="/usr/src/tensorrt/bin/trtexec"
if [[ ! -x "${TRTEXEC}" ]]; then
    TRTEXEC="$(command -v trtexec || true)"
fi
if [[ -z "${TRTEXEC}" || ! -x "${TRTEXEC}" ]]; then
    log "ERROR: trtexec not found. Install libnvinfer-bin from the JetPack repository."
    exit 1
fi
TRT_VERSION="$(${TRTEXEC} --version 2>&1 | tail -n 1 || true)"
ENGINE_FINGERPRINT="${ACTUAL_ONNX_SHA256}|${TRT_VERSION}"
ENGINE_META="yolo26n.engine.meta"

if [[ ! -s "yolo26n.engine" ]] || [[ "$(cat "${ENGINE_META}" 2>/dev/null || true)" != "${ENGINE_FINGERPRINT}" ]]; then
    log "Building TensorRT engine with trtexec (${TRT_VERSION:-unknown version})..."
    rm -f yolo26n.engine "${ENGINE_META}"
    TRT_MEMORY_ARG="--workspace=4096"
    if "${TRTEXEC}" --help 2>&1 | grep -q -- "--memPoolSize"; then
        TRT_MEMORY_ARG="--memPoolSize=workspace:4096"
    fi
    "${TRTEXEC}" \
        --onnx=yolo26n.onnx \
        --saveEngine=yolo26n.engine \
        --fp16 \
        "${TRT_MEMORY_ARG}"
    printf '%s' "${ENGINE_FINGERPRINT}" > "${ENGINE_META}"
    log "Engine built: yolo26n.engine"
else
    log "Using cached engine: yolo26n.engine"
fi

# ------------------------------------------------------------------
# 3. Compile C++ inference program
# ------------------------------------------------------------------
if [[ ! -x "build/yolo26_tensorrt" ]]; then
    log "Compiling yolo26_tensorrt..."
    rm -rf build
    mkdir -p build
    cmake -B build -S src
    cmake --build build -j"$(nproc)"
    log "Build complete: build/yolo26_tensorrt"
else
    log "Executable already exists: build/yolo26_tensorrt"
fi

if [[ "${BUILD_ONLY}" == "1" ]]; then
    log "Build-only mode finished."
    exit 0
fi

# ------------------------------------------------------------------
# 4. Run inference + HTTP server
# ------------------------------------------------------------------
log "Starting YOLO26 TensorRT inference server on port ${PORT} (cameras: ${CAMERA_ID})..."
pkill -f "build/yolo26_tensorrt" || true
sleep 1

nohup ./build/yolo26_tensorrt \
    --engine yolo26n.engine \
    --camera "${CAMERA_ID}" \
    --port "${PORT}" \
    --labels src/coco_labels.txt \
    > yolo26_tensorrt.log 2>&1 &

PID=$!
log "Started with PID ${PID}"

# Wait a moment and verify it is still alive
sleep 2
if ! kill -0 "${PID}" 2>/dev/null; then
    log "ERROR: process exited quickly. Check yolo26_tensorrt.log:"
    tail -n 30 yolo26_tensorrt.log || true
    exit 1
fi

log "Server is running. Open http://<jetson-ip>:${PORT}/ in your browser."
log "Logs: ${WORK_DIR}/yolo26_tensorrt.log"
