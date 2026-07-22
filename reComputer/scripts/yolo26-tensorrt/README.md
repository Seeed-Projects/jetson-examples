# YOLO26 TensorRT C++ Real-time Detection

Native, Docker-free YOLO26 deployment for Jetson devices running JetPack 6 or JetPack 7. The TensorRT engine is always built on the target Jetson, while inference and the browser preview are served by a lightweight C++ application.

This example is intentionally separate from the existing `yolo26` example:

- `yolo26`: Docker + Ultralytics workflow for files and videos.
- `yolo26-tensorrt`: native TensorRT C++ camera inference with a browser UI.

## Compatibility

- JetPack 6.x / L4T 36.x, including TensorRT 8.6 and TensorRT 10.x releases.
- JetPack 7.x / L4T 38.x and 39.x.
- Jetson Orin and Jetson Thor platforms with a USB or CSI camera exposed through OpenCV.

## What It Does

1. Downloads or receives the official `yolo26n.onnx` model and verifies its SHA256.
2. Uses the target Jetson's `trtexec` to build an FP16 TensorRT engine.
3. Compiles a C++ application against CUDA, TensorRT, and OpenCV.
4. Opens the camera and serves annotated frames at `http://<jetson-ip>:8080/`.

The C++ runtime supports both TensorRT 8 binding APIs and TensorRT 10 tensor APIs. It accepts the official end-to-end `[1,300,6]` output and retains the three-feature-map fallback decoder.

## Quick Start

```bash
reComputer run yolo26-tensorrt
```

Then open `http://<jetson-ip>:8080/`.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `YOLO26_TENSORRT_ONNX_URL` | Ultralytics v8.4.0 release asset | ONNX download URL |
| `YOLO26_TENSORRT_ONNX_SHA256` | Built-in official model hash | Expected ONNX SHA256 |
| `YOLO26_TENSORRT_CAMERA` | `0` | OpenCV camera index |
| `YOLO26_TENSORRT_PORT` | `8080` | HTTP server port |
| `YOLO26_TENSORRT_SKIP_DOWNLOAD` | `0` | Require a pre-uploaded ONNX file when set to `1` |

## Files

- `src/main.cpp` – TensorRT 8/10 inference and HTTP preview server.
- `src/CMakeLists.txt` – CUDA, TensorRT, and OpenCV build configuration.
- `src/coco_labels.txt` – COCO 80-class labels.
- `src/httplib.h` – single-header HTTP library.
- `run.sh` – model validation, engine build, compilation, and launch.
- `clean.sh` – removes the engine, build directory, metadata, and logs.
