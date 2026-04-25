# Jetson-Example: Run Qwen3.5-4B on NVIDIA Jetson

This example runs **Qwen3.5-4B** on Jetson Orin with **llama.cpp** and exposes an OpenAI-compatible API server.

It uses:
- a prebuilt Docker image archive imported locally on first run
- the `unsloth/Qwen3.5-4B-GGUF` model in `Q4_K_M` format

Supported JetPack/L4T targets:
- JetPack 6.1 -> L4T 36.3.0
- JetPack 6.2 -> L4T 36.4.0
- JetPack 6.2.1 -> L4T 36.4.3 / 36.4.4

Test status:
- validated on JetPack 6.2
- expected to work on JetPack 6.1 to 6.2.1

## Getting Started

### Prerequisites
- NVIDIA Jetson Orin device
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
reComputer run qwen3.5-4b
```

The first run downloads the image archive and model, then starts the server on:

```text
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
    "model": "qwen",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 512
  }'
```

Python example:

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:8080/v1", api_key="none")
response = client.chat.completions.create(
    model="qwen",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

## Environment Variables

- `QWEN35_PORT`: host port, default `8080`
- `QWEN35_CTX_SIZE`: context length, default `8192`
- `QWEN35_GPU_LAYERS`: override automatic GPU layer selection
- `QWEN35_MODELS_DIR`: model cache directory, default `$HOME/models`

## Cleanup

Stop and remove the container:

```sh
reComputer clean qwen3.5-4b
```

The downloaded image and model cache are kept for faster startup next time.
