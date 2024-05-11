# Abstract
This script facilitates YOLOv8 in counting retail products, enabling real-time detection of items removed from the shelf by users. 
The project includes a test video located in the ```/video``` directory within a Docker container, with the test results saved in ```/result``` and subsequently transmitted to the host Home directory via Docker.

## Install


PyPI(recommend)

```sh
pip install jetson-examples
```

Linux (github trick)
```sh
curl -fsSL https://raw.githubusercontent.com/Seeed-Projects/jetson-examples/main/install.sh | sh
```

Github (for Developer)

```sh
git clone https://github.com/Seeed-Projects/jetson-examples
cd jetson-examples
pip install .
```

## Quickstart
```sh
reComputer run yolov8-counter
```
## TODO List
- [ ] Add a host-side visual terminal interface for yolov8-counter.

## FAQs
1. The project has been tested on the Jetson Orin platform, and its execution entails the use of Docker; therefore, it is essential to ensure that all necessary Docker components are fully installed and functional.
2. During program execution, you may encounter an ```ERROR: Could not open requirements file.``` This error message does not impact the normal operation of the program and can be safely ignored.
3. Currently, real-time visualization of test results from within the Docker container to the host terminal is not supported. However, post-detection outcomes are copied from the container's image to the ```/Home/result``` directory on the host system for review.
