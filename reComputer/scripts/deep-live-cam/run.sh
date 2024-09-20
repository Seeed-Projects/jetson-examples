CONTAINER_NAME="deep-live-cam"
IMAGE_NAME="yaohui1998/deep-live-cam:1.0"

# Pull the latest image
docker pull $IMAGE_NAME
# Set display id
xhost +local:docker
export DISPLAY=:0
# mkdir image dir
mkdir ~/images
echo $DISPLAY
# Check if the container with the specified name already exists
if [ $(docker ps -a -q -f name=^/${CONTAINER_NAME}$) ]; then
    echo "Container $CONTAINER_NAME already exists. Starting and attaching..."
    docker start $CONTAINER_NAME
else
    echo "Container $CONTAINER_NAME does not exist. Creating and starting..."
    docker run -it --rm \
        --name $CONTAINER_NAME \
        --privileged \
        --network host \
        -v ~/images:/usr/src/Deep-Live-Cam/images \
        -e DISPLAY=$DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/*:/dev/* \
        -v /etc/localtime:/etc/localtime:ro \
        --runtime nvidia \
        $IMAGE_NAME
fi
