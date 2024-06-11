# jetson-examples

<div align="center">
  <img alt="jetson" width="1200px" src="https://files.seeedstudio.com/wiki/reComputer-Jetson/jetson-examples/Jetson1200x300.png">
</div>

[![Discord](https://dcbadge.vercel.app/api/server/5BQCkty7vN?style=flat&compact=true)](https://discord.gg/5BQCkty7vN)

This repository provides examples for running AI models and applications on [NVIDIA Jetson devices](https://www.seeedstudio.com/reComputer-J4012-p-5586.html) with a single command.

This repo builds upon the work of the [jetson-containers](https://github.com/dusty-nv/jetson-containers), which provides a modular container build system for various AI/ML packages on NVIDIA Jetson devices. 

## Features
- 🚀 **Easy Deployment:** Deploy state-of-the-art AI models on Jetson devices in one line.
- 🔄 **Versatile Examples:** Supports text generation, image generation, vision transformers, computer vision and so on.
- ⚡ **Optimized for Jetson:** Leverages Nvidia Jetson hardware for efficient performance.


## Install
To install the package, run:

```sh
pip3 install jetson-examples
```

> Notes: 
> - Check [here](./docs/install.md) for more installation methods 
> - To upgrade to the latest version, use:  `pip3 install jetson-examples --upgrade`.



## Quickstart
To run and chat with [LLaVA](https://www.jetson-ai-lab.com/tutorial_llava.html), execute:

```sh
reComputer run llava
```
<div align="center">
  <img alt="jetson" width="1200px" src="./docs/assets/llava.png">
</div>

## Example list

Here are some examples that can be run:

| Example                                          | Type                     | Model/Data Size | Docker Image Size | Command                                 |
| ------------------------------------------------ | ------------------------ | --------------- | ---------- | --------------------------------------- |
| 🆕 [yolov10](/reComputer/scripts/yolov10/README.md)     | Computer Vision         | 7.2M               | 5.74 GB     | `reComputer run yolov10`                 |
| 🆕 llama3                                         | Text (LLM)               | 4.9GB           | 10.5GB     | `reComputer run llama3`                 |
| 🆕 [ollama](https://github.com/ollama/ollama)     | Inference Server         | *               | 10.5GB     | `reComputer run ollama`                 |
| LLaVA                                            | Text + Vision (VLM)      | 13GB            | 14.4GB     | `reComputer run llava`                  |
| Live LLaVA                                       | Text + Vision (VLM)      | 13GB            | 20.3GB     | `reComputer run live-llava`             |
| stable-diffusion-webui                           | Image Generation         | 3.97G           | 7.3GB      | `reComputer run stable-diffusion-webui` |
| nanoowl                                          | Vision Transformers(ViT) | 613MB           | 15.1GB     | `reComputer run nanoowl`                |
| [nanodb](../reComputer/scripts/nanodb/readme.md) | Vector Database          | 76GB            | 7.0GB      | `reComputer run nanodb`                 |
| whisper                                          | Audio                    | 1.5GB           | 6.0GB      | `reComputer run whisper`                |
| [yolov8-rail-inspection](/reComputer/scripts/yolov8-rail-inspection/readme.md) |Computer Vision | 6M | 13.8GB  | `reComputer run yolov8-rail-inspection`  |
| [ultralytics-yolo](/reComputer/scripts/ultralytics-yolo/README.md) |Computer Vision |  | 15.4GB  | `reComputer run  ultralytics-yolo`  |
| [depth-anything](/reComputer/scripts/depth-anything/README.md) |Computer Vision |  | 12.9GB  | `reComputer run  depth-anything`  |

> Note: You should have enough space to run example, like `LLaVA`, at least `27.4GB` totally

More Examples can be found [examples.md](./docs/examples.md)

## Development
Want to add your own example? Check out the [development guide](./docs/develop.md).

We welcome contributions to improve jetson-examples! If you have an example you'd like to share, please submit a pull request. Thank you to all of our contributors! 🙏

## TODO List

- [ ] check disk space enough or not before run
- [ ] allow to setting some configs, such as `BASE_PATH`
- [ ] detect host environment and install what we need
- [ ] support jetson-containers update
- [ ] all type jetson support checking list
- [ ] better table to show example's difference
- [ ] try jetpack 6.0


## License
This project is licensed under the MIT License. 

## Resources
- https://github.com/dusty-nv/jetson-containers
- https://www.jetson-ai-lab.com/
- https://www.ultralytics.com/

