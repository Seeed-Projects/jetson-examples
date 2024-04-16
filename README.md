<div align="center">
  <img alt="jetson" width="1200px" src="https://files.seeedstudio.com/wiki/reComputer-Jetson/jetson-examples/Jetson1200x300.png">
</div>

# jetson-examples

[![Discord](https://dcbadge.vercel.app/api/server/5BQCkty7vN?style=flat&compact=true)](https://discord.gg/5BQCkty7vN)

This repository provides examples for running AI models and applications on NVIDIA Jetson devices.  For generative AI, it supports a variety of examples including text generation, image generation, vision transformers, vector databases, and audio models.
To run the examples, you need to install the jetson-examples package and use the Seeed Studio [reComputer](https://www.seeedstudio.com/reComputer-J4012-p-5586.html), the edge AI device powered by Jetson Orin.  The repo aims to make it easy to deploy state-of-the-art AI models, with just one line of command, on Jetson devices for tasks like language understanding, computer vision, and multimodal processing.

This repo builds upon the work of the [Jetson Containers](https://github.com/dusty-nv/jetson-containers), which provides a modular container build system for various AI/ML packages on NVIDIA Jetson devices. It also leverages resources and tutorials from the [Jetson Generative AI Lab](https://www.jetson-ai-lab.com/index.html), which showcases bringing generative AI to the edge, powered by Jetson hardware.

## Install

```sh
pip install jetson-examples
```

- [more installation methods](./docs/install.md)

## Quickstart

To run and chat with [LLaVA](https://www.jetson-ai-lab.com/tutorial_llava.html):

```sh
reComputer run llava
```

## Example list

reComputer supports a list of examples from [jetson-ai-lab](https://www.jetson-ai-lab.com/)

Here are some examples that can be run:

| Example                | Type                     | Model/Data Size | Image Size | Command                                 |
| ---------------------- | ------------------------ | --------------- | ---------- | --------------------------------------- |
| text-generation-webui  | Text (LLM)               | 3.9GB           | 14.8GB     | `reComputer run text-generation-webui`  |
| LLaVA                  | Text + Vision (VLM)      | 13GB            | 14.4GB     | `reComputer run llava`                  |
| stable-diffusion-webui | Image Generation         | 3.97G           | 7.3GB      | `reComputer run stable-diffusion-webui` |
| nanoowl                | Vision Transformers(ViT) | 613MB           | 15.1GB     | `reComputer run nanoowl`                |
| nanodb                 | Vector Database          | 76GB            | 7.0GB      | `reComputer run nanodb`                 |
| whisper                | Audio                    | 1.5GB           | 6.0GB      | `reComputer run whisper`                |

> Note: You should have enough space to run example, like `LLaVA`, at least `27.4GB` totally

More Examples can be found [examples.md](./docs/examples.md)

## TODO List

- [ ] check disk space enough or not before run
- [ ] allow to setting some configs, such as `BASE_PATH`
- [ ] detect host environment and install what we need
- [ ] support jetson-containers update
- [ ] all type jetson support checking list
- [ ] better table to show example's difference
- [ ] try jetpack 6.0
