# Jetson-Example: Run Ultralytics YOLO on NVIDIA Jetson Orin 🚀

## Experience all task models of Ultralytics YOLO with a single command.
<p align="center">
  <img src="images/Ultralytics-yolo.gif" alt="Ultralytics YOLO">
</p>

## Introduction 📘
This project enables you to deploy and experience all task models of Ultralytics YOLO on NVIDIA Jetson Orin devices with a single command. By accessing [http://127.0.0.1:5000](http://127.0.0.1:5000) on your local machine or within the same LAN, you can quickly start using Ultralytics YOLO. You can also upload your own trained models and test them with images, videos, or real-time camera feeds.

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

## Notes 📝
- To stop detection at any time, press the Stop button.
- When accessing the WebUI from other devices within the same LAN, use the URL: `http://{Jetson_IP}:5000`.

## Further Development 🔧
- [Training a YOLOv8 Model](https://wiki.seeedstudio.com/How_to_Train_and_Deploy_YOLOv8_on_reComputer/)
- [TensorRT Acceleration](https://wiki.seeedstudio.com/YOLOv8-DeepStream-TRT-Jetson/)
- [Multistreams using Deepstream](https://wiki.seeedstudio.com/YOLOv8-DeepStream-TRT-Jetson/#multistream-model-benchmarks) Tutorials.

## License

This project is licensed under the MIT License.
