#!/bin/bash

# Color definitions
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

echo "${BLUE}========================================${RESET}"
echo "${BLUE}  Jetson Containers Update Manager     ${RESET}"
echo "${BLUE}========================================${RESET}"

# Use environment variable if set, otherwise use default
BASE_PATH=${BASE_PATH:-/home/$USER/reComputer}
JETSON_REPO_PATH="${JETSON_REPO_PATH:-$BASE_PATH/jetson-containers}"

# Official jetson-containers repository
JETSON_CONTAINERS_REPO="https://github.com/dusty-nv/jetson-containers.git"

# Function to check current version
check_version() {
    if [ -d "$JETSON_REPO_PATH/.git" ]; then
        cd "$JETSON_REPO_PATH"
        CURRENT_COMMIT=$(git rev-parse --short HEAD)
        CURRENT_BRANCH=$(git branch --show-current)
        echo "${GREEN}Current version:${RESET}"
        echo "  Branch: $CURRENT_BRANCH"
        echo "  Commit: $CURRENT_COMMIT"
        echo "  Date: $(git log -1 --format=%cd --date=short)"
        
        # Check for updates
        git fetch origin >/dev/null 2>&1
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse origin/$CURRENT_BRANCH)
        
        if [ "$LOCAL" != "$REMOTE" ]; then
            echo ""
            echo "${YELLOW}⚠ Updates available!${RESET}"
            echo "  New commits: $(git rev-list HEAD..origin/$CURRENT_BRANCH --count)"
            return 1
        else
            echo ""
            echo "${GREEN}✓ Already up to date${RESET}"
            return 0
        fi
    else
        echo "${YELLOW}⚠ jetson-containers not found at $JETSON_REPO_PATH${RESET}"
        return 2
    fi
}

# Function to backup current installation
backup_installation() {
    BACKUP_DIR="$BASE_PATH/backups/jetson-containers-$(date +%Y%m%d-%H%M%S)"
    echo "${BLUE}Creating backup at $BACKUP_DIR...${RESET}"
    mkdir -p "$BASE_PATH/backups"
    cp -r "$JETSON_REPO_PATH" "$BACKUP_DIR"
    echo "${GREEN}✓ Backup created${RESET}"
}

# Function to update jetson-containers
update_jetson_containers() {
    echo ""
    echo "${BLUE}Updating jetson-containers...${RESET}"
    
    cd "$JETSON_REPO_PATH"
    
    # Stash any local changes
    if [[ -n $(git status -s) ]]; then
        echo "${YELLOW}Stashing local changes...${RESET}"
        git stash push -m "Auto-stash before update $(date)"
    fi
    
    # Pull updates
    echo "Pulling latest changes..."
    if git pull origin $(git branch --show-current); then
        echo "${GREEN}✓ Successfully updated${RESET}"
        
        # Update Python dependencies
        if [ -f "requirements.txt" ]; then
            echo ""
            echo "${BLUE}Updating Python dependencies...${RESET}"
            pip3 install -r requirements.txt --upgrade
            echo "${GREEN}✓ Dependencies updated${RESET}"
        fi
        
        # Show what's new
        echo ""
        echo "${BLUE}Recent changes:${RESET}"
        git log --oneline -5
        
        return 0
    else
        echo "${RED}✗ Update failed${RESET}"
        return 1
    fi
}

# Function to install jetson-containers
install_jetson_containers() {
    echo ""
    echo "${BLUE}Installing jetson-containers...${RESET}"
    
    mkdir -p "$BASE_PATH"
    cd "$BASE_PATH"
    
    echo "Cloning repository..."
    if git clone --depth=1 "$JETSON_CONTAINERS_REPO"; then
        cd "$JETSON_REPO_PATH"
        
        # Install dependencies
        echo ""
        echo "${BLUE}Installing dependencies...${RESET}"
        sudo apt update
        sudo apt install -y python3-pip
        
        if [ -f "requirements.txt" ]; then
            pip3 install -r requirements.txt
        fi
        
        echo "${GREEN}✓ Installation complete${RESET}"
        return 0
    else
        echo "${RED}✗ Installation failed${RESET}"
        return 1
    fi
}

# Function to rollback to backup
rollback() {
    echo ""
    echo "${BLUE}Available backups:${RESET}"
    
    if [ -d "$BASE_PATH/backups" ]; then
        ls -1 "$BASE_PATH/backups" | nl
        echo ""
        read -p "Enter backup number to restore (or 0 to cancel): " choice
        
        if [ "$choice" -ne 0 ]; then
            BACKUP=$(ls -1 "$BASE_PATH/backups" | sed -n "${choice}p")
            if [ -n "$BACKUP" ]; then
                echo "${YELLOW}Restoring from $BACKUP...${RESET}"
                rm -rf "$JETSON_REPO_PATH"
                cp -r "$BASE_PATH/backups/$BACKUP" "$JETSON_REPO_PATH"
                echo "${GREEN}✓ Rollback complete${RESET}"
            fi
        fi
    else
        echo "${YELLOW}No backups found${RESET}"
    fi
}

# Main update flow
main() {
    echo ""
    
    if [ -d "$JETSON_REPO_PATH" ]; then
        # Check current version
        check_version
        STATUS=$?
        
        if [ $STATUS -eq 1 ]; then
            # Updates available
            echo ""
            echo "Options:"
            echo "  1) Update to latest version"
            echo "  2) Update with backup"
            echo "  3) Show detailed changes"
            echo "  4) Skip update"
            echo ""
            read -p "Choose option (1-4): " choice
            
            case $choice in
                1)
                    update_jetson_containers
                    ;;
                2)
                    backup_installation
                    update_jetson_containers
                    ;;
                3)
                    cd "$JETSON_REPO_PATH"
                    git log HEAD..origin/$(git branch --show-current) --oneline --graph
                    echo ""
                    read -p "Continue with update? (y/N): " confirm
                    if [[ $confirm == "y" || $confirm == "Y" ]]; then
                        update_jetson_containers
                    fi
                    ;;
                4)
                    echo "${YELLOW}Update skipped${RESET}"
                    ;;
                *)
                    echo "${RED}Invalid option${RESET}"
                    ;;
            esac
        elif [ $STATUS -eq 0 ]; then
            # Already up to date
            echo ""
            echo "Options:"
            echo "  1) Force reinstall"
            echo "  2) Rollback to backup"
            echo "  3) Exit"
            echo ""
            read -p "Choose option (1-3): " choice
            
            case $choice in
                1)
                    backup_installation
                    rm -rf "$JETSON_REPO_PATH"
                    install_jetson_containers
                    ;;
                2)
                    rollback
                    ;;
                3)
                    echo "${GREEN}Done${RESET}"
                    ;;
                *)
                    echo "${RED}Invalid option${RESET}"
                    ;;
            esac
        fi
    else
        # Not installed
        echo "${YELLOW}jetson-containers is not installed${RESET}"
        echo ""
        read -p "Install now? (y/N): " choice
        if [[ $choice == "y" || $choice == "Y" ]]; then
            install_jetson_containers
        else
            echo "${YELLOW}Installation skipped${RESET}"
        fi
    fi
    
    echo ""
    echo "${GREEN}========================================${RESET}"
    echo "${GREEN}         Update Complete                ${RESET}"
    echo "${GREEN}========================================${RESET}"
}

# Run main function
main "$@"