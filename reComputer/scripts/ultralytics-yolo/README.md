# Jetson Examples for Ultralytics Yolo
Experience all task models of Ultralytics YOLO with a single command

##
## Introduction
This example allows you to experience all task models of Ultralytics YOLO with a single command. By accessing http://127.0.0.1:5000 on your local machine or within the same LAN, you can quickly deploy Ultralytics YOLO on edge devices. Additionally, you can upload your own trained models for testing with images, videos, or real-time camera feeds. We also provide [training](https://wiki.seeedstudio.com/How_to_Train_and_Deploy_YOLOv8_on_reComputer/) and [TensorRT acceleration](https://wiki.seeedstudio.com/YOLOv8-DeepStream-TRT-Jetson/) tutorials.


## Quickstart
- PyPI(recommend)

    ```sh
    pip install jetson-examples
    ```

- Restart reComputer 
    ```sh
    sudo restart
    ```
- Run ultralytics-yolo on jetson in one line:
    ```sh
    reComputer run ultralytics-yolo
    ```

## Note
The first time you start the code for detection, there will be a wait of at least 30 seconds for loading; this is normal. To stop detection at any time, please press the Stop button. When accessing the WebUI from other devices within the same LAN, please use the URL http://{Jetson_IP}:5001.
