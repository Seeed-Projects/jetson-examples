FROM nvcr.io/nvidia/l4t-pytorch:r35.2.1-pth2.0-py3
RUN mkdir /usr/src/DepthAnything-on-Jetson-Orin
WORKDIR /usr/src/DepthAnything-on-Jetson-Orin
COPY . /usr/src/DepthAnything-on-Jetson-Orin
RUN pip install flask onnx flask flask_socketio huggingface_hub
CMD ["python3", "app.py"]