#!/bin/bash
set -e
set -o pipefail

#
# DistributeX Universal Installer
# Supports: Linux, macOS, Windows (via WSL/Git Bash)
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash
#

# Configuration
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

# Default runtime options (may be changed interactively)
RESTART_POLICY="always"    # will be changed to "no" for on-demand
SETUP_SYSTEMD=false       # whether to create systemd unit (if linux)
# Colors (with Windows compatibility)
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; BOLD=''; NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
fi

# Global variables
declare OS ARCH HOSTNAME CPU_CORES CPU_MODEL RAM_TOTAL RAM_AVAILABLE
declare STORAGE_TOTAL STORAGE_AVAILABLE MAC_ADDRESS DEVICE_ID
declare GPU_AVAILABLE GPU_MODEL GPU_MEMORY GPU_COUNT GPU_DRIVER GPU_CUDA
declare CPU_SHARE RAM_SHARE STORAGE_SHARE GPU_SHARE
declare API_TOKEN WORKER_ID
declare IS_WSL=false
declare IS_WINDOWS=false

# Logging Functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"; }

# Enhanced input function with better terminal handling
read_input() {
    local prompt="$1"
    local silent="$2"
    local value=""
    
    # Save terminal state
    if [ "$silent" = "true" ]; then
        stty_orig=$(stty -g 2>/dev/null) || true
    fi
    
    # Try multiple input methods
    if [ -t 0 ]; then
        # Standard input available
        if [ "$silent" = "true" ]; then
            read -s -r -p "$prompt" value
            echo "" >&2
        else
            read -r -p "$prompt" value
        fi
    elif [ -c /dev/tty ]; then
        # Try /dev/tty
        exec </dev/tty
        if [ "$silent" = "true" ]; then
            read -s -r -p "$prompt" value
            echo "" >&2
        else
            read -r -p "$prompt" value
        fi
    else
        # Last resort
        if [ "$silent" = "true" ]; then
            read -s -r -p "$prompt" value
            echo "" >&2
        else
            read -r -p "$prompt" value
        fi
    fi
    
    # Restore terminal state
    if [ "$silent" = "true" ] && [ -n "$stty_orig" ]; then
        stty "$stty_orig" 2>/dev/null || true
    fi
    
    echo "$value"
}

# Detect Windows/WSL
detect_windows() {
    if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
        IS_WSL=true
        info "Running in WSL (Windows Subsystem for Linux)"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        IS_WINDOWS=true
        info "Running in Windows environment"
    fi
}

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        ██████╗ ██╗███████╗████████╗██████╗ ██╗██╗         ║
║        ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║╚██╗        ║
║        ██║  ██║██║███████╗   ██║   ██████╔╝██║ ██║        ║
║        ██║  ██║██║╚════██║   ██║   ██╔══██╗██║ ██║        ║
║        ██████╔╝██║███████║   ██║   ██║  ██║██║██╔╝        ║
║        ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝         ║
║                                                           ║
║              DistributeX Cloud Network                    ║
║           Distributed Computing Platform                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
}

# Install dependencies
install_dependencies() {
    section "Installing Required Dependencies"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$OS" = "linux" ]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y curl jq bc
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y curl jq bc
        elif command -v yum &> /dev/null; then
            sudo yum install -y curl jq bc
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy --noconfirm curl jq bc
        else
            warn "Could not install dependencies automatically"
            info "Please install manually: curl, jq, bc"
        fi
    elif [ "$OS" = "darwin" ]; then
        if ! command -v brew &> /dev/null; then
            warn "Homebrew not found. Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install curl jq bc 2>/dev/null || true
    fi
    
    log "Dependencies installed"
}

# Docker installation for Debian/Ubuntu
install_docker_debian_based() {
    info "Installing Docker on Debian/Ubuntu..."
    
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    
    log "Docker installed successfully!"
    warn "You may need to log out and back in for group changes to take effect"
}

# Docker installation for Fedora
install_docker_fedora() {
    info "Installing Docker on Fedora..."
    
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    
    log "Docker installed successfully!"
}

# Docker installation for RHEL/CentOS
install_docker_rhel() {
    info "Installing Docker on RHEL/CentOS..."
    
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    
    log "Docker installed successfully!"
}

# Docker installation for Arch Linux
install_docker_arch() {
    info "Installing Docker on Arch Linux..."
    
    sudo pacman -Sy --noconfirm docker docker-compose
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    
    log "Docker installed successfully!"
}

# Generic Docker installation
install_docker_generic() {
    info "Using Docker convenience script..."
    
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh
    
    sudo systemctl start docker 2>/dev/null || true
    sudo systemctl enable docker 2>/dev/null || true
    sudo usermod -aG docker $USER 2>/dev/null || true
    
    log "Docker installed successfully!"
}

# Install Docker on Linux
install_docker_linux() {
    info "Detecting Linux distribution..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        error "Cannot detect Linux distribution"
    fi
    
    info "Installing Docker on $DISTRO..."
    
    case "$DISTRO" in
        ubuntu|debian)
            install_docker_debian_based
            ;;
        fedora)
            install_docker_fedora
            ;;
        centos|rhel)
            install_docker_rhel
            ;;
        arch|manjaro)
            install_docker_arch
            ;;
        *)
            warn "Distribution $DISTRO not directly supported"
            info "Attempting generic installation..."
            install_docker_generic
            ;;
    esac
}

# Install Docker on macOS
install_docker_macos() {
    info "Checking for Docker Desktop on macOS..."
    
    if [ -d "/Applications/Docker.app" ]; then
        info "Docker Desktop found, checking if running..."
        
        if ! docker ps &> /dev/null; then
            warn "Docker Desktop is installed but not running"
            echo ""
            echo "Starting Docker Desktop..."
            open -a Docker
            
            info "Waiting for Docker to start (this may take a minute)..."
            local max_wait=120
            local waited=0
            while ! docker ps &> /dev/null && [ $waited -lt $max_wait ]; do
                sleep 5
                waited=$((waited + 5))
                echo -n "."
            done
            echo ""
            
            if docker ps &> /dev/null; then
                log "Docker Desktop started successfully"
            else
                error "Docker Desktop failed to start. Please start it manually and try again."
            fi
        else
            log "Docker Desktop is already running"
        fi
    else
        echo ""
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  Docker Desktop Required for macOS                        ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Please install Docker Desktop:"
        echo "  1. Visit: https://www.docker.com/products/docker-desktop"
        echo "  2. Download Docker Desktop for Mac"
        echo "  3. Install and start Docker Desktop"
        echo "  4. Wait for Docker to be fully running"
        echo "  5. Re-run this installer"
        echo ""
        
        local open_browser=$(read_input "Open Docker Desktop download page? [y/N]: ")
        if [[ "$open_browser" =~ ^[Yy]$ ]]; then
            open "https://www.docker.com/products/docker-desktop"
        fi
        
        error "Please install Docker Desktop and try again"
    fi
}

# Install Docker on Windows
install_docker_windows() {
    if [ "$IS_WSL" = true ]; then
        info "Running in WSL - checking for Docker Desktop..."
        
        if ! docker ps &> /dev/null; then
            echo ""
            echo "╔════════════════════════════════════════════════════════════╗"
            echo "║  Docker Desktop Required for WSL                          ║"
            echo "╚════════════════════════════════════════════════════════════╝"
            echo ""
            echo "To use Docker in WSL, you need:"
            echo "  1. Docker Desktop for Windows"
            echo "  2. WSL integration enabled in Docker Desktop settings"
            echo ""
            echo "Installation steps:"
            echo "  1. Download from: https://www.docker.com/products/docker-desktop"
            echo "  2. Install Docker Desktop on Windows"
            echo "  3. Open Docker Desktop"
            echo "  4. Go to Settings > Resources > WSL Integration"
            echo "  5. Enable integration with your WSL distro"
            echo "  6. Restart WSL: wsl --shutdown (in PowerShell)"
            echo "  7. Re-run this installer"
            echo ""
            error "Docker Desktop with WSL integration is required"
        else
            log "Docker is accessible from WSL"
        fi
    else
        error "Native Windows installation not supported. Please use WSL2 or Git Bash with Docker Desktop"
    fi
}

# Install Docker
install_docker() {
    section "Installing Docker"
    
    detect_windows
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$IS_WSL" = true ] || [ "$IS_WINDOWS" = true ]; then
        install_docker_windows
    elif [ "$OS" = "darwin" ]; then
        install_docker_macos
    elif [ "$OS" = "linux" ]; then
        install_docker_linux
    else
        error "Unsupported operating system: $OS"
    fi
}

# Check System Requirements
check_requirements() {
    section "Checking System Requirements"
    
    detect_windows
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        warn "Docker is not installed"
        echo ""
        
        local install_docker_choice=""
        while [ -z "$install_docker_choice" ]; do
            install_docker_choice=$(read_input "${BOLD}Would you like to install Docker now? [y/N]: ${NC}")
            
            if [[ "$install_docker_choice" =~ ^[Yy]$ ]]; then
                install_docker
                
                info "Waiting for Docker to start..."
                sleep 5
                
                if ! command -v docker &> /dev/null; then
                    error "Docker installation failed"
                fi
                break
            elif [[ "$install_docker_choice" =~ ^[Nn]$ ]] || [ -z "$install_docker_choice" ]; then
                error "Docker is required. Please install it from: https://docs.docker.com/get-docker/"
            else
                warn "Please answer 'y' or 'n'"
                install_docker_choice=""
            fi
        done
    fi
    
    # Check if Docker daemon is running - with retries
    local docker_retry=0
    local max_retries=3
    while ! docker ps &> /dev/null && [ $docker_retry -lt $max_retries ]; do
        docker_retry=$((docker_retry + 1))
        warn "Docker daemon is not running (attempt $docker_retry/$max_retries)"
        
        if command -v systemctl &> /dev/null; then
            info "Attempting to start Docker service..."
            sudo systemctl start docker 2>/dev/null || true
            sleep 3
        elif [ "$(uname)" = "Darwin" ]; then
            info "Attempting to start Docker Desktop..."
            open -a Docker 2>/dev/null || true
            info "Waiting for Docker Desktop to start..."
            sleep 15
        elif [ "$IS_WSL" = true ]; then
            warn "Please ensure Docker Desktop is running on Windows with WSL integration enabled"
            sleep 5
        fi
        
        if docker ps &> /dev/null; then
            break
        fi
        
        if [ $docker_retry -ge $max_retries ]; then
            error "Docker is not running. Please start Docker and try again."
        fi
    done
    
    # Check required commands
    local missing=()
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        warn "Missing required commands: ${missing[*]}"
        echo ""
        
        local install_deps_choice=""
        while [ -z "$install_deps_choice" ]; do
            install_deps_choice=$(read_input "${BOLD}Would you like to install missing dependencies? [y/N]: ${NC}")
            
            if [[ "$install_deps_choice" =~ ^[Yy]$ ]]; then
                install_dependencies
                break
            elif [[ "$install_deps_choice" =~ ^[Nn]$ ]] || [ -z "$install_deps_choice" ]; then
                error "Required commands missing: ${missing[*]}"
            else
                warn "Please answer 'y' or 'n'"
                install_deps_choice=""
            fi
        done
    fi
    
    log "All requirements satisfied"
    log "Docker version: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
}

# Get MAC Address
get_mac_address() {
    local mac=""
    local os_type=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$os_type" = "linux" ]; then
        for interface in eth0 en0 wlan0 wlp0s20f3 enp0s3 ens33 enp0s31f6 eno1; do
            if command -v ip &> /dev/null; then
                mac=$(ip link show "$interface" 2>/dev/null | awk '/link\/ether/ {print $2}')
            elif command -v ifconfig &> /dev/null; then
                mac=$(ifconfig "$interface" 2>/dev/null | awk '/ether/ {print $2}')
            fi
            [ -n "$mac" ] && break
        done
        
        if [ -z "$mac" ] && command -v ip &> /dev/null; then
            mac=$(ip link show 2>/dev/null | awk '/link\/ether/ {print $2; exit}')
        fi
    elif [ "$os_type" = "darwin" ]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2}')
        [ -z "$mac" ] && mac=$(ifconfig en1 2>/dev/null | awk '/ether/ {print $2}')
    fi
    
    if [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        echo "$mac"
    else
        echo ""
    fi
}

# Generate Device ID
generate_device_id() {
    local mac=$(get_mac_address)
    
    if [ -z "$mac" ]; then
        warn "MAC address not detected, generating fallback identifier"
        
        if command -v md5sum &> /dev/null; then
            echo "$(hostname)-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)" | md5sum | cut -d' ' -f1
        elif command -v md5 &> /dev/null; then
            echo "$(hostname)-$(date +%s)" | md5 | cut -d' ' -f1
        else
            echo "fallback-$(date +%s)-$$"
        fi
    else
        echo "$mac" | tr '[:upper:]' '[:lower:]' | tr -d ':'
    fi
}

# User Authentication with better input handling
authenticate_user() {
    section "User Authentication"
    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_DIR/token" ]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $API_TOKEN" \
            "$DISTRIBUTEX_API_URL/api/auth/user" 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ]; then
            log "Using existing authentication"
            return 0
        else
            warn "Existing token expired, please log in again"
            rm -f "$CONFIG_DIR/token"
        fi
    fi

    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║   Choose Authentication Method    ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Sign up (New user)"
    echo -e "  ${GREEN}2)${NC} Login (Existing user)"
    echo ""
    
    local choice=""
    while true; do
        choice=$(read_input "${BOLD}Enter your choice [1 or 2]: ${NC}")
        
        choice=$(echo "$choice" | tr -d '[:space:]')
        
        case "$choice" in
            1)
                signup_user
                log "Signup complete, now logging in..."
                login_user
                break
                ;;
            2)
                login_user
                break
                ;;
            *)
                warn "Invalid choice. Please enter 1 or 2."
                sleep 1
                ;;
        esac
    done
}

signup_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}     Create Your Account${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local first_name=""
    local last_name=""
    local email=""
    local password=""
    local password_confirm=""
    
    while [ -z "$first_name" ]; do
        first_name=$(read_input "${BOLD}First Name: ${NC}")
    done
    
    while [ -z "$last_name" ]; do
        last_name=$(read_input "${BOLD}Last Name: ${NC}")
    done
    
    while [ -z "$email" ]; do
        email=$(read_input "${BOLD}Email: ${NC}")
    done
    
    while true; do
        password=$(read_input "${BOLD}Password (min 8 chars): ${NC}" "true")
        
        if [ -z "$password" ]; then
            warn "Password cannot be empty"
            continue
        fi
        
        if [ ${#password} -lt 8 ]; then
            warn "Password must be at least 8 characters"
            continue
        fi
        
        password_confirm=$(read_input "${BOLD}Confirm Password: ${NC}" "true")
        
        if [ "$password" != "$password_confirm" ]; then
            warn "Passwords do not match. Please try again."
            continue
        fi
        break
    done

    echo ""
    info "Creating account..."
    
    local response=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\"}")
    
    local http_body=$(echo "$response" | head -n -1)
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        local error_msg=$(echo "$http_body" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Signup failed")
        error "Signup failed: $error_msg"
    fi

    log "Account created successfully!"
}

login_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}     Login to Your Account${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local email=""
    local password=""
    
    while [ -z "$email" ]; do
        email=$(read_input "${BOLD}Email: ${NC}")
    done
    
    while [ -z "$password" ]; do
        password=$(read_input "${BOLD}Password: ${NC}" "true")
    done
    
    info "Logging in..."
    local response=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    
    local http_body=$(echo "$response" | head -n -1)
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" != "200" ]; then
        local error_msg=$(echo "$http_body" | jq -r '.message // "Invalid credentials"' 2>/dev/null || echo "Login failed")
        error "Login failed: $error_msg"
    fi

    API_TOKEN=$(echo "$http_body" | jq -r '.token' 2>/dev/null)
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No authentication token returned"
    fi
    
    mkdir -p "$CONFIG_DIR"
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in successfully!"
    echo ""
}

# Detect GPU
detect_gpu() {
    GPU_AVAILABLE=false
    GPU_MODEL="Unknown"
    GPU_MEMORY=0
    GPU_COUNT=0
    GPU_DRIVER="Unknown"
    GPU_CUDA=""

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    # ----------------------------
    # 1. NVIDIA GPU (Best / Full)
    # ----------------------------
    if command -v nvidia-smi &>/dev/null; then
        GPU_AVAILABLE=true
        GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)
        GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
        GPU_CUDA=$(nvidia-smi | grep "CUDA Version" | awk -F'CUDA Version:' '{print $2}' | xargs)
        return
    fi

    # ----------------------------
    # 2. AMD GPU (ROCm or lspci)
    # ----------------------------
    if command -v rocminfo &>/dev/null; then
        GPU_AVAILABLE=true
        GPU_MODEL=$(rocminfo | grep -m1 "Name:" | awk -F': ' '{print $2}')
        GPU_COUNT=$(rocminfo | grep "Compute Unit:" | wc -l)
        GPU_MEMORY=$(rocminfo | grep -m1 "Device Memory" | grep -o "[0-9]*")
        GPU_DRIVER="ROCm"
        return
    fi

    # Fallback AMD detection via lspci
    if command -v lspci &>/dev/null; then
        if lspci | grep -qiE "AMD.*(VGA|Display|3D)"; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(lspci | grep -iE "AMD.*(VGA|Display|3D)" | head -n1 | cut -d: -f3 | xargs)
            GPU_COUNT=$(lspci | grep -iE "AMD.*(VGA|Display|3D)" | wc -l)
            GPU_DRIVER="AMDGPU"
            GPU_MEMORY=0
            return
        fi
    fi

    # ----------------------------
    # 3. Intel GPU
    # ----------------------------
    if command -v lspci &>/dev/null; then
        if lspci | grep -qiE "Intel.*(VGA|Display|3D)"; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(lspci | grep -iE "Intel.*(VGA|Display|3D)" | head -n1 | cut -d: -f3 | xargs)
            GPU_COUNT=1
            GPU_DRIVER="iGPU"
            GPU_MEMORY=0
            return
        fi
    fi

    # ----------------------------
    # 4. macOS GPU (Metal)
    # ----------------------------
    if [ "$OS" = "darwin" ]; then
        GPU_AVAILABLE=true
        GPU_MODEL=$(system_profiler SPDisplaysDataType | grep "Chipset Model" | head -n1 | awk -F': ' '{print $2}')
        GPU_COUNT=1
        GPU_DRIVER="Metal"
        GPU_MEMORY=0
        return
    fi

    # ----------------------------
    # 5. No GPU detected
    # ----------------------------
    GPU_AVAILABLE=false
}

# Detect System Capabilities
detect_system() {
    section "System Detection"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    HOSTNAME=$(hostname)
    
    if [ "$OS" = "linux" ]; then
        CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown CPU")
    elif [ "$OS" = "darwin" ]; then
        CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")
    else
        CPU_CORES=4
        CPU_MODEL="Unknown CPU"
    fi
    
    if command -v free &> /dev/null; then
        RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)
        RAM_AVAILABLE=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo $((RAM_TOTAL * 80 / 100)))
    else
        RAM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 8192)
        RAM_AVAILABLE=$((RAM_TOTAL * 80 / 100))
    fi
    
    if [ "$OS" = "darwin" ]; then
        STORAGE_TOTAL=$(df -g / 2>/dev/null | tail -1 | awk '{print $2}' || echo 100)
        STORAGE_AVAILABLE=$(df -g / 2>/dev/null | tail -1 | awk '{print $4}' || echo 80)
    else
        STORAGE_TOTAL=$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo 100)
        STORAGE_AVAILABLE=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo 80)
    fi
    
    detect_gpu
    
    MAC_ADDRESS=$(get_mac_address)
    DEVICE_ID=$(generate_device_id)
    
    if [ "$CPU_CORES" -ge 8 ]; then
        CPU_SHARE=40
    elif [ "$CPU_CORES" -ge 4 ]; then
        CPU_SHARE=30
    else
        CPU_SHARE=25
    fi
    
    RAM_SHARE=30
    STORAGE_SHARE=20
    GPU_SHARE=0
    [ "$GPU_AVAILABLE" = true ] && GPU_SHARE=50
    
    log "System: $OS ($ARCH)"
    log "Hostname: $HOSTNAME"
    log "Device ID: $DEVICE_ID"
    [ -n "$MAC_ADDRESS" ] && log "MAC Address: $MAC_ADDRESS"
    log "CPU: $CPU_CORES cores - $CPU_MODEL"
    log "RAM: ${RAM_TOTAL}MB (${RAM_AVAILABLE}MB available)"
    log "Storage: ${STORAGE_TOTAL}GB (${STORAGE_AVAILABLE}GB available)"
    
    if [ "$GPU_AVAILABLE" = true ]; then
        log "GPU: $GPU_MODEL"
        log "GPU Memory: ${GPU_MEMORY}MB"
        log "GPU Count: $GPU_COUNT"
        log "GPU Driver: $GPU_DRIVER"
        [ -n "$GPU_CUDA" ] && log "CUDA Version: $GPU_CUDA"
    else
        info "No GPU detected (optional)"
    fi
    
    echo ""
    info "Sharing Configuration:"
    echo "  CPU: ${CPU_SHARE}% ($((CPU_CORES * CPU_SHARE / 100)) cores)"
    echo "  RAM: ${RAM_SHARE}% ($((RAM_TOTAL * RAM_SHARE / 100))MB)"
    echo "  Storage: ${STORAGE_SHARE}% ($((STORAGE_TOTAL * STORAGE_SHARE / 100))GB)"
    [ "$GPU_AVAILABLE" = true ] && echo "  GPU: ${GPU_SHARE}%"
}

# Register Worker
register_worker() {
    section "Registering Worker"
    
    info "Registering device with network..."
    
    local device_identifier="${MAC_ADDRESS:-$DEVICE_ID}"
    
    if [ -z "$device_identifier" ]; then
        error "Unable to generate device identifier"
    fi

    local payload=$(jq -n \
        --arg name "${HOSTNAME}" \
        --arg hostname "${HOSTNAME}" \
        --arg platform "${OS}" \
        --arg architecture "${ARCH}" \
        --argjson cpuCores "${CPU_CORES}" \
        --arg cpuModel "${CPU_MODEL}" \
        --argjson ramTotal "${RAM_TOTAL}" \
        --argjson ramAvailable "${RAM_AVAILABLE}" \
        --argjson gpuAvailable "$([ "$GPU_AVAILABLE" = true ] && echo true || echo false)" \
        --arg gpuModel "${GPU_MODEL:-null}" \
        --argjson gpuMemory "${GPU_MEMORY:-0}" \
        --argjson gpuCount "${GPU_COUNT:-0}" \
        --arg gpuDriverVersion "${GPU_DRIVER:-null}" \
        --arg gpuCudaVersion "${GPU_CUDA:-null}" \
        --argjson storageTotal "${STORAGE_TOTAL}" \
        --argjson storageAvailable "${STORAGE_AVAILABLE}" \
        --argjson cpuSharePercent "${CPU_SHARE}" \
        --argjson ramSharePercent "${RAM_SHARE}" \
        --argjson gpuSharePercent "${GPU_SHARE}" \
        --argjson storageSharePercent "${STORAGE_SHARE}" \
        --arg macAddress "${device_identifier}" \
        '{
            name: $name,
            hostname: $hostname,
            platform: $platform,
            architecture: $architecture,
            cpuCores: $cpuCores,
            cpuModel: $cpuModel,
            ramTotal: $ramTotal,
            ramAvailable: $ramAvailable,
            gpuAvailable: $gpuAvailable,
            gpuModel: $gpuModel,
            gpuMemory: $gpuMemory,
            gpuCount: $gpuCount,
            gpuDriverVersion: $gpuDriverVersion,
            gpuCudaVersion: $gpuCudaVersion,
            storageTotal: $storageTotal,
            storageAvailable: $storageAvailable,
            cpuSharePercent: $cpuSharePercent,
            ramSharePercent: $ramSharePercent,
            gpuSharePercent: $gpuSharePercent,
            storageSharePercent: $storageSharePercent,
            macAddress: $macAddress
        }')

    local response=$(curl -s -w "\n%{http_code}" -X POST \
        "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1)

    local http_body=$(echo "$response" | head -n -1)
    local http_code=$(echo "$response" | tail -n 1)

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        local error_msg=$(echo "$http_body" | jq -r '.message // .error // "Registration failed"' 2>/dev/null || echo "Registration failed")
        error "Worker registration failed (HTTP $http_code): $error_msg"
    fi

    WORKER_ID=$(echo "$http_body" | jq -r '.worker.id // .id' 2>/dev/null)
    local is_new=$(echo "$http_body" | jq -r '.isNew // false' 2>/dev/null)
    
    if [ -z "$WORKER_ID" ] || [ "$WORKER_ID" = "null" ]; then
        error "Worker registered but no ID returned"
    fi

    mkdir -p "$CONFIG_DIR"

    # Save Worker ID
    echo "$WORKER_ID" > "$CONFIG_DIR/worker-id"
    chmod 600 "$CONFIG_DIR/worker-id"

    # Save API Token (needed for container + CLI)
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"

    # Full JSON config for the app, dashboard, container, CLI, etc.
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "workerId": "$WORKER_ID",
  "token": "$API_TOKEN",
  "deviceId": "$DEVICE_ID",
  "cpu": "$CPU_SHARE",
  "ram": "$RAM_SHARE",
  "storage": "$STORAGE_SHARE",
  "gpu": "$GPU_SHARE",
  "restartPolicy": "$RESTART_POLICY",
  "systemdEnabled": "$SETUP_SYSTEMD",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    chmod 600 "$CONFIG_DIR/config.json"

    # Output status
    if [ "$is_new" = "true" ]; then
        log "Worker registered successfully: $WORKER_ID"
    else
        log "Worker reconnected (existing device): $WORKER_ID"
    fi

    echo ""
}

# Pull Docker Image
pull_docker_image() {
    section "Preparing Docker Image"
    info "Pulling latest worker image..."
    
    if docker pull $DOCKER_IMAGE 2>&1 | grep -v "^$"; then
        log "Docker image ready: $DOCKER_IMAGE"
    else
        error "Failed to pull Docker image"
    fi
}

# Stop Existing Container
stop_existing_container() {
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        warn "Stopping existing container..."
        docker stop $CONTAINER_NAME &> /dev/null || true
        docker rm $CONTAINER_NAME &> /dev/null || true
        log "Existing container removed"
    fi
}

# Start Worker Container
start_worker_container() {
    section "Starting Worker Container"
    
    stop_existing_container
    
    info "Starting worker container (restart policy: $RESTART_POLICY)..."
    
    # Build docker run command safely
    local docker_cmd=(docker run -d --name "$CONTAINER_NAME" --restart "$RESTART_POLICY" -e "DISTRIBUTEX_API_URL=$DISTRIBUTEX_API_URL" -e "API_TOKEN=$API_TOKEN" -e "WORKER_ID=$WORKER_ID" -e "MAC_ADDRESS=${MAC_ADDRESS:-$DEVICE_ID}" -v "$CONFIG_DIR:/config:ro")

    # GPU support
    if [ "$GPU_AVAILABLE" = true ]; then
        if command -v nvidia-smi &> /dev/null; then
            docker_cmd+=("--gpus" "all")
        fi
    fi

    docker_cmd+=("$DOCKER_IMAGE" "--api-key" "$API_TOKEN" "--url" "$DISTRIBUTEX_API_URL")

    # Run the container
    if "${docker_cmd[@]}" &> /dev/null; then
        sleep 3
        
        if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
            log "Worker container started successfully"
            echo ""
            info "Container configured with:"
            echo "  ✓ Restart policy: $RESTART_POLICY"
            echo "  ✓ Auto-restart on failure (if restart policy enabled)"
            echo "  ✓ Background daemon mode"
            [ "$GPU_AVAILABLE" = true ] && echo "  ✓ GPU access enabled"
        else
            error "Container started but is not running"
        fi
    else
        error "Failed to start container"
    fi
}

# Setup systemd service
setup_systemd_autostart() {
    if [ "$OS" != "linux" ]; then
        return
    fi
    
    if ! command -v systemctl &> /dev/null; then
        return
    fi
    
    if [ "$SETUP_SYSTEMD" != true ]; then
        info "Systemd autostart not requested by user, skipping"
        return
    fi

    section "Setting Up Auto-Start"
    
    info "Creating systemd service..."
    
    sudo tee /etc/systemd/system/distributex-worker.service > /dev/null <<EOF
[Unit]
Description=DistributeX Worker Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start $CONTAINER_NAME
ExecStop=/usr/bin/docker stop $CONTAINER_NAME
User=$USER

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable distributex-worker.service &> /dev/null
    
    log "Auto-start on boot configured"
}

# Create Management Script
create_management_script() {
    section "Creating Management Tools"
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/manage.sh" <<'MGMT_EOF'
#!/bin/bash
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

case "$1" in
    start)
        echo -e "${CYAN}Starting worker...${NC}"
        docker start $CONTAINER_NAME
        ;;
    stop)
        echo -e "${YELLOW}Stopping worker...${NC}"
        docker stop $CONTAINER_NAME
        ;;
    restart)
        echo -e "${CYAN}Restarting worker...${NC}"
        docker restart $CONTAINER_NAME
        ;;
    logs)
        docker logs ${2:--f} $CONTAINER_NAME
        ;;
    status)
        echo -e "${CYAN}Worker Status:${NC}"
        docker ps -f name=$CONTAINER_NAME
        echo ""
        echo "Restart policy:"
        docker inspect $CONTAINER_NAME --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "Container not found"
        ;;
    stats)
        echo -e "${CYAN}Resource Usage:${NC}"
        docker stats --no-stream $CONTAINER_NAME
        ;;
    uninstall)
        echo -e "${YELLOW}Uninstalling...${NC}"
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
        if [ "$2" = "--purge" ]; then
            rm -rf "$CONFIG_DIR"
            echo "All data removed"
        fi
        echo -e "${GREEN}Done!${NC}"
        ;;
    *)
        echo "DistributeX Worker Management"
        echo ""
        echo "Usage: $0 {start|stop|restart|logs|status|stats|uninstall}"
        echo ""
        echo "Commands:"
        echo "  start      - Start the worker"
        echo "  stop       - Stop the worker"
        echo "  restart    - Restart the worker"
        echo "  logs       - View worker logs"
        echo "  status     - Check worker status"
        echo "  stats      - View resource usage"
        echo "  uninstall  - Remove worker (add --purge to delete all data)"
        echo ""
        exit 1
        ;;
esac
MGMT_EOF

    chmod +x "$CONFIG_DIR/manage.sh"
    
    if ! grep -q "alias distributex=" "$HOME/.bashrc" 2>/dev/null; then
        echo "alias distributex='$CONFIG_DIR/manage.sh'" >> "$HOME/.bashrc"
    fi
    
    if [ -f "$HOME/.zshrc" ] && ! grep -q "alias distributex=" "$HOME/.zshrc" 2>/dev/null; then
        echo "alias distributex='$CONFIG_DIR/manage.sh'" >> "$HOME/.zshrc"
    fi
    
    log "Management script created: $CONFIG_DIR/manage.sh"
    echo ""
    info "You can manage the worker with:"
    echo "  $CONFIG_DIR/manage.sh {start|stop|restart|logs|status|stats|uninstall}"
    echo ""
    info "Or use the alias after reloading your shell:"
    echo "  distributex {start|stop|restart|logs|status|stats|uninstall}"
}

# Display Success Summary
show_success() {
    section "Installation Complete! 🎉"
    
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"
    ✓ Worker registered and running
    ✓ Container configured for auto-restart (if selected)
    ✓ Management tools installed
EOF
    echo -e "${NC}"
    
    echo ""
    echo -e "${CYAN}${BOLD}Worker Information:${NC}"
    echo -e "  Worker ID:    ${GREEN}$WORKER_ID${NC}"
    echo -e "  Device ID:    ${GREEN}$DEVICE_ID${NC}"
    echo -e "  Container:    ${GREEN}$CONTAINER_NAME${NC}"
    local ctr_status
    ctr_status=$(docker ps --filter "name=$CONTAINER_NAME" --format '{{.Status}}' 2>/dev/null || echo "Not running")
    echo -e "  Status:       ${GREEN}${ctr_status}${NC}"
    
    echo ""
    echo -e "${CYAN}${BOLD}Resource Sharing:${NC}"
    echo -e "  CPU:          ${CPU_SHARE}% (${CPU_CORES} cores)"
    echo -e "  RAM:          ${RAM_SHARE}% (${RAM_TOTAL}MB)"
    echo -e "  Storage:      ${STORAGE_SHARE}% (${STORAGE_TOTAL}GB)"
    [ "$GPU_AVAILABLE" = true ] && echo -e "  GPU:          ${GPU_SHARE}% ($GPU_MODEL)"
    
    echo ""
    echo -e "${CYAN}${BOLD}Quick Commands:${NC}"
    echo -e "  View logs:    ${YELLOW}$CONFIG_DIR/manage.sh logs${NC}"
    echo -e "  Check status: ${YELLOW}$CONFIG_DIR/manage.sh status${NC}"
    echo -e "  View stats:   ${YELLOW}$CONFIG_DIR/manage.sh stats${NC}"
    echo -e "  Restart:      ${YELLOW}$CONFIG_DIR/manage.sh restart${NC}"
    echo -e "  Stop:         ${YELLOW}$CONFIG_DIR/manage.sh stop${NC}"
    echo -e "  Uninstall:    ${YELLOW}$CONFIG_DIR/manage.sh uninstall${NC}"
    
    echo ""
    echo -e "${CYAN}${BOLD}Dashboard:${NC}"
    echo -e "  Monitor your earnings and statistics at:"
    echo -e "  ${BLUE}https://distributex-cloud-network.pages.dev/dashboard${NC}"
    
    echo ""
    echo -e "${GREEN}${BOLD}Your worker is now earning rewards! 💰${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ──────────────────────────────────────────────────────────────
# Ask user about autostart behavior (MUST be defined BEFORE main)
# ──────────────────────────────────────────────────────────────
ask_autostart_choice() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}       Autostart / Always-on Mode${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Choose how you'd like the worker to run:"
    echo "  1) Always-on → auto-restarts + starts on boot (best for servers/desktops)"
    echo "  2) On-demand → runs only now, no auto-restart (best for laptops)"
    echo ""

    local choice=""
    while [[ -z "$choice" ]]; do
        choice=$(read_input "${BOLD}Enter your choice [1 or 2]: ${NC}")
        choice=$(echo "$choice" | tr -d '[:space:]')

        case "$choice" in
            1)
                RESTART_POLICY="always"
                if [[ "$(uname -s | tr '[:upper:]' '[:lower:]')" == "linux" ]]; then
                    SETUP_SYSTEMD=true
                else
                    SETUP_SYSTEMD=false
                fi
                info "Mode → Always-on (restart policy: always)"
                break
                ;;
            2)
                RESTART_POLICY="no"
                SETUP_SYSTEMD=false
                info "Mode → On-demand (no auto-restart)"
                break
                ;;
            *)
                warn "Please enter 1 or 2"
                choice=""
                ;;
        esac
    done
    echo ""
}

# ──────────────────────────────────────────────────────────────
# Cleanup on error
# ──────────────────────────────────────────────────────────────
cleanup_on_error() {
    warn "An error occurred – cleaning up..."
    docker stop "$CONTAINER_NAME" &>/dev/null || true
    docker rm "$CONTAINER_NAME" &>/dev/null || true
}

# ──────────────────────────────────────────────────────────────
# Error trap
# ──────────────────────────────────────────────────────────────
trap cleanup_on_error ERR

# ──────────────────────────────────────────────────────────────
# Main Installation Flow
# ──────────────────────────────────────────────────────────────
main() {
    show_banner
    check_requirements
    authenticate_user
    detect_system
    ask_autostart_choice        # now defined before main → works!
    register_worker
    pull_docker_image
    start_worker_container

    if [[ "$SETUP_SYSTEMD" == true ]]; then
        setup_systemd_autostart
    fi

    create_management_script
    show_success
}

# ──────────────────────────────────────────────────────────────
# Start the installer
# ──────────────────────────────────────────────────────────────
main "$@"
