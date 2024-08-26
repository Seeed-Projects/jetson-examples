CONTAINER_NAME="depth-anything-v2"
IMAGE_NAME="yaohui1998/depthanything-v2-on-jetson-orin:latest"

# Pull the latest image
docker pull $IMAGE_NAME

# Check if the container with the specified name already exists
if [ $(docker ps -a -q -f name=^/${CONTAINER_NAME}$) ]; then
    echo "Container $CONTAINER_NAME already exists. Starting and attaching..."
    docker start $CONTAINER_NAME
else
    echo "Container $CONTAINER_NAME does not exist. Creating and starting..."
    docker run -it \
        --name $CONTAINER_NAME \
        --privileged \
        --network host \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/*:/dev/* \
        -v /etc/localtime:/etc/localtime:ro \
        --runtime nvidia \
        $IMAGE_NAME
fi
