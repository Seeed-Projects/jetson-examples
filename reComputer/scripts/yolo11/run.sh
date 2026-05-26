#!/bin/bash
set -e

IMAGE_VERSION="8.3.225"

get_l4t_version() {
    local l4t_version=""
    if [ -f /etc/nv_tegra_release ]; then
        local release_line
        release_line=$(head -n 1 /etc/nv_tegra_release)
        if [[ $release_line =~ R([0-9]+)\ *\(release\),\ REVISION:\ ([0-9]+\.[0-9]+) ]]; then
            local major="${BASH_REMATCH[1]}"
            local revision="${BASH_REMATCH[2]}"
            l4t_version="${major}.${revision}"
        fi
    fi
    echo "$l4t_version"
}

L4T_VERSION=$(get_l4t_version)
echo "Detected L4T version: $L4T_VERSION"

case "$L4T_VERSION" in
    35.*)
        IMAGE_NAME="ultralytics/ultralytics:${IMAGE_VERSION}-jetson-jetpack5"
        ;;
    36.*)
        IMAGE_NAME="ultralytics/ultralytics:${IMAGE_VERSION}-jetson-jetpack6"
        ;;
    *)
        echo "Error: L4T version $L4T_VERSION is not supported by this YOLO11 demo."
        echo "Supported JetPack versions: 5.x and 6.x."
        exit 1
        ;;
esac

echo "Using Docker image: $IMAGE_NAME"
sudo docker pull "$IMAGE_NAME"
sudo docker run -it --ipc=host --runtime=nvidia "$IMAGE_NAME"
