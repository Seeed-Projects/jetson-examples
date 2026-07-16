#!/bin/bash
set -e
export TERM="${TERM:-xterm}"

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
CURRENT_MEM=$(free -g | awk '/^Mem:/{print $2}')

# ── Low-memory branch: 4-bit NF4 Docker on <16GB devices (Orin Nano 8G / NX) ─
# Full-precision bf16 needs ≥16GB; on smaller devices build+run the 4-bit Docker
# image (locateanything-4bit:latest, model volume locateanything-models).
if [ "$CURRENT_MEM" -lt 16 ]; then
    echo "=== LocateAnything 4-bit (low-memory, ${CURRENT_MEM}GB < 16GB) Init ==="

    # L4T allowlist (JetPack 7: 38.1.0 / 38.2.0 / 38.4.0 / 39.2.0)
    L4T="unknown"
    if [ -r /etc/nv_tegra_release ]; then
        L4T=$(awk '/^# R[0-9]+/ {m=$2; sub("R","",m)} /REVISION:/ {for(i=1;i<=NF;i++) if($i=="REVISION:"){r=$(i+1); sub(",","",r)}} END{if(m!=""&&r!="") print m"."r}' /etc/nv_tegra_release)
    fi
    case " 38.1.0 38.2.0 38.4.0 39.2.0 " in
        *" $L4T "*) echo "L4T $L4T in allowed: OK!" ;;
        *) echo "ERROR: L4T $L4T not in allowlist (38.1.0/38.2.0/38.4.0/39.2.0)."; exit 1 ;;
    esac

    # memory ≥7GB for 4-bit
    if [ "$CURRENT_MEM" -lt 7 ]; then
        echo "ERROR: Insufficient memory: ${CURRENT_MEM}GB (4-bit needs ≥7GB)."; exit 1
    fi
    echo "Memory ${CURRENT_MEM}GB (≥7 for 4-bit): OK!"

    # disk ≥20GB (image ~2GB + model 7.3GB volume)
    DISK_AVAIL=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
    if [ "$DISK_AVAIL" -lt 20 ]; then
        echo "ERROR: Insufficient disk: ${DISK_AVAIL}GB (need ≥20GB)."; exit 1
    fi
    echo "Disk ${DISK_AVAIL}GB (≥20): OK!"

    # GPU present
    if ! nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -q .; then
        echo "ERROR: no NVIDIA GPU detected (nvidia-smi)."; exit 1
    fi
    echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1): OK!"

    # Docker must be available
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: docker not found. Install Docker first."; exit 1
    fi

    # Ensure the nvidia container runtime is registered (daemon may predate daemon.json).
    # nvidia is listed on the "Runtimes:" line (e.g. "Runtimes: nvidia runc ..."), NOT
    # as a standalone "  nvidia" line — so grep the Runtimes line for the nvidia word.
    # The old `grep -q '^  nvidia'` always false-negatived -> restarted docker EVERY run,
    # killing any running container and forcing a ~2min model reload.
    if ! docker info 2>/dev/null | grep -i 'Runtimes:' | grep -qw nvidia; then
        echo "Registering nvidia docker runtime (restarting docker)…"
        sudo systemctl restart docker
    fi

    # Build the 4-bit image (idempotent — skips if already built)
    IMAGE_NAME="locateanything-4bit:latest"
    if docker images "$IMAGE_NAME" --format "{{.Repository}}" 2>/dev/null | grep -q "locateanything-4bit"; then
        echo "Docker image '$IMAGE_NAME' already built."
    else
        echo "Building 4-bit Docker image '$IMAGE_NAME'…"
        # Pre-download torch wheel on the host (more reliable than in-build curl,
        # which drops on the flaky .cn redirect under buildkit's network).
        TORCH_WHL="$SCRIPT_DIR/4bit/torch.whl"
        TORCH_URL="https://developer.download.nvidia.com/compute/redist/jp/v61/pytorch/torch-2.5.0a0+872d972e41.nv24.08.17622132-cp310-cp310-linux_aarch64.whl"
        if [ ! -f "$TORCH_WHL" ] || [ "$(stat -c%s "$TORCH_WHL" 2>/dev/null || echo 0)" -lt 800000000 ]; then
            echo "  Downloading torch v61 wheel (~770MB, host curl, resumable)…"
            curl -L -C - --retry 10 --retry-delay 3 --retry-all-errors -o "$TORCH_WHL" "$TORCH_URL"
        fi
        echo "  First build downloads cu12 libs ~1GB + deps (~10-15 min)."
        echo "  Build is cache-resumable — if it fails, re-run to resume."
        echo ""
        docker buildx build --network host --progress=plain -t "$IMAGE_NAME" \
            -f "$SCRIPT_DIR/4bit/Dockerfile" "$SCRIPT_DIR/4bit"
        echo ""
        echo "Image built successfully."
    fi

    # Model cache volume (persists the 7.3GB model across restarts)
    if ! docker volume inspect locateanything-models >/dev/null 2>&1; then
        echo "Creating model cache volume 'locateanything-models'…"
        docker volume create locateanything-models >/dev/null
    fi

    # Host swap (8GB + desktop leaves <1GB free → inference OOM-kills; 4GB swap gives headroom)
    if [ "$(swapon --show 2>/dev/null | wc -l)" -le 0 ]; then
        echo "Creating 4GB swapfile (prevents OOM-kill on 8GB+desktop)…"
        sudo fallocate -l 4G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile >/dev/null
        sudo swapon /swapfile
        grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
    fi

    echo ""
    echo "=== Init complete! ==="
    echo "Run:   reComputer run locateanything"
    echo "Open:  http://<jetson-ip>:7860"
    echo ""
    echo "Note: First 'run' downloads the 7.3GB model into the volume (~45 min via hf-mirror)."
    exit 0
fi

# ── bf16 Docker path (≥16GB devices: Thor / AGX) — unchanged ───────────────
# ── Environment check (L4T version, disk, memory) ──────────────────────────
source "$(dirname "$(realpath "$0")")/../utils.sh"
check_base_env "$(dirname "$(realpath "$0")")/config.yaml"

IMAGE_NAME="locateanything:latest"

echo "=== LocateAnything-3B Web UI — Init (Docker) ==="

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found. Install Docker first."
    exit 1
fi

# Build the image if it doesn't exist (idempotent — skips on subsequent runs)
if docker images "$IMAGE_NAME" --format "{{.Repository}}" 2>/dev/null | grep -q "locateanything"; then
    echo "Docker image '$IMAGE_NAME' already built."
else
    echo "Building Docker image '$IMAGE_NAME'..."
    echo "  First build downloads ~5GB of PyTorch + CUDA wheels (~30 min)."
    echo "  Build is cache-resumable — if it fails, re-run to resume."
    echo ""
    docker buildx build --network host --progress=plain -t "$IMAGE_NAME" "$SCRIPT_DIR"
    echo ""
    echo "Image built successfully."
fi

# Create the model cache volume (persists the 7.3GB model across restarts)
if ! docker volume inspect locateanything-models >/dev/null 2>&1; then
    echo "Creating model cache volume 'locateanything-models'..."
    docker volume create locateanything-models >/dev/null
fi

echo ""
echo "=== Init complete! ==="
echo "Run:   reComputer run locateanything"
echo "Open:  http://<jetson-ip>:7860"
echo ""
echo "Note: First 'run' downloads the 7.3GB model into the volume (~15 min)."
