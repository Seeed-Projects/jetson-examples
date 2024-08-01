# Jetson-Example: Run Ultralytics YOLO Platform Service on NVIDIA Jetson Orin 🚀

## "One-Click Quick Deployment of Plug-and-Play Ultralytics YOLOv8 for All Task Models with Web UI and HTTP API Interface"
<p align="center">
  <img src="images/Ultralytics-yolo.gif" alt="Ultralytics YOLO">
</p>

## Introduction 📘
In this project, you can quickly deploy all YOLOv8 task models on Nvidia Jetson Orin devices with one click. This setup enables object detection, segmentation, human pose estimation, and classification. It supports uploading local videos, images, and using a webcam, and also allows one-click TensorRT model conversion. By accessing [http://127.0.0.1:5001](http://127.0.0.1:5001) on your local machine or within the same LAN, you can quickly start using Ultralytics YOLO. Additionally, an HTTP API method has been added at [http://127.0.0.1:5001/results](http://127.0.0.1:5001/results) to display detection data results for any task, and an additional Python script is provided to read YOLOv8 detection data within Docker.

## **Key Features**:

1. **One-Click Deployment and Plug-and-Play**: Quickly deploy all YOLOv8 task models on Nvidia Jetson Orin devices.
2. **Comprehensive Task Support**: Enables object detection, segmentation, human pose estimation, and classification.
3. **Versatile Input Options**: Supports uploading local videos, images, and using a webcam.
4. **TensorRT Model Conversion**: Allows one-click conversion of models to TensorRT.
5. **Web UI Access**: Easy access via [`http://127.0.0.1:5001`](http://127.0.0.1:5001) on the local machine or within the same LAN.
6. **HTTP API Interface**: Added HTTP API at [`http://127.0.0.1:5001/results`](http://127.0.0.1:5001/results) to display detection data results.
7. **Python Script Support**: Provides an additional Python script to read YOLOv8 detection data within Docker.

[![My Project](images/tasks.png)](https://github.com/ultralytics/ultralytics?tab=readme-ov-file#models)
All models implemented in this project are from the official [Ultralytics Yolo](https://github.com/ultralytics/ultralytics?tab=readme-ov-file#models).

### Get a Jetson Orin Device 🛒
| Device Model | Description | Link |
|--------------|-------------|------|
| Jetson Orin Nano Dev Kit, Orin Nano 8GB, 40TOPS | Developer kit for NVIDIA Jetson Orin Nano | [Buy Here](https://www.seeedstudio.com/NVIDIAr-Jetson-Orintm-Nano-Developer-Kit-p-5617.html) |
| reComputer J4012, powered by Orin NX 16GB, 100 TOPS | Embedded computer powered by Orin NX | [Buy Here](https://www.seeedstudio.com/reComputer-J4012-p-5586.html) |

## Quickstart ⚡

### Modify Docker Daemon Configuration (Optional)
To enhance the experience of quickly loading models in Docker, you need to add the following content to the `/etc/docker/daemon.json` file:

```json
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "storage-driver": "overlay2",
  "data-root": "/var/lib/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "no-new-privileges": true,
  "experimental": false
}
```

After modifying the `daemon.json` file, you need to restart the Docker service to apply the configuration:

```sh
sudo systemctl restart docker
```

### Installation via PyPI (Recommended) 🐍
1. Install the package:
    ```sh
    pip install jetson-examples
    ```

2. Restart your reComputer:
    ```sh
    sudo reboot
    ```

3. Run Ultralytics YOLO on Jetson with one command:
    ```sh
    reComputer run ultralytics-yolo
    ```
4. "Enter [`http://127.0.0.1:5001`](http://127.0.0.1:5001) or http://device_IP:5001 in your browser to access the Web UI."
    <p align="center">
      <img src="images/ultralytics_fig1.png" alt="Ultralytics YOLO">
    </p>

- **Choose Model**: Select YOLOv8 n, s, l, m, x models and various tasks such as object detection, classification, segmentation, human pose estimation, OBB, etc.
- **Upload Custom Model**: Users can upload their own trained YOLOv8 models.
- **Choose Input Type**: Users can select to input locally uploaded images, videos, or real-time camera devices.
- **Enable TensorRT**: Choose whether to convert and use the TensorRT model. The initial conversion may require varying amounts of time.

5. If you want to see the detection result data, you can enter [`http://127.0.0.1:5001/results`](http://127.0.0.1:5001/results) in your browser to view the `JSON` formatted data results. These results include `boxes` for object detection, `masks` for segmentation, `keypoints` for human pose estimation, and the `names` corresponding to all numerical categories.
    <p align="center">
      <img src="images/ultralytics_fig2.png" alt="Ultralytics YOLO">
    </p>
    We also provide a Python script to help users integrate the data into their own programs.

    ```python
    import requests

    def fetch_results():
        response = requests.get('http://localhost:5001/results')
        if response.status_code == 200:
            results = response.json()
            return results
        else:
            print('Failed to fetch results')
            return None

    results = fetch_results()
    print(results)
    ```


## Notes 📝
- To stop detection at any time, press the Stop button.
- When accessing the WebUI from other devices within the same LAN, use the URL: `http://{Jetson_IP}:5001`.
- You can view the JSON formatted detection results by accessing http://{Jetson_IP}:5001/results.
- The first model conversion may require different amounts of time depending on the hardware and network environment, so please be patient.


## Further Development 🔧
- [Training a YOLOv8 Model](https://wiki.seeedstudio.com/How_to_Train_and_Deploy_YOLOv8_on_reComputer/)
- [TensorRT Acceleration](https://wiki.seeedstudio.com/YOLOv8-DeepStream-TRT-Jetson/)
- [Multistreams using Deepstream](https://wiki.seeedstudio.com/YOLOv8-DeepStream-TRT-Jetson/#multistream-model-benchmarks) Tutorials.

## License

This project is licensed under the MIT License.
