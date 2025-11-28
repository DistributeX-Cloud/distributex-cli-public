#!/bin/bash
#
# DistributeX Complete Installer - Production Ready (Fixed Prompts)
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash
#

set -e

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

# Logging Functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"; }

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

# Get MAC Address
get_mac_address() {
    local mac=""
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$os" = "linux" ]; then
        mac=$(ip link show | awk '/link\/ether/ {print $2; exit}')
    elif [ "$os" = "darwin" ]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2; exit}')
        [ -z "$mac" ] && mac=$(ifconfig en1 2>/dev/null | awk '/ether/ {print $2; exit}')
    fi
    
    if [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        echo "$mac"
    else
        echo ""
    fi
}

# Generate Device ID from MAC
generate_device_id() {
    local mac=$(get_mac_address)
    
    if [ -z "$mac" ]; then
        # Fallback for VMs/Cloud instances without MAC
        warn "MAC address not detected, using fallback identifier"
        echo "$(hostname)-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo $(date +%s))" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "fallback-$(date +%s)"
    else
        echo "$mac" | tr '[:upper:]' '[:lower:]' | tr -d ':'
    fi
}

# Check System Requirements
check_requirements() {
    section "Checking System Requirements"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Install from: https://docs.docker.com/get-docker/"
    fi
    
    # Check if Docker daemon is running
    if ! docker ps &> /dev/null; then
        warn "Docker daemon is not running. Attempting to start..."
        
        # Try to start Docker
        if command -v systemctl &> /dev/null; then
            sudo systemctl start docker || error "Failed to start Docker. Please start it manually."
            sleep 3
        else
            error "Docker daemon is not running. Please start Docker and try again."
        fi
        
        # Verify Docker is now running
        if ! docker ps &> /dev/null; then
            error "Docker is still not running after start attempt."
        fi
    fi
    
    # Check required commands
    local missing=()
    for cmd in curl jq bc; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required commands: ${missing[*]}. Install them first."
    fi
    
    log "All requirements satisfied"
    log "Docker version: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
}

# User Authentication
authenticate_user() {
    section "User Authentication"
    mkdir -p "$CONFIG_DIR"

    # Check for existing token
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
    echo -ne "${BOLD}Enter your choice [1 or 2]: ${NC}"
    
    while true; do
        read -r choice < /dev/tty
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
                echo -e "${RED}Invalid choice. Please enter 1 or 2: ${NC}"
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
    
    echo -ne "${BOLD}First Name: ${NC}"
    read -r first_name < /dev/tty
    
    echo -ne "${BOLD}Last Name: ${NC}"
    read -r last_name < /dev/tty
    
    echo -ne "${BOLD}Email: ${NC}"
    read -r email < /dev/tty
    
    while true; do
        echo -ne "${BOLD}Password (min 8 chars): ${NC}"
        read -s -r password < /dev/tty
        echo ""
        
        if [ ${#password} -lt 8 ]; then
            warn "Password must be at least 8 characters"
            continue
        fi
        
        echo -ne "${BOLD}Confirm Password: ${NC}"
        echo -ne "${BOLD}Confirm Password: ${NC}"
        read -s -r password_confirm < /dev/tty
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
    sleep 1
}

login_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}     Login to Your Account${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local email password
    
    echo -ne "${BOLD}Email: ${NC}"
    read -r email < /dev/tty
    
    echo -ne "${BOLD}Password: ${NC}"
    read -s -r password < /dev/tty
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
    sleep 1
}

# Detect GPU
detect_gpu() {
    local gpu_available=false
    local gpu_model=""
    local gpu_memory=0
    local gpu_count=0
    local gpu_driver=""
    local gpu_cuda=""
    
    # Check for NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            gpu_available=true
            gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n1)
            gpu_model=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
            gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
            gpu_driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
            
            # Get CUDA version if available
            if command -v nvcc &> /dev/null; then
                gpu_cuda=$(nvcc --version | grep "release" | awk '{print $5}' | cut -d',' -f1)
            else
                # Try to get CUDA version from nvidia-smi
                gpu_cuda=$(nvidia-smi | grep "CUDA Version" | awk '{print $9}')
            fi
        fi
    fi
    
    # Check for AMD GPU (ROCm)
    if [ "$gpu_available" = false ] && command -v rocm-smi &> /dev/null; then
        if rocm-smi &> /dev/null; then
            gpu_available=true
            gpu_model=$(rocm-smi --showproductname | grep "Card series" | awk -F': ' '{print $2}')
            gpu_count=1
            gpu_driver=$(rocm-smi --showdriverversion | grep "Driver version" | awk '{print $3}')
        fi
    fi
    
    # Export results
    GPU_AVAILABLE="$gpu_available"
    GPU_MODEL="$gpu_model"
    GPU_MEMORY="$gpu_memory"
    GPU_COUNT="$gpu_count"
    GPU_DRIVER="$gpu_driver"
    GPU_CUDA="$gpu_cuda"
}

# Detect System Capabilities
detect_system() {
    section "System Detection"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    HOSTNAME=$(hostname)
    
    # CPU Detection
    if [ "$OS" = "linux" ]; then
        CPU_CORES=$(nproc 2>/dev/null || echo 4)
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    elif [ "$OS" = "darwin" ]; then
        CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")
    else
        CPU_CORES=4
        CPU_MODEL="Unknown CPU"
    fi
    
    # RAM Detection
    if command -v free &> /dev/null; then
        RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
        RAM_AVAILABLE=$(free -m | awk '/^Mem:/{print $7}')
    else
        RAM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 8192)
        RAM_AVAILABLE=$((RAM_TOTAL * 80 / 100))
    fi
    
    # Storage Detection
    STORAGE_TOTAL=$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo 100)
    STORAGE_AVAILABLE=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo 80)
    
    # GPU Detection
    detect_gpu
    
    # Device ID (MAC-based with fallback)
    DEVICE_ID=$(generate_device_id)
    MAC_ADDRESS=$(get_mac_address)
    
    # Calculate sharing percentages (intelligent defaults)
    if [ "$CPU_CORES" -ge 8 ]; then
        CPU_SHARE=40
    elif [ "$CPU_CORES" -ge 4 ]; then
        CPU_SHARE=30
    else
        CPU_SHARE=25
    fi
    
    RAM_SHARE=30
    STORAGE_SHARE=20
    
    if [ "$GPU_AVAILABLE" = true ]; then
        GPU_SHARE=50
    else
        GPU_SHARE=0
    fi
    
    # Display detected capabilities
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

# Register Worker with API
register_worker() {
    section "Registering Worker"
    
    info "Registering device with network..."
    
    # Escape JSON strings to prevent invalid JSON
    escape_json() {
        local str="$1"
        # Escape backslashes, quotes, newlines, tabs
        echo "$str" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ' | tr '\t' ' '
    }
    
    # Build safe JSON payload with proper escaping
    SAFE_HOSTNAME=$(escape_json "$HOSTNAME")
    SAFE_CPU_MODEL=$(escape_json "$CPU_MODEL")
    SAFE_GPU_MODEL=$(escape_json "$GPU_MODEL")
    SAFE_GPU_DRIVER=$(escape_json "$GPU_DRIVER")
    SAFE_GPU_CUDA=$(escape_json "$GPU_CUDA")
    
    # CRITICAL: Ensure MAC address is included
    if [ -z "$MAC_ADDRESS" ]; then
        error "MAC address detection failed - cannot register worker"
    fi
    
    # Build JSON using jq to ensure validity
    local payload=$(jq -n \
        --arg name "${HOSTNAME}-worker" \
        --arg hostname "$SAFE_HOSTNAME" \
        --arg platform "$OS" \
        --arg arch "$ARCH" \
        --arg mac "$MAC_ADDRESS" \
        --arg cpuModel "$SAFE_CPU_MODEL" \
        --argjson cpuCores "$CPU_CORES" \
        --argjson ramTotal "$RAM_TOTAL" \
        --argjson ramAvailable "$RAM_AVAILABLE" \
        --argjson storageTotal "$STORAGE_TOTAL" \
        --argjson storageAvailable "$STORAGE_AVAILABLE" \
        --argjson cpuSharePercent "$CPU_SHARE" \
        --argjson ramSharePercent "$RAM_SHARE" \
        --argjson storageSharePercent "$STORAGE_SHARE" \
        '{
            name: $name,
            hostname: $hostname,
            platform: $platform,
            architecture: $arch,
            macAddress: $mac,
            cpuCores: $cpuCores,
            cpuModel: $cpuModel,
            ramTotal: $ramTotal,
            ramAvailable: $ramAvailable,
            storageTotal: $storageTotal,
            storageAvailable: $storageAvailable,
            cpuSharePercent: $cpuSharePercent,
            ramSharePercent: $ramSharePercent,
            storageSharePercent: $storageSharePercent
        }' | \
        # Add GPU fields conditionally
        if [ "$GPU_AVAILABLE" = true ]; then
            jq --arg gpuModel "$SAFE_GPU_MODEL" \
               --argjson gpuMemory "${GPU_MEMORY:-0}" \
               --argjson gpuCount "${GPU_COUNT:-0}" \
               --arg gpuDriver "$SAFE_GPU_DRIVER" \
               --arg gpuCuda "$SAFE_GPU_CUDA" \
               --argjson gpuSharePercent "$GPU_SHARE" \
               '. + {
                   gpuAvailable: true,
                   gpuModel: $gpuModel,
                   gpuMemory: $gpuMemory,
                   gpuCount: $gpuCount,
                   gpuDriverVersion: $gpuDriver,
                   gpuCudaVersion: $gpuCuda,
                   gpuSharePercent: $gpuSharePercent
               }'
        else
            jq '. + { gpuAvailable: false, gpuSharePercent: 0 }'
        fi
    )

    # Debug output (can be removed in production)
    echo "DEBUG: Registration payload:"
    echo "$payload" | jq '.'

    # Make API request with proper error handling
    echo ""
    info "Sending registration request..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1)

    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)

    # Debug output
    echo "DEBUG: HTTP Code: $HTTP_CODE"
    echo "DEBUG: Response Body: $HTTP_BODY"

    # Check for errors
    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
        error "Worker registration failed (HTTP $HTTP_CODE)
        
Response: $HTTP_BODY

Possible causes:
1. MAC address not detected (MAC: ${MAC_ADDRESS:-NOT DETECTED})
2. Invalid JSON payload
3. API authentication issue
4. Network connectivity problem

Please check the debug output above and report this issue."
    fi

    # Parse worker ID
    WORKER_ID=$(echo "$HTTP_BODY" | jq -r '.id')
    IS_NEW=$(echo "$HTTP_BODY" | jq -r '.isNew // true')

    if [ -z "$WORKER_ID" ] || [ "$WORKER_ID" = "null" ]; then
        error "Worker registration succeeded but no ID was returned

Response: $HTTP_BODY"
    fi

    # Save worker ID
    echo "$WORKER_ID" > "$CONFIG_DIR/worker-id"
    chmod 600 "$CONFIG_DIR/worker-id"

    # Success message
    if [ "$IS_NEW" = "true" ]; then
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
    
    if docker pull $DOCKER_IMAGE; then
        log "Docker image ready: $DOCKER_IMAGE"
    else
        error "Failed to pull Docker image"
    fi
}

# Stop Existing Container
stop_existing_container() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
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
    
    WORKER_ID=$(cat "$CONFIG_DIR/worker-id")
    
    # Build docker run command
    local docker_cmd="docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        -e DISTRIBUTEX_API_URL=\"$DISTRIBUTEX_API_URL\" \
        -e API_TOKEN=\"$API_TOKEN\" \
        -e WORKER_ID=\"$WORKER_ID\" \
        -e MAC_ADDRESS=\"$MAC_ADDRESS\" \
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
    eval $docker_cmd || error "Failed to start container"
    
    sleep 3
    
    # Verify container is running
    if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "Worker container started successfully"
        echo ""
        info "Container configured with:"
        echo "  ✓ Always-on restart policy (survives reboots)"
        echo "  ✓ Auto-restart on failure"
        echo "  ✓ Background daemon mode"
        [ "$GPU_AVAILABLE" = true ] && echo "  ✓ GPU access enabled"
    else
        error "Container failed to start"
    fi
}

# Setup systemd service for auto-start (Linux only)
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
        echo "  logs       - View worker logs (add -f to follow)"
        echo "  status     - Show worker status"
        echo "  stats      - Show resource usage"
        echo "  uninstall  - Remove worker (add --purge to delete config)"
        exit 1
        ;;
esac
MGMT_EOF
    
    chmod +x "$CONFIG_DIR/manage.sh"
    log "Management script created: $CONFIG_DIR/manage.sh"
}

# Save Configuration
save_config() {
    section "Saving Configuration"
    
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "version": "1.0.0",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "deviceId": "$DEVICE_ID",
  "macAddress": $([ -n "$MAC_ADDRESS" ] && echo "\"$MAC_ADDRESS\"" || echo "null"),
  "workerId": "$WORKER_ID",
  "hostname": "$HOSTNAME",
  "system": {
    "os": "$OS",
    "arch": "$ARCH",
    "cpuCores": $CPU_CORES,
    "cpuModel": "$CPU_MODEL",
    "ramTotal": $RAM_TOTAL,
    "storageTotal": $STORAGE_TOTAL,
    "gpuAvailable": $GPU_AVAILABLE,
    "gpuModel": $([ -n "$GPU_MODEL" ] && echo "\"$GPU_MODEL\"" || echo "null"),
    "gpuCount": $GPU_COUNT
  },
  "sharing": {
    "cpuPercent": $CPU_SHARE,
    "ramPercent": $RAM_SHARE,
    "storagePercent": $STORAGE_SHARE,
    "gpuPercent": $GPU_SHARE
  },
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    chmod 600 "$CONFIG_DIR/config.json"
    log "Configuration saved"
}

# Show Completion Summary
show_completion() {
    section "Installation Complete! 🎉"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     DistributeX Successfully Installed!               ║${NC}"
    echo -e "${GREEN}║     Worker Status: ONLINE                             ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Device ID: $DEVICE_ID"
    log "Worker ID: $WORKER_ID"
    log "Restart Policy: ALWAYS (survives reboots)"
    
    if [ "$GPU_AVAILABLE" = true ]; then
        log "GPU Support: ENABLED ($GPU_MODEL)"
    fi
    
    echo ""
    echo -e "${CYAN}Management Commands:${NC}"
    echo "  $CONFIG_DIR/manage.sh status   # Check worker status"
    echo "  $CONFIG_DIR/manage.sh logs     # View worker logs"
    echo "  $CONFIG_DIR/manage.sh stats    # Resource usage"
    echo "  $CONFIG_DIR/manage.sh restart  # Restart worker"
    echo "  $CONFIG_DIR/manage.sh stop     # Stop worker"
    echo ""
    echo -e "${CYAN}View Dashboard:${NC}"
    echo "  $DISTRIBUTEX_API_URL/dashboard"
    echo ""
    echo -e "${CYAN}Worker Features:${NC}"
    echo "  ✓ Auto-starts on system boot"
    echo "  ✓ Auto-restarts on failure"
    echo "  ✓ Runs 24/7 in background"
    echo "  ✓ Zero impact on performance"
    [ "$GPU_AVAILABLE" = true ] && echo "  ✓ GPU-accelerated tasks ready"
    echo ""
    echo -e "${GREEN}Thank you for joining DistributeX! 🚀${NC}"
    echo ""
    
    # Show live status
    info "Checking worker status..."
    sleep 2
    docker ps -f name=$CONTAINER_NAME --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

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
    save_config
    show_completion
}

# Run installer
main "$@"
