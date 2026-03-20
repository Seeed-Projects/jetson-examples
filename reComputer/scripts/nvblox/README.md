# Jetson Example: Run  NVBlox Mapping on NVIDIA Jetson 

![img](images/isaac_sim_nvblox_humans.gif)

[Isaac ROS NVBlox](https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nvblox) is a high-performance GPU-accelerated 3D mapping framework developed by NVIDIA for real-time robotic perception. Unlike monocular depth estimation models, NVBlox consumes true depth input from RGB-D cameras or stereo cameras to construct accurate 3D scene representations.This case enables you to **quickly deploy the necessary environment for nvblox to run on your reComputer with just one click.**

Detailed instructions for environment configuration can be found at:[Deploy NVBlox with Orbbec Camera](https://wiki.seeedstudio.com/deploy_nvblox_jetson_agx_orin/)



Main process run it will:

1. Download `nvblox_images.tar` from the built-in OneDrive share link into `~/.cache/jetson-examples/nvblox`
2. Run `docker load -i` on that archive
3. Build the derived image and prepared host/container workspaces
4. Launch the static Gemini2 NVBlox demo

## Requirements

- NVIDIA Jetson Orin 
- Ubuntu 22.04
- JetPack 6.x
- Docker with NVIDIA Container Runtime
- Orbbec Gemini2 or another Orbbec camera that provides `/camera/color/*` and `/camera/depth/*`
- Roughly 60GB free disk space for the cached archive, derived image, and managed workspace

## Usage

Run the full prepare + demo flow:

```sh
cd jetson-example/
pip install .
reComputer run nvblox
```

**Prepare only:**

```bash
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

- The default path checks ordinary Gemini2 color/depth readiness, not stereo IR capability.
- Host readiness now requires only:
  - `/camera/color/camera_info`
  - `/camera/depth/camera_info`
  - `/camera/color/image_raw`
  - `/camera/depth/image_raw`
- Container readiness now checks host camera discovery through `/camera/color/camera_info` and `/camera/depth/camera_info`.
- The runtime success criterion is static map output from `/nvblox_node/static_esdf_pointcloud` or `/nvblox_node/static_map_slice`.
- `usb speed: 5000 Mbps` is not treated as proof that the full demo is healthy. The final authority is whether host color/depth, container visibility, static TF, and static map output all succeed.
- If the host driver exits and Gemini2 falls back to `usb_present_no_video`, the run path still attempts automatic recovery with udev refresh and USB rebind so you can usually retry without unplugging the camera.
- If the run still fails, use the built-in connectivity debugger:

```sh
bash reComputer/scripts/nvblox/scripts/debug_runtime_connectivity.sh
```

That debug path follows the same stages as the default runtime:

1. Gemini2 device state
2. Host ROS discovery environment
3. Container ROS discovery environment
4. Host color/depth readiness
5. Container camera visibility
6. Managed static TF availability
7. Static NVBlox output

## Notes

- This example does not use `docker pull` for the base image path.
- The OneDrive downloader resolves the anonymous `download.aspx?...tempauth=...` URL from the preview page before downloading.
- `NVBLOX_MODE=run` expects an already prepared `MANAGED_ROOT`.
- The host camera is launched with `ros2 launch orbbec_camera gemini2.launch.py publish_tf:=false tf_publish_rate:=0.0`.
- The container workspace now centers on `nvblox_examples_bringup` static Orbbec launches and removes the old default dependence on Visual SLAM.
- The managed static TF chain is generated inside the prepared container workspace rather than relying on device-published TF.
- Headless mode switches the default launch file to `orbbec_debug.launch.py`, while GUI mode uses `orbbec_example.launch.py`.
