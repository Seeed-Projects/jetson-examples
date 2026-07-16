# locateanything-batch

**Batched + KV-cached inference for [NVIDIA LocateAnything-3B](https://huggingface.co/nvidia/LocateAnything-3B).**

The model ships a custom `generate` that **hard-asserts `batch == 1`** — you can only ground one
(image, query) pair at a time. The underlying Qwen2 LM and the vision encoder are perfectly
batch-safe; the lock lives only in the hand-rolled multi-token-prediction (MTP) decode loop.

This package is a faithful **batched fork** of that loop (restricted to `generation_mode='fast'`,
i.e. pure MTP, no autoregressive fallback). Under greedy decoding it is **numerically equivalent to
running each pair at `batch=1`** — same boxes, just many at once, with the image/prefill KV cache
shared across queries on the same image.

```python
from locateanything_batch import load, generate_batch, load_pil

load()                                              # lazily downloads / loads the model
img = load_pil("photo.jpg")
[answer] = generate_batch([(img, "a dog")])
print(answer)   # ... <box><312><144><688><902></box> ...
```

## Benchmark — MTP vs the community AR ports

End-to-end grounding throughput on one **RTX 5070 Ti (16 GB)** — single clean detection
per image, greedy, **batch 8**, precision-matched. Reproduce the MTP row with
[`examples/benchmark.py`](examples/benchmark.py); full method + raw data + the AR-port
harnesses are in [`examples/_bench_results/COMPARISON.md`](examples/_bench_results/COMPARISON.md).

| Implementation | decode | precision | **img/s** | ms/img |
|---|---|---|---:|---:|
| **`locateanything-batch` (this repo)** | **fast-MTP + batched** | bf16 | **4.53** | **221** |
| llama.cpp (`yuuko-eth` *mtmd-grounders*) | autoregressive | BF16 | 2.61 | 383 |
| vLLM (`WuNein/LocateAnything-vLLM`) | autoregressive | fp16 | 1.02 | 977 |

**~1.7× faster than llama.cpp, ~4.4× faster than vLLM**, end to end — and it's the only one
that runs the model's *native* multi-token-prediction path. All three decode the **identical
box**; the two community ports drop MTP and fall back to plain autoregression.

### Why it's this fast

For a short grounding output, **end-to-end time is dominated by vision-encode + prefill, not
decode** — so the win is in batching the *front* of the pipeline, which the MTP loop here does
and the AR ports don't:

- **Batched vision encode** — all images packed into one MoonViT `extract_feature` (flash
  varlen, block-diagonal): bit-identical to per-image but **2.6–3×**. The vLLM port instead runs
  vision *client-side, serially per image* — that alone is **~82%** of its end-to-end time.
- **Batched shared-prefix prefill** — the ~700-token image+instruction prefix is GPU-starved at
  batch 1; one batched prefill is **~3.6×**.
- **Multi-token (MTP) decode** — the model's own fast path emits a *whole box per accepted step*
  (k∈{1,3,4,6}), not one token at a time. The community ports don't implement it.
- **No per-row CPU syncs** — sampler + box decode run once over the whole `[B,6,V]` step on-GPU
  (greedy bit-exact).

> Quantization aside: llama.cpp's Q4_K_M is ~2× faster *single-stream decode* than BF16 (pure
> memory bandwidth) — but that edge collapses under batching, doesn't move the prefill-bound E2E,
> and degraded output quality on this model. The precision-matched **BF16** row above is the fair
> comparison.

## Why

| | stock `generate` | `locateanything-batch` |
|---|---|---|
| batch size | 1 (asserted) | arbitrary list of (image, query) pairs |
| same image, many queries | re-encode + re-prefill each time | vision + `[image+instruction]` prefix encoded **once**, forked across queries |
| vision encode | per image | one packed `extract_feature` (block-diagonal, exact) when flash is present |
| decode | per pair | one batched MTP step over all rows |

On an RTX 5070Ti (sm_120) the batched path measured roughly **2.6–3×** on the vision encode and
**~3.6×** on the shared-prefix prefill versus looping at `batch=1`. Your mileage depends on GPU,
image size, and whether a `flash-attn` wheel is installed (see [Hardware notes](#hardware-notes)).

## Features

- **True batching** — `generate_batch(pairs)` over a heterogeneous list of (PIL image, query string).
- **Prefix / vision reuse** — `generate_batch_grouped(groups)` shares the per-image prefill KV across
  that image's queries.
- **Numerically exact** under greedy (`temperature=0`): bit-identical box decode to the stock batch-1 path.
- **Per-row temperatures** — `temps=[...]` lets one batch cover N prompts × M temperatures.
- **Tunable** — several independent batching optimizations, each toggleable via an env var, all on by default.

## Requirements

- **NVIDIA GPU + CUDA.** The engine runs on `cuda` in bfloat16; there is no CPU path.
- **PyTorch matching your CUDA.** This package depends on `torch>=2.4` but does **not** pin a CUDA build
  — install the wheel for your toolkit yourself, e.g. from <https://pytorch.org/get-started/locally/>.
- **The model**, `nvidia/LocateAnything-3B` (~7.8 GB). It is loaded with `trust_remote_code=True`
  (it ships its own modeling code). By default it is fetched from the Hugging Face Hub on first use;
  set `HF_HUB_OFFLINE=1` to read your local HF cache only (air-gapped / already-downloaded runs).
- **Python ≥ 3.10**, `transformers>=4.57,<5` (the model's remote code is bound to the 4.x API).

## Install

```bash
# 1) install torch for your CUDA first (example: CUDA 12.4)
pip install torch --index-url https://download.pytorch.org/whl/cu124

# 2) then this package
pip install locateanything-batch              # or:  pip install -e .   (from a clone)
pip install "locateanything-batch[example]"   # adds opencv for the drawing example
pip install "locateanything-batch[flash]"     # vision flash kernel — see the speed warning below
```

> **⚠️ Install `flash-attn` for full speed.** Without a working `flash-attn`, the batched vision
> encode falls back to a per-image path and the engine runs **~30% slower end-to-end**. It is still
> *optional* (everything works without it, results are bit-identical), but on a supported GPU you
> really want it. PyPI has **no** prebuilt wheel for newer stacks (e.g. sm_120 / cu128 / torch 2.11),
> so `[flash]` would compile from source there — install a matching **prebuilt** wheel instead:
> ```bash
> pip install flash-attn==2.8.3+cu128torch2.11 --no-build-isolation   # example for RTX 50-series / cu128
> ```

> The model download happens lazily on the first `load()`. To pre-stage it offline, download
> `nvidia/LocateAnything-3B` into your HF cache once, then run with `HF_HUB_OFFLINE=1`.

## API

### `generate_batch(pairs, *, temperature=0.0, top_p=None, top_k=None, repetition_penalty=1.0, max_new_tokens=384) -> list[str]`
`pairs` = `[(PIL.Image, query_str), ...]`. Returns one decoded answer string per pair, in order.
Different prompt lengths are handled (left-padding). This is the simplest entry point.

```python
out = generate_batch([(img1, "a dog"), (img2, "a red car"), (img1, "a bicycle")])
```

### `generate_batch_grouped(groups, *, temperature=0.0, ..., temps=None) -> list[list[str]]`
`groups` = `[(PIL.Image, [query, ...]), ...]`. For each image the `[image + instruction]` prefix is
vision-encoded and prefilled **once** and forked to all that image's queries; only the differing
query tails + decode are batched across every row of every group. Returns a list aligned with
`groups`, each a list of one answer per query. `temps` (optional) is a flat per-row temperature
vector in row order (the concatenation of each group's queries).

```python
res = generate_batch_grouped([(img, ["a dog", "a cat"]), (img2, ["a person", "a bicycle"])])
# res == [["...dog...", "...cat..."], ["...person...", "...bicycle..."]]
```

> Each query must have a **non-empty tail** after the shared prefix, so `generate_batch_grouped`
> needs ≥ 2 distinct queries per group. For a single query per image, use `generate_batch`.

### `load() -> (tokenizer, processor, model)`
Lazily loads (and caches) the model. Called automatically by the generate functions; call it
yourself to control *when* the load cost is paid (e.g. before a timed loop).

### `load_pil(path) -> PIL.Image`
Opens an image as RGB and downscales its longest side to 1024 px (the engine's `MAX_DIM`).

## Tuning knobs (environment variables)

All are read at import time. Defaults are good; override only to A/B or debug.

| Env var | Default | Effect |
|---|---|---|
| `LA3B_MODEL` | `nvidia/LocateAnything-3B` | HF repo id or local path of the model |
| `HF_HUB_OFFLINE` | unset | `1` → never hit the network; read the local HF cache only |
| `MTP_BATCH_VISION` | `1` | Pack a micro-batch's images into one vision encode (needs flash; auto-falls back per-image without it) |
| `MTP_BATCH_PREFILL` | `1` | One batched shared-prefix prefill instead of per-image |
| `MTP_BATCH_SAN` | `1` | Run the logits/sample pipeline once over `[B,6,V]` instead of per row |
| `MTP_BATCH_BOXDECODE` | `1` | Fully-GPU batched box decode (one host transfer per step instead of ~6 per row) |
| `MTP_FLASH_PREFILL` | `1` | Flash attention for *prefill* (decode always stays sdpa). Faster than sdpa on sm_120 with the batched prefill; needs `flash-attn` (auto-falls back to sdpa without it). Set `0` to force sdpa |
| `MTP_COMPILE` | `0` | `torch.compile` the shared Qwen2 core (needs `triton`; ~42 s warm / ~187 s cold to compile, ~1.14× after) |

## Benchmarks & equivalence

Recorded during development. Reproduce on your own GPU with
[`examples/bench_equivalence.py`](examples/bench_equivalence.py).

**Test setup:** NVIDIA RTX 5070 Ti (sm_120) · CUDA 12.8 / torch 2.11.0+cu128 · flash-attn 2.8.3
(vision encoder only) · `nvidia/LocateAnything-3B` in bfloat16, `generation_mode='fast'` ·
transformers 4.57.x.

### Correctness — greedy is token-exact vs the stock model

Under **greedy** decoding (`temperature=0`) the batched path must be **token-identical** to (a) the
model's own stock `generate` in fast mode and (b) running each pair singly. The gate runs 5 tiers,
each isolating one failure mode:

| Tier | What it checks |
|---|---|
| A | `B=1` new path **==** stock `model.generate` (fast, greedy) |
| B | `B=2` identical rows **==** Tier A (no cross-row contamination) |
| C | `B=2` same image / different prompts, both orders **==** each pair's single run |
| D | `B=2` different images / different prompt lengths **==** each single run |
| E | ≥3 mixed frames (ragged accept counts) **==** each single run |

**Result: 12 / 12 checks pass, 0 fail** at `repetition_penalty=1.0` — bit-exact box decode.

> At `repetition_penalty=1.15` a few checks fall back from token-exact to "box Δ ≤ 8/1000". This is
> **expected and benign**: the penalty compresses logit margins, and bf16 batched-GEMM is
> non-associative (`B≠1` changes the reduction order, measured `|Δ| ≤ ~0.4`), which can flip a tight
> argmax. The greedy `rp=1.0` gate is the exact-equivalence guarantee.

### Throughput — production scan

Real workload: video contact-sheet crops, **2 prompts per frame**, batch ≈ 32 rows with
shared-prefix + vision reuse:

| Metric | Value |
|---|---|
| Frames inspected | 49,016 |
| Inference time | 3,006.9 s |
| **Throughput** | **61.3 ms/frame · 16.3 frame/s** |
| Per-video range | ~61–64 ms/frame (stable across 146 videos) |

For comparison, the single-image (batch=1) two-pass baseline on the same crops was **~430 ms/frame**.

### Where the speedups come from

Each optimization is independently toggleable (see the [tuning knobs](#tuning-knobs-environment-variables)):

| Optimization | Speedup | Notes |
|---|---|---|
| Batched vision encode (`MTP_BATCH_VISION`) | **2.6–3×** | Block-diagonal varlen packing; **bit-identical** to per-image (`max\|Δ\| = 0.00e+00`), flat VRAM (7.87→8.20 GB across batch 1→32). Needs flash; auto-falls back per-image without it. |
| Batched shared-prefix prefill (`MTP_BATCH_PREFILL`) | **~3.6×** | The ~66-token image+instruction prefix is GPU-starved at batch=1. |
| End-to-end batched pipeline | **~2.7×** | A 15-sample (5 prompt × 3 temp) decode as one batch-15 run vs serial: ~3.1 s → ~1.1 s/image. |
| Batched sample + fully-GPU box decode (`MTP_BATCH_SAN`, `MTP_BATCH_BOXDECODE`) | — | Removes per-row GPU↔CPU syncs (~30% of wall time at batch=1). Greedy bit-exact. |

Reproduce:

```bash
pip install "locateanything-batch[example]"
python examples/bench_equivalence.py ./photos            # correctness gate + throughput sweep
python examples/bench_equivalence.py ./photos "a dog" "a cat"
```

## How it works

- **Prefill is logit-free** — it runs the base Qwen2 model (no `lm_head`), scattering the image
  embeddings and returning the KV cache, which avoids the `[B, S, V]` fp32 logit OOM.
- **Decode replicates the stock loop exactly** — each step forwards `[accepted tokens + a 6-wide
  speculative window]`, decodes a whole box with the model's *own* `sample_tokens` / `handle_pattern`,
  accepts k∈{1,3,4,6} tokens, then **truncates the window KV** (its bidirectional self-attention
  contaminates it) and keeps the accepted block's clean causal KV.
- **Ragged accept counts stay rectangular** via right-padding + a persistent 2D key-validity mask;
  `position_ids` are tracked per row (left-padding desyncs them from KV columns).
- **The box decode is never approximated** — it is the model's exact top-k validated frame decode,
  not a probability-weighted average. Greedy output is bit-identical to the stock `batch=1` path.

## Hardware notes

- **Decode is sdpa-only.** The MTP generation window is *bidirectional* (the mask zeroes the
  `[-block:, -block:]` corner), which the causal-only flash kernel cannot express. The model was
  designed to run that window on a specialized flex-attention kernel that isn't available on sm_120.
- **flash-attn is optional but worth ~30% end-to-end.** When a `flash-attn` wheel is installed,
  MoonViT's varlen path lets the cross-image vision batch be block-diagonal (exact + faster). Without
  it the engine auto-detects the absence and falls back to a per-image vision encode — everything
  still works and stays bit-identical, but the whole pipeline runs **~30% slower**. A prebuilt wheel
  *does* exist for sm_120 / RTX 50-series (e.g. `flash-attn==2.8.3+cu128torch2.11`); install it with
  `--no-build-isolation` (it is not on PyPI, so a plain source build is the only other route). Flash
  speeds the vision encode and, with the batched prefill, the LLM prefill too (`MTP_FLASH_PREFILL`,
  on by default when the wheel is present) — only decode stays sdpa either way (see the first note).
- **Warnings.** transformers may print flash/attention fallback warnings on load. The engine does not
  silence them globally (it's a library); filter them in your own process if you prefer quiet output.

## Example

[`examples/locate_objects.py`](examples/locate_objects.py) scans a folder of images, runs your
prompt(s), draws the boxes, and writes overlays + `summary.json`:

```bash
pip install "locateanything-batch[example]"
python examples/locate_objects.py ./photos "a dog"
python examples/locate_objects.py ./photos "a dog" "a person riding a bicycle" --batch 32
```

## License

Code in this repository: [MIT](LICENSE).

The **NVIDIA LocateAnything-3B model weights are NOT covered by this license.** They are distributed
by NVIDIA under their own terms — at the time of writing, a **non-commercial / research-only**
license. This MIT-licensed wrapper does not grant any rights to the model; you are responsible for
obtaining it and complying with its license:
<https://huggingface.co/nvidia/LocateAnything-3B>.

## Acknowledgements

This is a thin batched wrapper around NVIDIA's LocateAnything-3B; all the model and its decode logic
are NVIDIA's. This package only lifts the `batch == 1` restriction of the stock generation loop.

## Quick Setup on NVIDIA Jetson (Thor / Orin)

Step-by-step environment configuration to run the web UI or CLI on a Jetson devkit.

### Prerequisites

| Item | Value |
|---|---|
| Hardware | NVIDIA Jetson Thor (or Orin NX/AGX) |
| JetPack | 7.1+ (L4T 38.x / CUDA 13.0) |
| Disk | ≥ 15 GB free on `/home` |
| Internet | needed once for `conda` + `pip` + model download |

### 1 — Install Miniconda (if not already present)

```bash
mkdir -p ~/miniconda
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O ~/miniconda.sh
bash ~/miniconda.sh -b -p ~/miniconda
rm ~/miniconda.sh
~/miniconda/bin/conda init bash
source ~/.bashrc          # or open a new terminal
```

### 2 — Create the conda environment

```bash
source ~/miniconda/etc/profile.d/conda.sh

conda create -n locateanything python=3.10.12 -y
conda activate locateanything
python --version          # should print Python 3.10.12
```

### 3 — Install PyTorch (aarch64 + CUDA 13.0)

Thor ships with JetPack 7.1 / CUDA 13.0. Install the matching aarch64 wheel:

```bash
pip install --upgrade pip
pip install torch==2.12.1
```

> If the default pip index does not have the aarch64 wheel for your exact CUDA version,
> pull the NVIDIA PyTorch container and copy the wheel out:
> ```bash
> docker pull nvcr.io/nvidia/pytorch:25.06-py3
> docker create --name tmp-pytorch nvcr.io/nvidia/pytorch:25.06-py3
> docker cp tmp-pytorch:/usr/local/lib/python3.10/dist-packages/torch ./torch_wheel
> docker rm tmp-pytorch
> pip install ./torch_wheel/*.whl
> ```

### 4 — Install project dependencies

```bash
pip install transformers==4.57.6
pip install accelerate==1.14.0
pip install fastapi==0.139.0
pip install uvicorn==0.50.1
pip install pillow==12.3.0
pip install numpy==2.2.6
pip install decord==0.6.0
```

> `decord` on aarch64 may need a source build if no wheel is available:
> ```bash
> pip install decord --no-binary :all:
> ```

### 5 — Install this package

```bash
cd ~/workspace/LocateAnything-3B-batch
pip install -e .                   # editable install (recommended)
# or:  pip install locateanything-batch   (from PyPI, once published)
```

### 6 — Run the Web UI

```bash
source ~/miniconda/etc/profile.d/conda.sh
conda activate locateanything
cd ~/workspace/LocateAnything-3B-batch

LA3B_VIDEO_DIM=512 LA3B_VIDEO_TOK=16 \
python -m uvicorn examples.locate_web_ui:app --host 0.0.0.0 --port 7860
```

Open **http://&lt;Jetson-IP&gt;:7860** in a browser.

### 7 — Run CLI examples

```bash
python examples/locate_objects.py ./photos "a dog"
python examples/locate_objects.py ./photos "a dog" "a person" --batch 16
```

### 8 — Stop the service

```bash
lsof -i :7860 -t | xargs kill -9
```

### 9 — Verify the service is running

```bash
lsof -i :7860 -t 2>/dev/null && echo "RUNNING" || echo "NOT RUNNING"
```

### Environment variable reference

| Variable | Default | Description |
|---|---|---|
| `LA3B_VIDEO_DIM` | `512` | Input image resolution (higher = more accurate, slower) |
| `LA3B_VIDEO_TOK` | `16` | Max output tokens per frame (higher = more detection boxes) |
| `LA3B_MODEL` | `nvidia/LocateAnything-3B` | HF repo id or local model path |
| `HF_HUB_OFFLINE` | unset | Set `1` to use only the local HF cache (no network) |
| `MTP_BATCH_VISION` | `1` | Batch vision encode (requires `flash-attn`, auto-falls back) |
| `MTP_BATCH_PREFILL` | `1` | Batch shared-prefix prefill |
| `MTP_BATCH_SAN` | `1` | Batched sample + logit pipeline |
| `MTP_BATCH_BOXDECODE` | `1` | Fully-GPU batched box decode |

### Troubleshooting

| Symptom | Fix |
|---|---|
| `ModuleNotFoundError: No module named decord` | `pip install decord==0.6.0` (or build from source, see step 4) |
| `torch.cuda.is_available() → False` | Ensure the PyTorch wheel matches your CUDA version; use the NVIDIA container wheel route in step 3 |
| `OutOfMemoryError` | Lower `LA3B_VIDEO_DIM` to `384`; reduce `--batch` size; stop other GPU processes |
| Port 7860 already in use | `lsof -i :7860 -t \| xargs kill -9` |
| Model download stalls | Set `HF_ENDPOINT=https://hf-mirror.com` before launching |
