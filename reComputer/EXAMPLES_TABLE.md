# Jetson Examples Comparison

## Example Overview

| Example                     | Type             | Disk Space   | Memory   | JetPack Support   | Description                                            |
|-----------------------------|------------------|--------------|----------|-------------------|--------------------------------------------------------|
| audiocraft                  | Audio            | 25GB         | 7GB      | 5.1.1...6.2.1     | 💡 In this demo, we refer to jetson-container to de... |
| whisper                     | Audio            | 25GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| comfyui                     | Computer Vision  | 30GB         | 15GB     | 5.1.1...6.2.1     | <p align="center">                                     |
| depth-anything              | Computer Vision  | 20GB         | 4GB      | 5.1.1...6.2.1     | This project provides an one-click deployment of t...  |
| depth-anything-v2           | Computer Vision  | 15GB         | 4GB      | 5.1.1...6.2.1     | This project provides an one-click deployment of t...  |
| ultralytics-yolo            | Computer Vision  | 16GB         | 2GB      | 5.1.1...6.2.1     | <p align="center">                                     |
| yolov10                     | Computer Vision  | 20GB         | 4GB      | 5.1.1...6.2.1     | 💡 Here's an example of quickly deploying YOLOv10 o... |
| yolov8-rail-inspection      | Computer Vision  | 20GB         | 4GB      | 5.1.1...6.2.1     |                                                        |
| stable-diffusion-webui      | Image Generation | 25GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| Sheared-LLaMA-2.7B-ShareGPT | LLM/VLM          | 25GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| llama-factory               | LLM/VLM          | 25GB         | 7GB      | 5.1.1...6.2.1     | Now you can tailor a custom private local LLM to m...  |
| llama3                      | LLM/VLM          | 15GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| llama3.2                    | LLM/VLM          | 15GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| llava                       | LLM/VLM          | 15GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| llava-v1.5-7b               | LLM/VLM          | 25GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| llava-v1.6-vicuna-7b        | LLM/VLM          | 25GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| ollama                      | LLM/VLM          | 15GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| deep-live-cam               | Unknown          | 40GB         | 20GB     | 6.0...6.2.1       | This project provides a one-click deployment of th...  |
| nanoowl                     | Unknown          | 25GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| text-generation-webui       | Unknown          | 25GB         | 7GB      | 5.1.1...6.2.1     |                                                        |
| nanodb                      | Vector Database  | 80GB         | 15GB     | 5.1.1...6.2.1     |                                                        |

## JetPack Compatibility Matrix

| Example                     | JP 5.1.1   | JP 5.1.2   | JP 5.1.3   | JP 6.0 DP   | JP 6.0   | JP 6.1   | JP 6.2   | JP 6.2.1   |
|-----------------------------|------------|------------|------------|-------------|----------|----------|----------|------------|
| audiocraft                  | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| whisper                     | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| comfyui                     | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| depth-anything              | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| depth-anything-v2           | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| ultralytics-yolo            | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| yolov10                     | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| yolov8-rail-inspection      | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| stable-diffusion-webui      | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| Sheared-LLaMA-2.7B-ShareGPT | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| llama-factory               | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| llama3                      | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| llama3.2                    | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| llava                       | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| llava-v1.5-7b               | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| llava-v1.6-vicuna-7b        | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| ollama                      | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| deep-live-cam               |            |            |            | ✓           | ✓        | ✓        | ✓        | ✓          |
| nanoowl                     | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| text-generation-webui       | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |
| nanodb                      | ✓          | ✓          | ✓          | ✓           | ✓        | ✓        | ✓        | ✓          |

## Resource Requirements by Category

| Category         |   Examples | Min Disk   | Max Disk   | Min Memory   | Max Memory   |
|------------------|------------|------------|------------|--------------|--------------|
| Audio            |          2 | 25GB       | 25GB       | 7GB          | 7GB          |
| Computer Vision  |          6 | 15GB       | 30GB       | 2GB          | 15GB         |
| Image Generation |          1 | 25GB       | 25GB       | 7GB          | 7GB          |
| LLM/VLM          |          8 | 15GB       | 25GB       | 7GB          | 7GB          |
| Unknown          |          3 | 25GB       | 40GB       | 7GB          | 20GB         |
| Vector Database  |          1 | 80GB       | 80GB       | 15GB         | 15GB         |

---
*Generated automatically by `reComputer/scripts/generate_example_table.py`*
