#!/bin/bash
# DistributeX Complete Docker Worker Installation - UPDATED
# curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/install.sh | bash

set -e

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
VERSION="2.0.0"
INSTALL_DIR="$HOME/.distributex"
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"
COORDINATOR_URL="${DISTRIBUTEX_COORDINATOR_URL:-wss://distributex-coordinator.distributex.workers.dev/ws}"

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
    ____  _      __       _ __          __      _  __
   / __ \(_)____/ /______(_) /_  __  __/ /____| |/ /
  / / / / / ___/ __/ ___/ / __ \/ / / / __/ _ \  / 
 / /_/ / (__  ) /_/ /  / / /_/ / /_/ / /_/  __/ |  
/_____/_/____/\__/_/  /_/_.___/\__,_/\__/\___/_/|_|
                                                    
         Docker-Based Distributed Computing
EOF
    echo -e "${NC}\n"
}

check_requirements() {
    echo -e "${BOLD}Checking requirements...${NC}"
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}✗ Docker not found${NC}"
        echo ""
        echo "Install Docker:"
        echo "  Linux: curl -fsSL https://get.docker.com | sh"
        echo "  Mac: brew install --cask docker"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker installed${NC}"
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        docker_error=$(docker info 2>&1 || true)
        echo -e "${RED}✗ Docker daemon not accessible${NC}"
        echo ""
        
        if echo "$docker_error" | grep -q "permission denied"; then
            echo -e "${YELLOW}Fixing Docker permissions...${NC}"
            sudo usermod -aG docker $USER
            echo -e "${GREEN}✓ Added $USER to docker group${NC}"
            echo ""
            echo -e "${YELLOW}Please run these commands:${NC}"
            echo "  newgrp docker"
            echo "  # Then re-run this installer"
            exit 1
        else
            echo "Please start Docker daemon:"
            echo "  Linux: sudo systemctl start docker"
            echo "  Mac: Open Docker Desktop"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓ Docker daemon running${NC}"
    
    # Check Docker Compose
    if command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker Compose available${NC}"
    else
        echo -e "${RED}✗ Docker Compose not found${NC}"
        echo "Install: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

setup_directories() {
    echo ""
    echo -e "${BOLD}Setting up directories...${NC}"
    
    mkdir -p "$INSTALL_DIR"/{logs,config}
    chmod 700 "$INSTALL_DIR"
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

authenticate_user() {
    echo ""
    echo -e "${BOLD}DistributeX Authentication${NC}\n"
    
    # Check if we can read from terminal
    if [ ! -t 0 ]; then
        exec < /dev/tty
    fi
    
    echo "Choose an option:"
    echo "  1) Create new account"
    echo "  2) Login to existing account"
    echo ""
    
    while true; do
        read -p "$(echo -e ${CYAN}Choice [1-2]:${NC} )" auth_choice
        
        if [ "$auth_choice" == "1" ] || [ "$auth_choice" == "2" ]; then
            break
        else
            echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        fi
    done
    
    if [ "$auth_choice" == "1" ]; then
        # Signup
        echo ""
        read -p "$(echo -e ${CYAN}Full Name:${NC} )" name
        read -p "$(echo -e ${CYAN}Email:${NC} )" email
        read -sp "$(echo -e ${CYAN}Password:${NC} )" password
        echo ""
        echo ""
        echo "Select Role:"
        echo "  1) Contributor (share resources)"
        echo "  2) Developer (submit jobs)"
        echo "  3) Both"
        
        while true; do
            read -p "$(echo -e ${CYAN}Choice [1-3]:${NC} )" role_choice
            
            case $role_choice in
                1) role="contributor"; break ;;
                2) role="developer"; break ;;
                3) role="both"; break ;;
                *) echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}" ;;
            esac
        done
        
        echo ""
        echo -e "${YELLOW}Creating account...${NC}"
        
        response=$(curl -s -X POST "$API_URL/api/auth/signup" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$name\",\"email\":\"$email\",\"password\":\"$password\",\"role\":\"$role\"}")
        
    else
        # Login
        echo ""
        read -p "$(echo -e ${CYAN}Email:${NC} )" email
        read -sp "$(echo -e ${CYAN}Password:${NC} )" password
        echo ""
        echo ""
        echo -e "${YELLOW}Logging in...${NC}"
        
        response=$(curl -s -X POST "$API_URL/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    fi
    
    # Parse response
    if echo "$response" | grep -q '"success":true'; then
        TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        USER_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        USER_ROLE=$(echo "$response" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
        
        # Extract worker credentials if available
        WORKER_ID=$(echo "$response" | grep -o '"workerId":"[^"]*"' | cut -d'"' -f4)
        WORKER_NAME=$(echo "$response" | grep -o '"workerName":"[^"]*"' | cut -d'"' -f4)
        
        echo ""
        echo -e "${GREEN}✅ Authentication successful!${NC}"
        
        # If no worker but user is contributor, create one
        if [ -z "$WORKER_ID" ] && ([ "$USER_ROLE" == "contributor" ] || [ "$USER_ROLE" == "both" ]); then
            echo ""
            echo -e "${YELLOW}Registering worker node...${NC}"
            
            worker_response=$(curl -s -X POST "$API_URL/api/workers/register" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $TOKEN" \
                -d "{\"nodeName\":\"$(hostname)-docker-node\",\"cpuCores\":1,\"memoryGb\":1}")
            
            if echo "$worker_response" | grep -q '"success":true'; then
                WORKER_ID=$(echo "$worker_response" | grep -o '"workerId":"[^"]*"' | cut -d'"' -f4)
                WORKER_NAME=$(echo "$worker_response" | grep -o '"nodeName":"[^"]*"' | cut -d'"' -f4)
                echo -e "${GREEN}✓ Worker registered${NC}"
            fi
        fi
        
        return 0
    else
        error=$(echo "$response" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        echo ""
        echo -e "${RED}✗ Authentication failed: ${error:-Unknown error}${NC}"
        exit 1
    fi
}

save_config() {
    echo ""
    echo -e "${BOLD}Saving configuration...${NC}"
    
    cat > "$INSTALL_DIR/config.json" << EOF
{
  "apiUrl": "$API_URL",
  "coordinatorUrl": "$COORDINATOR_URL",
  "authToken": "$TOKEN",
  "workerId": "$WORKER_ID",
  "userId": "$USER_ID",
  "nodeName": "$WORKER_NAME",
  "installedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    chmod 600 "$INSTALL_DIR/config.json"
    echo -e "${GREEN}✓ Configuration saved${NC}"
}

create_env_file() {
    echo ""
    echo -e "${BOLD}Creating Docker environment...${NC}"
    
    cat > "$INSTALL_DIR/.env" << EOF
# DistributeX Worker Configuration
AUTH_TOKEN=$TOKEN
WORKER_ID=$WORKER_ID
NODE_NAME=$WORKER_NAME
DISTRIBUTEX_API_URL=$API_URL
DISTRIBUTEX_COORDINATOR_URL=$COORDINATOR_URL

# Resource Limits (optional)
MAX_CPU_CORES=
MAX_MEMORY_GB=
MAX_STORAGE_GB=

# GPU Settings
ENABLE_GPU=true
GPU_TYPE=
EOF
    
    chmod 600 "$INSTALL_DIR/.env"
    echo -e "${GREEN}✓ Environment file created${NC}"
}

download_docker_files() {
    echo ""
    echo -e "${BOLD}Downloading Docker configuration...${NC}"
    
    cd "$INSTALL_DIR"
    
    # Download files
    curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/Dockerfile -o Dockerfile
    curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/docker-compose.yml -o docker-compose.yml
    curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/gpu-detect.sh -o gpu-detect.sh
    curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/packages/worker-node/distributex-worker.js -o distributex-worker.js
    curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/package.json -o package.json
    
    chmod +x gpu-detect.sh
    
    echo -e "${GREEN}✓ Docker files downloaded${NC}"
}

build_docker_image() {
    echo ""
    echo -e "${BOLD}Building Docker image...${NC}"
    
    cd "$INSTALL_DIR"
    docker build -t distributex-worker:latest . > /dev/null 2>&1 &
    
    # Show progress
    local pid=$!
    local spin='-\|/'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r  Building... ${spin:$i:1}"
        sleep .1
    done
    
    wait $pid
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        printf "\r${GREEN}✓ Docker image built          ${NC}\n"
    else
        printf "\r${RED}✗ Build failed               ${NC}\n"
        exit 1
    fi
}

install_cli() {
    echo ""
    echo -e "${BOLD}Installing CLI...${NC}"
    
    # Remove old CLI if exists
    sudo rm -f /usr/local/bin/dxcloud 2>/dev/null || true
    
    # Download new CLI
    sudo curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/dxcloud.sh \
        -o /usr/local/bin/dxcloud
    
    sudo chmod +x /usr/local/bin/dxcloud
    
    echo -e "${GREEN}✓ CLI installed to /usr/local/bin/dxcloud${NC}"
}

detect_and_start_worker() {
    echo ""
    echo -e "${BOLD}Detecting GPU and starting worker...${NC}"
    
    # Detect GPU type
    GPU_PROFILE="cpu"
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        GPU_PROFILE="nvidia"
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        echo -e "${GREEN}✓ NVIDIA GPU detected: $GPU_INFO${NC}"
    elif lspci 2>/dev/null | grep -iE "vga|3d" | grep -qi "amd\|radeon"; then
        GPU_PROFILE="amd"
        GPU_INFO=$(lspci | grep -iE "vga|3d" | grep -i "amd" | head -1)
        echo -e "${GREEN}✓ AMD GPU detected${NC}"
    else
        echo -e "${YELLOW}⚠ No GPU detected, using CPU-only mode${NC}"
    fi
    
    # Update .env with GPU type
    sed -i "s/GPU_TYPE=.*/GPU_TYPE=$GPU_PROFILE/" "$INSTALL_DIR/.env"
    
    # Start worker
    cd "$INSTALL_DIR"
    
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD="docker compose"
    fi
    
    echo ""
    echo -e "${CYAN}Starting worker container...${NC}"
    $COMPOSE_CMD --profile $GPU_PROFILE up -d
    
    sleep 3
    
    if $COMPOSE_CMD ps | grep -q "Up"; then
        echo -e "${GREEN}✓ Worker started successfully${NC}"
    else
        echo -e "${RED}✗ Worker failed to start${NC}"
        echo "Check logs: cd $INSTALL_DIR && $COMPOSE_CMD logs"
        exit 1
    fi
}

show_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                                                      ║${NC}"
    echo -e "${GREEN}${BOLD}║          ✅  Installation Complete!                 ║${NC}"
    echo -e "${GREEN}${BOLD}║                                                      ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BOLD}Worker Status:${NC}"
    echo -e "  ${GREEN}✓ Running in Docker${NC}"
    echo -e "  Profile: ${CYAN}$GPU_PROFILE${NC}"
    echo ""
    
    echo -e "${BOLD}Useful Commands:${NC}"
    echo -e "  ${CYAN}dxcloud worker status${NC}  - Check worker status"
    echo -e "  ${CYAN}dxcloud worker logs${NC}    - View worker logs"
    echo -e "  ${CYAN}dxcloud worker stop${NC}    - Stop worker"
    echo -e "  ${CYAN}dxcloud pool status${NC}    - View global pool"
    echo ""
    
    echo -e "${BOLD}Configuration:${NC}"
    echo "  Location: $INSTALL_DIR"
    echo "  Worker ID: $WORKER_ID"
    echo ""
    
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Check status: ${CYAN}dxcloud worker status${NC}"
    echo "  2. View logs: ${CYAN}dxcloud worker logs -f${NC}"
    echo "  3. Dashboard: ${CYAN}https://distributex.cloud/dashboard${NC}"
    echo ""
}

# Main execution
main() {
    show_banner
    check_requirements
    setup_directories
    authenticate_user
    save_config
    create_env_file
    download_docker_files
    build_docker_image
    install_cli
    
    # Only start worker if contributor/both
    if [ "$USER_ROLE" == "contributor" ] || [ "$USER_ROLE" == "both" ]; then
        detect_and_start_worker
    fi
    
    show_completion
}

main
