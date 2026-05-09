# Jetson-Example: Run Gemma4 on NVIDIA Jetson

This example runs **Gemma4 E4B** on Jetson Orin with a prebuilt `llama.cpp` Docker image and exposes an OpenAI-compatible API server.

It uses:
- a prebuilt Docker image archive from a public OneDrive/SharePoint link
- `unsloth/gemma-4-E4B-it-GGUF` in `Q4_K_M` format

Supported JetPack/L4T targets:
- JetPack 6.1 -> L4T 36.3.0
- JetPack 6.2 -> L4T 36.4.0
- JetPack 6.2.1 -> L4T 36.4.3 / 36.4.4

## Usage

Start the demo:

```sh
reComputer run gemma4
```

The first run installs missing runtime dependencies, downloads the image archive with `aria2c`, imports the Docker image, downloads the model, and starts the server on:

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
    "model": "gemma",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 512
  }'
```

Python example:

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:8080/v1", api_key="none")
response = client.chat.completions.create(
    model="gemma",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

## Environment Variables

- `GEMMA4_PORT`: host port, default `8080`
- `GEMMA4_CTX_SIZE`: context length, default `8192`
- `GEMMA4_GPU_LAYERS`: override automatic GPU layer selection
- `GEMMA4_MODELS_DIR`: model cache directory, default `$HOME/models`
- `GEMMA4_CACHE_DIR`: Docker archive cache directory, default `$HOME/.cache/jetson-examples/gemma4`
- `GEMMA4_IMAGE_ARCHIVE_NAME`: cached Docker archive filename, default `gemma4-jetson.tar`
- `GEMMA4_IMAGE_SHARE_URL`: OneDrive/SharePoint public share link override
- `GEMMA4_IMAGE_ARCHIVE_URL`: direct image archive URL override
- `GEMMA4_IMAGE_NAME`: expected Docker image tag, default `llama-jetson`

## Cleanup

Stop and remove the container:

```sh
reComputer clean gemma4
```

The downloaded image archive, Docker image, and model cache are kept for faster startup next time.
