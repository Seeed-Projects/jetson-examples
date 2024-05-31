# Jetson Examples for Ultralytics Yolo
Experience all task models of Ultralytics YOLO with a single command
![alt text](image.png)
##
## Introduction
This project allows you to experience all task models of Ultralytics YOLO with a single command. By accessing http://127.0.0.1:5000 on your local machine or within the same LAN, you can use the WebUI to select from various YOLO tasks such as object detection, image segmentation, action recognition, object classification, and oriented bounding box (OBB). Additionally, you can upload your own trained models for testing with images, videos, or real-time camera feeds.

For information on how to train your own models, please visit: [How to Train and Deploy YOLOv8 on reComputer](https://wiki.seeedstudio.com/How_to_Train_and_Deploy_YOLOv8_on_reComputer/).

For information on how to use TensorRT for acceleration, please visit: [YOLOv8-DeepStream-TRT-Jetson](https://wiki.seeedstudio.com/YOLOv8-DeepStream-TRT-Jetson/).

## Install

PyPI(recommend)

```sh
pip install jetson-examples
```

Linux (github trick)
```sh
curl -fsSL https://raw.githubusercontent.com/Seeed-Projects/jetson-examples/main/install.sh | sh
```

Github (for Developer)

```sh
git clone https://github.com/Seeed-Projects/jetson-examples
cd jetson-examples
pip install .
```

## Quickstart
```sh
reComputer run ultralytics-yolo
```

## Note
The first time you start the code for detection, there will be a wait of at least 30 seconds for loading; this is normal. To stop detection at any time, please press the Stop button. When accessing the WebUI from other devices within the same LAN, please use the URL http://{Jetson_IP}:5001.
