#!/bin/bash
set -e
set -o pipefail

#
# DistributeX Complete Installer with Docker Auto-Install
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash
#

# Configuration
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Global variables
declare OS ARCH HOSTNAME CPU_CORES CPU_MODEL RAM_TOTAL RAM_AVAILABLE
declare STORAGE_TOTAL STORAGE_AVAILABLE MAC_ADDRESS DEVICE_ID
declare GPU_AVAILABLE GPU_MODEL GPU_MEMORY GPU_COUNT GPU_DRIVER GPU_CUDA
declare CPU_SHARE RAM_SHARE STORAGE_SHARE GPU_SHARE
declare API_TOKEN WORKER_ID

# Logging Functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"; }

# Interactive input function with fallback
read_input() {
    local prompt="$1"
    local silent="$2"
    local value=""
    
    if [ -t 0 ]; then
        if [ "$silent" = "true" ]; then
            read -s -r -p "$prompt" value
            echo "" >&2
        else
            read -r -p "$prompt" value
        fi
    elif [ -c /dev/tty ]; then
        if [ "$silent" = "true" ]; then
            read -s -r -p "$prompt" value < /dev/tty
            echo "" >&2
        else
            read -r -p "$prompt" value < /dev/tty
        fi
    else
        error "Cannot read input: no terminal available"
    fi
    
    echo "$value"
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

# Install Docker
install_docker() {
    section "Installing Docker"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$OS" = "linux" ]; then
        install_docker_linux
    elif [ "$OS" = "darwin" ]; then
        install_docker_macos
    else
        error "Unsupported operating system: $OS"
    fi
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

# Docker installation for Debian/Ubuntu
install_docker_debian_based() {
    info "Installing Docker on Debian/Ubuntu..."
    
    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
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

# Generic Docker installation (using convenience script)
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

# Install Docker on macOS
install_docker_macos() {
    info "Docker Desktop required for macOS"
    echo ""
    echo "Please install Docker Desktop from:"
    echo "  https://www.docker.com/products/docker-desktop"
    echo ""
    echo "After installation, restart this script."
    error "Docker Desktop must be installed manually on macOS"
}

# Install required dependencies
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

# Check System Requirements
check_requirements() {
    section "Checking System Requirements"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        warn "Docker is not installed"
        echo ""
        local install_docker_choice=$(read_input "${BOLD}Would you like to install Docker now? [y/N]: ${NC}")
        
        if [[ "$install_docker_choice" =~ ^[Yy]$ ]]; then
            install_docker
            
            # Wait for Docker to start
            info "Waiting for Docker to start..."
            sleep 5
            
            # Verify installation
            if ! command -v docker &> /dev/null; then
                error "Docker installation failed"
            fi
        else
            error "Docker is required. Please install it from: https://docs.docker.com/get-docker/"
        fi
    fi
    
    # Check if Docker daemon is running
    if ! docker ps &> /dev/null; then
        warn "Docker daemon is not running. Attempting to start..."
        
        if command -v systemctl &> /dev/null; then
            sudo systemctl start docker 2>/dev/null || true
            sleep 3
        elif [ "$(uname)" = "Darwin" ]; then
            open -a Docker 2>/dev/null || true
            info "Please start Docker Desktop manually if it didn't open"
            sleep 10
        fi
        
        if ! docker ps &> /dev/null; then
            error "Docker is not running. Please start Docker and try again."
        fi
    fi
    
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
        local install_deps_choice=$(read_input "${BOLD}Would you like to install missing dependencies? [y/N]: ${NC}")
        
        if [[ "$install_deps_choice" =~ ^[Yy]$ ]]; then
            install_dependencies
        else
            error "Required commands missing: ${missing[*]}"
        fi
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

# User Authentication
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
    
    while true; do
        local choice=$(read_input "${BOLD}Enter your choice [1 or 2]: ${NC}")
        
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
    
    local first_name=$(read_input "${BOLD}First Name: ${NC}")
    local last_name=$(read_input "${BOLD}Last Name: ${NC}")
    local email=$(read_input "${BOLD}Email: ${NC}")
    
    local password password_confirm
    while true; do
        password=$(read_input "${BOLD}Password (min 8 chars): ${NC}" "true")
        
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
    
    local email=$(read_input "${BOLD}Email: ${NC}")
    local password=$(read_input "${BOLD}Password: ${NC}" "true")
    
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
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in successfully!"
    echo ""
}

# Detect GPU
detect_gpu() {
    GPU_AVAILABLE=false
    GPU_MODEL=""
    GPU_MEMORY=0
    GPU_COUNT=0
    GPU_DRIVER=""
    GPU_CUDA=""
    
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            GPU_AVAILABLE=true
            GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -n1 || echo 1)
            GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "NVIDIA GPU")
            GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo 0)
            GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || echo "Unknown")
            
            if command -v nvcc &> /dev/null; then
                GPU_CUDA=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $5}' | cut -d',' -f1)
            else
                GPU_CUDA=$(nvidia-smi 2>/dev/null | grep "CUDA Version" | awk '{print $9}')
            fi
        fi
    fi
    
    if [ "$GPU_AVAILABLE" = false ] && command -v rocm-smi &> /dev/null; then
        if rocm-smi &> /dev/null 2>&1; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(rocm-smi --showproductname 2>/dev/null | grep "Card series" | awk -F': ' '{print $2}' || echo "AMD GPU")
            GPU_COUNT=1
            GPU_DRIVER=$(rocm-smi --showdriverversion 2>/dev/null | grep "Driver version" | awk '{print $3}' || echo "Unknown")
        fi
    fi
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
            name: $name
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

    # Send registration request
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

    echo "$WORKER_ID" > "$CONFIG_DIR/worker-id"
    chmod 600 "$CONFIG_DIR/worker-id"

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
    
    info "Starting always-on worker container..."
    
    # Build docker run command
    local docker_cmd="docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        -e DISTRIBUTEX_API_URL=\"$DISTRIBUTEX_API_URL\" \
        -e API_TOKEN=\"$API_TOKEN\" \
        -e WORKER_ID=\"$WORKER_ID\" \
        -e MAC_ADDRESS=\"${MAC_ADDRESS:-$DEVICE_ID}\" \
        -v \"$CONFIG_DIR:/config:ro\""
    
    # Add GPU support if available
    if [ "$GPU_AVAILABLE" = true ]; then
        if command -v nvidia-smi &> /dev/null; then
            docker_cmd="$docker_cmd --gpus all"
        fi
    fi
    
    # Complete command
    docker_cmd="$docker_cmd $DOCKER_IMAGE --api-key $API_TOKEN --url $DISTRIBUTEX_API_URL"
    
    # Execute
    if eval "$docker_cmd" &> /dev/null; then
        sleep 3
        
        # Verify container is running
        if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
            log "Worker container started successfully"
            echo ""
            info "Container configured with:"
            echo "  ✓ Always-on restart policy (survives reboots)"
            echo "  ✓ Auto-restart on failure"
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
    
    # Create convenient aliases
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
    ✓ Container configured for auto-restart
    ✓ Management tools installed
EOF
    echo -e "${NC}"
    
    echo ""
    echo -e "${CYAN}${BOLD}Worker Information:${NC}"
    echo -e "  Worker ID:    ${GREEN}$WORKER_ID${NC}"
    echo -e "  Device ID:    ${GREEN}$DEVICE_ID${NC}"
    echo -e "  Container:    ${GREEN}$CONTAINER_NAME${NC}"
    echo -e "  Status:       ${GREEN}Running${NC}"
    
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

# Cleanup on Error
cleanup_on_error() {
    warn "Cleaning up after error..."
    docker stop $CONTAINER_NAME &> /dev/null || true
    docker rm $CONTAINER_NAME &> /dev/null || true
}

# Error trap
trap cleanup_on_error ERR

# Main Installation Flow
main() {
    show_banner
    check_requirements
    authenticate_user
    detect_system
    register_worker
    pull_docker_image
    start_worker_container
    setup_systemd_autostart
    create_management_script
    show_success
}

# Run main function
main "$@"
