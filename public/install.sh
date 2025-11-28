#!/bin/bash
set -e
set -o pipefail

#
# DistributeX Complete Installer - Enhanced Edition
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash
#
# Features:
# - Universal OS support (Linux, macOS, Windows via WSL)
# - Automatic Docker installation
# - GPU detection (NVIDIA, AMD, Intel, Apple)
# - Worker registration with full system detection
# - Role selection (Contributor/Developer)
# - Always-on background service with auto-restart
# - Management CLI tools
#

# Configuration
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"
RESTART_POLICY="always"
SETUP_SYSTEMD=true

# Colors with Windows compatibility
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
declare API_TOKEN WORKER_ID USER_ROLE
declare IS_WSL=false
declare IS_WINDOWS=false

# ═══════════════════════════════════════════════════════════════
# LOGGING FUNCTIONS
# ═══════════════════════════════════════════════════════════════

log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"; }

# ═══════════════════════════════════════════════════════════════
# INPUT HANDLING
# ═══════════════════════════════════════════════════════════════

read_input() {
    local prompt="$1"
    local silent="$2"
    local value=""
    
    if [ "$silent" = "true" ]; then
        stty_orig=$(stty -g 2>/dev/null) || true
    fi
    
    if [ -t 0 ]; then
        if [ "$silent" = "true" ]; then
            read -s -r -p "$prompt" value
            echo "" >&2
        else
            read -r -p "$prompt" value
        fi
    elif [ -c /dev/tty ]; then
        exec </dev/tty
        if [ "$silent" = "true" ]; then
            read -s -r -p "$prompt" value
            echo "" >&2
        else
            read -r -p "$prompt" value
        fi
    else
        if [ "$silent" = "true" ]; then
            read -s -r -p "$prompt" value
            echo "" >&2
        else
            read -r -p "$prompt" value
        fi
    fi
    
    if [ "$silent" = "true" ] && [ -n "$stty_orig" ]; then
        stty "$stty_orig" 2>/dev/null || true
    fi
    
    echo "$value"
}

# ═══════════════════════════════════════════════════════════════
# BANNER & DETECTION
# ═══════════════════════════════════════════════════════════════

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
║        ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═���═╝         ║
║                                                           ║
║              DistributeX Cloud Network                    ║
║           Distributed Computing Platform                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
}

detect_windows() {
    if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
        IS_WSL=true
        info "Running in WSL (Windows Subsystem for Linux)"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        IS_WINDOWS=true
        info "Running in Windows environment"
    fi
}

# ═══════════════════════════════════════════════════════════════
# DEPENDENCY INSTALLATION
# ═══════════════════════════════════════════════════════════════

install_dependencies() {
    section "Installing Required Dependencies"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$OS" = "linux" ]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y curl jq bc 2>/dev/null || true
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y curl jq bc 2>/dev/null || true
        elif command -v yum &> /dev/null; then
            sudo yum install -y curl jq bc 2>/dev/null || true
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy --noconfirm curl jq bc 2>/dev/null || true
        fi
    elif [ "$OS" = "darwin" ]; then
        if ! command -v brew &> /dev/null; then
            warn "Homebrew not found. Installing..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install curl jq bc 2>/dev/null || true
    fi
    
    log "Dependencies installed"
}

# ═══════════════════════════════════════════════════════════════
# DOCKER INSTALLATION
# ═══════════════════════════════════════════════════════════════

install_docker_debian() {
    info "Installing Docker on Debian/Ubuntu..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    sudo apt-get update -qq
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    log "Docker installed successfully!"
}

install_docker_macos() {
    if [ -d "/Applications/Docker.app" ]; then
        if ! docker ps &> /dev/null; then
            warn "Starting Docker Desktop..."
            open -a Docker
            info "Waiting for Docker to start..."
            local max_wait=120
            local waited=0
            while ! docker ps &> /dev/null && [ $waited -lt $max_wait ]; do
                sleep 5
                waited=$((waited + 5))
            done
            if docker ps &> /dev/null; then
                log "Docker Desktop started"
            else
                error "Docker failed to start. Please start it manually."
            fi
        fi
    else
        error "Docker Desktop not found. Install from: https://www.docker.com/products/docker-desktop"
    fi
}

install_docker_windows() {
    if [ "$IS_WSL" = true ]; then
        if ! docker ps &> /dev/null; then
            error "Docker Desktop with WSL integration required. Visit: https://www.docker.com/products/docker-desktop"
        fi
    else
        error "Please use WSL2 with Docker Desktop"
    fi
}

install_docker() {
    section "Docker Setup"
    detect_windows
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$IS_WSL" = true ] || [ "$IS_WINDOWS" = true ]; then
        install_docker_windows
    elif [ "$OS" = "darwin" ]; then
        install_docker_macos
    elif [ "$OS" = "linux" ]; then
        install_docker_debian
    fi
}

# ═══════════════════════════════════════════════════════════════
# SYSTEM REQUIREMENTS CHECK
# ═══════════════════════════════════════════════════════════════

check_requirements() {
    section "Checking System Requirements"
    detect_windows
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        warn "Docker not installed"
        local choice=$(read_input "${BOLD}Install Docker now? [Y/n]: ${NC}")
        if [[ ! "$choice" =~ ^[Nn]$ ]]; then
            install_docker
        else
            error "Docker is required"
        fi
    fi
    
    # Check Docker daemon
    local retries=0
    while ! docker ps &> /dev/null && [ $retries -lt 3 ]; do
        retries=$((retries + 1))
        warn "Docker not running (attempt $retries/3)"
        
        if command -v systemctl &> /dev/null; then
            sudo systemctl start docker 2>/dev/null || true
            sleep 3
        elif [ "$(uname)" = "Darwin" ]; then
            open -a Docker 2>/dev/null || true
            sleep 15
        fi
        
        if [ $retries -ge 3 ]; then
            error "Docker not running. Please start Docker."
        fi
    done
    
    # Check dependencies
    local missing=()
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        install_dependencies
    fi
    
    log "All requirements satisfied"
    log "Docker: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
}

# ═══════════════════════════════════════════════════════════════
# DEVICE IDENTIFICATION
# ═══════════════════════════════════════════════════════════════

get_mac_address() {
    local mac=""
    local os_type=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$os_type" = "linux" ]; then
        for iface in eth0 en0 wlan0 wlp0s20f3 enp0s3 ens33; do
            if command -v ip &> /dev/null; then
                mac=$(ip link show "$iface" 2>/dev/null | awk '/link\/ether/ {print $2}')
            elif command -v ifconfig &> /dev/null; then
                mac=$(ifconfig "$iface" 2>/dev/null | awk '/ether/ {print $2}')
            fi
            [ -n "$mac" ] && break
        done
    elif [ "$os_type" = "darwin" ]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2}')
        [ -z "$mac" ] && mac=$(ifconfig en1 2>/dev/null | awk '/ether/ {print $2}')
    fi
    
    if [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        echo "$mac"
    fi
}

generate_device_id() {
    local mac=$(get_mac_address)
    
    if [ -z "$mac" ]; then
        if command -v md5sum &> /dev/null; then
            echo "$(hostname)-$(date +%s)" | md5sum | cut -d' ' -f1
        else
            echo "fallback-$(date +%s)-$$"
        fi
    else
        echo "$mac" | tr '[:upper:]' '[:lower:]' | tr -d ':'
    fi
}

# ═══════════════════════════════════════════════════════════════
# USER AUTHENTICATION
# ═══════════════════════════════════════════════════════════════

authenticate_user() {
    section "User Authentication"
    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_DIR/token" ]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $API_TOKEN" \
            "$DISTRIBUTEX_API_URL/api/auth/user" 2>/dev/null || echo "000")
        
        if [ "$http_code" = "200" ]; then
            log "Using existing authentication"
            return 0
        else
            warn "Token expired, please log in again"
            rm -f "$CONFIG_DIR/token"
        fi
    fi

    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║   Authentication Required          ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Sign Up (New User)"
    echo -e "  ${GREEN}2)${NC} Login (Existing User)"
    echo ""
    
    local choice=""
    while true; do
        choice=$(read_input "${BOLD}Choose [1 or 2]: ${NC}")
        choice=$(echo "$choice" | tr -d '[:space:]')
        
        case "$choice" in
            1)
                signup_user
                login_user
                break
                ;;
            2)
                login_user
                break
                ;;
            *)
                warn "Please enter 1 or 2"
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
    
    local first_name last_name email password password_confirm
    
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
        
        if [ -z "$password" ] || [ ${#password} -lt 8 ]; then
            warn "Password must be at least 8 characters"
            continue
        fi
        
        password_confirm=$(read_input "${BOLD}Confirm Password: ${NC}" "true")
        
        if [ "$password" != "$password_confirm" ]; then
            warn "Passwords don't match"
            continue
        fi
        break
    done

    echo ""
    info "Creating account..."
    
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        "$DISTRIBUTEX_API_URL/api/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"firstName\":\"$first_name\",\"lastName\":\"$last_name\",\"email\":\"$email\",\"password\":\"$password\"}")
    
    local http_code=$(echo "$response" | tail -n1)
    local http_body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        local err=$(echo "$http_body" | jq -r '.message // "Signup failed"' 2>/dev/null || echo "Signup failed")
        error "$err"
    fi

    log "Account created successfully!"
}

login_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}     Login to Your Account${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local email password
    
    while [ -z "$email" ]; do
        email=$(read_input "${BOLD}Email: ${NC}")
    done
    
    while [ -z "$password" ]; do
        password=$(read_input "${BOLD}Password: ${NC}" "true")
    done
    
    info "Logging in..."
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    
    local http_body=$(echo "$response" | head -n -1)
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" != "200" ]; then
        local err=$(echo "$http_body" | jq -r '.message // "Invalid credentials"' 2>/dev/null || echo "Login failed")
        error "$err"
    fi

    API_TOKEN=$(echo "$http_body" | jq -r '.token' 2>/dev/null)
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No token returned"
    fi
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in successfully!"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# ROLE SELECTION
# ═══════════════════════════════════════════════════════════════

select_user_role() {
    section "Select Your Role"
    
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║          Choose Your Participation Type           ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} ${BOLD}Contributor${NC} - Share compute resources & earn rewards"
    echo -e "     • Run tasks on your hardware"
    echo -e "     • Earn based on contribution"
    echo -e "     • Always-on worker daemon"
    echo ""
    echo -e "  ${GREEN}2)${NC} ${BOLD}Developer${NC} - Use the network for your projects"
    echo -e "     • Submit compute tasks"
    echo -e "     • Access distributed resources"
    echo -e "     • API access & SDK"
    echo ""
    
    local choice=""
    while true; do
        choice=$(read_input "${BOLD}Choose your role [1 or 2]: ${NC}")
        choice=$(echo "$choice" | tr -d '[:space:]')
        
        case "$choice" in
            1)
                USER_ROLE="contributor"
                log "Role: Contributor (Resource Provider)"
                break
                ;;
            2)
                USER_ROLE="developer"
                log "Role: Developer (Resource Consumer)"
                break
                ;;
            *)
                warn "Please enter 1 or 2"
                ;;
        esac
    done
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# GPU DETECTION
# ═══════════════════════════════════════════════════════════════

detect_gpu() {
    GPU_AVAILABLE=false
    GPU_MODEL=""
    GPU_MEMORY=0
    GPU_COUNT=0
    GPU_DRIVER=""
    GPU_CUDA=""

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    # NVIDIA GPU
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        GPU_AVAILABLE=true
        GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
        GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
        GPU_CUDA=$(nvidia-smi | grep "CUDA Version" | awk '{print $9}')
        return
    fi

    # AMD GPU
    if command -v rocminfo &>/dev/null && rocminfo &>/dev/null; then
        GPU_AVAILABLE=true
        GPU_MODEL=$(rocminfo | grep -m1 "Name:" | awk -F': ' '{print $2}')
        GPU_COUNT=1
        GPU_DRIVER="ROCm"
        return
    fi

    # Fallback detection
    if command -v lspci &>/dev/null; then
        if lspci | grep -qiE "(VGA|3D|Display).*(NVIDIA|AMD|Intel)"; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(lspci | grep -iE "(VGA|3D|Display)" | head -n1 | cut -d: -f3 | xargs)
            GPU_COUNT=1
            GPU_DRIVER="Generic"
        fi
    fi

    # macOS GPU
    if [ "$OS" = "darwin" ]; then
        GPU_AVAILABLE=true
        GPU_MODEL=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -n1 | awk -F': ' '{print $2}' || echo "Apple GPU")
        GPU_COUNT=1
        GPU_DRIVER="Metal"
    fi
}

# ═══════════════════════════════════════════════════════════════
# SYSTEM DETECTION
# ═══════════════════════════════════════════════════════════════

detect_system() {
    section "System Detection"
   
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    HOSTNAME=$(hostname 2>/dev/null || echo "distributex-$(date +%s | tail -c 6)")
    
    # CPU
    if [ "$OS" = "linux" ]; then
        CPU_CORES=$(nproc 2>/dev/null || echo 4)
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    elif [ "$OS" = "darwin" ]; then
        CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    else
        CPU_CORES=4
        CPU_MODEL="Unknown"
    fi
    
    # RAM
    if command -v free &> /dev/null; then
        RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)
        RAM_AVAILABLE=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo $((RAM_TOTAL * 80 / 100)))
    else
        RAM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 8192)
        RAM_AVAILABLE=$((RAM_TOTAL * 80 / 100))
    fi
    
    # Storage
    if [ "$OS" = "darwin" ]; then
        STORAGE_TOTAL=$(df -g / 2>/dev/null | tail -1 | awk '{print $2}' || echo 100)
        STORAGE_AVAILABLE=$(df -g / 2>/dev/null | tail -1 | awk '{print $4}' || echo 80)
    else
        STORAGE_TOTAL=$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo 100)
        STORAGE_AVAILABLE=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo 80)
    fi
    
    # GPU
    detect_gpu
    
    # Device ID
    MAC_ADDRESS=$(get_mac_address)
    DEVICE_ID=$(generate_device_id)
    
    # Sharing percentages
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
    
    # Display
    log "System: $OS ($ARCH)"
    log "Hostname: $HOSTNAME"
    log "Device ID: $DEVICE_ID"
    [ -n "$MAC_ADDRESS" ] && log "MAC: $MAC_ADDRESS"
    log "CPU: $CPU_CORES cores - $CPU_MODEL"
    log "RAM: ${RAM_TOTAL}MB (${RAM_AVAILABLE}MB available)"
    log "Storage: ${STORAGE_TOTAL}GB (${STORAGE_AVAILABLE}GB available)"
    
    if [ "$GPU_AVAILABLE" = true ]; then
        log "GPU: $GPU_MODEL"
        [ "$GPU_MEMORY" -gt 0 ] && log "GPU Memory: ${GPU_MEMORY}MB"
        log "GPU Driver: $GPU_DRIVER"
        [ -n "$GPU_CUDA" ] && log "CUDA: $GPU_CUDA"
    else
        info "No GPU detected (optional)"
    fi
    
    echo ""
    info "Resource Sharing:"
    echo "  CPU: ${CPU_SHARE}% ($((CPU_CORES * CPU_SHARE / 100)) cores)"
    echo "  RAM: ${RAM_SHARE}% ($((RAM_TOTAL * RAM_SHARE / 100))MB)"
    echo "  Storage: ${STORAGE_SHARE}% ($((STORAGE_TOTAL * STORAGE_SHARE / 100))GB)"
    [ "$GPU_AVAILABLE" = true ] && echo "  GPU: ${GPU_SHARE}%"
}

# ═══════════════════════════════════════════════════════════════
# WORKER REGISTRATION
# ═══════════════════════════════════════════════════════════════

register_worker() {
    section "Worker Registration"
    
    info "Registering with DistributeX network..."
    
    local device_id="${MAC_ADDRESS:-$DEVICE_ID}"
    
    local payload=$(jq -n \
        --arg name "${HOSTNAME}-worker" \
        --arg hostname "$HOSTNAME" \
        --arg platform "$OS" \
        --arg arch "$ARCH" \
        --arg role "$USER_ROLE" \
        --argjson cpuCores "$CPU_CORES" \
        --arg cpuModel "$CPU_MODEL" \
        --argjson ramTotal "$RAM_TOTAL" \
        --argjson ramAvailable "$RAM_AVAILABLE" \
        --argjson gpuAvailable "$([ "$GPU_AVAILABLE" = true ] && echo true || echo false)" \
        --arg gpuModel "${GPU_MODEL:-null}" \
        --argjson gpuMemory "${GPU_MEMORY:-0}" \
        --argjson gpuCount "${GPU_COUNT:-0}" \
        --arg gpuDriver "${GPU_DRIVER:-null}" \
        --arg gpuCuda "${GPU_CUDA:-null}" \
        --argjson storageTotal "$STORAGE_TOTAL" \
        --argjson storageAvailable "$STORAGE_AVAILABLE" \
        --argjson cpuShare "$CPU_SHARE" \
        --argjson ramShare "$RAM_SHARE" \
        --argjson storageShare "$STORAGE_SHARE" \
        --argjson gpuShare "$GPU_SHARE" \
        --arg deviceId "$device_id" \
        --arg macAddress "${MAC_ADDRESS:-}" \
        '{
            name: $name,
            hostname: $hostname,
            platform: $platform,
            architecture: $arch,
            role: $role,
            deviceId: $deviceId,
            macAddress: $macAddress,
            specs: {
                cpu: {
                    cores: $cpuCores,
                    model: $cpuModel
                },
                ram: {
                    total: $ramTotal,
                    available: $ramAvailable
                },
                gpu: {
                    available: $gpuAvailable,
                    model: $gpuModel,
                    memory: $gpuMemory,
                    count: $gpuCount,
                    driver: $gpuDriver,
                    cuda: $gpuCuda
                },
                storage: {
                    total: $storageTotal,
                    available: $storageAvailable
                }
            },
            sharing: {
                cpu: $cpuShare,
                ram: $ramShare,
                storage: $storageShare,
                gpu: $gpuShare
            }
        }')
    
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    local http_body=$(echo "$response" | head -n -1)
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        local err=$(echo "$http_body" | jq -r '.message // "Registration failed"' 2>/dev/null || echo "Registration failed")
        error "Worker registration failed (HTTP $http_code): $err
        
Debug Info:
- Hostname: $HOSTNAME
- OS: $OS
- Role: $USER_ROLE
- CPU Cores: $CPU_CORES
- RAM: ${RAM_TOTAL}MB
- Device ID: $device_id

Payload sent:
$(echo "$payload" | jq . 2>/dev/null || echo "$payload")"
    fi
    
    WORKER_ID=$(echo "$http_body" | jq -r '.workerId // .id' 2>/dev/null)
    
    if [ -z "$WORKER_ID" ] || [ "$WORKER_ID" = "null" ]; then
        error "No worker ID returned from registration"
    fi
    
    echo "$WORKER_ID" > "$CONFIG_DIR/worker_id"
    echo "$USER_ROLE" > "$CONFIG_DIR/role"
    
    log "Worker registered successfully!"
    log "Worker ID: $WORKER_ID"
    log "Role: $USER_ROLE"
}

# ═══════════════════════════════════════════════════════════════
# DOCKER CONTAINER DEPLOYMENT
# ═══════════════════════════════════════════════════════════════

deploy_worker() {
    section "Deploying Worker Container"
    
    # Stop existing container
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        info "Stopping existing container..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
    fi
    
    # Pull latest image
    info "Pulling latest worker image..."
    docker pull "$DOCKER_IMAGE"
    
    # Prepare Docker run command
    local docker_cmd="docker run -d \
        --name $CONTAINER_NAME \
        --restart=$RESTART_POLICY \
        -e API_URL=$DISTRIBUTEX_API_URL \
        -e API_TOKEN=$API_TOKEN \
        -e WORKER_ID=$WORKER_ID \
        -e WORKER_ROLE=$USER_ROLE \
        -e CPU_CORES=$CPU_CORES \
        -e CPU_SHARE=$CPU_SHARE \
        -e RAM_TOTAL=$RAM_TOTAL \
        -e RAM_SHARE=$RAM_SHARE \
        -e STORAGE_TOTAL=$STORAGE_TOTAL \
        -e STORAGE_SHARE=$STORAGE_SHARE \
        -e HOSTNAME=$HOSTNAME \
        -e DEVICE_ID=$DEVICE_ID"
    
    # Add GPU support if available
    if [ "$GPU_AVAILABLE" = true ]; then
        if command -v nvidia-smi &>/dev/null; then
            docker_cmd="$docker_cmd --gpus all \
                -e GPU_ENABLED=true \
                -e GPU_MODEL=\"$GPU_MODEL\" \
                -e GPU_MEMORY=$GPU_MEMORY \
                -e GPU_SHARE=$GPU_SHARE"
        fi
    fi
    
    # Add volume mounts
    docker_cmd="$docker_cmd \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $CONFIG_DIR:/app/config"
    
    # Execute
    docker_cmd="$docker_cmd $DOCKER_IMAGE"
    
    info "Starting worker container..."
    eval $docker_cmd
    
    # Verify container is running
    sleep 3
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "Worker container deployed successfully!"
        log "Container: $CONTAINER_NAME"
    else
        error "Failed to start worker container"
    fi
}

# ═══════════════════════════════════════════════════════════════
# SYSTEMD SERVICE (Linux only)
# ═══════════════════════════════════════════════════════════════

setup_systemd_service() {
    if [ "$SETUP_SYSTEMD" != true ]; then
        return
    fi
    
    if ! command -v systemctl &>/dev/null; then
        return
    fi
    
    section "Setting Up Systemd Service"
    
    local service_file="/etc/systemd/system/distributex-worker.service"
    
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=DistributeX Worker Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start $CONTAINER_NAME
ExecStop=/usr/bin/docker stop $CONTAINER_NAME
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable distributex-worker.service
    
    log "Systemd service configured"
}

# ═══════════════════════════════════════════════════════════════
# CLI MANAGEMENT TOOLS
# ═══════════════════════════════════════════════════════════════

install_cli_tools() {
    section "Installing CLI Management Tools"
    
    local cli_script="/usr/local/bin/distributex"
    
    sudo tee "$cli_script" > /dev/null <<'EOF'
#!/bin/bash
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

case "$1" in
    start)
        docker start $CONTAINER_NAME
        echo "Worker started"
        ;;
    stop)
        docker stop $CONTAINER_NAME
        echo "Worker stopped"
        ;;
    restart)
        docker restart $CONTAINER_NAME
        echo "Worker restarted"
        ;;
    status)
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "Status: Running"
            docker ps --filter "name=$CONTAINER_NAME" --format "table {{.ID}}\t{{.Status}}\t{{.Names}}"
        else
            echo "Status: Stopped"
        fi
        ;;
    logs)
        docker logs -f $CONTAINER_NAME
        ;;
    stats)
        docker stats $CONTAINER_NAME
        ;;
    info)
        if [ -f "$CONFIG_DIR/worker_id" ]; then
            echo "Worker ID: $(cat $CONFIG_DIR/worker_id)"
        fi
        if [ -f "$CONFIG_DIR/role" ]; then
            echo "Role: $(cat $CONFIG_DIR/role)"
        fi
        ;;
    update)
        docker pull distributexcloud/worker:latest
        docker stop $CONTAINER_NAME
        docker rm $CONTAINER_NAME
        echo "Rerun installer to redeploy with latest image"
        ;;
    uninstall)
        docker stop $CONTAINER_NAME 2>/dev/null
        docker rm $CONTAINER_NAME 2>/dev/null
        rm -rf $CONFIG_DIR
        sudo rm -f /etc/systemd/system/distributex-worker.service
        sudo systemctl daemon-reload 2>/dev/null
        sudo rm -f /usr/local/bin/distributex
        echo "DistributeX worker uninstalled"
        ;;
    *)
        echo "DistributeX Worker CLI"
        echo ""
        echo "Usage: distributex <command>"
        echo ""
        echo "Commands:"
        echo "  start       - Start the worker"
        echo "  stop        - Stop the worker"
        echo "  restart     - Restart the worker"
        echo "  status      - Show worker status"
        echo "  logs        - View worker logs"
        echo "  stats       - Show resource usage"
        echo "  info        - Show worker info"
        echo "  update      - Update worker image"
        echo "  uninstall   - Remove worker completely"
        ;;
esac
EOF
    
    sudo chmod +x "$cli_script"
    log "CLI tools installed at: $cli_script"
}

# ═══════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════

show_summary() {
    section "Installation Complete!"
    
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   DistributeX Worker Successfully Installed!      ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}Worker Information:${NC}"
    echo "  • Worker ID: $WORKER_ID"
    echo "  • Role: $USER_ROLE"
    echo "  • Container: $CONTAINER_NAME"
    echo "  • Status: Running (auto-restart enabled)"
    echo ""
    
    echo -e "${CYAN}Resource Contribution:${NC}"
    echo "  • CPU: $CPU_SHARE% ($((CPU_CORES * CPU_SHARE / 100)) cores)"
    echo "  • RAM: $RAM_SHARE% ($((RAM_TOTAL * RAM_SHARE / 100))MB)"
    echo "  • Storage: $STORAGE_SHARE% ($((STORAGE_TOTAL * STORAGE_SHARE / 100))GB)"
    [ "$GPU_AVAILABLE" = true ] && echo "  • GPU: $GPU_SHARE% ($GPU_MODEL)"
    echo ""
    
    echo -e "${CYAN}Management Commands:${NC}"
    echo "  distributex status    - Check worker status"
    echo "  distributex logs      - View worker logs"
    echo "  distributex stats     - Monitor resource usage"
    echo "  distributex restart   - Restart worker"
    echo "  distributex stop      - Stop worker"
    echo "  distributex start     - Start worker"
    echo ""
    
    echo -e "${CYAN}Dashboard:${NC}"
    echo "  Visit: $DISTRIBUTEX_API_URL/dashboard"
    echo ""
    
    if [ "$USER_ROLE" = "contributor" ]; then
        echo -e "${YELLOW}${BOLD}💰 Earning Rewards:${NC}"
        echo "  Your worker is now contributing compute resources"
        echo "  and earning rewards based on task completion!"
        echo ""
    else
        echo -e "${YELLOW}${BOLD}🚀 Using the Network:${NC}"
        echo "  You can now submit tasks via the dashboard or API."
        echo "  Visit the docs for integration guides."
        echo ""
    fi
    
    echo -e "${GREEN}Thank you for joining DistributeX! 🎉${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════

main() {
    show_banner
    check_requirements
    authenticate_user
    select_user_role
    detect_system
    register_worker
    deploy_worker
    setup_systemd_service
    install_cli_tools
    show_summary
}

# Run main function
main "$@"
