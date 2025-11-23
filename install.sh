#!/bin/bash
# DistributeX Complete CLI + Worker Installation - FIXED
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
VERSION="1.0.0"
INSTALL_DIR="$HOME/.distributex"
BIN_DIR="/usr/local/bin"
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"
COORDINATOR_URL="${DISTRIBUTEX_COORDINATOR_URL:-wss://distributex-coordinator.distributex.workers.dev}"

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
    ____  _      __       _ __          __      _  __
   / __ \(_)____/ /______(_) /_  __  __/ /____| |/ /
  / / / / / ___/ __/ ___/ / __ \/ / / / __/ _ \  / 
 / /_/ / (__  ) /_/ /  / / /_/ / /_/ / /_/  __/ |  
/_____/_/____/\__/_/  /_/_.___/\__,_/\__/\___/_/|_|
                                                    
         Free Distributed Computing Network
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
            echo "Issue: Permission denied"
            echo "Solution: sudo usermod -aG docker $USER && newgrp docker"
        else
            echo "Issue: Docker daemon not running"
            echo "Solution: Start Docker Desktop or run: sudo systemctl start docker"
        fi
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker daemon is running${NC}"
    
    # Check Node.js
    if ! command -v node >/dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}Node.js not found. Installing...${NC}"
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew >/dev/null 2>&1; then
                brew install node
            else
                echo -e "${RED}Homebrew required. Install from: https://brew.sh${NC}"
                exit 1
            fi
        elif [[ -f /etc/debian_version ]]; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
        else
            echo -e "${RED}Please install Node.js manually: https://nodejs.org${NC}"
            exit 1
        fi
    fi
    
    node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$node_version" -lt 16 ]; then
        echo -e "${YELLOW}⚠ Node.js version $node_version detected. Version 16+ recommended.${NC}"
    fi
    
    echo -e "${GREEN}✓ Node.js $(node -v) available${NC}"
}

setup_directories() {
    echo ""
    echo -e "${BOLD}Setting up directories...${NC}"
    
    mkdir -p "$INSTALL_DIR"/{bin,logs,config}
    chmod 700 "$INSTALL_DIR"
    
    echo -e "${GREEN}✓ Directories created at $INSTALL_DIR${NC}"
}

# ✅ FIXED: Proper authentication flow with terminal check
authenticate_user() {
    echo ""
    echo -e "${BOLD}DistributeX Setup${NC}\n"
    
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
    
    # ✅ PARSE RESPONSE
    if echo "$response" | grep -q '"success":true'; then
        TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        USER_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        USER_ROLE=$(echo "$response" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
        
        # ✅ EXTRACT WORKER CREDENTIALS IF AVAILABLE
        WORKER_ID=$(echo "$response" | grep -o '"workerId":"[^"]*"' | cut -d'"' -f4)
        WORKER_NAME=$(echo "$response" | grep -o '"workerName":"[^"]*"' | cut -d'"' -f4)
        
        echo ""
        echo -e "${GREEN}✅ Authentication successful!${NC}"
        
        # ✅ IF NO WORKER BUT USER IS CONTRIBUTOR, CREATE ONE
        if [ -z "$WORKER_ID" ] && ([ "$USER_ROLE" == "contributor" ] || [ "$USER_ROLE" == "both" ]); then
            echo ""
            echo -e "${YELLOW}Registering worker node...${NC}"
            
            worker_response=$(curl -s -X POST "$API_URL/api/workers/register" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $TOKEN" \
                -d "{\"nodeName\":\"$(hostname)-node\",\"cpuCores\":1,\"memoryGb\":1}")
            
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

# ✅ SAVE CONFIGURATION WITH WORKER INFO
save_config() {
    cat > "$INSTALL_DIR/config.json" << EOF
{
  "apiUrl": "$API_URL",
  "coordinatorUrl": "$COORDINATOR_URL/ws",
  "authToken": "$TOKEN",
  "workerId": "$WORKER_ID",
  "userId": "$USER_ID",
  "nodeName": "$WORKER_NAME",
  "allowNetwork": false,
  "maxCpuCores": null,
  "maxMemoryGb": null,
  "maxStorageGb": null,
  "enableGpu": false,
  "installedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    chmod 600 "$INSTALL_DIR/config.json"
    echo -e "${GREEN}✓ Configuration saved${NC}"
}

install_cli() {
    echo ""
    echo -e "${BOLD}Installing CLI...${NC}"
    
    # Download CLI from your repo or embed it
    curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/dxcloud.sh \
        -o "$INSTALL_DIR/bin/dxcloud" 2>/dev/null || {
        # Fallback: Use embedded version from earlier
        cp /path/to/embedded/dxcloud "$INSTALL_DIR/bin/dxcloud"
    }
    
    chmod +x "$INSTALL_DIR/bin/dxcloud"
    
    # Create symlink
    if [ -w "$BIN_DIR" ]; then
        ln -sf "$INSTALL_DIR/bin/dxcloud" "$BIN_DIR/dxcloud"
    else
        sudo ln -sf "$INSTALL_DIR/bin/dxcloud" "$BIN_DIR/dxcloud"
    fi
    
    echo -e "${GREEN}✓ CLI installed${NC}"
}

install_worker() {
    echo ""
    echo -e "${BOLD}Installing worker daemon...${NC}"
    
    # ✅ USE THE ENHANCED WORKER FROM YOUR REPO
    curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cloud-network/main/packages/worker-node/distributex-worker.js \
        -o "$INSTALL_DIR/bin/worker.js" 2>/dev/null || {
        echo -e "${RED}Failed to download worker${NC}"
        exit 1
    }
    
    chmod +x "$INSTALL_DIR/bin/worker.js"
    
    # Install dependencies
    cd "$INSTALL_DIR/bin"
    cat > package.json <<'PKG'
{
  "name": "distributex-worker",
  "version": "1.0.0",
  "dependencies": {
    "ws": "^8.18.0",
    "dockerode": "^4.0.2"
  }
}
PKG
    
    echo -e "${YELLOW}Installing dependencies...${NC}"
    npm install --silent 2>&1 | grep -v "npm WARN" || true
    cd - >/dev/null
    
    echo -e "${GREEN}✓ Worker installed${NC}"
}

show_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                                                      ║${NC}"
    echo -e "${GREEN}${BOLD}║          ✅  Installation Complete!                 ║${NC}"
    echo -e "${GREEN}${BOLD}║                                                      ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ "$USER_ROLE" == "contributor" ] || [ "$USER_ROLE" == "both" ]; then
        echo -e "${BOLD}Start your worker:${NC}"
        echo -e "  ${CYAN}node $INSTALL_DIR/bin/worker.js${NC}"
        echo ""
        echo -e "${BOLD}Or run as service:${NC}"
        echo -e "  ${CYAN}dxcloud worker start${NC}"
        echo ""
    fi
    
    if [ "$USER_ROLE" == "developer" ] || [ "$USER_ROLE" == "both" ]; then
        echo -e "${BOLD}Submit a job:${NC}"
        echo -e "  ${CYAN}dxcloud submit --image python:3.11 --command 'python -c \"print(1+1)\"'${NC}"
        echo ""
    fi
    
    echo -e "${BOLD}Check status:${NC}"
    echo -e "  ${CYAN}dxcloud pool status${NC}"
    echo ""
}

# Main execution
main() {
    show_banner
    check_requirements
    setup_directories
    authenticate_user
    save_config
    install_cli
    
    # Only install worker if contributor/both
    if [ "$USER_ROLE" == "contributor" ] || [ "$USER_ROLE" == "both" ]; then
        install_worker
    fi
    
    show_completion
}

main
