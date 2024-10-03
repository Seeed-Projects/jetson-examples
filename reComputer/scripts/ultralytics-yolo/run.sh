#!/bin/bash

CONTAINER_NAME="ultralytics-yolo"

# Function to get L4T version
get_l4t_version() {
    local l4t_version=""
    local release_line=$(head -n 1 /etc/nv_tegra_release)
    if [[ $release_line =~ R([0-9]+)\ *\(release\),\ REVISION:\ ([0-9]+\.[0-9]+) ]]; then
        local major="${BASH_REMATCH[1]}"
        local revision="${BASH_REMATCH[2]}"
        l4t_version="${major}.${revision}"
    fi
    echo "$l4t_version"
}

L4T_VERSION=$(get_l4t_version)
echo "Detected L4T version: $L4T_VERSION"

# Determine the Docker image based on L4T version
if [[ "$L4T_VERSION" == "32.6.1" ]]; then
    IMAGE_NAME="yaohui1998/ultralytics-jetpack4:1.0"
elif [[ "$L4T_VERSION" == "35.3.1" || "$L4T_VERSION" == "35.4.1" || "$L4T_VERSION" == "35.5.0" ]]; then
    IMAGE_NAME="yaohui1998/ultralytics-jetpack5:1.0"
elif [[ "$L4T_VERSION" == "36.3.0" ]]; then
    IMAGE_NAME="yaohui1998/ultralytics-jetpack6:1.0"
else
    echo "Error: L4T version $L4T_VERSION is not supported."
    exit 1
fi

echo "Using Docker image: $IMAGE_NAME"

# Pull the Docker image
docker pull $IMAGE_NAME
# make dir for save models
mkdir ~/yolo_models

# Check if the container with the specified name already exists
if [ $(docker ps -a -q -f name=^/${CONTAINER_NAME}$) ]; then
    echo "Container $CONTAINER_NAME already exists. Starting and attaching..."
    echo "Please open http://127.0.0.1:5000 to access the WebUI."
    docker start $CONTAINER_NAME
    docker exec -it $CONTAINER_NAME /bin/bash
else
    echo "Container $CONTAINER_NAME does not exist. Creating and starting..."
    docker run -it \
        --name $CONTAINER_NAME \
        --privileged \
        --network host \
        -v ~/yolo_models/:/usr/src/ultralytics/models/ \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/*:/dev/* \
        -v /etc/localtime:/etc/localtime:ro \
        --runtime nvidia \
        $IMAGE_NAME
fi
