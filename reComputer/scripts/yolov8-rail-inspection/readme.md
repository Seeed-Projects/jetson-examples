# Abstract
This project harnesses YOLOv8 technology, specifically tailored for precise identification and counting of bolts at fixed distances along a designated track, as well as for estimating odometer readings and vehicle speed calculations. It incorporates a test video stored within the ```/video``` directory of a Docker container, with the outcomes of these tests saved in the ```/result``` directory, subsequently relayed to the host machine's home directory via Docker mechanisms. Furthermore, the system offers real-time visualization of these processes through a WebUI accessible at ```http://127.0.0.1:5000``` within the local network.

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
reComputer run yolov8-rail-inspection
```
## Note
The display feature of the WebUI is experimental. Opening the WebUI visualization requires waiting for loading time of less than one minute. Optimization for this issue will be addressed in future updates.

## FAQs
1. The project has been tested on the Jetson Orin platform, and its execution entails the use of Docker; therefore, it is essential to ensure that all necessary Docker components are fully installed and functional.
2. During program execution, you may encounter an ```ERROR: Could not open requirements file.``` This error message does not impact the normal operation of the program and can be safely ignored.
3. The ultimate visualization of the results is presented through a web interface. Upon executing the command to run the ```reComputer yolov8-rail-inspection```, the terminal will output the URL for the visualization webpage. Upon clicking the link, you may need to wait a few seconds for the program to initialize and commence operation.