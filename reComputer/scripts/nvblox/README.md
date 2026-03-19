# Jetson Example: Run NVBlox on NVIDIA Jetson from a OneDrive Docker Archive

This example vendors the NVBlox setup flow into `reComputer`, uses a shared OneDrive `.tar` archive instead of `docker pull`, and runs mobile mapping with `isaac_ros_visual_slam`.

On the first prepare run it will:

1. Download `nvblox_images.tar` from the built-in OneDrive share link into `~/.cache/jetson-examples/nvblox`
2. Run `docker load -i` on that archive
3. Reuse the vendored NVBlox host/container prepare scripts
4. Launch the mobile mapping demo

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

## Troubleshooting

- If the host Gemini2 camera stage fails, `reComputer run nvblox` now prints the tail of the host camera log, the Gemini2 device state, the current `/dev/video*` snapshot, and the readiness-probe failure details.
- If the host driver exits and the Gemini2 device falls back to `usb_present_no_video`, the run path automatically attempts one full recovery before exiting, so you can usually retry without unplugging the camera first.
- If the camera is enumerated over a low-bandwidth USB link, the run path can automatically switch to the bundled low-bandwidth host profile (`config/orbbec_vslam_mobile_low_bandwidth.yaml`) and retry once without requiring a rebuild.
- If the run still fails, use the built-in connectivity debugger to isolate the host camera stage before investigating container-side ROS discovery:

```sh
bash reComputer/scripts/nvblox/scripts/debug_runtime_connectivity.sh
```

## Notes

- This example does not use `docker pull` for the base image path.
- The OneDrive downloader resolves the anonymous `download.aspx?...tempauth=...` URL from the preview page before downloading.
- `NVBLOX_MODE=run` expects an already prepared `MANAGED_ROOT`.
- The packaged runtime starts the Orbbec camera on the host and runs `isaac_ros_visual_slam + nvblox` in the container.
- The host launch enables left/right IR, depth, and color streams so Visual SLAM can publish live odometry for hand-held/mobile mapping.
- The container launch uses `isaac_orbbec_launch` with a managed top-level launch file that skips the in-container camera driver and consumes the host ROS topics instead.
- The managed container workspace intentionally excludes upstream `nvblox_examples_bringup` and its segmentation/detection example dependencies. This mobile profile only builds the packages needed for Orbbec + Visual SLAM + dynamic NVBlox mapping.
- If Visual SLAM odometry starts but the map looks sparse at first, move the camera to accumulate dynamic NVBlox output in RViz.
