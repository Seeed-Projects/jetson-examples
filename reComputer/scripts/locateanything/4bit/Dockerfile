# 4-bit LocateAnything Web UI image for low-memory Jetson (Orin Nano 8G / NX, <16GB).
# Mirrors the bf16 reference Dockerfile structure but uses the verified 4-bit env
# (torch v61 redist wheel cu124/SM8.7 + nvidia-*-cu12 runtime libs + bitsandbytes
# + torchvision/decord stubs + LD_LIBRARY_PATH + device_map={":cuda"} fix).
# NOTE: no `# syntax=docker/dockerfile:1` — that frontend image is pulled from
# docker.io (unreachable in CN); Docker 29's built-in buildkit supports --mount.
FROM arm64v8/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# System deps: +libopenblas0 (v61 torch links libopenblas.so.0) +curl (fetch wheel) + opencv libs
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip libgomp1 libgl1 libglib2.0-0 libopenblas0 git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# uv (v61 torch wheel is cp310; Ubuntu 24.04 system python is 3.12 → use uv's 3.10)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

RUN uv python install 3.10 && uv venv --python 3.10 /opt/la4bit
ENV PATH="/opt/la4bit/bin:${PATH}"
ENV VIRTUAL_ENV=/opt/la4bit

# torch v61 redist wheel (cp310, cu124, SM8.7) — COPY the pre-downloaded wheel now
# but install it LAST (after the deps below). Reason: uv's resolver treats the
# Jetson wheel as a pre-release (2.5.0a0+nv24.08) and would "upgrade" it to the
# latest stable torch (e.g. 2.13.0+cu130, which does NOT support Orin CC 8.7 and
# trips the nvmlDeviceGetGpuFabricInfoV_ assert). Installing the wheel after the
# deps with --no-deps --prerelease=allow force-overwrites torch back to the
# Jetson build. (The bare name "torch.whl" fails uv's must-have-version check;
# we rename to the wheel's real PEP-440 filename. That filename's build-number
# (.17622132) differs from the wheel METADATA version (nv24.8), so we also set
# UV_SKIP_WHEEL_FILENAME_CHECK=1 to skip uv's version-match check — the very
# check uv names in its error message for this NVIDIA wheel.)
COPY torch.whl /tmp/torch.whl

# nvidia-*-cu12 surgical set — COMPLETE for the v61 torch sonames:
# libcudart(cuda_runtime) libcublas(cublas) libcudnn(cudnn) libcufft(cufft)
# libcusparse(cusparse) libcurand(curand) libnvrtc(cuda_nvrtc) libnvJitLink(nvjitlink)
# libcusparseLt(cusparselt) libcupti(cuda_cupti) libnvToolsExt(nvtx<12.6).
# (older nvtx<12.6 ships libnvToolsExt.so.1; the v61 torch links cu12 sonames)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --index-url https://mirrors.aliyun.com/pypi/simple/ \
    nvidia-cuda-runtime-cu12 nvidia-cublas-cu12 nvidia-cudnn-cu12 nvidia-cufft-cu12 \
    nvidia-cusparse-cu12 nvidia-curand-cu12 nvidia-cuda-nvrtc-cu12 nvidia-nvjitlink-cu12 \
    nvidia-cusparselt-cu12 nvidia-cuda-cupti-cu12 "nvidia-nvtx-cu12<12.6"

# bitsandbytes (4-bit NF4) + inference deps + fastapi/uvicorn/multipart.
# NOTE: this step pulls a stable torch (2.13.0+cu130) as a transitive dep of
# bitsandbytes/transformers/accelerate — it is overwritten by the Jetson wheel
# in the next RUN. The cu13 libs it pulls coexist (different sonames) and are
# simply unused (LD_LIBRARY_PATH points at the cu12 dirs above).
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --index-url https://mirrors.aliyun.com/pypi/simple/ \
    bitsandbytes "numpy>=1.25,<2" "transformers==4.57.1" "tokenizers==0.22.0" "sentencepiece==0.2.0" \
    "accelerate==1.5.2" "peft==0.12.0" pillow safetensors huggingface_hub "timm>=1.0.11" \
    einops einops-exts "scipy>=1.10.0" "scikit-learn>=1.2.2" scikit-image imagehash \
    opencv-python-headless filetype shortuuid "pydantic==2.7.1" lmdb fastapi uvicorn python-multipart

# Force-install the Jetson v61 torch wheel OVER the stable torch pulled above.
# --no-deps: torch's python deps (sympy/networkx/jinja2/...) are already satisfied.
# --prerelease=allow: let uv accept the 2.5.0a0 pre-release for this explicit install.
# Also drop triton (pulled by the stable torch) — the Jetson torch has no triton
# on aarch64 and the leftover 3.x raises a noisy compile_worker ImportError.
RUN mv /tmp/torch.whl "/tmp/torch-2.5.0a0+872d972e41.nv24.08.17622132-cp310-cp310-linux_aarch64.whl" \
    && export UV_SKIP_WHEEL_FILENAME_CHECK=1 \
    && uv pip install --no-deps --prerelease=allow \
       "/tmp/torch-2.5.0a0+872d972e41.nv24.08.17622132-cp310-cp310-linux_aarch64.whl" \
    && rm "/tmp/torch-2.5.0a0+872d972e41.nv24.08.17622132-cp310-cp310-linux_aarch64.whl" \
    && (uv pip uninstall triton >/dev/null 2>&1 || true)

# cuDNN consistency fix: step #10 installed nvidia-cudnn-cu12 (9.24.0.43) and the
# deps step pulled nvidia-cudnn-cu13 (9.20.0.48) transitively — both write
# libcudnn*.so.9 into nvidia/cudnn/lib/, mixing sublib versions and tripping
# CUDNN_STATUS_SUBLIBRARY_VERSION_MISMATCH at the first conv. Remove both, wipe
# the dir, reinstall ONE consistent version (9.20.0.48 == the JetPack/host cuDNN
# 9.20.0 the v61 torch was built against; verified: inference runs clean).
RUN uv pip uninstall nvidia-cudnn-cu12 nvidia-cudnn-cu13 >/dev/null 2>&1 || true \
    && rm -rf /opt/la4bit/lib/python3.10/site-packages/nvidia/cudnn/lib/* \
    && uv pip install --no-deps --index-url https://mirrors.aliyun.com/pypi/simple/ nvidia-cudnn-cu13==9.20.0.48

# torchvision stub (no aarch64 wheel works vs the Jetson torch) + decord stub
# (build context = 4bit/ dir, so COPY paths are relative to it)
COPY stubs/torchvision /opt/la4bit/lib/python3.10/site-packages/torchvision
COPY stubs/decord.py /opt/la4bit/lib/python3.10/site-packages/decord.py

# transformers NEAREST_EXACT → getattr fallback (old torchvision lacks NEAREST_EXACT; stub has it but keep the patch)
RUN sed -i 's/InterpolationMode\.NEAREST_EXACT/getattr(InterpolationMode, "NEAREST_EXACT", InterpolationMode.NEAREST)/g' \
    /opt/la4bit/lib/python3.10/site-packages/transformers/image_utils.py || true

# LD_LIBRARY_PATH → the cu12 runtime libs the v61 torch links (libcudart.so.12,
# libcublas.so.12, libcudnn.so.9, libcufft.so.11, libcusparse.so.12,
# libcurand.so.10, libnvrtc/libnvJitLink/libcusparseLt/libcupti/libnvToolsExt).
# cudnn/cusparse/curand MUST be listed — the v61 torch links them but the base
# image has none; without these dirs torch import fails at libcudnn.so.9.
ENV LD_LIBRARY_PATH="/opt/la4bit/lib/python3.10/site-packages/nvidia/cuda_runtime/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/cublas/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/cudnn/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/cufft/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/cusparse/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/curand/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/cuda_nvrtc/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/nvjitlink/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/cusparselt/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/nvtx/lib:/opt/la4bit/lib/python3.10/site-packages/nvidia/cuda_cupti/lib"
# HF mirror (NOT offline — first run must download the 7.3GB model into the volume)
ENV HF_ENDPOINT=https://hf-mirror.com
ENV HF_HUB_DISABLE_XET=1
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

WORKDIR /app
COPY web_ui.py run_web_ui.py /app/

EXPOSE 7860
# run_web_ui.py: device-detects MAX_SIDE (sees host /proc via --network=host), sets alloc-conf, auto-restart on crash
ENTRYPOINT ["python", "-u", "run_web_ui.py"]
