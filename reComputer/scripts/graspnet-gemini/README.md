# Jetson-Example: GraspNet With Gemini Camera

This example runs the **ReBot Grasp / GraspNet** Web demo with an Orbbec Gemini camera on NVIDIA Jetson. On first run it downloads a prebuilt Docker archive from SharePoint, imports it as:

```sh
rebot-grasp:jp621-lowmem
```

The default launch uses the verified low-memory mode:

```text
width=640 height=480 fps=15 num_point=3000 cloud_crop_nsample=8 --no-yolo
```

Archive size: about **2.0 GB**

Supported JetPack/L4T targets:
- JetPack 6.0 -> L4T 36.3.0
- JetPack 6.1 -> L4T 36.4.0
- JetPack 6.2 -> L4T 36.4.3
- JetPack 6.2.1 -> L4T 36.4.4

## Getting Started

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

Connect the Gemini camera, then start the demo:

```sh
reComputer run graspnet-gemini
```

Open:

```text
http://127.0.0.1:8090
```

Use another machine on the same network:

```text
http://<jetson-ip>:8090
```

The first run will:

1. Download the Docker archive from the SharePoint backend download URL
2. Run `docker load -i` to import the image
3. Start the low-memory GraspNet Web demo with Jetson-friendly Docker flags

Cache location:

```sh
~/.cache/jetson-examples/graspnet-gemini/rebot-grasp-jp621-lowmem.tar
```

## YOLO Mode

The default mode disables YOLO so the camera stream and full-scene GraspNet result can run on 8 GB Jetson devices. To enable YOLO detection:

```sh
GRASPNET_GEMINI_ENABLE_YOLO=1 reComputer run graspnet-gemini
```

Use a smaller YOLO TensorRT engine if memory is tight:

```sh
GRASPNET_GEMINI_ENABLE_YOLO=1 \
GRASPNET_GEMINI_YOLO_MODEL=yolo11n-seg-320.engine \
reComputer run graspnet-gemini
```

## Environment Variables

- `GRASPNET_GEMINI_PORT`: Web UI port, default `8090`
- `GRASPNET_GEMINI_WIDTH`: camera width, default `640`
- `GRASPNET_GEMINI_HEIGHT`: camera height, default `480`
- `GRASPNET_GEMINI_FPS`: camera FPS, default `15`
- `GRASPNET_GEMINI_NUM_POINT`: GraspNet point count, default `3000`
- `GRASPNET_GEMINI_CLOUD_CROP_NSAMPLE`: cloud crop sample count, default `8`
- `GRASPNET_GEMINI_ENABLE_YOLO`: set `1` to enable YOLO mode
- `GRASPNET_GEMINI_YOLO_MODEL`: YOLO model path/name inside the image
- `GRASPNET_GEMINI_IMAGE_ARCHIVE_URL`: override the SharePoint download URL
- `GRASPNET_GEMINI_CACHE_DIR`: archive cache directory
- `GRASPNET_GEMINI_REQUIRE_CAMERA`: set `1` to fail fast when no Orbbec USB camera is detected

## Cleanup

Stop and remove the container:

```sh
reComputer clean graspnet-gemini
```

The Docker image and downloaded archive are kept locally for faster startup next time.
