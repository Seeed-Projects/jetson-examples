# LocateAnything-3B Web UI — Jetson Example (Docker)

Real-time object detection web UI powered by NVIDIA **LocateAnything-3B** (a 3B-parameter vision-language model with MoonViT + Qwen2 + MTP decoding). Upload a video or image, type a natural-language prompt (e.g. `"a person"`, `"cat"`, `"red car"`), and see bounding boxes streamed in real time.

Runs entirely inside a **Docker container** — no host Python/conda pollution.

<p align="center">
  <img src="images/lca.gif" alt="LocateAnything-3B real-time detection demo">
</p>

## Supported Devices

| JetPack | L4T | Device |
|---------|-----|--------|
| 7.0 | 38.1.0 | Jetson Thor |
| 7.1 | 38.2.0 | Jetson Thor |
| 7.0.1 | 38.4.0 | reComputer Thor J6015 |
| 7.2 | 39.2.0 | Jetson Thor |

> **Why Thor only?** LocateAnything-3B uses CUDA 13.0 + sm_120 GPU architecture, exclusive to JetPack 7 / Thor.

**Requirements:** 16 GB RAM, 20 GB free disk, Docker + NVIDIA Container Runtime.

## Quick Start

### One-command run

```sh
pip3 install jetson-examples
reComputer run locateanything
```

**First run** (`init.sh`):
1. Builds the Docker image `locateanything:latest` (~30 min — downloads PyTorch 2.12.1 + CUDA 13.0 wheels, ~5GB)
2. Creates a model cache volume `locateanything-models`

**Every run** (`run.sh`):
1. Starts the container with GPU access
2. First time: downloads the 7.3GB model into the volume (~15 min)
3. Starts the web UI server on port 7860

Subsequent runs are fast — image and model are cached.

### Open the Web UI

```
http://<jetson-ip>:7860
```

## Usage

1. **Upload** a video or image (drag & drop, or click browse)
2. **Type** a detection prompt, e.g. `a person`, `cat`, `red car`
3. Click **Run** — boxes stream in real time
4. Adjust **Detect 1/N frames** slider for speed vs. accuracy

## Custom Port

```sh
PORT=8080 reComputer run locateanything
```

## Tuning Knobs

Environment variables (set before `reComputer run`):

| Variable | Default | Effect |
|----------|---------|--------|
| `LA3B_VIDEO_DIM` | 512 | Max image dimension fed to model (smaller = faster) |
| `LA3B_VIDEO_TOK` | 16 | MTP max new tokens (more = more boxes per frame) |
| `LA3B_DETECT_SKIP` | 5 | Detect every N-th frame (higher = faster, less accurate) |
| `LA3B_MODEL` | nvidia/LocateAnything-3B | HF repo id or local path |

Example:
```sh
LA3B_VIDEO_DIM=384 LA3B_DETECT_SKIP=3 reComputer run locateanything
```

## File Structure

```
locateanything/
├── Dockerfile           # Self-contained image (torch + CUDA + web UI)
├── init.sh              # Build image + create model volume
├── run.sh               # Run container with GPU + model volume
├── config.yaml          # JetPack version + resource requirements
├── locate_web_ui.py     # The FastAPI + WebSocket web UI
├── .dockerignore        # Exclude non-build files from context
└── README.md            # This file
```

## How It Works

- **Image**: `arm64v8/ubuntu:24.04` base + PyTorch 2.12.1 (with bundled CUDA 13.0 runtime) + transformers + FastAPI + the `locateanything-batch` engine. ~6GB.
- **Model**: Downloaded at runtime into a named Docker volume `locateanything-models` (7.3GB, persists across restarts).
- **GPU**: `--runtime=nvidia` mounts the host GPU driver; torch's bundled CUDA runtime handles the rest.
- **Inference**: `locateanything-batch` — a batched, KV-cached fork of the stock MTP decode loop (3-5× faster than batch=1).
- **Streaming**: JPEG frames + bounding boxes over WebSocket at source-video rate.

## Build Details

The Dockerfile uses BuildKit cache mounts (`--mount=type=cache`) so the build is **resumable** — if it fails mid-download, re-running `reComputer run locateanything` resumes from the pip cache instead of restarting.

The pip install is split into 3 layers (torch, torchvision+triton, web deps) so a failure in one layer doesn't lose the others.

## Troubleshooting

### Build fails / crashes
Re-run `reComputer run locateanything`. The BuildKit cache persists downloaded wheels, so the build resumes where it left off.

### `CUDA error: no kernel image`
Your JetPack version doesn't support CUDA 13.0 / sm_120. This example requires JetPack 7 (Thor). Check:
```sh
cat /etc/nv_tegra_release  # must show R38.x or R39.x
```

### Model download fails
Re-run — the HuggingFace cache in the volume resumes the download.

### Low FPS
- Increase `LA3B_DETECT_SKIP` (e.g. `LA3B_DETECT_SKIP=8`)
- Decrease `LA3B_VIDEO_DIM` (e.g. `LA3B_VIDEO_DIM=384`)

## References

- [LocateAnything-3B-batch](https://github.com/liuwang97/LocateAnything-3B-batch) — batched inference engine
- [nvidia/LocateAnything-3B](https://huggingface.co/nvidia/LocateAnything-3B) — model on HuggingFace
