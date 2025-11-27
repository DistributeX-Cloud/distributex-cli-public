#!/bin/bash
#
# DistributeX Complete Installer - FIXED VERSION
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
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

# Get MAC Address (Primary network interface)
get_mac_address() {
    local mac=""
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$os" = "linux" ]; then
        # Get MAC from primary interface
        mac=$(ip link show | awk '/link\/ether/ {print $2; exit}')
    elif [ "$os" = "darwin" ]; then
        # macOS
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2; exit}')
        if [ -z "$mac" ]; then
            mac=$(ifconfig en1 2>/dev/null | awk '/ether/ {print $2; exit}')
        fi
    fi
    
    # Fallback to reading from sysfs on Linux
    if [ -z "$mac" ] && [ "$os" = "linux" ]; then
        for iface in /sys/class/net/*; do
            if [ -f "$iface/address" ] && [ "$(basename $iface)" != "lo" ]; then
                mac=$(cat "$iface/address")
                break
            fi
        done
    fi
    
    # Validate MAC address format
    if [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        echo "$mac"
    else
        echo ""
    fi
}

# Generate Device ID from MAC address
generate_device_id() {
    local mac=$(get_mac_address)
    
    if [ -z "$mac" ]; then
        error "Could not detect MAC address. This is required for device identification."
    fi
    
    # Use MAC address as the device ID (normalized)
    echo "$mac" | tr '[:upper:]' '[:lower:]' | tr -d ':'
}

# Check Requirements
check_requirements() {
    section "Checking System Requirements"
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Install from: https://docs.docker.com/get-docker/"
    fi
    
    if ! docker ps &> /dev/null; then
        error "Docker daemon is not running. Please start Docker and try again."
    fi
    
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

# User Authentication
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
    sleep 1
}

# Select User Role
select_role() {
    section "Select Your Role"
    
    echo ""
    echo -e "${CYAN}How do you want to use DistributeX?${NC}"
    echo ""
    echo "  1) ${GREEN}Contributor${NC} - Share my computer's resources"
    echo "     • Earn by contributing CPU, RAM, GPU, Storage"
    echo "     • Lightweight agent runs in background"
    echo "     • Zero impact on your daily use"
    echo ""
    echo "  2) ${BLUE}Developer${NC} - Use pooled computing resources"
    echo "     • Run scripts and code on distributed network"
    echo "     • Access global pool of CPU/GPU/Storage"
    echo "     • Pay-as-you-go or free tier available"
    echo ""
    
    while true; do
        read -r -p "Enter choice [1-2]: " ROLE_CHOICE </dev/tty
        case "$ROLE_CHOICE" in
            1)
                USER_ROLE="contributor"
                echo "$USER_ROLE" > "$CONFIG_DIR/role"
                log "Role set to: Contributor"
                break
                ;;
            2)
                USER_ROLE="developer"
                echo "$USER_ROLE" > "$CONFIG_DIR/role"
                log "Role set to: Developer"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1 or 2${NC}"
                ;;
        esac
    done
    echo ""
}

# GPU Detection
detect_gpu() {
    GPU_AVAILABLE=false
    GPU_MODEL="null"
    GPU_MEMORY="null"
    GPU_COUNT=0
    GPU_DRIVER_VERSION="null"
    GPU_CUDA_VERSION="null"
    
    if command -v nvidia-smi &> /dev/null; then
        info "Detecting NVIDIA GPU..."
        GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null | head -1)
        if [ ! -z "$GPU_INFO" ]; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(echo "$GPU_INFO" | cut -d',' -f1 | xargs)
            GPU_MEMORY=$(echo "$GPU_INFO" | cut -d',' -f2 | grep -oE '[0-9]+')
            GPU_DRIVER_VERSION=$(echo "$GPU_INFO" | cut -d',' -f3 | xargs)
            GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -1)
            
            if command -v nvcc &> /dev/null; then
                GPU_CUDA_VERSION=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9.]+' | head -1)
            fi
            
            log "NVIDIA GPU detected: $GPU_MODEL (${GPU_MEMORY}MB)"
        fi
    fi
    
    if [ "$GPU_AVAILABLE" = false ]; then
        info "No GPU detected"
    fi
}

# System Detection
detect_system() {
    section "System Detection"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    
    if [ "$OS" = "linux" ]; then
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    elif [ "$OS" = "darwin" ]; then
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")
    else
        CPU_MODEL="Unknown CPU"
    fi
    
    if command -v free &> /dev/null; then
        RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    else
        RAM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 8192)
    fi
    
    STORAGE_TOTAL=$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo 100)
    
    detect_gpu
    
    # Generate device ID from MAC address
    DEVICE_ID=$(generate_device_id)
    
    log "System: $OS ($ARCH)"
    log "Device ID (MAC): $DEVICE_ID"
    log "CPU: $CPU_CORES cores - $CPU_MODEL"
    log "RAM: ${RAM_TOTAL}MB"
    log "Storage: ${STORAGE_TOTAL}GB"
    if [ "$GPU_AVAILABLE" = true ]; then
        log "GPU: $GPU_MODEL"
    fi
}

# Register Worker (Contributor Only)
register_worker() {
    section "Registering Worker Device"

    info "Registering device with MAC-based ID: $DEVICE_ID"

    GPU_JSON=""
    if [ "$GPU_AVAILABLE" = true ]; then
        GPU_JSON="\"gpuAvailable\": true,
        \"gpuModel\": \"$GPU_MODEL\",
        \"gpuMemory\": ${GPU_MEMORY:-0},
        \"gpuCount\": ${GPU_COUNT:-1},
        \"gpuDriverVersion\": \"$GPU_DRIVER_VERSION\",
        \"gpuCudaVersion\": \"$GPU_CUDA_VERSION\","
    else
        GPU_JSON="\"gpuAvailable\": false,
        \"gpuCount\": 0,"
    fi

    CPU_SHARE_PERCENT=$([ $CPU_CORES -ge 8 ] && echo 50 || echo 40)
    RAM_SHARE_PERCENT=$([ $RAM_TOTAL -ge 16384 ] && echo 30 || echo 25)
    STORAGE_SHARE_PERCENT=20
    GPU_SHARE_PERCENT=50

    REGISTER_DATA=$(cat <<EOF
{
  "name": "$(hostname)",
  "hostname": "$(hostname)",
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
  "gpuSharePercent": $GPU_SHARE_PERCENT,
  "storageSharePercent": $STORAGE_SHARE_PERCENT,
  "macAddress": "$(get_mac_address)"
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
        fi
        
        echo "$WORKER_ID" > "$CONFIG_DIR/worker-id"
    else
        error "Failed to register worker ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message // "Unknown error"')"
    fi
}

# Start Contributor Container
start_contributor() {
    section "Starting Contributor Worker"
    
    pull_docker_image
    stop_existing_container
    register_worker
    
    info "Starting worker container..."
    
    docker run -d \
        --name $CONTAINER_NAME \
        --restart unless-stopped \
        -e DISTRIBUTEX_API_URL="$DISTRIBUTEX_API_URL" \
        -v "$CONFIG_DIR:/config:ro" \
        $DOCKER_IMAGE \
        --api-key "$API_TOKEN" \
        --url "$DISTRIBUTEX_API_URL"
    
    sleep 2
    
    if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "Worker container started successfully"
    else
        error "Container failed to start"
    fi
}

# Setup Developer Environment
setup_developer() {
    section "Setting Up Developer Environment"
    
    info "Installing DistributeX CLI..."
    
    # Save API key
    echo "$API_TOKEN" > "$CONFIG_DIR/api-key"
    chmod 600 "$CONFIG_DIR/api-key"
    
    # Create CLI wrapper
    cat > "$CONFIG_DIR/distributex-cli" << 'EOF'
#!/bin/bash
# DistributeX CLI Wrapper
API_KEY=$(cat ~/.distributex/api-key)
export DISTRIBUTEX_API_KEY="$API_KEY"
# Add CLI commands here
echo "DistributeX Developer CLI"
echo "API Key configured: ${API_KEY:0:10}..."
EOF
    
    chmod +x "$CONFIG_DIR/distributex-cli"
    
    log "Developer environment configured"
    log "API Key saved to: $CONFIG_DIR/api-key"
    echo ""
    echo -e "${CYAN}Usage Examples:${NC}"
    echo "  • API Documentation: $DISTRIBUTEX_API_URL/docs"
    echo "  • Your API Key: ${API_TOKEN:0:20}..."
    echo ""
}

# Pull Docker Image
pull_docker_image() {
    info "Pulling Docker image..."
    docker pull $DOCKER_IMAGE || error "Failed to pull Docker image"
    log "Docker image ready"
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

# Save Configuration
save_config() {
    section "Saving Configuration"
    
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "version": "3.0.0",
  "role": "$USER_ROLE",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "deviceId": "$DEVICE_ID",
  "macAddress": "$(get_mac_address)",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    chmod 600 "$CONFIG_DIR/config.json"
    log "Configuration saved"
}

# Create Management Script
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
        ;;
    uninstall)
        echo "Uninstalling..."
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
        if [ "$2" = "--purge" ]; then
            rm -rf "$CONFIG_DIR"
        fi
        echo "Done!"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status|uninstall}"
        exit 1
        ;;
esac
MGMT_EOF
    
    chmod +x "$CONFIG_DIR/manage.sh"
    log "Management script created"
}

# Show Completion
show_completion() {
    section "Installation Complete! 🎉"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     DistributeX Successfully Installed!               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ "$USER_ROLE" = "contributor" ]; then
        log "Role: Contributor (Resource Sharing)"
        log "Worker ID: $(cat $CONFIG_DIR/worker-id 2>/dev/null || echo 'N/A')"
        log "Device ID: $DEVICE_ID"
        echo ""
        echo -e "${CYAN}Management Commands:${NC}"
        echo "  $CONFIG_DIR/manage.sh status"
        echo "  $CONFIG_DIR/manage.sh logs"
        echo "  $CONFIG_DIR/manage.sh restart"
    else
        log "Role: Developer (Resource Consumer)"
        log "API Key: ${API_TOKEN:0:20}..."
        echo ""
        echo -e "${CYAN}Next Steps:${NC}"
        echo "  • View API Documentation: $DISTRIBUTEX_API_URL/docs"
        echo "  • Your API Key is saved in: $CONFIG_DIR/api-key"
    fi
    
    echo ""
    echo -e "${GREEN}Thank you for joining DistributeX! 🚀${NC}"
    echo ""
}

# Main Installation Flow
main() {
    show_banner
    check_requirements
    authenticate_user
    select_role
    detect_system
    
    if [ "$USER_ROLE" = "contributor" ]; then
        start_contributor
    else
        setup_developer
    fi
    
    save_config
    
    if [ "$USER_ROLE" = "contributor" ]; then
        create_management_script
    fi
    
    show_completion
}

# Run
main
