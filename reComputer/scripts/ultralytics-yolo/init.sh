#!/bin/bash
echo "run example: ultralytics-yolo"
# Define allowed L4T versions
ALLOWED_L4T_VERSIONS=("35.3.1" "35.4.1" "35.5.0" "36.3.0")
REQUIRED_DISK_SPACE="20G"  # Example value for disk space
MIN_MEM_GB=15
MIN_SWAP_GB=7

NVIDIA_JETSON_PACKAGE="nvidia-jetpack"
# Check if NVIDIA Jetson package is installed
if ! dpkg -l | grep -qw "$NVIDIA_JETSON_PACKAGE"; then
    echo "$NVIDIA_JETSON_PACKAGE is not installed. Installing $NVIDIA_JETSON_PACKAGE..."

    # Command to install NVIDIA Jetson package (example)
    # Replace with the actual installation command if different
    sudo apt-get update
    sudo apt-get install -y $NVIDIA_JETSON_PACKAGE

    echo "$NVIDIA_JETSON_PACKAGE has been installed."
else
    echo "$NVIDIA_JETSON_PACKAGE is already installed."
fi

# Get system architecture
ARCH=$(uname -i)
if [ "$ARCH" = "aarch64" ]; then
    # Check for L4T version string
    L4T_VERSION_STRING=$(head -n 1 /etc/nv_tegra_release)

    if [ -z "$L4T_VERSION_STRING" ]; then
        # Fallback to dpkg-query if /etc/nv_tegra_release is empty
        L4T_VERSION_STRING=$(dpkg-query --showformat='${Version}' --show nvidia-l4t-core)
        L4T_VERSION_ARRAY=(${L4T_VERSION_STRING//./ })
        L4T_RELEASE=${L4T_VERSION_ARRAY[0]}
        L4T_REVISION=${L4T_VERSION_ARRAY[1]}
    else
        # Extract release and revision from the version string
        L4T_RELEASE=$(echo "$L4T_VERSION_STRING" | cut -f 2 -d ' ' | grep -Po '(?<=R)[^;]+')
        L4T_REVISION=$(echo "$L4T_VERSION_STRING" | cut -f 2 -d ',' | grep -Po '(?<=REVISION: )[^;]+')
    fi

    # Construct the L4T version
    L4T_VERSION="$L4T_RELEASE.$L4T_REVISION"

elif [ "$ARCH" = "x86_64" ]; then
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

CURRENT_DISK_SPACE=$(df -h / | grep / | awk '{print $4}')
DISK_SPACE_GB=$(echo $CURRENT_DISK_SPACE | sed 's/G//') # Convert to GB
MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
SWAP_GB=$(free -g | awk '/^Swap:/{print $2}')
echo "L4T_VERSION: $L4T_VERSION"
echo "Allowed versions: ${ALLOWED_L4T_VERSIONS[@]}"
echo "Memory, Disk and swap space requirements met: $MIN_MEM_GB GB memory, $REQUIRED_DISK_SPACE GB memory, $MIN_SWAP_GB GB swap."
echo "Memory, Disk and swap space is: $MEM_GB GB memory, $REQUIRED_DISK_SPACE GB memory, $SWAP_GB GB swap."

# Check if the L4T version is in the allowed versions list
if [[ ! " ${ALLOWED_L4T_VERSIONS[@]} " =~ " ${L4T_VERSION} " ]]; then
    echo "L4T_VERSION is not in the allowed versions list. Exiting."
    exit 1
fi

# Check disk space

if [ "$(echo "$DISK_SPACE_GB < ${REQUIRED_DISK_SPACE%G}" | bc)" -eq 1 ]; then
    echo "Insufficient disk space. Required: $REQUIRED_DISK_SPACE, Available: $CURRENT_DISK_SPACE. Exiting."
    exit 1
fi

# Check memory and swap space

if [ "$MEM_GB" -lt "$MIN_MEM_GB" ]; then
    echo "Insufficient memory: $MEM_GB GB (minimum required: $MIN_MEM_GB GB). Exiting."
    exit 1
fi

if [ "$SWAP_GB" -lt "$MIN_SWAP_GB" ]; then
    echo "Insufficient swap space: $SWAP_GB GB (minimum required: $MIN_SWAP_GB GB). Exiting."
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Installing Docker..."

    # Update package list
    sudo apt-get update

    # Install necessary packages
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        software-properties-common

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

    # Add Docker's stable repository
    sudo add-apt-repository \
       "deb [arch=arm64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable"

    # Update package list again
    sudo apt-get update

    # Install Docker CE
    sudo apt-get install -y docker-ce

    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl start docker

    # Add the current user to the docker group
    sudo usermod -aG docker $USER
    sudo systemctl restart docker
    newgrp docker

    echo "Docker has been installed and configured."
else
    echo "Docker is already installed."
fi

# Check if the current user has permissions to use Docker
if ! docker info &> /dev/null; then
    echo "The current user does not have permissions to use Docker. Adding permissions..."

    # Add the current user to the docker group
    sudo usermod -aG docker $USER
    sudo systemctl restart docker
    newgrp docker

    echo "Permissions added. Please log out and log back in for the changes to take effect."
else
    echo "Docker is installed and the current user has permissions to use it."
fi

# Check if /etc/docker/daemon.json exists and has the correct content
DAEMON_JSON_PATH="/etc/docker/daemon.json"
DESIRED_DAEMON_JSON='{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "storage-driver": "overlay2",
  "data-root": "/var/lib/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "no-new-privileges": true,
  "experimental": false
}'

if [ ! -f "$DAEMON_JSON_PATH" ] || [ "$(cat $DAEMON_JSON_PATH)" != "$DESIRED_DAEMON_JSON" ]; then
    echo "Creating/updating /etc/docker/daemon.json with the desired content..."
    echo "$DESIRED_DAEMON_JSON" | sudo tee $DAEMON_JSON_PATH > /dev/null
    sudo systemctl restart docker
    echo "/etc/docker/daemon.json has been created/updated."
else
    echo "/etc/docker/daemon.json already exists and has the correct content."
fi
