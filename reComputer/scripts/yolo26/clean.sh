#!/bin/bash
set -e

IMAGE_VERSION="8.4.54"

if [ -f /etc/nv_tegra_release ]; then
    L4T_RELEASE=$(head -n 1 /etc/nv_tegra_release | grep -o 'R[0-9]*' | head -1 | cut -dR -f2)
else
    L4T_RELEASE=""
fi

case "$L4T_RELEASE" in
    35)
        IMAGE_NAME="ultralytics/ultralytics:${IMAGE_VERSION}-jetson-jetpack5"
        ;;
    36)
        IMAGE_NAME="ultralytics/ultralytics:${IMAGE_VERSION}-jetson-jetpack6"
        ;;
    38)
        IMAGE_NAME="ultralytics/ultralytics:${IMAGE_VERSION}-nvidia-arm64"
        ;;
    *)
        echo "Unable to detect a supported JetPack 5.x/6.x/7.x image for cleanup."
        exit 0
        ;;
esac

if [ "$(sudo docker ps -q --filter ancestor="$IMAGE_NAME")" ]; then
    sudo docker ps -q --filter ancestor="$IMAGE_NAME" | xargs -r sudo docker stop
fi

if sudo docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    sudo docker rmi "$IMAGE_NAME"
    echo "Removed image: $IMAGE_NAME"
else
    echo "Image does not exist: $IMAGE_NAME"
fi
