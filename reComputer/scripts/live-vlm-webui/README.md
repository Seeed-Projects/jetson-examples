# Jetson-Examples: Live VLM WebUI on NVIDIA Jetson

One-click deployment for **Live VLM WebUI** (real-time Vision Language Model streaming via WebRTC) on NVIDIA Jetson devices, powered by Ollama as the inference backend.

## Hardware Requirements

- NVIDIA Jetson Orin or Thor series
- At least **8 GB** system memory
- At least **15 GB** available disk space
- USB or CSI camera for live streaming (optional)

## Supported JetPack / L4T Versions

| JetPack | L4T    | Platform   |
|---------|--------|------------|
| 6.0     | 36.3.0 | Orin       |
| 6.1     | 36.4.0 | Orin       |
| 6.2     | 36.4.3 | Orin       |
| 6.2.1   | 36.4.4 | Orin       |
| 7.0     | 38.1.0 | Thor       |
| 7.1     | 38.2.0 | Thor       |

## Features

- **No custom Dockerfile** — uses official GHCR pre-built images
- **Dual-container architecture** — Ollama backend + WebUI frontend via docker compose
- **Interactive model selection** — choose from 7 pre-configured VLM models, or skip
- **Smart checks** — skips pulling already-downloaded models and re-creating existing containers
- **Automatic GPU mode detection** — supports both `--runtime nvidia` and `--gpus all`

## Prerequisites

Install the jetson-examples CLI (recommended):

```sh
pip install jetson-examples
```

Or use the source directly:

```sh
git clone https://github.com/Seeed-Projects/jetson-examples
cd jetson-examples
pip install .
```

## Usage

### One-line deployment

```sh
reComputer run live-vlm-webui
```

The script will:

1. Verify the JetPack version, disk space, and memory
2. Probe available Docker GPU mode (`--runtime nvidia`)
3. Start the Ollama container and wait for it to be healthy
4. Ask you to select a VLM model (or skip)
5. Pull the selected model if needed
6. Start the live-vlm-webui container
7. Wait for the HTTPS server on port 8090 to become ready
8. Print access URLs

### Model selection

The script presents 7 pre-configured models:

| # | Model                    | Parameters | VRAM            | Use Case           |
|---|--------------------------|------------|-----------------|--------------------|
| 1 | `gemma3:4b`              | 4B         | 6GB             | Entry-level        |
| 2 | `gemma3:12b`             | 12B        | 10GB            | Balanced           |
| 3 | `llava:7b`               | 7B         | 6GB             | Vision             |
| 4 | `llama3.2-vision:11b`    | 11B        | 14GB            | Vision             |
| 5 | `moondream:latest`       | ~1B        | 1GB             | Ultra-light vision |
| 6 | `gemma3:4b`              | 4B         | 6GB             | Entry-level        |
| 7 | `nomic-embed-text:latest` | —         | —               | Embedding (opt.)   |
| 0 | Skip (no model)          | —          | —               | Manual pull later  |

### Skip model selection (automated)

```sh
OLLAMA_MODEL=qwen2.5-vl:7b reComputer run live-vlm-webui
```

### Verify service

Open in browser:

```
https://<jetson-ip>:8090
```

Or test with curl:

```sh
curl -k https://localhost:8090
```

### Check logs

```sh
docker logs -f live-vlm-webui
docker logs -f ollama
```

### Manage models inside container

```sh
docker exec ollama ollama list
docker exec ollama ollama pull llama3.2-vision:11b
docker exec ollama ollama rm <model-name>
```

## Cleanup

Remove containers (keep images for faster next startup):

```sh
reComputer clean live-vlm-webui
```

To also remove downloaded models:

```sh
docker volume rm live-vlm-webui_ollama-data
```

## Architecture

```
reComputer run live-vlm-webui
  |
  +-- run.sh          (docker access, GPU mode detection, container management)
         |
         +-- Ollama container        :11434 (VLM inference backend)
         +-- live-vlm-webui container :8090 HTTPS (WebRTC streaming UI)
```

## Environment Variables

| Variable       | Description                                   | Default |
|----------------|-----------------------------------------------|---------|
| `OLLAMA_MODEL` | Pre-select a model, skip interactive prompt  | —       |

## References

- [live-vlm-webui](https://github.com/nvidia-ai-iot/live-vlm-webui)
- [Ollama](https://ollama.com/)
- [Seeed jetson-examples](https://github.com/Seeed-Projects/jetson-examples)
- [Jetson AI Lab](https://www.jetson-ai-lab.com/)
