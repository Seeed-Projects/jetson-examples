#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
IMAGE_NAME="locateanything:latest"
PORT="${PORT:-7860}"

# ── Low-memory branch: 4-bit NF4 Docker on <16GB devices (Orin Nano 8G / NX) ─
CURRENT_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$CURRENT_MEM" -lt 16 ]; then
    IMAGE_NAME="locateanything-4bit:latest"
    if ! docker images "$IMAGE_NAME" --format "{{.Repository}}" 2>/dev/null | grep -q "locateanything-4bit"; then
        echo "ERROR: 4-bit Docker image '$IMAGE_NAME' not found."
        echo "Run 'reComputer run locateanything' first (init.sh builds it)."
        exit 1
    fi

    IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo "Starting LocateAnything 4-bit Web UI (Docker) on port $PORT..."
    echo "  Model: nvidia/LocateAnything-3B, 4-bit NF4 (device-detected MAX_SIDE)"
    echo "  Local:   http://localhost:$PORT"
    echo "  Network: http://${IP:-<jetson-ip>}:$PORT"
    echo "  Stop:    Ctrl+C"
    echo ""
    # Image ENV carries LD_LIBRARY_PATH (cu12 libs), HF mirror, PYTORCH_CUDA_ALLOC_CONF.
    # run_web_ui.py ENTRYPOINT device-detects MAX_SIDE + auto-restarts on crash.
    # Mount the host HF cache (reuses the 7.3GB model already downloaded; fresh
    # devices download into it on first run). Swap on host absorbs inference spikes.
    exec docker run --rm \
        --runtime=nvidia \
        --network=host \
        -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
        -e NVIDIA_VISIBLE_DEVICES=all \
        -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
        -e LA_PORT="$PORT" \
        -e LA_HOST=0.0.0.0 \
        -p "$PORT":"$PORT" \
        "$IMAGE_NAME"
fi

# ── bf16 Docker path (≥16GB devices: Thor / AGX) ────────────────────────────
# ── Verify image exists ────────────────────────────────────────────────────
if ! docker images "$IMAGE_NAME" --format "{{.Repository}}" 2>/dev/null | grep -q "locateanything"; then
    echo "ERROR: Docker image '$IMAGE_NAME' not found."
    echo "Run 'reComputer run locateanything' first (init.sh builds it)."
    exit 1
fi

# ── Check if model is already cached in the volume ────────────────────────
MODEL_CACHED=$(docker run --rm -v locateanything-models:/root/.cache/huggingface:ro \
    alpine:latest sh -c \
    'ls /root/.cache/huggingface/hub/models--nvidia--LocateAnything-3B/snapshots/*/model-00001-of-00002.safetensors 2>/dev/null | head -1' 2>/dev/null || echo "")

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

echo "Starting LocateAnything-3B Web UI (Docker) on port $PORT..."
if [ -z "$MODEL_CACHED" ]; then
    echo "  ⚠ First run: downloading 7.3GB model (~15 min) — server starts after."
else
    echo "  Model cached — starting immediately."
fi
echo "  Local:   http://localhost:$PORT"
echo "  Network: http://${IP:-<jetson-ip>}:$PORT"
echo "  Stop:    Ctrl+C"
echo ""

# ── Run container ──────────────────────────────────────────────────────────
# --runtime=nvidia: mounts GPU driver
# --network=host:   shares host network (simpler than port mapping)
# -v locateanything-models: persists the 7.3GB HF model cache across restarts
exec docker run --rm \
    --runtime=nvidia \
    --network=host \
    -v locateanything-models:/root/.cache/huggingface \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    -e LA3B_MODEL="${LA3B_MODEL:-nvidia/LocateAnything-3B}" \
    -e LA3B_VIDEO_DIM="${LA3B_VIDEO_DIM:-512}" \
    -e LA3B_VIDEO_TOK="${LA3B_VIDEO_TOK:-16}" \
    -e LA3B_DETECT_SKIP="${LA3B_DETECT_SKIP:-5}" \
    -p "$PORT":"$PORT" \
    "$IMAGE_NAME"
