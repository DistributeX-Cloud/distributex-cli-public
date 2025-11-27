#!/bin/bash
#
# DistributeX Complete Installer
# Supports both Contributors (share resources) and Developers (use resources)
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
#

set -e

# --------------------------
# Configuration
# --------------------------
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributex/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"
LOCAL_DOCKERFILE_URL="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/Dockerfile"
LOCAL_WORKER_JS_URL="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/worker-agent.js"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# --------------------------
# Logging Functions
# --------------------------
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"; }

# --------------------------
# Banner
# --------------------------
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║        ██████╗ ██╗███████╗████████╗██████╗ ██╗██╗        ║"
    echo "║        ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║╚██╗       ║"
    echo "║        ██║  ██║██║███████╗   ██║   ██████╔╝██║ ██║       ║"
    echo "║        ██║  ██║██║╚════██║   ██║   ██╔══██╗██║ ██║       ║"
    echo "║        ██████╔╝██║███████║   ██║   ██║  ██║██║██╔╝       ║"
    echo "║        ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝        ║"
    echo "║                                                           ║"
    echo "║              DistributeX Cloud Network                   ║"
    echo "║          Distributed Computing Platform                  ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
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
    for cmd in curl jq bc uname; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required commands: ${missing[*]}"
    fi
    
    # Check for GPU tools (informational only)
    local gpu_tools=()
    if command -v nvidia-smi &> /dev/null; then
        gpu_tools+=("NVIDIA GPU detected")
    fi
    if command -v rocm-smi &> /dev/null; then
        gpu_tools+=("AMD GPU detected")
    fi
    
    log "All requirements satisfied"
    log "Docker version: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
    
    if [ ${#gpu_tools[@]} -gt 0 ]; then
        log "GPU tools: ${gpu_tools[*]}"
    fi
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
    
    while true; do
        read -p "Enter choice [1-2]: " choice < /dev/tty
        case "$choice" in
            1) signup_user; break ;;
            2) login_user; break ;;
            *) echo "Invalid choice, please enter 1 or 2" ;;
        esac
    done
}

signup_user() {
    echo ""
    echo -e "${CYAN}Create Your Account${NC}"
    read -p "First Name: " first_name < /dev/tty
    read -p "Last Name: " last_name < /dev/tty
    read -p "Email: " email < /dev/tty
    
    while true; do
        read -s -p "Password (min 8 chars): " password < /dev/tty; echo
        if [ ${#password} -lt 8 ]; then
            warn "Password must be at least 8 characters"
            continue
        fi
        read -s -p "Confirm Password: " password_confirm < /dev/tty; echo
        if [ "$password" != "$password_confirm" ]; then
            warn "Passwords do not match"
            continue
        fi
        break
    done

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
}

login_user() {
    echo ""
    echo -e "${CYAN}Login to Your Account${NC}"
    read -p "Email: " email < /dev/tty
    read -s -p "Password: " password < /dev/tty; echo
    
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
}

# --------------------------
# User Role Selection
# --------------------------
select_user_role() {
    section "Select Your Role"
    
    echo ""
    echo -e "${CYAN}What would you like to do?${NC}"
    echo ""
    echo "  1) ${GREEN}Contributor${NC} - Share my computing resources (CPU, RAM, GPU, Storage)"
    echo "     • Install Docker worker agent"
    echo "     • Automatically share idle resources"
    echo "     • Support developers"
    echo ""
    echo "  2) ${BLUE}Developer${NC} - Use distributed computing resources"
    echo "     • Get free access"
    echo "     • Submit computational tasks"
    echo "     • Access global resource pool"
    echo ""
    
    while true; do
        read -p "Enter choice [1-2]: " role_choice < /dev/tty
        case "$role_choice" in
            1) 
                USER_ROLE="contributor"
                log "Role: Contributor (Resource Sharer)"
                break 
                ;;
            2) 
                USER_ROLE="developer"
                log "Role: Developer (Resource User)"
                break 
                ;;
            *) 
                echo "Invalid choice, please enter 1 or 2" 
                ;;
        esac
    done
}

# --------------------------
# Developer Setup
# --------------------------
setup_developer() {
    section "Developer Setup"
    
    # Save role
    echo "developer" > "$CONFIG_DIR/role"
    
    # Display API information
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Developer Access Configured!                ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Your API Key:${NC}"
    echo -e "${YELLOW}$API_TOKEN${NC}"
    echo ""
    echo -e "${CYAN}API Endpoint:${NC}"
    echo "$DISTRIBUTEX_API_URL/api"
    echo ""
    echo -e "${CYAN}Quick Start Example:${NC}"
    echo ""
    echo "# Submit a task"
    echo "curl -X POST $DISTRIBUTEX_API_URL/api/tasks/submit \\"
    echo "  -H \"Authorization: Bearer $API_TOKEN\" \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d '{"
    echo "    \"name\": \"My Task\","
    echo "    \"cpuRequired\": 4,"
    echo "    \"ramRequired\": 8192,"
    echo "    \"storageRequired\": 10"
    echo "  }'"
    echo ""
    echo -e "${CYAN}Documentation:${NC}"
    echo "$DISTRIBUTEX_API_URL/api-docs"
    echo ""
    echo -e "${CYAN}Dashboard:${NC}"
    echo "$DISTRIBUTEX_API_URL/dashboard"
    echo ""
    
    # Save API key to config
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "role": "developer",
  "apiKey": "$API_TOKEN",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    chmod 600 "$CONFIG_DIR/config.json"
    
    log "Developer setup complete!"
    log "Configuration saved to: $CONFIG_DIR/config.json"
}

# --------------------------
# GPU Detection
# --------------------------
detect_gpu() {
    GPU_AVAILABLE=false
    GPU_MODEL="null"
    GPU_MEMORY="null"
    GPU_SHARE_PERCENT=0
    
    # NVIDIA GPU Detection (Linux)
    if command -v nvidia-smi &> /dev/null; then
        info "Detecting NVIDIA GPU..."
        GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)
        if [ ! -z "$GPU_INFO" ]; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(echo "$GPU_INFO" | cut -d',' -f1 | xargs)
            GPU_MEMORY=$(echo "$GPU_INFO" | cut -d',' -f2 | grep -oE '[0-9]+')
            GPU_SHARE_PERCENT=50
            log "NVIDIA GPU detected: $GPU_MODEL (${GPU_MEMORY}MB)"
        fi
    # AMD GPU Detection (Linux)
    elif command -v rocm-smi &> /dev/null; then
        info "Detecting AMD GPU..."
        GPU_INFO=$(rocm-smi --showproductname 2>/dev/null | grep "GPU" | head -1)
        if [ ! -z "$GPU_INFO" ]; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(echo "$GPU_INFO" | cut -d':' -f2 | xargs)
            GPU_MEMORY=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "Total" | grep -oE '[0-9]+' | head -1)
            GPU_SHARE_PERCENT=50
            log "AMD GPU detected: $GPU_MODEL"
        fi
    # Metal GPU Detection (macOS)
    elif [ "$OS" = "darwin" ]; then
        info "Detecting Metal GPU (macOS)..."
        GPU_INFO=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -1)
        if [ ! -z "$GPU_INFO" ]; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(echo "$GPU_INFO" | cut -d':' -f2 | xargs)
            # macOS GPU memory is harder to detect, estimate from total RAM
            GPU_MEMORY=$(echo "scale=0; $RAM_TOTAL * 0.5" | bc)
            GPU_SHARE_PERCENT=30
            log "Metal GPU detected: $GPU_MODEL"
        fi
    # Intel GPU Detection (Linux)
    elif command -v intel_gpu_top &> /dev/null; then
        info "Detecting Intel GPU..."
        GPU_INFO=$(lspci | grep -i "vga.*intel" | head -1)
        if [ ! -z "$GPU_INFO" ]; then
            GPU_AVAILABLE=true
            GPU_MODEL="Intel Integrated Graphics"
            GPU_MEMORY=2048  # Estimate
            GPU_SHARE_PERCENT=40
            log "Intel GPU detected"
        fi
    fi
    
    if [ "$GPU_AVAILABLE" = false ]; then
        info "No GPU detected or GPU tools not installed"
        info "If you have a GPU, install nvidia-smi (NVIDIA) or rocm-smi (AMD)"
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
    
    if command -v free &> /dev/null; then
        RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    else
        RAM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 8192)
    fi
    
    STORAGE_TOTAL=$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo 100)
    
    # Detect GPU
    detect_gpu
    
    # Calculate Docker resource limits (more conservative)
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
    log "CPU: $CPU_CORES cores (Docker limit: ${DOCKER_CPU_LIMIT} cores)"
    log "RAM: ${RAM_TOTAL}MB (Docker limit: ${DOCKER_RAM_LIMIT}GB)"
    log "Storage: ${STORAGE_TOTAL}GB"
    if [ "$GPU_AVAILABLE" = true ]; then
        log "GPU: $GPU_MODEL (Sharing: ${GPU_SHARE_PERCENT}%)"
    fi
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
        warn "Failed to pull $DOCKER_IMAGE from Docker Hub"
        info "Building image locally..."
        
        mkdir -p "$CONFIG_DIR/docker-build"

        # Download required files
        curl -sSL "$LOCAL_DOCKERFILE_URL" -o "$CONFIG_DIR/docker-build/Dockerfile"
        curl -sSL "$LOCAL_WORKER_JS_URL" -o "$CONFIG_DIR/docker-build/worker-agent.js"
        curl -sSL "https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/package.json" -o "$CONFIG_DIR/docker-build/package.json"

        docker build -t $DOCKER_IMAGE "$CONFIG_DIR/docker-build" || error "Failed to build Docker image"
        log "Docker image built locally"
    fi
    
    # Check for GPU runtime support
    if [ "$GPU_AVAILABLE" = true ]; then
        if command -v nvidia-smi &> /dev/null; then
            # Check if nvidia-docker is installed
            if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi &> /dev/null; then
                log "NVIDIA Docker runtime verified"
            else
                warn "NVIDIA GPU detected but Docker GPU runtime not available"
                warn "Install nvidia-docker for GPU support: https://github.com/NVIDIA/nvidia-docker"
                warn "Worker will run without GPU acceleration"
                GPU_AVAILABLE=false
            fi
        fi
    fi
}

# --------------------------
# Stop Existing Container
# --------------------------
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
# Register Worker Device
# --------------------------
register_worker() {
    section "Registering Worker Device"

    WORKER_NAME="${HOSTNAME:-$(hostname)}"

    # CPU model
    if [ "$OS" = "linux" ]; then
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    elif [ "$OS" = "darwin" ]; then
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")
    else
        CPU_MODEL="Unknown CPU"
    fi

    info "Registering device: $WORKER_NAME"

    # GPU JSON emission
    if [ "$GPU_AVAILABLE" = true ]; then
        GPU_JSON="
        \"gpuAvailable\": true,
        \"gpuModel\": \"$GPU_MODEL\",
        \"gpuMemory\": $GPU_MEMORY,
        \"gpuCount\": ${GPU_COUNT:-1},
        \"gpuDriverVersion\": \"$GPU_DRIVER_VERSION\",
        \"gpuCudaVersion\": \"$GPU_CUDA_VERSION\",
        \"gpuSharePercent\": ${GPU_SHARE_PERCENT:-50},"
    else
        GPU_JSON="
        \"gpuAvailable\": false,
        \"gpuCount\": 0,
        \"gpuSharePercent\": 0,"
    fi

    # Stable fingerprint (same as worker-agent.js)
    MAC=$(ip link show | awk '/link\/ether/ {print $2; exit}')
    FINGERPRINT_SRC="${MAC}-${CPU_MODEL}-${OS}-${ARCH}"
    DEVICE_FINGERPRINT=$(echo -n "$FINGERPRINT_SRC" | sha256sum | cut -c1-32)

    # Is Docker?
    if [ -f "/.dockerenv" ]; then
        IS_DOCKER=true
        DOCKER_ID=$(cat /proc/self/cgroup | grep -oE 'docker/[a-f0-9]+' | head -1 | cut -d/ -f2 | cut -c1-12)
    else
        IS_DOCKER=false
        DOCKER_ID=null
    fi

    REGISTER_DATA=$(cat <<EOF
{
  "name": "$WORKER_NAME",
  "hostname": "$WORKER_NAME",
  "platform": "$OS",
  "architecture": "$ARCH",
  "cpuCores": $CPU_CORES,
  "cpuModel": "$CPU_MODEL",
  "ramTotal": $RAM_TOTAL,
  "ramAvailable": $RAM_TOTAL,
  $GPU_JSON
  "storageTotal": $STORAGE_TOTAL,
  "storageAvailable": $STORAGE_TOTAL,
  "cpuSharePercent": 40,
  "ramSharePercent": 30,
  "storageSharePercent": 20,
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
        log "Worker registered successfully! ID: $WORKER_ID"
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
        # NVIDIA GPU support
        if command -v nvidia-smi &> /dev/null; then
            info "Enabling NVIDIA GPU support..."
            DOCKER_CMD="$DOCKER_CMD --gpus all"
        # AMD GPU support (rocm)
        elif command -v rocm-smi &> /dev/null; then
            info "Enabling AMD GPU support..."
            DOCKER_CMD="$DOCKER_CMD --device=/dev/kfd --device=/dev/dri"
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
# Verify Worker Connection
# --------------------------
verify_worker_connection() {
    section "Verifying Worker Connection"
    
    info "Waiting for worker to send first heartbeat..."
    sleep 10
    
    # Check if worker is reporting as online
    RESPONSE=$(curl -s -H "Authorization: Bearer $API_TOKEN" \
        "$DISTRIBUTEX_API_URL/api/workers/my")
    
    ONLINE_COUNT=$(echo "$RESPONSE" | jq '[.[] | select(.status=="online")] | length')
    
    if [ "$ONLINE_COUNT" -gt 0 ]; then
        log "Worker is online and connected!"
        log "Heartbeat system is working correctly"
    else
        warn "Worker may not be online yet. Check logs with: docker logs $CONTAINER_NAME"
    fi
}

# --------------------------
# Setup Auto-Start on Boot
# --------------------------
setup_auto_start() {
    section "Configuring Auto-Start on Boot"
    
    # Docker's --restart unless-stopped already handles auto-start
    log "Auto-start configured via Docker restart policy"
    
    # Additional systemd service for extra reliability (Linux only)
    if [ "$OS" = "linux" ] && command -v systemctl &> /dev/null; then
        info "Creating systemd service for additional reliability..."
        
        sudo tee /etc/systemd/system/distributex-worker.service > /dev/null <<EOF
[Unit]
Description=DistributeX Worker Container
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start $CONTAINER_NAME
ExecStop=/usr/bin/docker stop $CONTAINER_NAME
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        sudo systemctl daemon-reload
        sudo systemctl enable distributex-worker.service
        log "Systemd service installed and enabled"
    fi
    
    info "Worker will automatically start when your system boots"
}

# --------------------------
# Save Configuration
# --------------------------
save_config() {
    section "Saving Configuration"
    
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "version": "2.0.0",
  "role": "contributor",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "containerName": "$CONTAINER_NAME",
  "dockerImage": "$DOCKER_IMAGE",
  "workerId": "$(cat $CONFIG_DIR/worker-id 2>/dev/null || echo "unknown")",
  "system": {
    "os": "$OS",
    "arch": "$ARCH",
    "cpuCores": $CPU_CORES,
    "cpuModel": "$(echo $CPU_MODEL | sed 's/"/\\"/g')",
    "ramTotal": $RAM_TOTAL,
    "storageTotal": $STORAGE_TOTAL,
    "gpuAvailable": $GPU_AVAILABLE,
    "gpuModel": "$(echo $GPU_MODEL | sed 's/"/\\"/g')",
    "gpuMemory": $GPU_MEMORY
  },
  "resourceLimits": {
    "cpuLimit": "$DOCKER_CPU_LIMIT",
    "memoryLimit": "${DOCKER_RAM_LIMIT}G"
  },
  "sharing": {
    "cpuPercent": 40,
    "ramPercent": 30,
    "gpuPercent": $GPU_SHARE_PERCENT,
    "storagePercent": 20
  },
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    chmod 600 "$CONFIG_DIR/config.json"
    log "Configuration saved to: $CONFIG_DIR/config.json"
}

# --------------------------
# Show Management Commands
# --------------------------
show_management_commands() {
    section "Management Commands"
    
    echo ""
    echo -e "${CYAN}Easy Management (Recommended):${NC}"
    echo "  $CONFIG_DIR/manage.sh {start|stop|restart|logs|status|uninstall}"
    echo ""
    echo "  Examples:"
    echo "    $CONFIG_DIR/manage.sh status        # Check worker status"
    echo "    $CONFIG_DIR/manage.sh logs          # View logs"
    echo "    $CONFIG_DIR/manage.sh restart       # Restart worker"
    echo ""
    echo -e "${CYAN}Direct Docker Commands:${NC}"
    echo "  View logs:       docker logs $CONTAINER_NAME"
    echo "  View live logs:  docker logs -f $CONTAINER_NAME"
    echo "  Stop worker:     docker stop $CONTAINER_NAME"
    echo "  Start worker:    docker start $CONTAINER_NAME"
    echo "  Restart worker:  docker restart $CONTAINER_NAME"
    echo ""
    echo -e "${CYAN}Status & Monitoring:${NC}"
    echo "  Container status: docker ps -f name=$CONTAINER_NAME"
    echo "  Resource usage:   docker stats $CONTAINER_NAME --no-stream"
    echo ""
}

# --------------------------
# Contributor Setup
# --------------------------
setup_contributor() {
    detect_system
    pull_docker_image
    stop_existing_container
    register_worker
    start_container
    verify_worker_connection
    setup_auto_start
    save_config
    create_management_script
    
    section "Installation Complete! 🎉"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     DistributeX Worker Successfully Installed!        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "Worker is running and contributing to the network"
    log "Auto-start on boot: Enabled"
    log "Container name: $CONTAINER_NAME"
    log "Config directory: $CONFIG_DIR"
    echo ""
    
    show_management_commands
}

# --------------------------
# Main Installation Flow
# --------------------------
main() {
    show_banner
    check_requirements
    authenticate_user
    select_user_role
    
    case "$USER_ROLE" in
        contributor)
            setup_contributor
            ;;
        developer)
            setup_developer
            ;;
        *)
            error "Invalid role selected"
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}Thank you for joining DistributeX! 🚀${NC}"
    echo ""
}

# --------------------------
# Create Management Script
# --------------------------
create_management_script() {
    cat > "$CONFIG_DIR/manage.sh" <<'MGMT_EOF'
#!/bin/bash
# DistributeX Worker Management Script

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
        echo ""
        echo "Commands:"
        echo "  start       - Start the worker container"
        echo "  stop        - Stop the worker container"
        echo "  restart     - Restart the worker container"
        echo "  logs        - View worker logs (use 'logs -f' for live)"
        echo "  status      - Show worker status and resource usage"
        echo "  uninstall   - Remove worker (use '--purge' to delete config)"
        exit 1
        ;;
esac
MGMT_EOF
    
    chmod +x "$CONFIG_DIR/manage.sh"
    log "Management script created: $CONFIG_DIR/manage.sh"
}

# Run main installation
main
