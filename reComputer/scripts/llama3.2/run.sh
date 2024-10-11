#!/bin/bash

BASE_PATH=/home/$USER/reComputer
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
cd $JETSON_REPO_PATH

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
if [[ "$L4T_VERSION" == "35.3.1" || "$L4T_VERSION" == "35.4.1" || "$L4T_VERSION" == "35.5.0" ]]; then
    IMAGE_NAME="youjiang9977/ollama:r35.3.1"
elif [[ "$L4T_VERSION" == "36.3.0" || "$L4T_VERSION" == "36.4.0" ]]; then
    IMAGE_NAME="youjiang9977/ollama:r36.3.0"
else
    echo "Error: L4T version $L4T_VERSION is not supported."
    exit 1
fi

docker rm -f ollama
./run.sh -d --name ollama $IMAGE_NAME
./run.sh $IMAGE_NAME /bin/ollama run llama3.2
docker rm -f ollama

