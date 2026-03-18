# Jetson Example: Run NVBlox on NVIDIA Jetson from a OneDrive Docker Archive

This example vendors the NVBlox setup flow into `reComputer` and uses a shared OneDrive `.tar` archive instead of `docker pull`.

On the first prepare run it will:

1. Download `nvblox_images.tar` from the built-in OneDrive share link into `~/.cache/jetson-examples/nvblox`
2. Run `docker load -i` on that archive
3. Reuse the vendored NVBlox host/container prepare scripts
4. Launch the demo

## Requirements

- NVIDIA Jetson Orin
- Ubuntu 22.04
- JetPack 6.x
- Docker with NVIDIA Container Runtime
- Orbbec Gemini2 camera
- Roughly 60GB free disk space for the cached archive, derived image, and managed workspace

## Usage

Run the full prepare + demo flow:

```sh
reComputer run nvblox
```

Prepare only:

```sh
NVBLOX_MODE=prepare reComputer run nvblox
```

Run only after preparation:

```sh
NVBLOX_MODE=run reComputer run nvblox
```

Force a rebuild of the prepared host/container workspaces:

```sh
NVBLOX_FORCE_REBUILD=1 reComputer run nvblox
```

Run headless:

```sh
NVBLOX_HEADLESS=1 reComputer run nvblox
```

Override the managed workspace root:

```sh
MANAGED_ROOT=/path/to/nvblox_demo reComputer run nvblox
```

Override the built-in OneDrive archive settings:

```sh
NVBLOX_IMAGE_SHARE_URL='https://...'
NVBLOX_IMAGE_ARCHIVE_NAME='nvblox_images.tar'
NVBLOX_IMAGE_CACHE_DIR="$HOME/.cache/jetson-examples/nvblox"
reComputer run nvblox
```

## Cleanup

```sh
reComputer clean nvblox
```

This removes the managed workspace, logs, partial downloads, the derived image `local/isaac_ros_nvblox_orbbec:jp6-humble`, and the running demo container if it exists.

It keeps:

- the cached base archive in `~/.cache/jetson-examples/nvblox`
- the loaded base image imported from `nvblox_images.tar`

## Notes

- This example does not use `docker pull` for the base image path.
- The OneDrive downloader resolves the anonymous `download.aspx?...tempauth=...` URL from the preview page before downloading.
- `NVBLOX_MODE=run` expects an already prepared `MANAGED_ROOT`.
