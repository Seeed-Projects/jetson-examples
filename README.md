<div align="center">
  <img alt="jetson" height="200px" src="https://avatars.githubusercontent.com/u/688117?s=200&v=4">
</div>

# jetson-examples

[![Discord](https://dcbadge.vercel.app/api/server/5BQCkty7vN?style=flat&compact=true)](https://discord.gg/5BQCkty7vN)

- run ai examples on jetson.
- all you need is `reComputer`.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Seeed-Projects/jetson-examples/main/install.sh | sh
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
