#!/bin/bash
#
# DistributeX Production Worker Installer - FIXED VERSION
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
#

set -e

# Configuration
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
AGENT_VERSION="2.0.0"
CONFIG_DIR="$HOME/.distributex"
USE_DOCKER="${USE_DOCKER:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${MAGENTA}━━━ $1 ━━━${NC}\n"; }

# Check requirements
check_requirements() {
  section "Checking Requirements"
  local missing=()
  for cmd in curl jq bc; do
    if ! command -v $cmd &> /dev/null; then
      missing+=($cmd)
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing required commands: ${missing[*]}. Install with: sudo apt install ${missing[*]}"
  fi
  log "All requirements satisfied"
}

# User authentication
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
  
  local auth_choice=""
  while true; do
    read -p "Enter choice [1-2]: " auth_choice < /dev/tty
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

# Sign up new user
signup_user() {
  echo ""
  read -p "First Name: " first_name < /dev/tty
  read -p "Last Name: " last_name < /dev/tty
  read -p "Email: " email < /dev/tty
  
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
  
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\"}")
  
  HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
  HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
  
  if [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "200" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Unknown error"')
    error "Signup failed (HTTP $HTTP_CODE): $ERROR_MSG"
  fi
  
  API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token // empty')
  
  if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "No token received"')
    error "Authentication failed: $ERROR_MSG"
  fi
  
  mkdir -p "$CONFIG_DIR"
  echo "$API_TOKEN" > "$CONFIG_DIR/token"
  chmod 600 "$CONFIG_DIR/token"
  
  log "Account created successfully!"
}

# Login existing user
login_user() {
  echo ""
  read -p "Email: " email < /dev/tty
  read -s -p "Password: " password < /dev/tty
  echo ""
  
  info "Logging in..."
  
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$password\"}")
  
  HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
  HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
  
  if [ "$HTTP_CODE" != "200" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Unknown error"')
    error "Login failed (HTTP $HTTP_CODE): $ERROR_MSG"
  fi
  
  API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token // empty')
  
  if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
    ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "No token received"')
    error "Authentication failed: $ERROR_MSG"
  fi
  
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

# Install Docker
install_docker() {
  if [ "$USE_DOCKER" = "false" ]; then
    info "Skipping Docker installation (using Node.js agent)"
    return 0
  fi
  
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
  
  if command -v nvidia-smi &> /dev/null; then
    GPU_AVAILABLE=true
    GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
    GPU_SHARE=50
    log "NVIDIA GPU: $GPU_MODEL (${GPU_MEMORY}MB)"
  elif command -v rocm-smi &> /dev/null; then
    GPU_AVAILABLE=true
    GPU_MODEL="AMD GPU"
    GPU_SHARE=50
    log "AMD GPU detected"
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

# Detect storage
detect_storage() {
  section "Storage Detection"
  
  STORAGE_DEVICES=()
  
  if [ "$OS" = "linux" ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^Filesystem ]] || [[ "$line" =~ ^tmpfs ]] || [[ "$line" =~ ^devtmpfs ]] || [[ "$line" =~ ^udev ]]; then
        continue
      fi
      
      DEV=$(echo "$line" | awk '{print $1}')
      MOUNT=$(echo "$line" | awk '{print $6}')
      TOTAL=$(echo "$line" | awk '{print $2}')
      AVAIL=$(echo "$line" | awk '{print $4}')
      
      TOTAL_GB=$((TOTAL / 1024 / 1024))
      AVAIL_GB=$((AVAIL / 1024 / 1024))
      
      if [ $AVAIL_GB -gt 1 ]; then
        STORAGE_DEVICES+=("$DEV|$MOUNT|$TOTAL_GB|$AVAIL_GB")
        log "Found: $DEV at $MOUNT (${TOTAL_GB}GB total, ${AVAIL_GB}GB free)"
      fi
    done < <(df -k | grep "^/dev/")
    
    if [ ${#STORAGE_DEVICES[@]} -eq 0 ]; then
      ROOT_INFO=$(df -k / | tail -1)
      DEV=$(echo "$ROOT_INFO" | awk '{print $1}')
      TOTAL=$(($(echo "$ROOT_INFO" | awk '{print $2}') / 1024 / 1024))
      AVAIL=$(($(echo "$ROOT_INFO" | awk '{print $4}') / 1024 / 1024))
      STORAGE_DEVICES+=("$DEV|/|$TOTAL|$AVAIL")
      log "Using root filesystem: $DEV (${TOTAL}GB total, ${AVAIL}GB free)"
    fi
    
  elif [ "$OS" = "darwin" ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^Filesystem ]] || [[ "$line" =~ ^map ]] || [[ "$line" =~ ^devfs ]]; then
        continue
      fi
      
      DEV=$(echo "$line" | awk '{print $1}')
      MOUNT=$(echo "$line" | awk '{print $9}')
      TOTAL=$(echo "$line" | awk '{print $2}')
      AVAIL=$(echo "$line" | awk '{print $4}')
      
      TOTAL_GB=$((TOTAL / 2 / 1024 / 1024))
      AVAIL_GB=$((AVAIL / 2 / 1024 / 1024))
      
      if [ $AVAIL_GB -gt 1 ]; then
        STORAGE_DEVICES+=("$DEV|$MOUNT|$TOTAL_GB|$AVAIL_GB")
        log "Found: $DEV at $MOUNT (${TOTAL_GB}GB total, ${AVAIL_GB}GB free)"
      fi
    done < <(df -k | grep "^/dev/")
    
    if [ ${#STORAGE_DEVICES[@]} -eq 0 ]; then
      ROOT_INFO=$(df -k / | tail -1)
      DEV=$(echo "$ROOT_INFO" | awk '{print $1}')
      TOTAL=$(($(echo "$ROOT_INFO" | awk '{print $2}') / 2 / 1024 / 1024))
      AVAIL=$(($(echo "$ROOT_INFO" | awk '{print $4}') / 2 / 1024 / 1024))
      STORAGE_DEVICES+=("$DEV|/|$TOTAL|$AVAIL")
      log "Using root filesystem: $DEV (${TOTAL}GB total, ${AVAIL}GB free)"
    fi
  else
    ROOT_INFO=$(df / | tail -1)
    DEV=$(echo "$ROOT_INFO" | awk '{print $1}')
    TOTAL=100
    AVAIL=50
    STORAGE_DEVICES+=("$DEV|/|$TOTAL|$AVAIL")
    warn "Could not detect storage, using defaults"
  fi
  
  if [ ${#STORAGE_DEVICES[@]} -eq 0 ]; then
    error "No storage devices detected"
  fi
}

# Select storage
select_storage() {
  section "Storage Configuration"
  
  SELECTED_STORAGE=()
  TOTAL_STORAGE=0
  
  if [ ${#STORAGE_DEVICES[@]} -eq 1 ]; then
    device="${STORAGE_DEVICES[0]}"
    IFS='|' read -r dev mount total avail <<< "$device"
    log "Auto-selected: $mount (${avail}GB available)"
    SELECTED_STORAGE+=("$device")
    TOTAL_STORAGE=$avail
  else
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
  fi
  
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

# Register worker
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
  
  if [ -f "$CONFIG_DIR" ]; then
    rm -f "$CONFIG_DIR"
  fi
  mkdir -p "$CONFIG_DIR"
  
  if [ -d "$CONFIG_DIR/config.json" ]; then
    rm -rf "$CONFIG_DIR/config.json"
  fi
  
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

# Install Node.js
install_nodejs() {
  section "Node.js Setup"
  
  if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v)
    log "Node.js already installed: $NODE_VERSION"
    return 0
  fi
  
  info "Installing Node.js..."
  
  if [ "$OS" = "linux" ]; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
  elif [ "$OS" = "darwin" ]; then
    if command -v brew &> /dev/null; then
      brew install node
    else
      error "Please install Node.js manually from https://nodejs.org/"
    fi
  else
    error "Please install Node.js manually from https://nodejs.org/"
  fi
  
  log "Node.js installed: $(node -v)"
}

# Install worker agent
install_worker_agent() {
  section "Installing Worker Agent"
  
  info "Downloading worker agent..."
  
  curl -fsSL "https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/worker-agent.js" \
    -o "$CONFIG_DIR/worker-agent.js"
  
  chmod +x "$CONFIG_DIR/worker-agent.js"
  
  log "Worker agent installed"
}

# Start worker (Node.js version)
start_worker_nodejs() {
  section "Starting Worker"
  
  info "Starting Node.js worker..."
  
  # Create systemd service if on Linux with systemd
  if [ "$OS" = "linux" ] && command -v systemctl &> /dev/null; then
    sudo tee /etc/systemd/system/distributex-worker.service > /dev/null <<EOF
[Unit]
Description=DistributeX Worker
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$CONFIG_DIR
ExecStart=$(which node) $CONFIG_DIR/worker-agent.js --api-key $API_TOKEN --url $DISTRIBUTEX_API_URL
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable distributex-worker
    sudo systemctl start distributex-worker
    
    log "Worker service installed and started"
    info "Check status with: sudo systemctl status distributex-worker"
  else
    # Fallback: run in background with nohup
    nohup node "$CONFIG_DIR/worker-agent.js" --api-key "$API_TOKEN" --url "$DISTRIBUTEX_API_URL" > "$CONFIG_DIR/worker.log" 2>&1 &
    echo $! > "$CONFIG_DIR/worker.pid"
    
    log "Worker started in background (PID: $(cat $CONFIG_DIR/worker.pid))"
    info "Check logs: tail -f $CONFIG_DIR/worker.log"
  fi
}

# Start worker
start_worker() {
  if [ "$USE_DOCKER" = "true" ]; then
    error "Docker mode not yet implemented. Set USE_DOCKER=false"
  else
    install_nodejs
    install_worker_agent
    start_worker_nodejs
  fi
}

# Setup monitoring
setup_monitoring() {
  section "Monitoring Setup"
  
  if [ "$OS" = "linux" ] && command -v systemctl &> /dev/null; then
    log "Using systemd for monitoring (auto-restart enabled)"
  else
    # Create simple health check script
    cat > "$CONFIG_DIR/monitor.sh" <<'EOF'
#!/bin/bash
if [ ! -f "$HOME/.distributex/worker.pid" ]; then
  exit 0
fi

PID=$(cat "$HOME/.distributex/worker.pid")
if ! ps -p $PID > /dev/null 2>&1; then
  cd "$HOME/.distributex"
  nohup node worker-agent.js --api-key $(cat token) --url ${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev} > worker.log 2>&1 &
  echo $! > worker.pid
fi
EOF
    chmod +x "$CONFIG_DIR/monitor.sh"
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v distributex-monitor; echo "*/5 * * * * $CONFIG_DIR/monitor.sh") | crontab -
    
    log "Health monitoring enabled (every 5 minutes)"
  fi
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
EOF

  if [ "$OS" = "linux" ] && command -v systemctl &> /dev/null; then
    cat <<EOF
  • Status:  sudo systemctl status distributex-worker
  • Logs:    sudo journalctl -u distributex-worker -f
  • Stop:    sudo systemctl stop distributex-worker
  • Restart: sudo systemctl restart distributex-worker
EOF
  else
    cat <<EOF
  • Status:  ps aux | grep worker-agent
  • Logs:    tail -f $CONFIG_DIR/worker.log
  • Stop:    kill \$(cat $CONFIG_DIR/worker.pid)
  • Restart: $CONFIG_DIR/monitor.sh
EOF
  fi

  cat <<EOF

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
