#!/bin/bash
#
# DistributeX Production Worker Installer
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
#
# FIXED: Proper authentication flow and input handling
#

set -e

# Configuration
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
WORKER_IMAGE="distributex/worker:latest"
AGENT_VERSION="2.0.0"
CONFIG_DIR="$HOME/.distributex"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${MAGENTA}━━━ $1 ━━━${NC}\n"; }

# Check requirements
check_requirements() {
  local missing=()
  for cmd in curl jq bc; do
    if ! command -v $cmd &> /dev/null; then
      missing+=($cmd)
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing required commands: ${missing[*]}. Install with: sudo apt install ${missing[*]}"
  fi
}

# User authentication - FIXED to prevent premature exit
authenticate_user() {
  section "User Authentication"
  
  # Check for existing token
  if [ -f "$CONFIG_DIR/token" ]; then
    API_TOKEN=$(cat "$CONFIG_DIR/token")
    
    # Verify token is still valid
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $API_TOKEN" \
      "$DISTRIBUTEX_API_URL/api/auth/user")
    
    if [ "$HTTP_CODE" = "200" ]; then
      log "Using existing authentication"
      return 0
    else
      warn "Existing token expired, need to login again"
      rm -f "$CONFIG_DIR/token"
    fi
  fi
  
  echo ""
  echo "Choose an option:"
  echo "  1) Sign up for new account"
  echo "  2) Login to existing account"
  echo ""
  
  # Force valid input before continuing - FIXED to work with piped input
  local auth_choice=""
  while true; do
    # Redirect from /dev/tty to read from terminal even when piped
    read -p "Enter choice [1-2]: " auth_choice < /dev/tty
    
    # Remove any whitespace
    auth_choice=$(echo "$auth_choice" | tr -d '[:space:]')
    
    case "$auth_choice" in
      1)
        signup_user
        break
        ;;
      2)
        login_user
        break
        ;;
      *)
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        ;;
    esac
  done
} 

# Sign up new user - FIXED for piped input
signup_user() {
  echo ""
  read -p "First Name: " first_name < /dev/tty
  read -p "Last Name: " last_name < /dev/tty
  read -p "Email: " email < /dev/tty
  
  # Password input with validation
  while true; do
    read -s -p "Password (min 8 chars): " password < /dev/tty
    echo ""
    
    if [ ${#password} -lt 8 ]; then
      warn "Password must be at least 8 characters"
      continue
    fi
    
    read -s -p "Confirm Password: " password_confirm < /dev/tty
    echo ""
    
    if [ "$password" != "$password_confirm" ]; then
      warn "Passwords do not match, try again"
      continue
    fi
    
    break
  done
  
  info "Creating account..."
  
  # Make signup request
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\"}")
  
  # Split response body and status code
  HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
  HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
  
  if [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "200" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Unknown error"')
    error "Signup failed (HTTP $HTTP_CODE): $ERROR_MSG"
  fi
  
  # Extract token from response
  API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token // empty')
  
  if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "No token received"')
    error "Authentication failed: $ERROR_MSG"
  fi
  
  # Save token
  mkdir -p "$CONFIG_DIR"
  echo "$API_TOKEN" > "$CONFIG_DIR/token"
  chmod 600 "$CONFIG_DIR/token"
  
  log "Account created successfully!"
}

# Login existing user - FIXED for piped input
login_user() {
  echo ""
  read -p "Email: " email < /dev/tty
  read -s -p "Password: " password < /dev/tty
  echo ""
  
  info "Logging in..."
  
  # Make login request
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$password\"}")
  
  # Split response body and status code
  HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
  HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
  
  if [ "$HTTP_CODE" != "200" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Unknown error"')
    error "Login failed (HTTP $HTTP_CODE): $ERROR_MSG"
  fi
  
  # Extract token
  API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token // empty')
  
  if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "No token received"')
    error "Authentication failed: $ERROR_MSG"
  fi
  
  # Save token
  mkdir -p "$CONFIG_DIR"
  echo "$API_TOKEN" > "$CONFIG_DIR/token"
  chmod 600 "$CONFIG_DIR/token"
  
  log "Logged in successfully!"
}

# Detect operating system
detect_os() {
  section "System Detection"
  
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  
  case "$OS" in
    linux*)
      OS="linux"
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
      fi
      ;;
    darwin*)
      OS="darwin"
      DISTRO="macos"
      DISTRO_VERSION=$(sw_vers -productVersion)
      ;;
    *)
      error "Unsupported OS: $OS"
      ;;
  esac
  
  log "OS: $OS ($DISTRO $DISTRO_VERSION)"
  log "Architecture: $ARCH"
}

# Install Docker if needed
install_docker() {
  if command -v docker &> /dev/null; then
    log "Docker already installed: $(docker --version)"
    return 0
  fi

  section "Installing Docker"
  
  if [ "$OS" = "linux" ]; then
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER || true
    sudo systemctl start docker || true
    sudo systemctl enable docker || true
    log "Docker installed"
    warn "You may need to log out and back in for group changes"
  else
    error "Please install Docker Desktop manually: https://www.docker.com/products/docker-desktop"
  fi
}

# Detect CPU
detect_cpu() {
  section "CPU Detection"
  
  CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
  CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name:" | cut -d: -f2 | xargs || sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")
  
  # Calculate share percentage
  if [ $CPU_CORES -ge 8 ]; then
    CPU_SHARE=50
  elif [ $CPU_CORES -ge 4 ]; then
    CPU_SHARE=40
  else
    CPU_SHARE=30
  fi
  
  log "CPU: $CPU_MODEL"
  log "Cores: $CPU_CORES"
  log "Share: ${CPU_SHARE}% (~$(echo "$CPU_CORES * $CPU_SHARE / 100" | bc) cores)"
}

# Detect RAM
detect_ram() {
  section "RAM Detection"
  
  if [ "$OS" = "linux" ]; then
    RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    RAM_AVAILABLE=$(free -m | awk '/^Mem:/{print $7}')
  else
    RAM_TOTAL=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
    RAM_AVAILABLE=$(( $(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//') * 4096 / 1024 / 1024 ))
  fi
  
  RAM_TOTAL_GB=$(echo "scale=2; $RAM_TOTAL / 1024" | bc)
  
  # Calculate share
  if [ $RAM_TOTAL -ge 16384 ]; then
    RAM_SHARE=30
  elif [ $RAM_TOTAL -ge 8192 ]; then
    RAM_SHARE=25
  else
    RAM_SHARE=20
  fi
  
  log "Total RAM: ${RAM_TOTAL_GB}GB"
  log "Share: ${RAM_SHARE}%"
}

# Detect GPU
detect_gpu() {
  section "GPU Detection"
  
  GPU_AVAILABLE=false
  GPU_MODEL="none"
  GPU_MEMORY=0
  GPU_SHARE=0
  
  # NVIDIA
  if command -v nvidia-smi &> /dev/null; then
    GPU_AVAILABLE=true
    GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
    GPU_SHARE=50
    log "NVIDIA GPU: $GPU_MODEL (${GPU_MEMORY}MB)"
  # AMD
  elif command -v rocm-smi &> /dev/null; then
    GPU_AVAILABLE=true
    GPU_MODEL="AMD GPU"
    GPU_SHARE=50
    log "AMD GPU detected"
  # Apple Silicon
  elif [ "$OS" = "darwin" ] && [[ "$ARCH" == "arm64" ]]; then
    GPU_AVAILABLE=true
    GPU_MODEL="Apple Silicon GPU"
    GPU_SHARE=50
    log "Apple Silicon GPU detected"
  else
    warn "No compatible GPU found"
  fi
  
  if [ "$GPU_AVAILABLE" = true ]; then
    log "GPU Share: ${GPU_SHARE}%"
  fi
}

# Detect storage devices
detect_storage() {
  section "Storage Detection"
  
  STORAGE_DEVICES=()
  
  if [ "$OS" = "linux" ]; then
    while IFS= read -r line; do
      DEV=$(echo $line | awk '{print $1}')
      MOUNT=$(echo $line | awk '{print $7}')
      
      if [ -z "$MOUNT" ] || [[ "$DEV" == loop* ]]; then
        continue
      fi
      
      TOTAL=$(df -BG "$MOUNT" 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//')
      AVAIL=$(df -BG "$MOUNT" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
      
      if [ ! -z "$AVAIL" ] && [ $AVAIL -gt 0 ]; then
        STORAGE_DEVICES+=("$DEV|$MOUNT|$TOTAL|$AVAIL")
        log "Found: $DEV at $MOUNT (${TOTAL}GB total, ${AVAIL}GB free)"
      fi
    done < <(lsblk -o NAME,MOUNTPOINT | grep "/" | grep -v "^NAME")
  else
    while IFS= read -r line; do
      DEV=$(echo $line | awk '{print $1}')
      MOUNT=$(echo $line | awk '{print $9}')
      TOTAL=$(echo $line | awk '{print $2}' | sed 's/Gi//')
      AVAIL=$(echo $line | awk '{print $4}' | sed 's/Gi//')
      
      STORAGE_DEVICES+=("$DEV|$MOUNT|$TOTAL|$AVAIL")
      log "Found: $DEV at $MOUNT (${TOTAL}GB total, ${AVAIL}GB free)"
    done < <(df -H | grep "^/dev/")
  fi
}

# Select storage
select_storage() {
  section "Storage Configuration"
  
  SELECTED_STORAGE=()
  TOTAL_STORAGE=0
  
  for device in "${STORAGE_DEVICES[@]}"; do
    IFS='|' read -r dev mount total avail <<< "$device"
    
    if [ "$mount" = "/" ]; then
      log "Auto-selected: $mount (${avail}GB available)"
      SELECTED_STORAGE+=("$device")
      TOTAL_STORAGE=$((TOTAL_STORAGE + avail))
      continue
    fi
    
    read -p "Include $mount with ${avail}GB available? (y/N): " -n 1 -r REPLY < /dev/tty
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      SELECTED_STORAGE+=("$device")
      TOTAL_STORAGE=$((TOTAL_STORAGE + avail))
      log "Added: $mount"
    fi
  done
  
  if [ $TOTAL_STORAGE -ge 500 ]; then
    STORAGE_SHARE=20
  elif [ $TOTAL_STORAGE -ge 100 ]; then
    STORAGE_SHARE=15
  else
    STORAGE_SHARE=10
  fi
  
  STORAGE_GB_SHARED=$(echo "$TOTAL_STORAGE * $STORAGE_SHARE / 100" | bc)
  log "Total: ${TOTAL_STORAGE}GB, Share: ${STORAGE_SHARE}% (~${STORAGE_GB_SHARED}GB)"
}

# Register worker via API - FIXED error handling
register_worker() {
  section "Worker Registration"
  
  info "Registering worker with API..."
  
  PAYLOAD=$(cat <<EOF
{
  "name": "$(hostname)",
  "hostname": "$(hostname)",
  "platform": "$OS",
  "architecture": "$ARCH",
  "cpuCores": $CPU_CORES,
  "cpuModel": "$CPU_MODEL",
  "ramTotal": $RAM_TOTAL,
  "ramAvailable": $RAM_AVAILABLE,
  "gpuAvailable": $GPU_AVAILABLE,
  "gpuModel": "$GPU_MODEL",
  "gpuMemory": $GPU_MEMORY,
  "storageTotal": $TOTAL_STORAGE,
  "storageAvailable": $TOTAL_STORAGE,
  "cpuSharePercent": $CPU_SHARE,
  "ramSharePercent": $RAM_SHARE,
  "gpuSharePercent": $GPU_SHARE,
  "storageSharePercent": $STORAGE_SHARE
}
EOF
)
  
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  
  HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
  HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
  
  if [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "200" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Unknown error"')
    error "Worker registration failed (HTTP $HTTP_CODE): $ERROR_MSG"
  fi
  
  WORKER_ID=$(echo "$HTTP_BODY" | jq -r '.id // empty')
  
  if [ -z "$WORKER_ID" ] || [ "$WORKER_ID" = "null" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "No worker ID received"')
    error "Worker registration failed: $ERROR_MSG"
  fi
  
  echo "$WORKER_ID" > "$CONFIG_DIR/worker-id"
  log "Worker registered! ID: $WORKER_ID"
}

# Create configuration
create_config() {
  section "Configuration"
  
  mkdir -p "$CONFIG_DIR"
  
  cat > "$CONFIG_DIR/config.json" <<EOF
{
  "version": "$AGENT_VERSION",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "workerId": "$WORKER_ID",
  "worker": {
    "name": "$(hostname)",
    "cpuCores": $CPU_CORES,
    "cpuShare": $CPU_SHARE,
    "ramTotal": $RAM_TOTAL,
    "ramShare": $RAM_SHARE,
    "gpuAvailable": $GPU_AVAILABLE,
    "gpuShare": $GPU_SHARE,
    "storageTotal": $TOTAL_STORAGE,
    "storageShare": $STORAGE_SHARE
  },
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  
  chmod 600 "$CONFIG_DIR/config.json"
  log "Configuration saved"
}

# Start worker container
start_worker() {
  section "Starting Worker"
  
  docker stop distributex-worker 2>/dev/null || true
  docker rm distributex-worker 2>/dev/null || true
  
  DOCKER_CMD="docker run -d --name distributex-worker --restart unless-stopped"
  DOCKER_CMD="$DOCKER_CMD -v $CONFIG_DIR:/config:ro"
  DOCKER_CMD="$DOCKER_CMD --cpus=$(echo "$CPU_CORES * $CPU_SHARE / 100" | bc)"
  DOCKER_CMD="$DOCKER_CMD --memory=$(echo "$RAM_TOTAL * $RAM_SHARE / 100" | bc)m"
  
  if [ "$GPU_AVAILABLE" = true ]; then
    if command -v nvidia-smi &> /dev/null; then
      DOCKER_CMD="$DOCKER_CMD --gpus all"
    fi
  fi
  
  for device in "${SELECTED_STORAGE[@]}"; do
    IFS='|' read -r dev mount total avail <<< "$device"
    DOCKER_CMD="$DOCKER_CMD -v $mount:/storage$(echo $mount | tr '/' '_'):rw"
  done
  
  DOCKER_CMD="$DOCKER_CMD $WORKER_IMAGE"
  
  info "Pulling image..."
  docker pull $WORKER_IMAGE
  
  info "Starting container..."
  eval $DOCKER_CMD
  
  sleep 2
  
  if docker ps | grep -q distributex-worker; then
    log "Worker container started!"
  else
    error "Failed to start container"
  fi
}

# Setup monitoring
setup_monitoring() {
  section "Monitoring Setup"
  
  cat > /usr/local/bin/distributex-monitor <<'EOF'
#!/bin/bash
if ! docker ps | grep -q distributex-worker; then
  docker start distributex-worker || exit 1
fi
EOF
  
  chmod +x /usr/local/bin/distributex-monitor
  
  (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/distributex-monitor") | crontab -
  
  log "Health monitoring enabled (every 5 minutes)"
}

# Show summary
show_summary() {
  section "Installation Complete!"
  
  cat <<EOF

${GREEN}╔═══════════════════════════════════════════════════════════╗
        ║                ✨ Successfully Installed! ✨              ║
        ╚═══════════════════════════════════════════════════════════╝${NC}

${CYAN}Worker Details:${NC}
  • ID: $WORKER_ID
  • CPU: ${CPU_CORES} cores (${CPU_SHARE}% shared)
  • RAM: ${RAM_TOTAL_GB}GB (${RAM_SHARE}% shared)
  • GPU: $GPU_MODEL (${GPU_SHARE}% shared)
  • Storage: ${TOTAL_STORAGE}GB (${STORAGE_SHARE}% shared)

${CYAN}Management:${NC}
  • Status:  docker ps | grep distributex
  • Logs:    docker logs -f distributex-worker
  • Stop:    docker stop distributex-worker
  • Restart: docker restart distributex-worker

${CYAN}Dashboard:${NC}
  ${DISTRIBUTEX_API_URL}/dashboard

${GREEN}🎉 Your device is now contributing to the network!${NC}

EOF
}

# Main execution
main() {
  clear
  
  cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║              DistributeX Cloud Network                   ║
║           Production Installer v2.0                      ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝

EOF

  check_requirements
  authenticate_user
  detect_os
  install_docker
  detect_cpu
  detect_ram
  detect_gpu
  detect_storage
  select_storage
  register_worker
  create_config
  start_worker
  setup_monitoring
  show_summary
}

# Run main function
main
