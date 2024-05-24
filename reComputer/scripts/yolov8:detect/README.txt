# Run YOLOv8 Detect Model on Jetson in One Line

## Introduction

This is a simple demo about how to quickly run the ultralytics YOLOv8 detection model on Jetson device.

## Getting Started

- install **jetson-examples** by pip:
    ```sh
    pip3 install jetson-examples
    ```
- restart reComputer 
    ```sh
    sudo restart
    ```
- run yolov8 detect model on jetson in one line:
    ```sh
    reComputer run yolov8-counter
    ```

## FAQs
1. The project has been tested on the Jetson Orin platform, and its execution entails the use of Docker; therefore, it is essential to ensure that all necessary Docker components are fully installed and functional.
2. During program execution, you may encounter an ```ERROR: Could not open requirements file.``` This error message does not impact the normal operation of the program and can be safely ignored.
3. If you want to run `Docker` commands without using `sudo` you can configure it with the following commands:
    ```sh
    sudo groupadd docker
    sudo gpasswd -a ${USER} docker
    sudo systemctl restart docker
    sudo chmod a+rw /var/run/docker.sock
    ```

