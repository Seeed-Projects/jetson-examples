#!/bin/bash

# Setup script for jetson-examples
# This script detects the host environment and installs necessary dependencies

set -e

# Color definitions
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

echo "${BLUE}========================================${RESET}"
echo "${BLUE}   Jetson Examples Environment Setup   ${RESET}"
echo "${BLUE}========================================${RESET}"

# Function to check if running on Jetson
check_jetson() {
    if [ -f "/proc/device-tree/model" ]; then
        model=$(tr -d '\0' < /proc/device-tree/model | tr '[:upper:]' '[:lower:]')
        if [[ $model =~ jetson|orin|nv|agx|xavier|nano|tx2|tx1 ]]; then
            echo "${GREEN}✓ Jetson device detected: $model${RESET}"
            return 0
        else
            echo "${YELLOW}⚠ Device may not be a Jetson: $model${RESET}"
            return 1
        fi
    else
        echo "${RED}✗ Not running on a Jetson device${RESET}"
        return 1
    fi
}

# Function to detect L4T/JetPack version
detect_jetpack_version() {
    echo "${BLUE}Detecting JetPack version...${RESET}"
    
    if [ -f "/etc/nv_tegra_release" ]; then
        L4T_VERSION_STRING=$(head -n 1 /etc/nv_tegra_release)
        L4T_RELEASE=$(echo "$L4T_VERSION_STRING" | cut -f 2 -d ' ' | grep -Po '(?<=R)[^;]+')
        L4T_REVISION=$(echo "$L4T_VERSION_STRING" | cut -f 2 -d ',' | grep -Po '(?<=REVISION: )[^;]+')
        L4T_VERSION="$L4T_RELEASE.$L4T_REVISION"
        echo "${GREEN}✓ L4T Version: $L4T_VERSION${RESET}"
        
        # Map L4T to JetPack version
        case "$L4T_VERSION" in
            "32.7.1"|"32.7.2"|"32.7.3") JETPACK_VERSION="4.6.x" ;;
            "34.1.0"|"34.1.1") JETPACK_VERSION="5.0.x" ;;
            "35.1.0") JETPACK_VERSION="5.0.2" ;;
            "35.2.1") JETPACK_VERSION="5.1" ;;
            "35.3.1") JETPACK_VERSION="5.1.1" ;;
            "35.4.1") JETPACK_VERSION="5.1.2" ;;
            "35.5.0") JETPACK_VERSION="5.1.3" ;;
            "36.2.0") JETPACK_VERSION="6.0 DP" ;;
            "36.3.0") JETPACK_VERSION="6.0" ;;
            "36.4.0") JETPACK_VERSION="6.1" ;;
            *) JETPACK_VERSION="Unknown" ;;
        esac
        echo "${GREEN}✓ JetPack Version: $JETPACK_VERSION${RESET}"
    else
        echo "${YELLOW}⚠ Could not detect L4T version${RESET}"
    fi
}

# Function to check system resources
check_system_resources() {
    echo "${BLUE}Checking system resources...${RESET}"
    
    # Check disk space
    DISK_AVAILABLE=$(df -BG --output=avail / | tail -1 | sed 's/[^0-9]*//g')
    if [ "$DISK_AVAILABLE" -lt 20 ]; then
        echo "${YELLOW}⚠ Low disk space: ${DISK_AVAILABLE}GB available (minimum 20GB recommended)${RESET}"
    else
        echo "${GREEN}✓ Disk space: ${DISK_AVAILABLE}GB available${RESET}"
    fi
    
    # Check memory
    MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
    echo "${GREEN}✓ Memory: ${MEM_TOTAL}GB total${RESET}"
    
    # Check swap
    SWAP_TOTAL=$(free -g | awk '/^Swap:/{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ]; then
        echo "${YELLOW}⚠ No swap configured (recommended for AI workloads)${RESET}"
    else
        echo "${GREEN}✓ Swap: ${SWAP_TOTAL}GB configured${RESET}"
    fi
}

# Function to install basic dependencies
install_basic_deps() {
    echo "${BLUE}Installing basic dependencies...${RESET}"
    
    # Update package list
    sudo apt-get update
    
    # Install essential packages
    PACKAGES=(
        "python3-pip"
        "python3-dev"
        "curl"
        "wget"
        "git"
        "build-essential"
        "cmake"
        "pkg-config"
        "jq"
    )
    
    for pkg in "${PACKAGES[@]}"; do
        if dpkg -l | grep -qw "$pkg"; then
            echo "${GREEN}✓ $pkg already installed${RESET}"
        else
            echo "Installing $pkg..."
            sudo apt-get install -y "$pkg"
        fi
    done
    
    # Install Python packages
    echo "${BLUE}Installing Python dependencies...${RESET}"
    pip3 install --upgrade pip
    
    # Install yq for YAML parsing
    if ! command -v yq &> /dev/null; then
        echo "Installing yq..."
        pip3 install yq
    else
        echo "${GREEN}✓ yq already installed${RESET}"
    fi
}

# Function to setup Docker
setup_docker() {
    echo "${BLUE}Setting up Docker...${RESET}"
    
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        sudo apt-get install -y docker.io
        sudo systemctl enable docker
        sudo systemctl start docker
    else
        echo "${GREEN}✓ Docker already installed${RESET}"
    fi
    
    # Add user to docker group
    if ! groups $USER | grep -q docker; then
        echo "Adding $USER to docker group..."
        sudo usermod -aG docker $USER
        echo "${YELLOW}⚠ Please log out and back in for group changes to take effect${RESET}"
    else
        echo "${GREEN}✓ User already in docker group${RESET}"
    fi
    
    # Configure Docker for NVIDIA runtime
    DAEMON_JSON="/etc/docker/daemon.json"
    if [ ! -f "$DAEMON_JSON" ] || ! grep -q "nvidia" "$DAEMON_JSON"; then
        echo "Configuring Docker for NVIDIA runtime..."
        sudo tee "$DAEMON_JSON" > /dev/null <<EOF
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF
        sudo systemctl restart docker
        echo "${GREEN}✓ Docker configured for NVIDIA runtime${RESET}"
    else
        echo "${GREEN}✓ Docker already configured for NVIDIA${RESET}"
    fi
}

# Function to check CUDA
check_cuda() {
    echo "${BLUE}Checking CUDA installation...${RESET}"
    
    if [ -d "/usr/local/cuda" ]; then
        CUDA_VERSION=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $5}' | cut -d',' -f1)
        echo "${GREEN}✓ CUDA version: $CUDA_VERSION${RESET}"
    else
        echo "${YELLOW}⚠ CUDA not found in /usr/local/cuda${RESET}"
    fi
}

# Function to setup environment variables
setup_environment() {
    echo "${BLUE}Setting up environment variables...${RESET}"
    
    # Create config directory
    CONFIG_DIR="$HOME/.config/jetson-examples"
    mkdir -p "$CONFIG_DIR"
    
    # Create environment config file
    ENV_FILE="$CONFIG_DIR/env.conf"
    cat > "$ENV_FILE" <<EOF
# Jetson Examples Configuration
# Generated on $(date)

# Base path for jetson-containers
export BASE_PATH=\${BASE_PATH:-/home/\$USER/reComputer}

# Jetson repo path
export JETSON_REPO_PATH=\${JETSON_REPO_PATH:-\$BASE_PATH/jetson-containers}

# L4T Version
export L4T_VERSION=$L4T_VERSION

# JetPack Version
export JETPACK_VERSION="$JETPACK_VERSION"
EOF
    
    echo "${GREEN}✓ Configuration saved to $ENV_FILE${RESET}"
    
    # Add to bashrc if not already present
    if ! grep -q "jetson-examples/env.conf" "$HOME/.bashrc"; then
        echo "" >> "$HOME/.bashrc"
        echo "# Jetson Examples Environment" >> "$HOME/.bashrc"
        echo "[ -f \"$ENV_FILE\" ] && source \"$ENV_FILE\"" >> "$HOME/.bashrc"
        echo "${GREEN}✓ Added to .bashrc${RESET}"
    fi
}

# Main setup flow
main() {
    echo ""
    
    # Check if running on Jetson
    if ! check_jetson; then
        echo "${YELLOW}⚠ Warning: Not running on a Jetson device${RESET}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    echo ""
    detect_jetpack_version
    
    echo ""
    check_system_resources
    
    echo ""
    install_basic_deps
    
    echo ""
    setup_docker
    
    echo ""
    check_cuda
    
    echo ""
    setup_environment
    
    echo ""
    echo "${GREEN}========================================${RESET}"
    echo "${GREEN}    Setup completed successfully!      ${RESET}"
    echo "${GREEN}========================================${RESET}"
    echo ""
    echo "Next steps:"
    echo "1. Source your environment: ${BLUE}source ~/.bashrc${RESET}"
    echo "2. Check system status: ${BLUE}reComputer check${RESET}"
    echo "3. List available examples: ${BLUE}reComputer list${RESET}"
    echo "4. Run an example: ${BLUE}reComputer run llava${RESET}"
    echo ""
}

# Run main function
main "$@"