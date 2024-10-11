#!/bin/bash

check_base_env() 
{
    # 1. Set color value
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    RESET=$(tput sgr0)

    # 2. Load config file
    local CONFIG_FILE=$1
    echo "CONFIG_FILE_PATH=$CONFIG_FILE"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: YAML file '$CONFIG_FILE' not found."
        exit 1
    fi
    # Install yq for parsing YAML file
    if ! command -v yq &> /dev/null
    then
        echo "yq is not installed. Installing yq with pip3..."
        pip3 install yq
        if command -v yq &> /dev/null
        then
            echo "yq has been successfully installed."
        else
            echo "Failed to install yq."
            exit 1
        fi
    else
        echo "yq is already installed."
    fi

    if ! command -v jq &> /dev/null
    then
        echo "jq is not installed. Installing jq..."
        sudo apt-get update
        sudo apt-get install -y jq

        if command -v jq &> /dev/null
        then
            echo "jq has been successfully installed."
            jq --version
        else
            echo "Failed to install jq."
            exit 1
        fi
    else
        echo "jq is already installed."
        jq --version
    fi
    ALLOWED_L4T_VERSIONS=($(yq -r '.ALLOWED_L4T_VERSIONS[]' $CONFIG_FILE))
    REQUIRED_DISK_SPACE=$(yq -r '.REQUIRED_DISK_SPACE' $CONFIG_FILE)
    REQUIRED_MEM_SPACE=$(yq -r '.REQUIRED_MEM_SPACE' $CONFIG_FILE)
    PACKAGES=($(yq -r '.PACKAGES[]' $CONFIG_FILE))
    DOCKER=$(yq -r '.DOCKER.ENABLE' $CONFIG_FILE)
    DESIRED_DAEMON_JSON=$(yq -r '.DOCKER.DAEMON' $CONFIG_FILE)
    echo "${ALLOWED_L4T_VERSIONS[@]}"
    # 3. Check L4T version
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

    if [[ " ${ALLOWED_L4T_VERSIONS[@]} " =~ " ${L4T_VERSION} " ]]; then
        echo "L4T VERSION ${GREEN}${L4T_VERSION}${RESET} is in the allowed: ${GREEN}OK!${RESET}"
    else
        echo "${RED}L4T VERSION ${GREEN}${L4T_VERSION}${RESET}${RED} is not in the allowed versions list.${RESET}"
        echo "${RED}The JetPack versions currently supported by this container are: ${GREEN}${ALLOWED_L4T_VERSIONS[@]}${RESET}${RED}. ${RESET}"
        echo "${RED}For more information : https://github.com/Seeed-Projects/jetson-examples ${RESET}"
        exit 1
    fi

    # Install additional apt packages
    for PACKAGE in $PACKAGES; do
        if ! dpkg -l | grep -qw "$PACKAGE"; then
            echo "Installing $PACKAGE..."
            sudo apt-get install -y $PACKAGE
        fi
        echo "$PACKAGE is installed: ${GREEN}OK!${RESET}"
    done

    # 4. Check disk space
    CURRENT_DISK_SPACE=$(df -BG --output=avail / | tail -1 | sed 's/[^0-9]*//g')
    if [ "$CURRENT_DISK_SPACE" -lt "$REQUIRED_DISK_SPACE" ]; then
        echo "${RED}Insufficient disk space. Required: ${REQUIRED_DISK_SPACE}G, Available: ${CURRENT_DISK_SPACE}G. ${RESET}"
        exit 1
    else
        echo "Required ${GREEN}${REQUIRED_DISK_SPACE}GB${RESET}/${GREEN}${CURRENT_DISK_SPACE}GB${RESET} disk space: ${GREEN}OK!${RESET}"
    fi

    # 5. Check memory space
    CURRENT_MEM_SPACE=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$CURRENT_MEM_SPACE" -lt "$REQUIRED_MEM_SPACE" ]; then
        echo "${RED}Insufficient memory: $CURRENT_MEM_SPACE GB (minimum required: $REQUIRED_MEM_SPACE GB).${RESET}"
        exit 1
    else
        echo "Required ${GREEN}${REQUIRED_MEM_SPACE}GB${RESET}/${GREEN}${CURRENT_MEM_SPACE}GB${RESET} memory space: ${GREEN}OK!${RESET}"
    fi

    # 6. Prepare Docker env
    if [ "$DOCKER" = "true" ]; then
        # 6.1 Check if Docker is installed
        if ! command -v docker &> /dev/null; then
            echo "${BLUE}Docker is not installed. Installing Docker...${RESET}"
            sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            sudo add-apt-repository "deb [arch=arm64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

            sudo apt-get update
            sudo apt-get install -y docker-ce
            sudo systemctl enable docker
            sudo systemctl start docker
            sudo usermod -aG docker $USER
            sudo systemctl restart docker
            echo "${BLUE}Permissions added. Please rerun the command.${RESET}"
            newgrp docker

            echo "Docker has been installed and configured."
        fi
        # 6.2 Modify the Docker configuration file
        DAEMON_JSON_PATH="/etc/docker/daemon.json"
        NECESSARY_CONTENT=
        if [ ! -f "$DAEMON_JSON_PATH" ]; then
            echo "${BLUE}Creating $DAEMON_JSON_PATH with the desired content...${RESET}"
            echo "$DESIRED_DAEMON_JSON" | sudo tee $DAEMON_JSON_PATH > /dev/null
            sudo systemctl restart docker
            echo "${GREEN}$DAEMON_JSON_PATH has been created.${RESET}"
        elif [ "$(jq -e '.["default-runtime"] == "nvidia" and .runtimes.nvidia.path == "nvidia-container-runtime" and (.runtimes.nvidia.runtimeArgs | length == 0)' "$DAEMON_JSON_PATH")" != "true" ]; then
        # elif [ "$(cat $DAEMON_JSON_PATH)" != "$DESIRED_DAEMON_JSON" ]; then
            echo "${BLUE}Backing up the existing $DAEMON_JSON_PATH to /etc/docker/daemon_backup.json ...${RESET}"
            sudo cp "$DAEMON_JSON_PATH" "/etc/docker/daemon_backup.json"
            echo "${GREEN}Backup completed.${RESET}"
            echo "${BLUE}Updating $DAEMON_JSON_PATH with the desired content...${RESET}"
            echo "$DESIRED_DAEMON_JSON" | sudo tee $DAEMON_JSON_PATH > /dev/null
            sudo systemctl restart docker
            echo "${GREEN}$DAEMON_JSON_PATH has been updated.${RESET}"
        else
            echo "${GREEN}$DAEMON_JSON_PATH already exists and has the correct content.${RESET}"
        fi
        # 6.3 Check permissions
        if ! docker info &> /dev/null; then
            echo "The current user does not have permissions to use Docker. Adding permissions..."
            sudo usermod -aG docker $USER
            sudo systemctl restart docker
            echo "${BLUE}Permissions added. Please rerun the command.${RESET}"
            newgrp docker
        else
            echo "${GREEN}Docker is installed and the current user has permissions to use it.${RESET}"
        fi
    else
        echo "No need to configure Docker."
    fi
}
