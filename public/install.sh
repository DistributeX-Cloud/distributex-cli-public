#!/bin/bash
# DistributeX Worker Installation Script
# Usage: curl -sSL https://distributex.pages.dev/install.sh | bash

set -e

DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex.pages.dev}"
DOCKER_IMAGE="distributex/worker:latest"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[DistributeX]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check for sudo/root
check_permissions() {
  if [ "$EUID" -ne 0 ]; then
    warn "This script requires sudo privileges"
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
  log "Detected: $OS ($DISTRO)"
}

# Install Docker if not present
install_docker() {
  if command -v docker &> /dev/null; then
    log "Docker already installed: $(docker --version)"
    return 0
  fi

  log "Installing Docker..."
  if [[ "$OS" == "linux" ]]; then
    curl -fsSL https://get.docker.com | $SUDO sh
    $SUDO usermod -aG docker $USER || true
    log "Docker installed. You may need to log out and back in."
  elif [[ "$OS" == "macos" ]]; then
    error "Please install Docker Desktop: https://www.docker.com/products/docker-desktop"
  fi
}

# Auto-detect system capabilities
detect_hardware() {
  log "Detecting system capabilities..."
  
  # CPU
  if [[ "$OS" == "linux" ]]; then
    CPU_CORES=$(nproc)
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
  elif [[ "$OS" == "macos" ]]; then
    CPU_CORES=$(sysctl -n hw.ncpu)
    CPU_MODEL=$(sysctl -n machdep.cpu.brand_string)
    RAM_TOTAL=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
  fi
  
  # GPU detection
  GPU_AVAILABLE=false
  GPU_MODEL="none"
  if command -v nvidia-smi &> /dev/null; then
    GPU_AVAILABLE=true
    GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
  elif [[ "$OS" == "macos" ]] && [[ $(uname -m) == "arm64" ]]; then
    GPU_AVAILABLE=true
    GPU_MODEL="Apple Silicon GPU"
  fi
  
  # Storage
  if [[ "$OS" == "linux" ]]; then
    STORAGE_TOTAL=$(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
  elif [[ "$OS" == "macos" ]]; then
    STORAGE_TOTAL=$(df -g / | awk 'NR==2 {print $2}')
  fi
  
  log "CPU: $CPU_CORES cores - $CPU_MODEL"
  log "RAM: ${RAM_TOTAL}MB"
  log "Storage: ${STORAGE_TOTAL}GB"
  log "GPU: $GPU_MODEL"
  
  # Calculate safe sharing percentages
  CPU_SHARE=40
  RAM_SHARE=30
  STORAGE_SHARE=20
  GPU_SHARE=50
}

# Get API key
get_api_key() {
  if [ -z "$DISTRIBUTEX_API_KEY" ]; then
    echo ""
    echo "Enter your DistributeX API key:"
    echo "(Get one from: ${DISTRIBUTEX_API_URL}/dashboard)"
    read -r DISTRIBUTEX_API_KEY
    
    if [ -z "$DISTRIBUTEX_API_KEY" ]; then
      error "API key is required"
    fi
  fi
}

# Create config
create_config() {
  log "Creating configuration..."
  mkdir -p ~/.distributex
  
  cat > ~/.distributex/config.json <<EOF
{
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "apiKey": "$DISTRIBUTEX_API_KEY",
  "worker": {
    "name": "$(hostname)",
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
}

# Start worker container
start_worker() {
  log "Starting DistributeX worker..."
  
  # Stop existing
  $SUDO docker stop distributex-worker 2>/dev/null || true
  $SUDO docker rm distributex-worker 2>/dev/null || true
  
  # Pull image
  $SUDO docker pull $DOCKER_IMAGE
  
  # Build run command
  DOCKER_CMD="docker run -d --name distributex-worker --restart unless-stopped"
  DOCKER_CMD="$DOCKER_CMD -v ~/.distributex:/config:ro"
  DOCKER_CMD="$DOCKER_CMD -v /var/run/docker.sock:/var/run/docker.sock"
  
  # Resource limits
  DOCKER_CMD="$DOCKER_CMD --cpus=$(echo "scale=2; $CPU_CORES * $CPU_SHARE / 100" | bc)"
  DOCKER_CMD="$DOCKER_CMD --memory=$(echo "$RAM_TOTAL * $RAM_SHARE / 100" | bc)m"
  
  # GPU support
  if [ "$GPU_AVAILABLE" = true ] && command -v nvidia-smi &> /dev/null; then
    DOCKER_CMD="$DOCKER_CMD --gpus all"
  fi
  
  DOCKER_CMD="$DOCKER_CMD $DOCKER_IMAGE"
  
  $SUDO eval $DOCKER_CMD
  
  log "Worker started successfully!"
}

# Main
main() {
  echo ""
  echo "╔═══════════════════════════════════════╗"
  echo "║   DistributeX Worker Installation     ║"
  echo "╚═══════════════════════════════════════╝"
  echo ""
  
  check_permissions
  detect_os
  install_docker
  detect_hardware
  get_api_key
  create_config
  start_worker
  
  echo ""
  log "✓ Installation complete!"
  echo ""
  echo "Worker Status:"
  $SUDO docker ps | grep distributex-worker
  echo ""
  echo "Commands:"
  echo "  View logs:    docker logs -f distributex-worker"
  echo "  Stop worker:  docker stop distributex-worker"
  echo "  Start worker: docker start distributex-worker"
  echo ""
  echo "Dashboard: ${DISTRIBUTEX_API_URL}/dashboard"
  echo ""
}

main
