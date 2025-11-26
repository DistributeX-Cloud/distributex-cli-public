#!/bin/bash
#
# DistributeX Production Worker Installer - FIXED FOR BACKEND
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
#

set -e

# --------------------------
# Configuration
# --------------------------
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
AGENT_VERSION="2.0.0"
CONFIG_DIR="$HOME/.distributex"
USE_DOCKER="${USE_DOCKER:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n━━━ $1 ━━━\n"; }

# --------------------------
# Requirements
# --------------------------
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

# --------------------------
# User Authentication
# --------------------------
authenticate_user() {
    section "User Authentication"

    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_DIR/token" ]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $API_TOKEN" \
            "$DISTRIBUTEX_API_URL/api/auth/user")
        if [ "$HTTP_CODE" = "200" ]; then
            log "Using existing authentication"
            return 0
        else
            warn "Existing token expired"
            rm -f "$CONFIG_DIR/token"
        fi
    fi

    echo "Choose an option:"
    echo "  1) Sign up"
    echo "  2) Login"
    local choice
    while true; do
        read -p "Enter choice [1-2]: " choice < /dev/tty
        case "$choice" in
            1) signup_user; break ;;
            2) login_user; break ;;
            *) echo "Invalid choice" ;;
        esac
    done
}

signup_user() {
    read -p "First Name: " first_name < /dev/tty
    read -p "Last Name: " last_name < /dev/tty
    read -p "Email: " email < /dev/tty
    while true; do
        read -s -p "Password (min 8 chars): " password < /dev/tty
        echo
        [ ${#password} -lt 8 ] && warn "Password too short" && continue
        read -s -p "Confirm Password: " password_confirm < /dev/tty
        echo
        [ "$password" != "$password_confirm" ] && warn "Passwords do not match" && continue
        break
    done

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ] && \
        error "Signup failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message')"

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    [ -z "$API_TOKEN" ] && error "No token returned"

    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Account created successfully"
}

login_user() {
    read -p "Email: " email < /dev/tty
    read -s -p "Password: " password < /dev/tty
    echo

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")

    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    [ "$HTTP_CODE" != "200" ] && error "Login failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message')"

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    [ -z "$API_TOKEN" ] && error "No token returned"

    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in successfully"
}

# --------------------------
# System Detection
# --------------------------
detect_os() {
    section "System Detection"
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    DISTRO="unknown"
    DISTRO_VERSION="unknown"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
    fi

    log "OS: $OS ($DISTRO $DISTRO_VERSION)"
    log "ARCH: $ARCH"
}

detect_cpu() {
    section "CPU Detection"
    CPU_CORES=$(nproc 2>/dev/null || echo 4)
    CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | cut -d: -f2 | xargs || echo "Unknown CPU")
    CPU_SHARE=$([ $CPU_CORES -ge 8 ] && echo 50 || [ $CPU_CORES -ge 4 ] && echo 40 || echo 30)
    log "CPU: $CPU_MODEL ($CPU_CORES cores, $CPU_SHARE% share)"
}

detect_ram() {
    section "RAM Detection"
    RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    RAM_AVAILABLE=$(free -m | awk '/^Mem:/{print $7}')
    RAM_SHARE=$([ $RAM_TOTAL -ge 16384 ] && echo 30 || [ $RAM_TOTAL -ge 8192 ] && echo 25 || echo 20)
    log "RAM: ${RAM_TOTAL}MB total ($RAM_SHARE% share)"
}

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
    fi
    log "GPU: $GPU_MODEL (Available: $GPU_AVAILABLE, Share: $GPU_SHARE%)"
}

detect_storage() {
    section "Storage Detection"
    STORAGE_TOTAL=0
    STORAGE_AVAILABLE=0
    ROOT_INFO=$(df -k / | tail -1)
    STORAGE_TOTAL=$(($(echo $ROOT_INFO | awk '{print $2}') / 1024 / 1024))
    STORAGE_AVAILABLE=$(($(echo $ROOT_INFO | awk '{print $4}') / 1024 / 1024))
    STORAGE_SHARE=$([ $STORAGE_TOTAL -ge 500 ] && echo 20 || [ $STORAGE_TOTAL -ge 100 ] && echo 15 || echo 10)
    log "Storage: ${STORAGE_TOTAL}GB total, ${STORAGE_SHARE}% share (~$((STORAGE_TOTAL*STORAGE_SHARE/100))GB)"
}

# --------------------------
# Worker Registration
# --------------------------
register_worker() {
    section "Worker Registration"

    PAYLOAD=$(jq -n \
        --arg name "$(hostname)" \
        --arg hostname "$(hostname)" \
        --arg platform "$OS" \
        --arg architecture "$ARCH" \
        --arg cpuModel "$CPU_MODEL" \
        --argjson cpuCores "$CPU_CORES" \
        --argjson ramTotal "$RAM_TOTAL" \
        --argjson ramAvailable "$RAM_AVAILABLE" \
        --argjson gpuAvailable "$GPU_AVAILABLE" \
        --arg gpuModel "$GPU_MODEL" \
        --argjson gpuMemory "$GPU_MEMORY" \
        --argjson storageTotal "$STORAGE_TOTAL" \
        --argjson storageAvailable "$STORAGE_AVAILABLE" \
        --argjson cpuSharePercent "$CPU_SHARE" \
        --argjson ramSharePercent "$RAM_SHARE" \
        --argjson gpuSharePercent "$GPU_SHARE" \
        --argjson storageSharePercent "$STORAGE_SHARE" \
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
            storageTotal: $storageTotal,
            storageAvailable: $storageAvailable,
            cpuSharePercent: $cpuSharePercent,
            ramSharePercent: $ramSharePercent,
            gpuSharePercent: $gpuSharePercent,
            storageSharePercent: $storageSharePercent
        }'
    )

    echo "DEBUG: Payload: $PAYLOAD"

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")

    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    echo "DEBUG: HTTP $HTTP_CODE, BODY: $HTTP_BODY"

    [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ] && \
        error "Worker registration failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message')"

    WORKER_ID=$(echo "$HTTP_BODY" | jq -r '.id')
    [ -z "$WORKER_ID" ] && error "No worker ID returned"

    echo "$WORKER_ID" > "$CONFIG_DIR/worker-id"
    log "Worker registered with ID: $WORKER_ID"
}

# --------------------------
# Configuration
# --------------------------
create_config() {
    section "Saving Configuration"
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
    "storageTotal": $STORAGE_TOTAL,
    "storageShare": $STORAGE_SHARE
  },
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    chmod 600 "$CONFIG_DIR/config.json"
    log "Configuration saved"
}

# --------------------------
# Start Worker
# --------------------------
install_nodejs() {
    section "Node.js Setup"
    command -v node >/dev/null && { log "Node.js already installed"; return; }
    info "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
}

install_worker_agent() {
    section "Worker Agent"
    curl -fsSL "https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/worker-agent.js" \
        -o "$CONFIG_DIR/worker-agent.js"
    chmod +x "$CONFIG_DIR/worker-agent.js"
    log "Worker agent installed"
}

start_worker_nodejs() {
    section "Starting Worker"
    nohup node "$CONFIG_DIR/worker-agent.js" --api-key "$API_TOKEN" --url "$DISTRIBUTEX_API_URL" > "$CONFIG_DIR/worker.log" 2>&1 &
    echo $! > "$CONFIG_DIR/worker.pid"
    log "Worker started (PID: $(cat $CONFIG_DIR/worker.pid))"
}

# --------------------------
# Main Execution
# --------------------------
main() {
    clear
    echo "╔════════════════════════════════╗"
    echo "║   DistributeX Cloud Installer  ║"
    echo "╚════════════════════════════════╝"

    check_requirements
    authenticate_user
    detect_os
    detect_cpu
    detect_ram
    detect_gpu
    detect_storage
    register_worker
    create_config
    install_nodejs
    install_worker_agent
    start_worker_nodejs

    section "Installation Complete"
    echo "Worker ID: $WORKER_ID"
    echo "Logs: $CONFIG_DIR/worker.log"
    echo "Dashboard: $DISTRIBUTEX_API_URL/dashboard"
}

main
