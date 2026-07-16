#!/bin/bash
# setup_4bit.sh — self-contained provisioning of the LocateAnything 4-bit venv
# on a low-memory Jetson (Orin Nano 8G / NX, <16GB).
#
# Encodes the verified env-config (see project memory project_locate_anything_jetson):
#   torch 2.5.0a0+nv (v61 redist, cu124, SM8.7) + nvidia-*-cu12 runtime libs
#   (Jetson integrated GPU's NVML can't report free mem → CUDACachingAllocator
#   NVML assert; bridged by LD_LIBRARY_PATH + expandable_segments).
#   bitsandbytes 0.49.2 (4-bit NF4). torchvision/decord stubs (no aarch64 wheels).
#   HF offline (huggingface.co unreachable) + hf-mirror model download.
#
# Idempotent: re-running skips done steps.
# Usage: bash setup_4bit.sh [target_dir]
#   target_dir default: ${LA4BIT_DIR:-$HOME/workspace/locate-anything-4bit}
set -e

LA4BIT_DIR="${1:-${LA4BIT_DIR:-$HOME/workspace/locate-anything-4bit}}"
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
mkdir -p "$LA4BIT_DIR"
cd "$LA4BIT_DIR"

export PATH="$HOME/.local/bin:$PATH"

TORCH_WHL_URL="https://developer.download.nvidia.com/compute/redist/jp/v61/pytorch/torch-2.5.0a0+872d972e41.nv24.08.17622132-cp310-cp310-linux_aarch64.whl"
TORCH_WHL_NAME="torch-2.5.0a0+872d972e41.nv24.08.17622132-cp310-cp310-linux_aarch64.whl"
MODEL_ID="nvidia/LocateAnything-3B"

echo "=== [4bit] target dir: $LA4BIT_DIR ==="

# ── 1. uv ──────────────────────────────────────────────────────────────────
if ! command -v uv >/dev/null 2>&1; then
  echo "[4bit] installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
# shellcheck disable=SC1091
[ -f "$HOME/.local/bin/uv" ] && export PATH="$HOME/.local/bin:$PATH"
echo "[4bit] uv: $(uv --version 2>/dev/null || echo '?')"

# ── 2. python 3.10 venv ────────────────────────────────────────────────────
if [ ! -x "$LA4BIT_DIR/.venv/bin/python" ]; then
  echo "[4bit] creating python 3.10 venv…"
  uv python install 3.10
  uv venv --python 3.10 "$LA4BIT_DIR/.venv"
fi
PY="$LA4BIT_DIR/.venv/bin/python"
echo "[4bit] python: $($PY --version 2>&1)"

# ── helper: is torch already importable with CUDA? ─────────────────────────
torch_ok() {
  # needs LD_LIBRARY_PATH if already configured in activate; try via activate
  if [ -f "$LA4BIT_DIR/.venv/bin/activate" ]; then
    ( source "$LA4BIT_DIR/.venv/bin/activate" 2>/dev/null
      "$PY" -c 'import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)' ) 2>/dev/null
  else
    "$PY" -c 'import torch' 2>/dev/null
  fi
}

# ── 3. torch (v61 redist wheel; curl -L follows .cn redirect; uv client times out) ─
if ! "$PY" -c 'import torch' 2>/dev/null; then
  echo "[4bit] downloading torch v61 wheel (770MB, curl -L)…"
  curl -L --retry 5 --retry-delay 3 -C - -o "/tmp/$TORCH_WHL_NAME" "$TORCH_WHL_URL"
  echo "[4bit] installing torch (UV_SKIP_WHEEL_FILENAME_CHECK=1)…"
  UV_SKIP_WHEEL_FILENAME_CHECK=1 uv pip install --python "$PY" "/tmp/$TORCH_WHL_NAME"
else
  echo "[4bit] torch already installed."
fi

# ── 4. nvidia-*-cu12 runtime libs (surgical set; older nvtx for libnvToolsExt.so.1) ─
if [ ! -d "$LA4BIT_DIR/.venv/lib/python3.10/site-packages/nvidia/cuda_runtime" ]; then
  echo "[4bit] installing nvidia-*-cu12 runtime libs…"
  UV_SKIP_WHEEL_FILENAME_CHECK=1 uv pip install --python "$PY" \
    nvidia-cuda-runtime-cu12 nvidia-cublas-cu12 nvidia-cuda-nvrtc-cu12 \
    nvidia-nvjitlink-cu12 nvidia-cufft-cu12 nvidia-cusparselt-cu12 \
    nvidia-cuda-cupti-cu12 "nvidia-nvtx-cu12<12.6"
else
  echo "[4bit] nvidia cu12 libs already installed."
fi

# ── 5. libopenblas0 (torch links libopenblas.so.0) ──────────────────────────
if ! ldconfig -p 2>/dev/null | grep -q 'libopenblas.so.0'; then
  echo "[4bit] installing libopenblas0 (sudo)…"
  echo "[4bit] (needs sudo; enter password if prompted)"
  sudo apt-get install -y libopenblas0
else
  echo "[4bit] libopenblas0 already present."
fi

# ── 5b. swap (8GB + desktop leaves <1GB free → inference OOM-kills; 4GB swap gives headroom) ─
if [ "$(swapon --show 2>/dev/null | wc -l)" -le 0 ]; then
  echo "[4bit] creating 4GB swapfile (prevents OOM-kill on 8GB+desktop)…"
  echo "[4bit] (needs sudo)"
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile >/dev/null
  sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  echo "[4bit] swap enabled: $(swapon --show 2>/dev/null | tail -1)"
else
  echo "[4bit] swap already present."
fi

# ── 6. inference deps + fastapi/uvicorn/multipart ──────────────────────────
if ! "$PY" -c 'import bitsandbytes, transformers, fastapi, uvicorn' 2>/dev/null; then
  echo "[4bit] installing inference deps + fastapi/uvicorn/multipart…"
  UV_SKIP_WHEEL_FILENAME_CHECK=1 uv pip install --python "$PY" \
    bitsandbytes "numpy>=1.25,<2" "transformers==4.57.1" "tokenizers==0.22.0" \
    "sentencepiece==0.2.0" "accelerate==1.5.2" "peft==0.12.0" pillow safetensors \
    huggingface_hub "timm>=1.0.11" einops einops-exts "scipy>=1.10.0" \
    "scikit-learn>=1.2.2" scikit-image imagehash opencv-python-headless \
    filetype shortuuid "pydantic==2.7.1" lmdb fastapi uvicorn python-multipart
else
  echo "[4bit] inference deps already installed."
fi

# ── 7. torchvision stub (no aarch64 wheel works vs Jetson torch) ────────────
SP="$LA4BIT_DIR/.venv/lib/python3.10/site-packages"
if [ ! -f "$SP/torchvision/transforms/v2/functional.py" ]; then
  echo "[4bit] creating torchvision stub…"
  rm -rf "$SP/torchvision" "$SP"/torchvision-*.dist-info
  mkdir -p "$SP/torchvision/transforms/v2" "$SP/torchvision/io"
  cat > "$SP/torchvision/__init__.py" <<'PYEOF'
__version__ = "0.20.1"
from . import transforms  # noqa
PYEOF
  cat > "$SP/torchvision/transforms/functional.py" <<'PYEOF'
import numpy as np, torch
from PIL import Image
from enum import Enum
class InterpolationMode(Enum):
    NEAREST=0; NEAREST_EXACT=1; BILINEAR=2; BICUBIC=3; BOX=4; HAMMING=5; LANCZOS=6
_PIL={0:Image.NEAREST,1:Image.NEAREST,2:Image.BILINEAR,3:Image.BICUBIC,4:Image.BOX,5:Image.HAMMING,6:Image.LANCZOS}
def to_tensor(pic):
    if isinstance(pic, Image.Image):
        if pic.mode=="I;16": a=np.array(pic,dtype=np.int32)
        elif pic.mode=="I": a=np.array(pic,dtype=np.int32)
        elif pic.mode=="F": a=np.array(pic,dtype=np.float32)
        else: a=np.array(pic,dtype=np.uint8)
        t=torch.from_numpy(a)
        if t.ndim==2: t=t.unsqueeze(-1)
        t=t.permute(2,0,1).contiguous()
        return t.float().div(255.0) if t.dtype==torch.uint8 else t
    if isinstance(pic, np.ndarray):
        t=torch.from_numpy(pic.copy())
        if t.ndim==2: t=t.unsqueeze(-1)
        if t.ndim==3: t=t.permute(2,0,1).contiguous()
        return t.float().div(255.0) if t.dtype==torch.uint8 else t
    if torch.is_tensor(pic): return pic
    raise TypeError(f"to_tensor: unsupported {type(pic)}")
def normalize(tensor, mean, std):
    d=tensor.dtype
    mean=torch.as_tensor(mean,dtype=d,device=tensor.device).view(-1,1,1)
    std=torch.as_tensor(std,dtype=d,device=tensor.device).view(-1,1,1)
    return tensor.sub(mean).div(std)
def resize(img, size, interpolation=InterpolationMode.BILINEAR, max_size=None, antialias=True):
    if isinstance(img, Image.Image):
        if isinstance(size,int): size=(size,size)
        m=interpolation.value if isinstance(interpolation,InterpolationMode) else interpolation
        return img.resize(size[::-1], _PIL.get(m, Image.BILINEAR))
    raise TypeError(f"resize: unsupported {type(img)}")
PYEOF
  cat > "$SP/torchvision/transforms/__init__.py" <<'PYEOF'
from . import functional as F  # noqa
from .functional import InterpolationMode  # noqa
PYEOF
  cat > "$SP/torchvision/transforms/v2/__init__.py" <<'PYEOF'
from ..functional import InterpolationMode  # noqa
from . import functional  # noqa
PYEOF
  cat > "$SP/torchvision/transforms/v2/functional.py" <<'PYEOF'
from ..functional import to_tensor, normalize, resize, InterpolationMode  # noqa
PYEOF
  cat > "$SP/torchvision/io/__init__.py" <<'PYEOF'
def read_video(*a, **k):
    raise NotImplementedError("torchvision stub: video unavailable on aarch64 Jetson")
PYEOF
else
  echo "[4bit] torchvision stub already present."
fi

# ── 7b. decord stub (no aarch64 wheel; model imports it for video only) ────
if [ ! -f "$SP/decord.py" ]; then
  echo "[4bit] creating decord stub…"
  cat > "$SP/decord.py" <<'PYEOF'
class VideoReader:
    def __init__(self, *a, **k):
        raise NotImplementedError("decord stub: no aarch64 wheel; video unavailable")
class cpu: pass
class gpu: pass
def ndarray(*a, **k):
    raise NotImplementedError("decord stub")
PYEOF
else
  echo "[4bit] decord stub already present."
fi

# ── 7c. patch transformers NEAREST_EXACT (old torchvision lacks it; stub has it) ─
IU="$SP/transformers/image_utils.py"
if [ -f "$IU" ] && grep -q 'InterpolationMode.NEAREST_EXACT' "$IU" 2>/dev/null; then
  echo "[4bit] patching transformers image_utils.py NEAREST_EXACT → getattr fallback…"
  sed -i 's/InterpolationMode\.NEAREST_EXACT/getattr(InterpolationMode, "NEAREST_EXACT", InterpolationMode.NEAREST)/g' "$IU"
else
  echo "[4bit] transformers NEAREST_EXACT patch already applied (or file absent)."
fi

# ── 8. bake LD_LIBRARY_PATH + HF-offline into venv activate ────────────────
ACT="$LA4BIT_DIR/.venv/bin/activate"
if ! grep -q 'LOCATE_ANYTHING_LD_LIBRARY_PATH' "$ACT" 2>/dev/null; then
  echo "[4bit] baking LD_LIBRARY_PATH + HF-offline into venv activate…"
  NVLIB="$LA4BIT_DIR/.venv/lib/python3.10/site-packages/nvidia"
  cat >> "$ACT" <<EOF

# locate-anything-4bit: CUDA 12 runtime libs for v61 torch on R39/CUDA13.2
export LOCATE_ANYTHING_LD_LIBRARY_PATH="$NVLIB/cuda_runtime/lib:$NVLIB/cublas/lib:$NVLIB/cuda_nvrtc/lib:$NVLIB/nvjitlink/lib:$NVLIB/cufft/lib:$NVLIB/cusparselt/lib:$NVLIB/nvtx/lib:$NVLIB/cuda_cupti/lib:/usr/local/cuda/targets/sbsa-linux/lib:/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu"
export LD_LIBRARY_PATH="\$LOCATE_ANYTHING_LD_LIBRARY_PATH:\$LD_LIBRARY_PATH"
# locate-anything-4bit: huggingface.co unreachable; use cache + mirror
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export HF_ENDPOINT=https://hf-mirror.com
export HF_HUB_DISABLE_XET=1
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
EOF
else
  echo "[4bit] activate already configured (LD_LIBRARY_PATH + HF-offline)."
fi

# ── 9. download model (7.3GB, hf-mirror, xet disabled, resume-capable) ─────
if [ ! -d "$HOME/.cache/huggingface/hub/models--nvidia--LocateAnything-3B" ] || \
   ! ls "$HOME/.cache/huggingface/hub/models--nvidia--LocateAnything-3B/snapshots/"*/model-*.safetensors >/dev/null 2>&1; then
  echo "[4bit] downloading model $MODEL_ID (~7.3GB via hf-mirror, first time ~45min)…"
  HF_ENDPOINT=https://hf-mirror.com HF_HUB_DISABLE_XET=1 \
    uvx --from huggingface_hub hf download "$MODEL_ID"
else
  echo "[4bit] model already cached."
fi

# ── 10. copy web_ui.py + run_web_ui.py ─────────────────────────────────────
echo "[4bit] copying web_ui.py + run_web_ui.py…"
cp -f "$SCRIPT_DIR/web_ui.py" "$LA4BIT_DIR/web_ui.py"
cp -f "$SCRIPT_DIR/run_web_ui.py" "$LA4BIT_DIR/run_web_ui.py"
chmod +x "$LA4BIT_DIR/web_ui.py" "$LA4BIT_DIR/run_web_ui.py"

# ── verify ──────────────────────────────────────────────────────────────────
echo "[4bit] verifying torch+cuda…"
( source "$ACT" 2>/dev/null
  "$PY" -c 'import torch,transformers,bitsandbytes,fastapi;print("torch",torch.__version__,"| cuda",torch.cuda.is_available())' )

echo ""
echo "=== [4bit] provisioning complete: $LA4BIT_DIR ==="
echo "Run:   reComputer run locateanything   (or: cd $LA4BIT_DIR && source .venv/bin/activate && python run_web_ui.py)"
echo "Open:  http://<jetson-ip>:7860"
