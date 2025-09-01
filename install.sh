#!/bin/bash

# Installation script for jetson-examples
# Usage: curl -fsSL https://raw.githubusercontent.com/Seeed-Projects/jetson-examples/main/install.sh | bash
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Jetson Examples Installation        ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check Python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python3 is not installed${NC}"
    echo "Please install Python3 first:"
    echo "  sudo apt update && sudo apt install -y python3 python3-pip"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo -e "${GREEN}✓${NC} Python3 found: $PYTHON_VERSION"

# Check pip
if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
    echo -e "${YELLOW}Installing pip3...${NC}"
    sudo apt update
    sudo apt install -y python3-pip
fi

# Check if running on Jetson (optional but recommended)
if [ -f "/proc/device-tree/model" ]; then
    MODEL=$(tr -d '\0' < /proc/device-tree/model)
    echo -e "${GREEN}✓${NC} Jetson device detected: $MODEL"
else
    echo -e "${YELLOW}⚠ Warning: Not running on a Jetson device${NC}"
    read -p "Continue installation anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create temp directory for installation
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo ""
echo "Downloading jetson-examples..."
cd "$TEMP_DIR"

# Clone the repository
REPO_URL="${JETSON_EXAMPLES_REPO:-https://github.com/Seeed-Projects/jetson-examples}"
echo "Repository: $REPO_URL"

if ! git clone --depth=1 "$REPO_URL"; then
    echo -e "${RED}Error: Failed to clone repository${NC}"
    exit 1
fi

cd jetson-examples

# Install the package
echo ""
echo "Installing jetson-examples..."
if pip3 install --user .; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Installation Completed!              ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "reComputer has been installed successfully!"
    echo ""
    echo "Getting started:"
    echo "  reComputer help     - Show available commands"
    echo "  reComputer check    - Check system compatibility"
    echo "  reComputer setup    - Setup environment"
    echo "  reComputer list     - List available examples"
    echo "  reComputer run llava - Run an example"
    echo ""
    echo -e "${GREEN}Enjoy using jetson-examples!${NC}"
else
    echo -e "${RED}Error: Installation failed${NC}"
    echo "Please check the error messages above"
    exit 1
fi