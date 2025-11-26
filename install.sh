#!/bin/bash
# DistributeX Worker Installation Script
# Usage: curl -sSL https://distributex.io/install.sh | bash

set -e

DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://api.distributex.io}"
WORKER_VERSION="1.0.0"
DOCKER_IMAGE="distributex/worker:latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[DistributeX]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running with sudo/root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        warn "This script requires sudo privileges for Docker installation."
        if ! sudo -v; then
            error "Failed to obtain sudo privileges. Please run with sudo or as root."
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        DISTRO="macos"
    else
        error "Unsupported OS: $OSTYPE"
    fi
    log "Detected OS: $OS ($DISTRO)"
}

# Check if Docker is installed
check_docker() {
    if command -v docker &> /dev/null; then
        log "Docker is already installed: $(docker --version)"
        return 0
    else
        log "Docker not found. Installing Docker..."
        install_docker
    fi
}

# Install Docker
install_docker() {
    if [[ "$OS" == "linux" ]]; then
        log "Installing Docker on Linux..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        $SUDO sh get-docker.sh
        rm get-docker.sh
        
        # Add current user to docker group
        if [ -n "$SUDO" ]; then
            $SUDO usermod -aG docker $USER
            log "Added user to docker group. You may need to log out and back in."
        fi
    elif [[ "$OS" == "macos" ]]; then
        error "Please install Docker Desktop for Mac from https://www.docker.com/products/docker-desktop"
    fi
    
    # Verify installation
    if ! command -v docker &> /dev/null; then
        error "Docker installation failed"
    fi
    
    log "Docker installed successfully"
}

# Start Docker service
start_docker() {
    if [[ "$OS" == "linux" ]]; then
        if ! $SUDO systemctl is-active --quiet docker; then
            log "Starting Docker service..."
            $SUDO systemctl start docker
            $SUDO systemctl enable docker
        fi
    fi
}

# Detect system resources
detect_resources() {
    log "Detecting system resources..."
    
    # CPU
    if [[ "$OS" == "linux" ]]; then
        CPU_CORES=$(nproc)
        CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
        RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
        STORAGE_TOTAL=$(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
    elif [[ "$OS" == "macos" ]]; then
        CPU_CORES=$(sysctl -n hw.ncpu)
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string)
        RAM_TOTAL=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
        STORAGE_TOTAL=$(df -g / | awk 'NR==2 {print $2}')
    fi
    
    # GPU detection
    GPU_AVAILABLE=false
    GPU_MODEL="none"
    
    if command -v nvidia-smi &> /dev/null; then
        GPU_AVAILABLE=true
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
        log "Detected NVIDIA GPU: $GPU_MODEL"
    elif [[ "$OS" == "macos" ]]; then
        # Check for Apple Silicon
        if [[ $(uname -m) == "arm64" ]]; then
            GPU_AVAILABLE=true
            GPU_MODEL="Apple Silicon GPU"
            log "Detected Apple Silicon GPU"
        fi
    fi
    
    log "CPU: $CPU_CORES cores - $CPU_MODEL"
    log "RAM: ${RAM_TOTAL}MB"
    log "Storage: ${STORAGE_TOTAL}GB"
}

# Get API key from user
get_api_key() {
    if [ -z "$DISTRIBUTEX_API_KEY" ]; then
        echo ""
        echo "Please enter your DistributeX API key:"
        echo "(Get one from: https://distributex.io/dashboard)"
        read -r DISTRIBUTEX_API_KEY
        
        if [ -z "$DISTRIBUTEX_API_KEY" ]; then
            error "API key is required"
        fi
    fi
}

# Configure worker
configure_worker() {
    log "Configuring worker..."
    
    # Set worker name (default: hostname)
    WORKER_NAME="${WORKER_NAME:-$(hostname)}"
    
    # Calculate resource sharing percentages
    CPU_SHARE="${CPU_SHARE_PERCENT:-40}"
    RAM_SHARE="${RAM_SHARE_PERCENT:-30}"
    GPU_SHARE="${GPU_SHARE_PERCENT:-50}"
    STORAGE_SHARE="${STORAGE_SHARE_PERCENT:-20}"
    
    # Create config directory
    mkdir -p ~/.distributex
    
    # Create worker config
    cat > ~/.distributex/config.json <<EOF
{
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "apiKey": "$DISTRIBUTEX_API_KEY",
  "worker": {
    "name": "$WORKER_NAME",
    "cpuCores": $CPU_CORES,
    "cpuModel": "$CPU_MODEL",
    "ramTotal": $RAM_TOTAL,
    "gpuAvailable": $GPU_AVAILABLE,
    "gpuModel": "$GPU_MODEL",
    "storageTotal": $STORAGE_TOTAL,
    "cpuSharePercent": $CPU_SHARE,
    "ramSharePercent": $RAM_SHARE,
    "gpuSharePercent": $GPU_SHARE,
    "storageSharePercent": $STORAGE_SHARE
  }
}
EOF
    
    chmod 600 ~/.distributex/config.json
    log "Configuration saved to ~/.distributex/config.json"
}

# Pull and start worker container
start_worker() {
    log "Starting DistributeX worker container..."
    
    # Stop existing container if running
    $SUDO docker stop distributex-worker 2>/dev/null || true
    $SUDO docker rm distributex-worker 2>/dev/null || true
    
    # Pull latest image
    log "Pulling worker image..."
    $SUDO docker pull $DOCKER_IMAGE
    
    # Run worker container
    DOCKER_OPTS="--name distributex-worker"
    DOCKER_OPTS="$DOCKER_OPTS --restart unless-stopped"
    DOCKER_OPTS="$DOCKER_OPTS -d"
    DOCKER_OPTS="$DOCKER_OPTS -v ~/.distributex:/config:ro"
    DOCKER_OPTS="$DOCKER_OPTS -v /var/run/docker.sock:/var/run/docker.sock"
    
    # Add GPU support if available
    if [ "$GPU_AVAILABLE" = true ] && command -v nvidia-smi &> /dev/null; then
        DOCKER_OPTS="$DOCKER_OPTS --gpus all"
    fi
    
    # Resource limits
    DOCKER_OPTS="$DOCKER_OPTS --cpus=$(echo "scale=2; $CPU_CORES * $CPU_SHARE / 100" | bc)"
    DOCKER_OPTS="$DOCKER_OPTS --memory=$(echo "$RAM_TOTAL * $RAM_SHARE / 100" | bc)m"
    
    $SUDO docker run $DOCKER_OPTS $DOCKER_IMAGE
    
    log "Worker container started successfully!"
}

# Create systemd service for auto-start
create_systemd_service() {
    if [[ "$OS" != "linux" ]]; then
        return
    fi
    
    log "Creating systemd service for auto-start..."
    
    cat | $SUDO tee /etc/systemd/system/distributex-worker.service > /dev/null <<EOF
[Unit]
Description=DistributeX Worker
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start distributex-worker
ExecStop=/usr/bin/docker stop distributex-worker
User=$USER

[Install]
WantedBy=multi-user.target
EOF
    
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable distributex-worker.service
    
    log "Systemd service created and enabled"
}

# Main installation flow
main() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║   DistributeX Worker Installation     ║"
    echo "║         Version: $WORKER_VERSION      ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    
    check_root
    detect_os
    check_docker
    start_docker
    detect_resources
    get_api_key
    configure_worker
    start_worker
    create_systemd_service
    
    echo ""
    log "✓ Installation complete!"
    echo ""
    echo "Worker Status:"
    $SUDO docker ps | grep distributex-worker
    echo ""
    echo "View logs: docker logs -f distributex-worker"
    echo "Stop worker: docker stop distributex-worker"
    echo "Start worker: docker start distributex-worker"
    echo ""
    echo "Dashboard: https://distributex.io/dashboard"
    echo ""
}

main
