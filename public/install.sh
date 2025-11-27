#!/bin/bash
#
# DistributeX Complete Installer - FIXED VERSION
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
#

set -e

# --------------------------
# Configuration
# --------------------------
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributex/worker:latest"
CONTAINER_NAME="distributex-worker"

# FIX: Stable hostname detection
get_stable_hostname() {
    local hostname=""
    
    # Try multiple methods in order of reliability
    if [ -f /etc/hostname ]; then
        hostname=$(cat /etc/hostname 2>/dev/null | tr -d '[:space:]' | head -1)
    fi
    
    if [ -z "$hostname" ] || [ "$hostname" = "unknown" ]; then
        hostname=$(hostname 2>/dev/null | tr -d '[:space:]' | head -1)
    fi
    
    if [ -z "$hostname" ] || [ "$hostname" = "unknown" ]; then
        hostname=$(uname -n 2>/dev/null | tr -d '[:space:]' | head -1)
    fi
    
    # Fallback to Docker container ID if inside Docker
    if [ -z "$hostname" ] || [ "$hostname" = "unknown" ]; then
        if [ -f /.dockerenv ]; then
            hostname="docker-$(cat /proc/self/cgroup | grep -oE 'docker/[a-f0-9]+' | head -1 | cut -d'/' -f2 | cut -c1-12)"
        fi
    fi
    
    # Final fallback
    if [ -z "$hostname" ] || [ "$hostname" = "unknown" ]; then
        hostname="distributex-$(date +%s)"
    fi
    
    echo "$hostname"
}

HOSTNAME=$(get_stable_hostname)
CONFIG_DIR="$HOME/.distributex"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# --------------------------
# Logging Functions
# --------------------------
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"; }

# --------------------------
# Banner
# --------------------------
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        ██████╗ ██╗███████╗████████╗██████╗ ██╗██╗        ║
║        ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║╚██╗       ║
║        ██║  ██║██║███████╗   ██║   ██████╔╝██║ ██║       ║
║        ██║  ██║██║╚════██║   ██║   ██╔══██╗██║ ██║       ║
║        ██████╔╝██║███████║   ██║   ██║  ██║██║██╔╝       ║
║        ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝        ║
║                                                           ║
║              DistributeX Cloud Network                   ║
║          Distributed Computing Platform                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
}

# --------------------------
# Requirements Check
# --------------------------
check_requirements() {
    section "Checking System Requirements"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Install from: https://docs.docker.com/get-docker/"
    fi
    
    # Check if Docker daemon is running
    if ! docker ps &> /dev/null; then
        error "Docker daemon is not running. Please start Docker and try again."
    fi
    
    # Check other required commands
    local missing=()
    for cmd in curl jq bc; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required commands: ${missing[*]}"
    fi
    
    log "All requirements satisfied"
    log "Docker version: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
}

# --------------------------
# User Authentication
# --------------------------
authenticate_user() {
    section "User Authentication"
    mkdir -p "$CONFIG_DIR"

    # Check for existing token
    if [ -f "$CONFIG_DIR/token" ]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $API_TOKEN" \
            "$DISTRIBUTEX_API_URL/api/auth/user")
        
        if [ "$HTTP_CODE" = "200" ]; then
            log "Using existing authentication"
            return 0
        else
            warn "Existing token expired, please log in again"
            rm -f "$CONFIG_DIR/token"
        fi
    fi

    echo ""
    echo -e "${CYAN}Choose an option:${NC}"
    echo "  1) Sign up (New user)"
    echo "  2) Login (Existing user)"
    echo ""
    
    local choice=""
    while true; do
        # Read from /dev/tty to bypass pipe issues
        read -r -p "Enter choice [1-2]: " choice </dev/tty
        case "$choice" in
            1) 
                signup_user
                break
                ;;
            2) 
                login_user
                break
                ;;
            *) 
                echo -e "${RED}Invalid choice. Please enter 1 or 2${NC}"
                ;;
        esac
    done
}

signup_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}     Create Your Account${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local first_name last_name email password password_confirm
    
    read -r -p "First Name: " first_name </dev/tty
    read -r -p "Last Name: " last_name </dev/tty
    read -r -p "Email: " email </dev/tty
    
    while true; do
        read -s -r -p "Password (min 8 chars): " password </dev/tty
        echo ""
        
        if [ ${#password} -lt 8 ]; then
            warn "Password must be at least 8 characters"
            continue
        fi
        
        read -s -r -p "Confirm Password: " password_confirm </dev/tty
        echo ""
        
        if [ "$password" != "$password_confirm" ]; then
            warn "Passwords do not match. Please try again."
            continue
        fi
        break
    done

    echo ""
    info "Creating account..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
        error "Signup failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message // "Unknown error"')"
    fi

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No authentication token returned"
    fi
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Account created successfully!"
    echo ""
    
    # Pause to let user see the success message
    sleep 1
}

login_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}     Login to Your Account${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local email password
    
    read -r -p "Email: " email </dev/tty
    read -s -r -p "Password: " password </dev/tty
    echo ""
    echo ""
    
    info "Logging in..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" != "200" ]; then
        error "Login failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message // "Invalid credentials"')"
    fi

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No authentication token returned"
    fi
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in successfully!"
    echo ""
    
    # Pause to let user see the success message
    sleep 1
}

# --------------------------
# GPU Detection
# --------------------------
detect_gpu() {
    GPU_AVAILABLE=false
    GPU_MODEL="null"
    GPU_MEMORY="null"
    GPU_COUNT=0
    GPU_DRIVER_VERSION="null"
    GPU_CUDA_VERSION="null"
    GPU_SHARE_PERCENT=0
    
    # NVIDIA GPU Detection
    if command -v nvidia-smi &> /dev/null; then
        info "Detecting NVIDIA GPU..."
        GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null | head -1)
        if [ ! -z "$GPU_INFO" ]; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(echo "$GPU_INFO" | cut -d',' -f1 | xargs)
            GPU_MEMORY=$(echo "$GPU_INFO" | cut -d',' -f2 | grep -oE '[0-9]+')
            GPU_DRIVER_VERSION=$(echo "$GPU_INFO" | cut -d',' -f3 | xargs)
            GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -1)
            GPU_SHARE_PERCENT=50
            
            # Try to get CUDA version
            if command -v nvcc &> /dev/null; then
                GPU_CUDA_VERSION=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9.]+' | head -1)
            elif nvidia-smi --help 2>&1 | grep -q "CUDA Version"; then
                GPU_CUDA_VERSION=$(nvidia-smi | grep "CUDA Version" | grep -oP 'CUDA Version: \K[0-9.]+')
            fi
            
            log "NVIDIA GPU detected: $GPU_MODEL (${GPU_MEMORY}MB, Count: ${GPU_COUNT:-1})"
        fi
    fi
    
    if [ "$GPU_AVAILABLE" = false ]; then
        info "No GPU detected or GPU tools not installed"
    fi
}

# --------------------------
# System Detection
# --------------------------
detect_system() {
    section "System Detection"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    
    # CPU Model
    if [ "$OS" = "linux" ]; then
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    elif [ "$OS" = "darwin" ]; then
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")
    else
        CPU_MODEL="Unknown CPU"
    fi
    
    # RAM
    if command -v free &> /dev/null; then
        RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    else
        RAM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 8192)
    fi
    
    # Storage
    STORAGE_TOTAL=$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo 100)
    
    # Detect GPU
    detect_gpu
    
    # Calculate Docker resource limits
    DOCKER_CPU_LIMIT=$(echo "scale=1; $CPU_CORES * 0.5" | bc)
    DOCKER_RAM_LIMIT=$(echo "scale=0; $RAM_TOTAL * 0.3 / 1024" | bc)
    
    # Ensure minimum values
    if (( $(echo "$DOCKER_CPU_LIMIT < 1" | bc -l) )); then
        DOCKER_CPU_LIMIT="1.0"
    fi
    if [ "$DOCKER_RAM_LIMIT" -lt 1 ]; then
        DOCKER_RAM_LIMIT="1"
    fi
    
    log "System: $OS ($ARCH)"
    log "Hostname: $HOSTNAME"
    log "CPU: $CPU_CORES cores - $CPU_MODEL"
    log "RAM: ${RAM_TOTAL}MB (Docker limit: ${DOCKER_RAM_LIMIT}GB)"
    log "Storage: ${STORAGE_TOTAL}GB"
    if [ "$GPU_AVAILABLE" = true ]; then
        log "GPU: $GPU_MODEL (Sharing: ${GPU_SHARE_PERCENT}%)"
    fi
}

# --------------------------
# Generate Device Fingerprint
# --------------------------
generate_device_fingerprint() {
    section "Generating Device Fingerprint"
    
    # Get MAC address (most stable identifier)
    MAC=""
    if [ "$OS" = "linux" ]; then
        MAC=$(ip link show | awk '/link\/ether/ {print $2; exit}')
    elif [ "$OS" = "darwin" ]; then
        MAC=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2; exit}')
    fi
    
    # Fallback if no MAC found
    if [ -z "$MAC" ]; then
        MAC="00:00:00:00:00:00"
    fi
    
    # Create stable fingerprint
    FINGERPRINT_SRC="${MAC}-${CPU_MODEL}-${OS}-${ARCH}"
    DEVICE_FINGERPRINT=$(echo -n "$FINGERPRINT_SRC" | sha256sum | cut -c1-32)
    
    log "Device fingerprint generated: $DEVICE_FINGERPRINT"
    info "Components: MAC=$MAC, CPU=$CPU_MODEL, OS=$OS, ARCH=$ARCH"
}

# --------------------------
# Docker Setup
# --------------------------
pull_docker_image() {
    section "Pulling Docker Image"
    
    info "Pulling $DOCKER_IMAGE..."
    if docker pull $DOCKER_IMAGE 2>&1 | grep -q "Status: Downloaded newer image\|Status: Image is up to date"; then
        log "Docker image pulled successfully"
    else
        warn "Failed to pull from Docker Hub, will build locally if needed"
    fi
}

stop_existing_container() {
    section "Checking for Existing Container"
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        warn "Existing container found, stopping and removing..."
        docker stop $CONTAINER_NAME &> /dev/null || true
        docker rm $CONTAINER_NAME &> /dev/null || true
        log "Existing container removed"
    else
        log "No existing container found"
    fi
}

# --------------------------
# Register Worker
# --------------------------
register_worker() {
    section "Registering Worker Device"

    info "Registering device: $HOSTNAME"

    # GPU JSON
    if [ "$GPU_AVAILABLE" = true ]; then
        GPU_JSON="\"gpuAvailable\": true,
        \"gpuModel\": \"$GPU_MODEL\",
        \"gpuMemory\": ${GPU_MEMORY:-0},
        \"gpuCount\": ${GPU_COUNT:-1},
        \"gpuDriverVersion\": \"$GPU_DRIVER_VERSION\",
        \"gpuCudaVersion\": \"$GPU_CUDA_VERSION\",
        \"gpuSharePercent\": ${GPU_SHARE_PERCENT:-50},"
    else
        GPU_JSON="\"gpuAvailable\": false,
        \"gpuCount\": 0,
        \"gpuSharePercent\": 0,"
    fi

    # Is Docker?
    IS_DOCKER=false
    DOCKER_ID="null"
    if [ -f "/.dockerenv" ]; then
        IS_DOCKER=true
        DOCKER_ID=$(cat /proc/self/cgroup | grep -oE 'docker/[a-f0-9]+' | head -1 | cut -d/ -f2 | cut -c1-12 || echo "null")
    fi

    # Calculate share percentages
    CPU_SHARE_PERCENT=$([ $CPU_CORES -ge 8 ] && echo 50 || echo 40)
    RAM_SHARE_PERCENT=$([ $RAM_TOTAL -ge 16384 ] && echo 30 || echo 25)
    STORAGE_SHARE_PERCENT=20

    REGISTER_DATA=$(cat <<EOF
{
  "name": "$HOSTNAME",
  "hostname": "$HOSTNAME",
  "platform": "$OS",
  "architecture": "$ARCH",
  "cpuCores": $CPU_CORES,
  "cpuModel": "$CPU_MODEL",
  "ramTotal": $RAM_TOTAL,
  "ramAvailable": $RAM_TOTAL,
  $GPU_JSON
  "storageTotal": $STORAGE_TOTAL,
  "storageAvailable": $STORAGE_TOTAL,
  "cpuSharePercent": $CPU_SHARE_PERCENT,
  "ramSharePercent": $RAM_SHARE_PERCENT,
  "storageSharePercent": $STORAGE_SHARE_PERCENT,
  "isDocker": $IS_DOCKER,
  "dockerContainerId": "$DOCKER_ID",
  "deviceFingerprint": "$DEVICE_FINGERPRINT"
}
EOF
)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$REGISTER_DATA")

    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
        WORKER_ID=$(echo "$HTTP_BODY" | jq -r '.id')
        IS_NEW=$(echo "$HTTP_BODY" | jq -r '.isNew')
        
        if [ "$IS_NEW" = "true" ]; then
            log "Worker registered successfully! ID: $WORKER_ID"
        else
            log "Worker reconnected successfully! ID: $WORKER_ID"
            info "Existing worker recognized - no duplicate created"
        fi
        
        echo "$WORKER_ID" > "$CONFIG_DIR/worker-id"
    else
        error "Failed to register worker ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message // "Unknown error"')"
    fi
}

# --------------------------
# Start Docker Container
# --------------------------
start_container() {
    section "Starting Docker Worker Container"
    
    info "Starting container with auto-restart enabled..."
    
    # Base docker run command
    DOCKER_CMD="docker run -d \
        --name $CONTAINER_NAME \
        --restart unless-stopped \
        --cpus=\"$DOCKER_CPU_LIMIT\" \
        --memory=\"${DOCKER_RAM_LIMIT}g\" \
        -e DISTRIBUTEX_API_URL=\"$DISTRIBUTEX_API_URL\" \
        -v \"$CONFIG_DIR:/config:ro\""
    
    # Add GPU support if available
    if [ "$GPU_AVAILABLE" = true ]; then
        if command -v nvidia-smi &> /dev/null; then
            info "Enabling NVIDIA GPU support..."
            DOCKER_CMD="$DOCKER_CMD --gpus all"
        fi
    fi
    
    # Complete the command
    DOCKER_CMD="$DOCKER_CMD \
        $DOCKER_IMAGE \
        --api-key \"$API_TOKEN\" \
        --url \"$DISTRIBUTEX_API_URL\""
    
    # Execute
    eval $DOCKER_CMD || error "Failed to start container"

    sleep 3
    
    if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "Container started successfully"
        if [ "$GPU_AVAILABLE" = true ]; then
            log "GPU passthrough enabled"
        fi
    else
        error "Container failed to start. Check logs: docker logs $CONTAINER_NAME"
    fi
}

# --------------------------
# Save Configuration
# --------------------------
save_config() {
    section "Saving Configuration"
    
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "version": "3.0.0",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "containerName": "$CONTAINER_NAME",
  "dockerImage": "$DOCKER_IMAGE",
  "workerId": "$(cat $CONFIG_DIR/worker-id 2>/dev/null || echo "unknown")",
  "deviceFingerprint": "$DEVICE_FINGERPRINT",
  "system": {
    "hostname": "$HOSTNAME",
    "os": "$OS",
    "arch": "$ARCH",
    "cpuCores": $CPU_CORES,
    "cpuModel": "$CPU_MODEL",
    "ramTotal": $RAM_TOTAL,
    "storageTotal": $STORAGE_TOTAL,
    "gpuAvailable": $GPU_AVAILABLE,
    "gpuModel": "$GPU_MODEL",
    "gpuMemory": ${GPU_MEMORY:-0}
  },
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    chmod 600 "$CONFIG_DIR/config.json"
    log "Configuration saved to: $CONFIG_DIR/config.json"
}

# --------------------------
# Create Management Script
# --------------------------
create_management_script() {
    cat > "$CONFIG_DIR/manage.sh" <<'MGMT_EOF'
#!/bin/bash
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

case "$1" in
    start)
        echo "Starting worker..."
        docker start $CONTAINER_NAME
        ;;
    stop)
        echo "Stopping worker..."
        docker stop $CONTAINER_NAME
        ;;
    restart)
        echo "Restarting worker..."
        docker restart $CONTAINER_NAME
        ;;
    logs)
        docker logs ${2:--f} $CONTAINER_NAME
        ;;
    status)
        docker ps -f name=$CONTAINER_NAME
        echo ""
        docker stats $CONTAINER_NAME --no-stream
        ;;
    uninstall)
        echo "Uninstalling DistributeX worker..."
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
        if [ "$2" = "--purge" ]; then
            echo "Removing configuration..."
            rm -rf "$CONFIG_DIR"
        fi
        echo "Uninstall complete!"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status|uninstall}"
        exit 1
        ;;
esac
MGMT_EOF
    
    chmod +x "$CONFIG_DIR/manage.sh"
    log "Management script created: $CONFIG_DIR/manage.sh"
}

# --------------------------
# Final Confirmation
# --------------------------
show_completion() {
    section "Installation Complete! 🎉"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     DistributeX Worker Successfully Installed!        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "Worker is running and contributing to the network"
    log "Worker ID: $(cat $CONFIG_DIR/worker-id 2>/dev/null || echo 'N/A')"
    log "Device Fingerprint: $DEVICE_FINGERPRINT"
    echo ""
    
    echo -e "${CYAN}Management Commands:${NC}"
    echo "  $CONFIG_DIR/manage.sh status        # Check worker status"
    echo "  $CONFIG_DIR/manage.sh logs          # View logs"
    echo "  $CONFIG_DIR/manage.sh restart       # Restart worker"
    echo ""
    echo -e "${GREEN}Thank you for joining DistributeX! 🚀${NC}"
    echo ""
    
    # Wait for user acknowledgment
    read -r -p "Press Enter to exit..." </dev/tty
}

# --------------------------
# Main Installation Flow
# --------------------------
main() {
    show_banner
    check_requirements
    authenticate_user
    detect_system
    generate_device_fingerprint
    pull_docker_image
    stop_existing_container
    register_worker
    start_container
    save_config
    create_management_script
    show_completion
}

# Run main installation
main
