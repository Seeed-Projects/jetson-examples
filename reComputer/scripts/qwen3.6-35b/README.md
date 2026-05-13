# Jetson-Example: Run Qwen3.6-35B on NVIDIA Jetson

This example runs **Qwen3.6-35B** (UD-Q6_K quantization) on Jetson Orin with **llama.cpp** and exposes an OpenAI-compatible API server.

> **Hardware Requirement:** This model requires an **AGX Orin 64G** module (or equivalent 64GB system memory). Running on smaller devices (e.g. Orin NX, Orin Nano) will fail due to insufficient memory.

It uses:
- The prebuilt Docker image `chenduola6/llama-jetson:latest`
- The `unsloth/Qwen3.6-35B-A3B-GGUF` model in `Qwen3.6-35B-A3B-UD-Q6_K.gguf` format

Supported JetPack/L4T targets:
- JetPack 6.1 -> L4T 36.3.0
- JetPack 6.2 -> L4T 36.4.0
- JetPack 6.2.1 -> L4T 36.4.3 / 36.4.4

## Getting Started

### Prerequisites
- NVIDIA Jetson AGX Orin **64G** module
- Docker installed and available
- `aria2` installed

### Installation

PyPI:
```sh
pip install jetson-examples
```

GitHub:
```sh
git clone https://github.com/Seeed-Projects/jetson-examples
cd jetson-examples
pip install .
```

## Usage

Start the demo:

```sh
reComputer run qwen3.6-35b
```

The first run downloads the model, then starts the server on:

```
http://127.0.0.1:8080
```

Check the model list:

```sh
curl http://127.0.0.1:8080/v1/models
```

Chat via OpenAI-compatible API:

```sh
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.6-35b-a3b",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 512
  }'
```

Python example:

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:8080/v1", api_key="none")
response = client.chat.completions.create(
    model="qwen3.6-35b-a3b",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

## Environment Variables

| Variable             | Description                              | Default                        |
|----------------------|------------------------------------------|-------------------------------|
| `QWEN36_PORT`        | Host port for the API server             | `8080`                        |
| `QWEN36_CTX_SIZE`    | Context window size                      | `8192`                        |
| `QWEN36_GPU_LAYERS`  | Override automatic GPU layer selection   | auto (999 on 64G, 80 on 32G)  |
| `QWEN36_MODELS_DIR`  | Model cache directory                    | `$HOME/models`                |

## Cleanup

Stop and remove the container:

```sh
reComputer clean qwen3.6-35b
```

The downloaded model cache is kept for faster startup next time.
