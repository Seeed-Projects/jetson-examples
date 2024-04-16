# Example list

reComputer supports a list of examples from [jetson-ai-lab](https://www.jetson-ai-lab.com/)

All examples that can be run:

| Example                                          | Type                     | Model Size | Image Size | Command                                      | Device   |
| ------------------------------------------------ | ------------------------ | ---------- | ---------- | -------------------------------------------- | -------- |
| text-generation-webui                            | Text (LLM)               | 3.9GB      | 14.8GB     | `reComputer run text-generation-webui`       |          |
| LLaMA                                            | Text (LLM)               | 1.5GB      | 10.5GB     | `reComputer run Sheared-LLaMA-2.7B-ShareGPT` |          |
| llava-v1.5                                       | Text + Vision (VLM)      | 13GB       | 14.4GB     | `reComputer run llava-v1.5-7b`               |          |
| llava-v1.6                                       | Text + Vision (VLM)      | 13GB       | 20.3GB     | `reComputer run llava-v1.6-vicuna-7b`        |          |
| LLaVA                                            | Text + Vision (VLM)      | 13GB       | 14.4GB     | `reComputer run llava`                       |          |
| Live LLaVA                                       | Text + Vision (VLM)      | 13GB       | 20.3GB     | `reComputer run live-llava`                  | USB-CAM* |
| stable-diffusion-webui                           | Image Generation         | 3.97G      | 7.3GB      | `reComputer run stable-diffusion-webui`      |          |
| nanoowl                                          | Vision Transformers(ViT) | 613MB      | 15.1GB     | `reComputer run nanoowl`                     | USB-CAM* |
| [nanodb](../reComputer/scripts/nanodb/readme.md) | Vector Database          | 76GB       | 7.0GB      | `reComputer run nanodb`                      |          |
| whisper                                          | Audio                    | 1.5GB      | 6.0GB      | `reComputer run whisper`                     | USB-CAM* |

> Note: You should have enough space to run example, like `llava-v1.5`, at least `27.4GB` totally
