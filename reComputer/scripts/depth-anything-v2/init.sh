#!/bin/bash
#set color value
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

echo "${CYAN}This script will install the necessary packages and configurations for running depth-anything on a Jetson Nano.${RESET}"

# Install yq for parsing YAML files
sudo apt-get update
sudo apt-get install -y jq

# Read configuration
CURRENT_DIR="depth-anything-v2"
CONFIG_FILE="./jetson-examples/reComputer/scripts/${CURRENT_DIR}/config.yaml"
ALLOWED_L4T_VERSIONS=$(yq -r '.allowed_l4t_versions[]' $CONFIG_FILE)
ALLOWED_L4T_VERSIONS_ARRAY=($ALLOWED_L4T_VERSIONS)
REQUIRED_DISK_SPACE=$(yq -r '.required_disk_space' $CONFIG_FILE)
MIN_MEM_GB=$(yq -r '.min_mem_gb' $CONFIG_FILE)
MIN_SWAP_GB=$(yq -r '.min_swap_gb' $CONFIG_FILE)
NVIDIA_JETSON_PACKAGE=$(yq -r '.nvidia_jetson_package' $CONFIG_FILE)
PACKAGES=$(yq -r '.packages[]' $CONFIG_FILE)
DESIRED_DAEMON_JSON=$(yq -r '.docker.desired_daemon_json' $CONFIG_FILE)
CURRENT_DISK_SPACE=$(df -BG --output=avail / | tail -1 | sed 's/[^0-9]*//g')
MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
SWAP_GB=$(free -g | awk '/^Swap:/{print $2}')

echo "${MAGENTA}Allowed L4T versions:${RESET} ${GREEN}$ALLOWED_L4T_VERSIONS ${RESET}"
echo "${MAGENTA}Required disk space:  ${GREEN}${REQUIRED_DISK_SPACE}G ${RESET}"
echo "${MAGENTA}Minimum memory:  ${GREEN}${MIN_MEM_GB}G ${RESET}"
echo "${MAGENTA}Minimum swap:  ${GREEN}${MIN_SWAP_GB}G ${RESET}" 
echo "${MAGENTA}NVIDIA Jetson package:${RESET}  ${GREEN}$NVIDIA_JETSON_PACKAGE ${RESET}"
echo "${MAGENTA}Additional packages: ${RESET} ${GREEN}$PACKAGES ${RESET}"

# Check if NVIDIA Jetson package is installed
if ! dpkg -l | grep -qw "$NVIDIA_JETSON_PACKAGE"; then
    echo "$NVIDIA_JETSON_PACKAGE is not installed. Installing $NVIDIA_JETSON_PACKAGE..."
    sudo apt-get install -y $NVIDIA_JETSON_PACKAGE
else
    echo "$NVIDIA_JETSON_PACKAGE is installed: ${GREEN}OK!${RESET}"
fi

# Install additional packages
for PACKAGE in $PACKAGES; do
    if ! dpkg -l | grep -qw "$PACKAGE"; then
        echo "$PACKAGE is not installed. Installing $PACKAGE..."
        sudo apt-get install -y $PACKAGE
    else
        echo "$PACKAGE is installed: ${GREEN}OK!${RESET}"
    fi
done

# Get system architecture
ARCH=$(uname -i)
if [ "$ARCH" = "aarch64" ]; then
    # Check for L4T version string
    L4T_VERSION_STRING=$(head -n 1 /etc/nv_tegra_release)

    if [ -z "$L4T_VERSION_STRING" ]; then
        L4T_VERSION_STRING=$(dpkg-query --showformat='${Version}' --show nvidia-l4t-core)
    fi

    L4T_RELEASE=$(echo "$L4T_VERSION_STRING" | cut -f 2 -d ' ' | grep -Po '(?<=R)[^;]+')
    L4T_REVISION=$(echo "$L4T_VERSION_STRING" | cut -f 2 -d ',' | grep -Po '(?<=REVISION: )[^;]+')
    L4T_VERSION="$L4T_RELEASE.$L4T_REVISION"

elif [ "$ARCH" = "x86_64" ]; then
    echo "${RED}Unsupported architecture: $ARCH${RESET}"
    exit 1
fi


# Check L4T version
if [[ " ${ALLOWED_L4T_VERSIONS_ARRAY[@]} " =~ " ${L4T_VERSION} " ]]; then
    echo "L4T VERSION ${GREEN}${L4T_VERSION}${RESET} is in the allowed: ${GREEN}OK!${RESET}"
else
    echo "${RED}L4T VERSION ${GREEN}${L4T_VERSION}${RESET}${RED} is not in the allowed versions list.${RESET}"
    exit 1
fi

# Check disk space
if [ "$CURRENT_DISK_SPACE" -lt "$REQUIRED_DISK_SPACE" ]; then
    echo "${RED}Insufficient disk space. Required: ${REQUIRED_DISK_SPACE}G, Available: ${CURRENT_DISK_SPACE}G. ${RESET}"
    exit 1
else
    echo "Required ${GREEN}${REQUIRED_DISK_SPACE}${RESET} G disk space: ${GREEN}OK!${RESET}"
fi

# Check memory and swap space
if [ "$MEM_GB" -lt "$MIN_MEM_GB" ]; then
    echo "${RED}Insufficient memory: $MEM_GB GB (minimum required: $MIN_MEM_GB GB).${RESET}"
    exit 1
else
    echo "Required ${GREEN}$MIN_MEM_GB${RESET} G memory space: ${GREEN}OK!${RESET}"
fi

if [ "$SWAP_GB" -lt "$MIN_SWAP_GB" ]; then
    echo "${RED}Insufficient swap space: $SWAP_GB GB (minimum required: $MIN_SWAP_GB GB). ${RESET}"
    exit 1
else
    echo "Required ${GREEN}$MIN_SWAP_GB${RESET} G swap space: ${GREEN}OK!${RESET}"
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "${BLUE}Docker is not installed. Installing Docker...${RESET}"

    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        software-properties-common

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository \
        "deb [arch=arm64] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) \
        stable"

    sudo apt-get update
    sudo apt-get install -y docker-ce
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER
    sudo systemctl restart docker
    newgrp docker

    echo "Docker has been installed and configured."
fi

# Check if the current user has permissions to use Docker
if ! docker info &> /dev/null; then
    echo "The current user does not have permissions to use Docker. Adding permissions..."
    sudo usermod -aG docker $USER
    sudo systemctl restart docker
    newgrp docker
    echo "${BLUE}Permissions added. Please log out and log back in for the changes to take effect.${RESET}"
else
    echo "${GREEN}Docker is installed and the current user has permissions to use it.${RESET}"
fi

DAEMON_JSON_PATH="/etc/docker/daemon.json"
if [ ! -f "$DAEMON_JSON_PATH" ] || [ "$(cat $DAEMON_JSON_PATH)" != "$DESIRED_DAEMON_JSON" ]; then
    echo "${BLUE}Creating/updating $DAEMON_JSON_PATH with the desired content...${RESET}"
    echo "$DESIRED_DAEMON_JSON" | sudo tee $DAEMON_JSON_PATH > /dev/null
    sudo systemctl restart docker
    echo "${GREEN}$DAEMON_JSON_PATH has been created/updated.${RESET}"
else
    echo "${GREEN}$DAEMON_JSON_PATH already exists and has the correct content.${RESET}"
fi

# Install additional packages
for PACKAGE in $PACKAGES; do
    if ! dpkg -l | grep -qw "$PACKAGE"; then
        echo "${CYAN}$PACKAGE${RESET} ${BLUE}is not installed. Installing $PACKAGE...${RESET}"
        sudo apt-get install -y $PACKAGE
    else
        echo "${GREEN}$PACKAGE${RESET} is already installed: ${GREEN}OK!${RESET}"
    fi
done
