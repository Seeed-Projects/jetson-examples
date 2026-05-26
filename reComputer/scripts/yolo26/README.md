# Quickly Run YOLO26 on Jetson

This example runs the official Ultralytics YOLO26 Jetson container with one command.

## Supported Images

| JetPack | Docker image |
| ------- | ------------ |
| 5.x | `ultralytics/ultralytics:8.4.54-jetson-jetpack5` |
| 6.x | `ultralytics/ultralytics:8.4.54-jetson-jetpack6` |
| 7.x | `ultralytics/ultralytics:8.4.54-nvidia-arm64` |

## Getting Started

Install `jetson-examples`:

```sh
pip3 install jetson-examples
```

Restart your reComputer:

```sh
sudo reboot
```

Run YOLO26 on Jetson:

```sh
reComputer run yolo26
```

The script detects the L4T / JetPack version, pulls the matching Ultralytics image, and starts the container:

```sh
t=ultralytics/ultralytics:8.4.54-jetson-jetpack6
sudo docker pull $t && sudo docker run -it --ipc=host --runtime=nvidia $t
```

For JetPack 5.x, use:

```sh
t=ultralytics/ultralytics:8.4.54-jetson-jetpack5
sudo docker pull $t && sudo docker run -it --ipc=host --runtime=nvidia $t
```

For JetPack 7.x, use:

```sh
t=ultralytics/ultralytics:8.4.54-nvidia-arm64
sudo docker pull $t && sudo docker run -it --ipc=host --runtime=nvidia $t
```

## Reference

- https://github.com/ultralytics/ultralytics
