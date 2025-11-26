#!/bin/bash
#
# DistributeX Production Worker Installer
# Downloads automatically from: curl -sSL https://your-site.pages.dev/install.sh | bash
#
# This script:
# - Detects all system resources (CPU, RAM, GPU, Storage)
# - Offers to mount additional storage devices
# - Sets up Docker containers for isolation
# - Auto-registers with the DistributeX network
# - Configures auto-updates and health monitoring
# - Reports real-time metrics to the API
#

set -e

# Configuration
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud.pages.dev}"
WORKER_IMAGE="distributex/worker:latest"
AGENT_VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${MAGENTA}▶ $1${NC}\n"; }

# Check for required commands
check_requirements() {
  local missing=()
  
  for cmd in curl jq bc; do
    if ! command -v $cmd &> /dev/null; then
      missing+=($cmd)
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing required commands: ${missing[*]}. Please install them first."
  fi
}

# Check permissions
check_permissions() {
  if [ "$EUID" -ne 0 ]; then
    warn "Running without root privileges. Some features may be limited."
    SUDO="sudo"
    # Check if user has sudo access
    if ! sudo -n true 2>/dev/null; then
      warn "This script may prompt for your password to install system components."
    fi
  else
    SUDO=""
  fi
}

# Detect operating system
detect_os() {
  section "Detecting Operating System"
  
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      DISTRO=$ID
      DISTRO_VERSION=$VERSION_ID
    fi
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    DISTRO="macos"
    DISTRO_VERSION=$(sw_vers -productVersion)
  else
    error "Unsupported OS: $OSTYPE"
  fi
  
  log "Operating System: $OS"
  log "Distribution: $DISTRO $DISTRO_VERSION"
  log "Architecture: $(uname -m)"
}

# Install Docker
install_docker() {
  if command -v docker &> /dev/null; then
    log "Docker already installed: $(docker --version)"
    return 0
  fi

  section "Installing Docker"
  
  if [[ "$OS" == "linux" ]]; then
    info "Installing Docker via official script..."
    curl -fsSL https://get.docker.com | $SUDO sh
    
    # Add current user to docker group
    $SUDO usermod -aG docker $USER || true
    
    # Start Docker service
    $SUDO systemctl start docker || true
    $SUDO systemctl enable docker || true
    
    log "Docker installed successfully"
    warn "Note: You may need to log out and back in for group changes to take effect"
  elif [[ "$OS" == "macos" ]]; then
    error "Please install Docker Desktop manually: https://www.docker.com/products/docker-desktop"
  fi
}

# Detect CPU capabilities
detect_cpu() {
  section "Detecting CPU"
  
  if [[ "$OS" == "linux" ]]; then
    CPU_CORES=$(nproc)
    CPU_MODEL=$(lscpu | grep "^Model name:" | cut -d: -f2 | xargs)
    CPU_ARCH=$(uname -m)
    CPU_FREQ=$(lscpu | grep "^CPU MHz:" | cut -d: -f2 | xargs | cut -d. -f1)
    
    # Check for virtualization support
    if grep -q "vmx\|svm" /proc/cpuinfo; then
      CPU_VIRT="enabled"
    else
      CPU_VIRT="disabled"
    fi
  elif [[ "$OS" == "macos" ]]; then
    CPU_CORES=$(sysctl -n hw.ncpu)
    CPU_MODEL=$(sysctl -n machdep.cpu.brand_string)
    CPU_ARCH=$(uname -m)
    CPU_FREQ=$(sysctl -n hw.cpufrequency | awk '{print int($1/1000000)}')
    CPU_VIRT="unknown"
  fi
  
  log "CPU Model: $CPU_MODEL"
  log "CPU Cores: $CPU_CORES"
  log "CPU Architecture: $CPU_ARCH"
  log "CPU Frequency: ~${CPU_FREQ}MHz"
  log "Virtualization: $CPU_VIRT"
  
  # Calculate safe CPU share (30-50% based on core count)
  if [ $CPU_CORES -ge 8 ]; then
    CPU_SHARE=50
  elif [ $CPU_CORES -ge 4 ]; then
    CPU_SHARE=40
  else
    CPU_SHARE=30
  fi
  
  CPU_CORES_SHARED=$(echo "scale=1; $CPU_CORES * $CPU_SHARE / 100" | bc)
  info "Will share: ${CPU_SHARE}% (~${CPU_CORES_SHARED} cores)"
}

# Detect RAM
detect_ram() {
  section "Detecting RAM"
  
  if [[ "$OS" == "linux" ]]; then
    RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    RAM_AVAILABLE=$(free -m | awk '/^Mem:/{print $7}')
    RAM_TYPE=$(dmidecode -t memory 2>/dev/null | grep "Type:" | head -1 | awk '{print $2}' || echo "Unknown")
  elif [[ "$OS" == "macos" ]]; then
    RAM_TOTAL=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
    RAM_AVAILABLE=$(( $(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//') * 4096 / 1024 / 1024 ))
    RAM_TYPE="Unknown"
  fi
  
  RAM_TOTAL_GB=$(echo "scale=2; $RAM_TOTAL / 1024" | bc)
  RAM_AVAILABLE_GB=$(echo "scale=2; $RAM_AVAILABLE / 1024" | bc)
  
  log "Total RAM: ${RAM_TOTAL_GB}GB (${RAM_TOTAL}MB)"
  log "Available RAM: ${RAM_AVAILABLE_GB}GB (${RAM_AVAILABLE}MB)"
  log "Memory Type: $RAM_TYPE"
  
  # Calculate safe RAM share (20-30% of available)
  if [ $RAM_TOTAL -ge 16384 ]; then
    RAM_SHARE=30
  elif [ $RAM_TOTAL -ge 8192 ]; then
    RAM_SHARE=25
  else
    RAM_SHARE=20
  fi
  
  RAM_MB_SHARED=$(echo "$RAM_AVAILABLE * $RAM_SHARE / 100" | bc)
  RAM_GB_SHARED=$(echo "scale=2; $RAM_MB_SHARED / 1024" | bc)
  info "Will share: ${RAM_SHARE}% (~${RAM_GB_SHARED}GB)"
}

# Detect GPU
detect_gpu() {
  section "Detecting GPU"
  
  GPU_AVAILABLE=false
  GPU_MODEL="none"
  GPU_MEMORY=0
  GPU_DRIVER=""
  
  # NVIDIA GPU Detection
  if command -v nvidia-smi &> /dev/null; then
    GPU_AVAILABLE=true
    GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
    GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
    GPU_TYPE="NVIDIA"
    
    log "NVIDIA GPU Detected: $GPU_MODEL"
    log "GPU Memory: ${GPU_MEMORY}MB"
    log "Driver Version: $GPU_DRIVER"
    
  # AMD GPU Detection (Linux)
  elif [[ "$OS" == "linux" ]] && lspci | grep -i "vga\|3d\|display" | grep -i "amd\|radeon" &> /dev/null; then
    GPU_AVAILABLE=true
    GPU_MODEL=$(lspci | grep -i "vga\|3d" | grep -i "amd\|radeon" | head -n1 | cut -d: -f3 | xargs)
    GPU_TYPE="AMD"
    
    # Try to detect VRAM
    if command -v rocm-smi &> /dev/null; then
      GPU_MEMORY=$(rocm-smi --showmeminfo vram --json | jq -r '.card0."VRAM Total Memory (B)"' | awk '{print int($1/1024/1024)}')
    fi
    
    log "AMD GPU Detected: $GPU_MODEL"
    if [ $GPU_MEMORY -gt 0 ]; then
      log "GPU Memory: ${GPU_MEMORY}MB"
    fi
    
  # Apple Silicon GPU (macOS)
  elif [[ "$OS" == "macos" ]] && [[ $(uname -m) == "arm64" ]]; then
    GPU_AVAILABLE=true
    GPU_MODEL="Apple Silicon GPU"
    GPU_TYPE="Apple"
    
    # Apple Silicon shares system RAM
    GPU_MEMORY=$(echo "$RAM_TOTAL / 2" | bc)
    
    log "Apple Silicon GPU Detected"
    log "Unified Memory: ${GPU_MEMORY}MB available for GPU"
  
  # Intel Integrated Graphics
  elif [[ "$OS" == "linux" ]] && lspci | grep -i "vga\|3d\|display" | grep -i "intel" &> /dev/null; then
    GPU_MODEL=$(lspci | grep -i "vga\|3d" | grep -i "intel" | head -n1 | cut -d: -f3 | xargs)
    GPU_TYPE="Intel"
    
    info "Intel Integrated Graphics detected: $GPU_MODEL"
    info "Note: Integrated graphics have limited compute capability"
    
    # Ask if user wants to share integrated GPU
    read -p "Enable Intel GPU sharing? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      GPU_AVAILABLE=true
      log "Intel GPU enabled for sharing"
    else
      warn "Intel GPU disabled for sharing"
    fi
  else
    warn "No compatible GPU detected"
  fi
  
  # GPU share percentage
  if [ "$GPU_AVAILABLE" = true ]; then
    GPU_SHARE=50
    info "Will share: ${GPU_SHARE}% of GPU when idle"
  else
    GPU_SHARE=0
  fi
}

# Detect storage
detect_storage() {
  section "Detecting Storage Devices"
  
  STORAGE_DEVICES=()
  
  if [[ "$OS" == "linux" ]]; then
    # Get all block devices
    while IFS= read -r line; do
      DEVICE=$(echo $line | awk '{print $1}')
      SIZE=$(echo $line | awk '{print $4}')
      MOUNTPOINT=$(echo $line | awk '{print $7}')
      TYPE=$(echo $line | awk '{print $6}')
      
      # Skip if no mountpoint or if it's a loop device
      if [ -z "$MOUNTPOINT" ] || [[ "$DEVICE" == loop* ]]; then
        continue
      fi
      
      # Get available space
      AVAIL=$(df -BG "$MOUNTPOINT" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
      USED=$(df -BG "$MOUNTPOINT" 2>/dev/null | tail -1 | awk '{print $3}' | sed 's/G//')
      
      if [ ! -z "$AVAIL" ]; then
        STORAGE_DEVICES+=("$DEVICE|$SIZE|$MOUNTPOINT|$AVAIL|$USED|$TYPE")
      fi
    done < <(lsblk -o NAME,SIZE,MOUNTPOINT,FSTYPE | grep -v "^NAME" | grep -E "/$|/home|/mnt|/media")
    
  elif [[ "$OS" == "macos" ]]; then
    # macOS storage detection
    MOUNT_OUTPUT=$(df -H | grep "^/dev/")
    while IFS= read -r line; do
      DEVICE=$(echo $line | awk '{print $1}')
      SIZE=$(echo $line | awk '{print $2}')
      AVAIL=$(echo $line | awk '{print $4}' | sed 's/G//')
      USED=$(echo $line | awk '{print $3}' | sed 's/G//')
      MOUNTPOINT=$(echo $line | awk '{print $9}')
      TYPE="apfs"
      
      STORAGE_DEVICES+=("$DEVICE|$SIZE|$MOUNTPOINT|$AVAIL|$USED|$TYPE")
    done <<< "$MOUNT_OUTPUT"
  fi
  
  log "Found ${#STORAGE_DEVICES[@]} storage device(s):"
  for i in "${!STORAGE_DEVICES[@]}"; do
    IFS='|' read -r dev size mount avail used type <<< "${STORAGE_DEVICES[$i]}"
    log "  [$((i+1))] $dev ($type) - $size total, ${avail}GB available - $mount"
  done
}

# Select storage devices
select_storage() {
  section "Storage Configuration"
  
  echo "Which storage devices would you like to contribute?"
  echo ""
  
  SELECTED_STORAGE=()
  TOTAL_STORAGE=0
  TOTAL_AVAILABLE=0
  
  for i in "${!STORAGE_DEVICES[@]}"; do
    IFS='|' read -r dev size mount avail used type <<< "${STORAGE_DEVICES[$i]}"
    
    # Auto-select main system drive
    if [[ "$mount" == "/" ]]; then
      echo -e "${GREEN}[✓]${NC} Auto-selected: $dev ($mount) - ${avail}GB available"
      SELECTED_STORAGE+=("${STORAGE_DEVICES[$i]}")
      TOTAL_AVAILABLE=$((TOTAL_AVAILABLE + avail))
      continue
    fi
    
    # Ask about other drives
    read -p "  Include $dev ($mount) with ${avail}GB available? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      SELECTED_STORAGE+=("${STORAGE_DEVICES[$i]}")
      TOTAL_AVAILABLE=$((TOTAL_AVAILABLE + avail))
      log "Added $dev to sharing pool"
    fi
  done
  
  if [ ${#SELECTED_STORAGE[@]} -eq 0 ]; then
    error "No storage devices selected. Cannot proceed."
  fi
  
  log "Total available storage: ${TOTAL_AVAILABLE}GB across ${#SELECTED_STORAGE[@]} device(s)"
  
  # Calculate safe storage share (10-20% of available)
  if [ $TOTAL_AVAILABLE -ge 500 ]; then
    STORAGE_SHARE=20
  elif [ $TOTAL_AVAILABLE -ge 100 ]; then
    STORAGE_SHARE=15
  else
    STORAGE_SHARE=10
  fi
  
  STORAGE_GB_SHARED=$(echo "$TOTAL_AVAILABLE * $STORAGE_SHARE / 100" | bc)
  info "Will share: ${STORAGE_SHARE}% (~${STORAGE_GB_SHARED}GB)"
  
  # Store storage configuration
  STORAGE_TOTAL=$TOTAL_AVAILABLE
  STORAGE_AVAILABLE=$TOTAL_AVAILABLE
}

# Get API key
get_api_key() {
  section "API Configuration"
  
  if [ -z "$DISTRIBUTEX_API_KEY" ]; then
    echo ""
    echo "Enter your DistributeX API key:"
    echo "(Get one from: ${DISTRIBUTEX_API_URL}/dashboard)"
    echo ""
    read -r DISTRIBUTEX_API_KEY
    
    if [ -z "$DISTRIBUTEX_API_KEY" ]; then
      error "API key is required"
    fi
  fi
  
  # Verify API key
  info "Verifying API key..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $DISTRIBUTEX_API_KEY" \
    "${DISTRIBUTEX_API_URL}/api/auth/user")
  
  if [ "$HTTP_CODE" != "200" ]; then
    error "Invalid API key. Please check and try again."
  fi
  
  log "API key verified successfully"
}

# Configure auto-updates
setup_auto_updates() {
  section "Configuring Auto-Updates"
  
  # Create update script
  cat > /tmp/distributex-update.sh <<'UPDATEEOF'
#!/bin/bash
# DistributeX Auto-Update Script

DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud.pages.dev}"
WORKER_IMAGE="distributex/worker:latest"

# Pull latest image
docker pull $WORKER_IMAGE

# Restart worker with new image
docker restart distributex-worker

# Send notification
WORKER_ID=$(docker exec distributex-worker cat /config/worker-id 2>/dev/null || echo "unknown")
echo "Worker $WORKER_ID updated to $(docker inspect --format='{{.Config.Image}}' distributex-worker)"
UPDATEEOF
  
  chmod +x /tmp/distributex-update.sh
  $SUDO mv /tmp/distributex-update.sh /usr/local/bin/distributex-update
  
  # Create systemd timer for auto-updates (Linux)
  if [[ "$OS" == "linux" ]] && command -v systemctl &> /dev/null; then
    cat > /tmp/distributex-update.timer <<EOF
[Unit]
Description=DistributeX Worker Auto-Update Timer
Requires=distributex-update.service

[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

    cat > /tmp/distributex-update.service <<EOF
[Unit]
Description=DistributeX Worker Auto-Update
After=network.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/distributex-update
StandardOutput=journal
StandardError=journal
EOF

    $SUDO mv /tmp/distributex-update.timer /etc/systemd/system/
    $SUDO mv /tmp/distributex-update.service /etc/systemd/system/
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable distributex-update.timer
    $SUDO systemctl start distributex-update.timer
    
    log "Auto-updates configured (daily checks)"
  else
    # Fallback to cron (macOS or non-systemd Linux)
    CRON_CMD="0 2 * * * /usr/local/bin/distributex-update"
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    log "Auto-updates configured (daily at 2 AM)"
  fi
}

# Create monitoring script
setup_monitoring() {
  section "Setting Up Health Monitoring"
  
  cat > /tmp/distributex-monitor.sh <<'MONEOF'
#!/bin/bash
# DistributeX Health Monitor

check_worker() {
  if ! docker ps | grep -q distributex-worker; then
    echo "Worker container not running, attempting restart..."
    docker start distributex-worker || docker run -d --name distributex-worker --restart unless-stopped -v ~/.distributex:/config:ro distributex/worker:latest
  fi
  
  # Check if worker is responsive
  if ! docker exec distributex-worker curl -f http://localhost:8080/health &>/dev/null; then
    echo "Worker not responding, restarting..."
    docker restart distributex-worker
  fi
}

check_worker
MONEOF
  
  chmod +x /tmp/distributex-monitor.sh
  $SUDO mv /tmp/distributex-monitor.sh /usr/local/bin/distributex-monitor
  
  # Create monitoring service/cron
  if [[ "$OS" == "linux" ]] && command -v systemctl &> /dev/null; then
    cat > /tmp/distributex-monitor.timer <<EOF
[Unit]
Description=DistributeX Worker Health Monitor
Requires=distributex-monitor.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    cat > /tmp/distributex-monitor.service <<EOF
[Unit]
Description=DistributeX Worker Health Check
After=network.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/distributex-monitor
StandardOutput=journal
StandardError=journal
EOF

    $SUDO mv /tmp/distributex-monitor.timer /etc/systemd/system/
    $SUDO mv /tmp/distributex-monitor.service /etc/systemd/system/
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable distributex-monitor.timer
    $SUDO systemctl start distributex-monitor.timer
    
    log "Health monitoring configured (every 5 minutes)"
  else
    CRON_CMD="*/5 * * * * /usr/local/bin/distributex-monitor"
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    log "Health monitoring configured (every 5 minutes)"
  fi
}

# Create configuration
create_config() {
  section "Creating Configuration"
  
  mkdir -p ~/.distributex
  
  # Generate storage mounts JSON
  STORAGE_MOUNTS="["
  for i in "${!SELECTED_STORAGE[@]}"; do
    IFS='|' read -r dev size mount avail used type <<< "${SELECTED_STORAGE[$i]}"
    
    if [ $i -gt 0 ]; then
      STORAGE_MOUNTS="$STORAGE_MOUNTS,"
    fi
    
    STORAGE_MOUNTS="$STORAGE_MOUNTS{\"device\":\"$dev\",\"mount\":\"$mount\",\"size\":\"$size\",\"available\":\"$avail\",\"type\":\"$type\"}"
  done
  STORAGE_MOUNTS="$STORAGE_MOUNTS]"
  
  # Create config file
  cat > ~/.distributex/config.json <<EOF
{
  "version": "$AGENT_VERSION",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "apiKey": "$DISTRIBUTEX_API_KEY",
  "worker": {
    "name": "$(hostname)",
    "hostname": "$(hostname)",
    "platform": "$OS",
    "architecture": "$(uname -m)",
    "cpuCores": $CPU_CORES,
    "cpuModel": "$CPU_MODEL",
    "cpuFreq": $CPU_FREQ,
    "ramTotal": $RAM_TOTAL,
    "ramAvailable": $RAM_AVAILABLE,
    "gpuAvailable": $GPU_AVAILABLE,
    "gpuModel": "$GPU_MODEL",
    "gpuMemory": $GPU_MEMORY,
    "gpuDriver": "$GPU_DRIVER",
    "gpuType": "$GPU_TYPE",
    "storageTotal": $STORAGE_TOTAL,
    "storageAvailable": $STORAGE_AVAILABLE,
    "storageMounts": $STORAGE_MOUNTS,
    "cpuSharePercent": $CPU_SHARE,
    "ramSharePercent": $RAM_SHARE,
    "gpuSharePercent": $GPU_SHARE,
    "storageSharePercent": $STORAGE_SHARE
  },
  "features": {
    "autoUpdate": true,
    "healthMonitoring": true,
    "telemetry": true
  },
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  
  chmod 600 ~/.distributex/config.json
  log "Configuration saved to ~/.distributex/config.json"
}

# Start worker container
start_worker() {
  section "Starting DistributeX Worker"
  
  # Stop and remove existing container
  $SUDO docker stop distributex-worker 2>/dev/null || true
  $SUDO docker rm distributex-worker 2>/dev/null || true
  
  # Pull latest image
  info "Pulling worker image..."
  $SUDO docker pull $WORKER_IMAGE
  
  # Build docker run command
  DOCKER_CMD="docker run -d"
  DOCKER_CMD="$DOCKER_CMD --name distributex-worker"
  DOCKER_CMD="$DOCKER_CMD --restart unless-stopped"
  
  # Mount configuration
  DOCKER_CMD="$DOCKER_CMD -v ~/.distributex:/config:ro"
  
  # Mount storage devices
  for storage in "${SELECTED_STORAGE[@]}"; do
    IFS='|' read -r dev size mount avail used type <<< "$storage"
    DOCKER_CMD="$DOCKER_CMD -v $mount:/storage$(echo $mount | tr '/' '_'):rw"
  done
  
  # Resource limits (CPU)
  DOCKER_CMD="$DOCKER_CMD --cpus=$CPU_CORES_SHARED"
  
  # Resource limits (RAM)
  DOCKER_CMD="$DOCKER_CMD --memory=${RAM_MB_SHARED}m"
  
  # GPU support
  if [ "$GPU_AVAILABLE" = true ]; then
    if [ "$GPU_TYPE" = "NVIDIA" ]; then
      DOCKER_CMD="$DOCKER_CMD --gpus all"
    elif [ "$GPU_TYPE" = "AMD" ]; then
      DOCKER_CMD="$DOCKER_CMD --device=/dev/kfd --device=/dev/dri"
    fi
  fi
  
  # Monitoring port (internal)
  DOCKER_CMD="$DOCKER_CMD -p 127.0.0.1:8080:8080"
  
  # Health check
  DOCKER_CMD="$DOCKER_CMD --health-cmd='curl -f http://localhost:8080/health || exit 1'"
  DOCKER_CMD="$DOCKER_CMD --health-interval=30s"
  DOCKER_CMD="$DOCKER_CMD --health-timeout=10s"
  DOCKER_CMD="$DOCKER_CMD --health-retries=3"
  
  # Image
  DOCKER_CMD="$DOCKER_CMD $WORKER_IMAGE"
  
  # Execute
  info "Starting worker container..."
  $SUDO eval $DOCKER_CMD
  
  # Wait for container to start
  sleep 3
  
  # Check if running
  if $SUDO docker ps | grep -q distributex-worker; then
    log "Worker container started successfully"
    
    # Get worker ID from API response
    sleep 2
    WORKER_ID=$($SUDO docker logs distributex-worker 2>&1 | grep "Worker ID:" | awk '{print $NF}' || echo "pending")
    echo "$WORKER_ID" > ~/.distributex/worker-id
    
    log "Worker ID: $WORKER_ID"
  else
    error "Failed to start worker container"
  fi
}

# Display summary
show_summary() {
  section "Installation Complete!"
  
  cat <<EOF

${GREEN}╔═══════════════════════════════════════════════════════════╗
        ║                 Installation Successful!                  ║
        ╚═══════════════════════════════════════════════════════════╝${NC}

${CYAN}Worker Configuration:${NC}
  • CPU: ${CPU_CORES} cores (sharing ${CPU_SHARE}% = ~${CPU_CORES_SHARED} cores)
  • RAM: ${RAM_TOTAL_GB}GB (sharing ${RAM_SHARE}% = ~${RAM_GB_SHARED}GB)
  • GPU: ${GPU_MODEL} (sharing ${GPU_SHARE}%)
  • Storage: ${STORAGE_TOTAL}GB (sharing ${STORAGE_SHARE}% = ~${STORAGE_GB_SHARED}GB)

${CYAN}Features Enabled:${NC}
  ✓ Automatic updates (daily)
  ✓ Health monitoring (every 5 minutes)
  ✓ Real-time metrics reporting
  ✓ Docker isolation

${CYAN}Management Commands:${NC}
  • View status:    docker ps | grep distributex-worker
  • View logs:      docker logs -f distributex-worker
  • Stop worker:    docker stop distributex-worker
  • Start worker:   docker start distributex-worker
  • Restart worker: docker restart distributex-worker
  • Uninstall:      curl -sSL ${DISTRIBUTEX_API_URL}/uninstall.sh | bash

${CYAN}Dashboard:${NC}
  ${DISTRIBUTEX_API_URL}/dashboard

${CYAN}Configuration:${NC}
  ~/.distributex/config.json

${GREEN}Your worker is now contributing to the DistributeX network!${NC}

EOF
}

# Main installation flow
main() {
  clear
  
  cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║         ████████▄   ███                                  ║
║         ██      ██                                       ║
║         ██       █   █    ▒██████▒   ▐███▄               ║
║         ██       █   █   ▓█▀    ▀█▌       ██             ║
║         ██       █   █   ██       ▓  ▐██████▓            ║
║         ██       █   █   ██▌          █                  ║
║         ██      ██   █    ██▄    ▄█  ▐█                  ║
║         ████████▀   ███    ▀██████▀   ▀████▌             ║
║                                                          ║
║               DistributeX Cloud Network                  ║
║            Production Worker Installer v1.0              ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝

EOF

  info "This installer will set up your device as a DistributeX worker."
  info "You'll contribute unused computing resources to the global network."
  echo ""
  
  # Run installation steps
  check_requirements
  check_permissions
  detect_os
  install_docker
  detect_cpu
  detect_ram
  detect_gpu
  detect_storage
  select_storage
  get_api_key
  create_config
  setup_auto_updates
  setup_monitoring
  start_worker
  show_summary
}

# Run main installation
main
