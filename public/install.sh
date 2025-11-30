#!/bin/bash
#
# DistributeX Complete Production Installer v3.5.0
# One command. Two modes. Infinite possibilities.
#
# Features:
# - Role selection (Contributor/Developer) with change support
# - Smart status detection based on heartbeat timing
# - Single worker per device (MAC-based identification)
# - Cross-platform authentication sync
# - Auto-restart on failure
# - Comprehensive system detection
#
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash
#

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"
VERSION="3.5.0"

# ============================================================================
# COLORS
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# ============================================================================
# BANNER
# ============================================================================
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
║                DistributeX Cloud Network                  ║
║             Distributed Computing Platform                ║
║                      Version 3.5.0                        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
}

# ============================================================================
# SYSTEM REQUIREMENTS CHECK
# ============================================================================
check_requirements() {
    section "Checking System Requirements"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Install from: https://docs.docker.com/get-docker/"
    fi
    
    if ! docker ps &> /dev/null; then
        error "Docker daemon is not running. Please start Docker and try again."
    fi
    
    log "Docker is running"
    log "Docker version: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
    
    # Check and install missing dependencies
    local missing=()
    for cmd in curl jq bc; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        warn "Installing missing dependencies: ${missing[*]}"
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq && sudo apt-apt install -y "${missing[@]}"
        elif command -v yum &> /dev/null; then
            sudo yum install -y "${missing[@]}"
        elif command -v brew &> /dev/null; then
            brew install "${missing[@]}"
        else
            error "Please install manually: ${missing[*]}"
        fi
    fi
    
    log "All requirements satisfied"
    echo ""
}

# ============================================================================
# MAC ADDRESS DETECTION
# ============================================================================
get_mac_address() {
    local mac=""
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')

    # Get raw MAC based on OS
    if [ "$os" = "linux" ]; then
        mac=$(ip link show 2>/dev/null | awk '/link\/ether/ {print $2; exit}')
    elif [ "$os" = "darwin" ]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2; exit}')
        [ -z "$mac" ] && mac=$(ifconfig en1 2>/dev/null | awk '/ether/ {print $2; exit}')
    fi

    # Normalize: remove colons/dashes, lowercase
    mac=$(echo "$mac" | tr -d ':-' | tr '[:upper:]' '[:lower:]')

    # Validate: must be 12 hex characters
    if [[ ! "$mac" =~ ^[0-9a-f]{1,12}$ ]]; then
        echo ""
        return
    fi

    # Pad to 12 characters (left-pad with zeros)
    printf "%012s\n" "$mac" | tr ' ' '0'
}

# ============================================================================
# SYSTEM DETECTION
# ============================================================================
detect_system() {
    section "Detecting System"

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name:" | sed 's/Model name:\s*//' || sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")
    HOSTNAME=$(hostname)

    # RAM Detection
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 4096)
    RAM_AVAILABLE=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo 2048)

    # Storage Detection (ALL drives)
    if command -v lsblk &> /dev/null; then
        STORAGE_TOTAL_BYTES=$(lsblk -b -d -o TYPE,SIZE 2>/dev/null | awk '$1=="disk"{sum+=$2}END{print sum}')
        STORAGE_TOTAL=$(( ${STORAGE_TOTAL_BYTES:-0} / 1024 / 1024 )) # Convert to MB
    else
        STORAGE_TOTAL=102400 # 100GB fallback
    fi
    
    STORAGE_AVAILABLE=$(df -m 2>/dev/null | awk 'NR>1{sum+=$4}END{print sum}' || echo 51200)
    STORAGE_TOTAL_GB=$((STORAGE_TOTAL / 1024))

    # MAC Address
    MAC_ADDRESS=$(get_mac_address)
    if [ -z "$MAC_ADDRESS" ]; then
        error "Could not detect MAC address. Please check network interfaces."
    fi

    # GPU Detection
    GPU_AVAILABLE="false"
    GPU_MODEL=""
    GPU_MEMORY=0
    GPU_COUNT=0
    GPU_DRIVER_VERSION=""
    GPU_CUDA_VERSION=""

    if command -v nvidia-smi &> /dev/null; then
        GPU_AVAILABLE="true"
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader -i 0 2>/dev/null | head -1 || echo "")
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader -i 0 2>/dev/null | sed 's/ MiB//' || echo 0)
        GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l | xargs || echo 0)
        GPU_DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader -i 0 2>/dev/null || echo "")
        
        if command -v nvcc &> /dev/null; then
            GPU_CUDA_VERSION=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $5}' | cut -d, -f1 || echo "")
        fi
    fi

    # Display Results
    log "System: $OS ($ARCH)"
    log "Hostname: $HOSTNAME"
    log "MAC Address: $MAC_ADDRESS"
    log "CPU: $CPU_CORES cores - $CPU_MODEL"
    log "RAM: ${RAM_TOTAL}MB total, ${RAM_AVAILABLE}MB available"
    log "Storage: ${STORAGE_TOTAL_GB}GB total"
    log "GPU Available: $GPU_AVAILABLE"
    
    if [ "$GPU_AVAILABLE" = "true" ]; then
        log "GPU Model: $GPU_MODEL"
        log "GPU Memory: ${GPU_MEMORY}MB"
        log "GPU Count: $GPU_COUNT"
        [ -n "$GPU_DRIVER_VERSION" ] && log "GPU Driver: $GPU_DRIVER_VERSION"
        [ -n "$GPU_CUDA_VERSION" ] && log "CUDA Version: $GPU_CUDA_VERSION"
    fi
    
    echo ""
}

# ============================================================================
# USER AUTHENTICATION
# ============================================================================
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
            echo ""
            return 0
        else
            warn "Existing token expired, please log in again"
            rm -f "$CONFIG_DIR/token"
        fi
    fi
    
    # Prompt for signup or login
    echo ""
    echo -e "${CYAN}Choose an option:${NC}"
    echo " 1) Sign up (New user)"
    echo " 2) Login (Existing user)"
    echo ""
    
    while true; do
        read -r -p "Enter choice [1-2]: " choice </dev/tty
        case "$choice" in
            1) signup_user; break ;;
            2) login_user; break ;;
            *) echo -e "${RED}Invalid choice. Please enter 1 or 2${NC}" ;;
        esac
    done
}

signup_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD} Create Your Account${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local first_name last_name email password password_confirm role
    
    read -r -p "First Name: " first_name </dev/tty
    read -r -p "Last Name: " last_name </dev/tty
    read -r -p "Email: " email </dev/tty
    
    # Password validation
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
    echo -e "${CYAN}Select Your Role:${NC}"
    echo " 1) ${GREEN}Contributor${NC} - Share my computer's resources (earn rewards)"
    echo " 2) ${BLUE}Developer${NC} - Use pooled computing resources (run tasks)"
    echo ""
    
    while true; do
        read -r -p "Enter choice [1-2]: " role_choice </dev/tty
        case "$role_choice" in
            1) role="contributor"; break ;;
            2) role="developer"; break ;;
            *) echo -e "${RED}Invalid choice. Please enter 1 or 2${NC}" ;;
        esac
    done
    
    echo ""
    info "Creating account..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\",\"role\":\"$role\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
        ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Unknown error")
        error "Signup failed ($HTTP_CODE): $ERROR_MSG"
    fi
    
    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token' 2>/dev/null)
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No authentication token returned"
    fi
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    
    USER_ROLE="$role"
    echo "$USER_ROLE" > "$CONFIG_DIR/role"
    
    log "Account created successfully as $role!"
    echo ""
    sleep 1
}

login_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD} Login to Your Account${NC}"
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
        ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Invalid credentials"' 2>/dev/null || echo "Invalid credentials")
        error "Login failed ($HTTP_CODE): $ERROR_MSG"
    fi
    
    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token' 2>/dev/null)
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No authentication token returned"
    fi
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    
    log "Logged in successfully!"
    echo ""
    sleep 1
}

# ============================================================================
# ROLE SELECTION / UPDATE
# ============================================================================
select_role() {
    section "Role Selection"
    
    # Check if user already has a role saved locally
    if [ -f "$CONFIG_DIR/role" ]; then
        CURRENT_ROLE=$(cat "$CONFIG_DIR/role")
        echo ""
        echo -e "${CYAN}Current Role: ${GREEN}${BOLD}$CURRENT_ROLE${NC}"
        echo ""
        echo "Would you like to change your role?"
        echo " 1) ${GREEN}Keep current role${NC} ($CURRENT_ROLE)"
        echo " 2) ${YELLOW}Change to Contributor${NC} (share resources)"
        echo " 3) ${BLUE}Change to Developer${NC} (use resources)"
        echo ""
        
        while true; do
            read -r -p "Enter choice [1-3]: " CHANGE_CHOICE </dev/tty
            case "$CHANGE_CHOICE" in
                1)
                    USER_ROLE="$CURRENT_ROLE"
                    log "Keeping role: $USER_ROLE"
                    echo ""
                    return 0
                    ;;
                2)
                    USER_ROLE="contributor"
                    break
                    ;;
                3)
                    USER_ROLE="developer"
                    break
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please enter 1-3${NC}"
                    ;;
            esac
        done
    else
        echo ""
        echo -e "${CYAN}${BOLD}Select Your Role:${NC}"
        echo ""
        echo " 1) ${GREEN}Contributor${NC} - Share my computer's resources"
        echo "    • Earn rewards by contributing CPU, RAM, GPU, Storage"
        echo "    • Your device runs in the background"
        echo "    • Help power the distributed network"
        echo ""
        echo " 2) ${BLUE}Developer${NC} - Use pooled computing resources"
        echo "    • Run your code on distributed workers"
        echo "    • Access global pool of CPU, RAM, GPU"
        echo "    • Scale your applications instantly"
        echo ""
        
        while true; do
            read -r -p "Enter choice [1-2]: " ROLE_CHOICE </dev/tty
            case "$ROLE_CHOICE" in
                1)
                    USER_ROLE="contributor"
                    break
                    ;;
                2)
                    USER_ROLE="developer"
                    break
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please enter 1 or 2${NC}"
                    ;;
            esac
        done
    fi
    
    # Update role in backend
    echo ""
    info "Updating role to: $USER_ROLE..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$DISTRIBUTEX_API_URL/api/auth/update-role" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"role\":\"$USER_ROLE\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" != "200" ]; then
        ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Failed to update role"' 2>/dev/null || echo "Failed to update role")
        warn "Role update failed: $ERROR_MSG"
        warn "Continuing with installation anyway..."
    else
        # Update local token if new one was provided
        NEW_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token // empty' 2>/dev/null)
        if [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "null" ]; then
            echo "$NEW_TOKEN" > "$CONFIG_DIR/token"
            API_TOKEN="$NEW_TOKEN"
        fi
        
        PREVIOUS_ROLE=$(echo "$HTTP_BODY" | jq -r '.previousRole // "none"' 2>/dev/null)
        if [ "$PREVIOUS_ROLE" != "null" ] && [ "$PREVIOUS_ROLE" != "$USER_ROLE" ]; then
            log "Role changed from $PREVIOUS_ROLE to $USER_ROLE"
        else
            log "Role set to: $USER_ROLE"
        fi
    fi
    
    # Save role locally
    echo "$USER_ROLE" > "$CONFIG_DIR/role"
    echo ""
}

# ============================================================================
# WORKER REGISTRATION (Contributors only)
# ============================================================================
check_existing_worker() {
    info "Checking if worker already registered..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$DISTRIBUTEX_API_URL/api/workers/check/$MAC_ADDRESS" \
        -H "Authorization: Bearer $API_TOKEN")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        WORKER_EXISTS=$(echo "$HTTP_BODY" | jq -r '.exists' 2>/dev/null || echo "false")
        if [ "$WORKER_EXISTS" = "true" ]; then
            WORKER_ID=$(echo "$HTTP_BODY" | jq -r '.workerId' 2>/dev/null || echo "")
            if [ -n "$WORKER_ID" ] && [ "$WORKER_ID" != "null" ]; then
                log "Worker already exists: $WORKER_ID"
                echo "$WORKER_ID" > "$CONFIG_DIR/worker_id"
                return 0
            fi
        fi
    fi
    
    return 1
}

register_worker() {
    section "Registering Worker"
    
    # Check if already exists
    if check_existing_worker; then
        warn "Worker already registered, skipping new registration"
        echo ""
        return 0
    fi
    
    info "Registering new worker..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
          \"macAddress\": \"$MAC_ADDRESS\",
          \"name\": \"Worker-$MAC_ADDRESS\",
          \"hostname\": \"$HOSTNAME\",
          \"platform\": \"$OS\",
          \"architecture\": \"$ARCH\",
          \"cpuCores\": $CPU_CORES,
          \"cpuModel\": \"$CPU_MODEL\",
          \"ramTotal\": $RAM_TOTAL,
          \"ramAvailable\": $RAM_AVAILABLE,
          \"gpuAvailable\": $GPU_AVAILABLE,
          \"gpuModel\": \"$GPU_MODEL\",
          \"gpuMemory\": $GPU_MEMORY,
          \"gpuCount\": $GPU_COUNT,
          \"gpuDriverVersion\": \"$GPU_DRIVER_VERSION\",
          \"gpuCudaVersion\": \"$GPU_CUDA_VERSION\",
          \"storageTotal\": $STORAGE_TOTAL,
          \"storageAvailable\": $STORAGE_AVAILABLE,
          \"cpuSharePercent\": 90,
          \"ramSharePercent\": 80,
          \"gpuSharePercent\": 70,
          \"storageSharePercent\": 50
        }")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        WORKER_ID=$(echo "$HTTP_BODY" | jq -r '.workerId' 2>/dev/null || echo "")
        if [ -z "$WORKER_ID" ] || [ "$WORKER_ID" = "null" ]; then
            error "Worker registration succeeded but no workerId returned"
        fi
        
        echo "$WORKER_ID" > "$CONFIG_DIR/worker_id"
        log "Worker successfully registered!"
        log "Worker ID: $WORKER_ID"
        log "Worker Name: Worker-$MAC_ADDRESS"
        log "Hostname: $HOSTNAME"
    else
        ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // .error // "Unknown error"' 2>/dev/null || echo "Unknown error")
        error "Worker registration failed (HTTP $HTTP_CODE): $ERROR_MSG"
    fi
    
    echo ""
}

# ============================================================================
# DOCKER OPERATIONS
# ============================================================================
pull_docker_image() {
    info "Pulling Docker image: $DOCKER_IMAGE..."
    
    if docker pull $DOCKER_IMAGE 2>&1 | grep -q "up to date\|Downloaded newer"; then
        log "Docker image ready"
    else
        error "Failed to pull Docker image"
    fi
}

stop_existing_container() {
    local containers
    containers=$(docker ps -a --format '{{.Names}}' | grep "^${CONTAINER_NAME}" || true)
    
    if [ -n "$containers" ]; then
        warn "Stopping existing worker containers..."
        for c in $containers; do
            docker stop "$c" >/dev/null 2>&1 || true
            docker rm "$c" >/dev/null 2>&1 || true
        done
        log "Old containers removed"
    fi
}

# ============================================================================
# START CONTRIBUTOR
# ============================================================================
start_contributor() {
    section "Starting Worker Container"
    
    pull_docker_image
    stop_existing_container
    register_worker
    
    info "Launching worker container (heartbeat mode)..."
    
    # Save MAC address for container
    echo "$MAC_ADDRESS" > "$CONFIG_DIR/mac_address"
    chmod 600 "$CONFIG_DIR/mac_address"
    
    # Start container with restart policy
    docker run -d \
        --name $CONTAINER_NAME \
        --restart unless-stopped \
        --shm-size=1g \
        -e DISTRIBUTEX_API_URL="$DISTRIBUTEX_API_URL" \
        -e DISABLE_SELF_REGISTER=true \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -v "$CONFIG_DIR:/config:ro" \
        $DOCKER_IMAGE \
        --api-key "$API_TOKEN" \
        --url "$DISTRIBUTEX_API_URL" > /dev/null

    sleep 5
    
    if docker ps | grep -q $CONTAINER_NAME; then
        log "Worker container running"
        log "Container: $CONTAINER_NAME"
        log "MAC Address: $MAC_ADDRESS"
        log "Status Detection: Real-time (heartbeat-based)"
        echo ""
        info "The worker will:"
        echo "  • Send heartbeat every 60 seconds"
        echo "  • Show as Online when last heartbeat < 1 minute"
        echo "  • Show as Idle when last heartbeat 1-5 minutes"
        echo "  • Show as Offline when last heartbeat > 5 minutes"
    else
        error "Failed to start worker container"
    fi
}

# ============================================================================
# SETUP DEVELOPER
# ============================================================================
setup_developer() {
    section "Setting Up Developer Environment"
    
    info "Configuring API access..."
    
    echo "$API_TOKEN" > "$CONFIG_DIR/api-key"
    chmod 600 "$CONFIG_DIR/api-key"
    
    log "Developer environment configured"
    log "API Key saved to: $CONFIG_DIR/api-key"
    echo ""
    
    echo -e "${CYAN}${BOLD}Usage Examples:${NC}"
    echo ""
    echo -e "${GREEN}Python:${NC}"
    echo "  pip install distributex-cloud"
    echo "  from distributex import DistributeX"
    echo "  dx = DistributeX(api_key='${API_TOKEN:0:20}...')"
    echo ""
    echo -e "${BLUE}JavaScript:${NC}"
    echo "  npm install distributex-cloud"
    echo "  const dx = new DistributeX('${API_TOKEN:0:20}...')"
    echo ""
    echo -e "${MAGENTA}Resources:${NC}"
    echo "  • API Docs: $DISTRIBUTEX_API_URL/docs"
    echo "  • Dashboard: $DISTRIBUTEX_API_URL/dashboard"
    echo "  • Examples: github.com/DistributeX-Cloud/examples"
    echo ""
}

# ============================================================================
# MANAGEMENT SCRIPT
# ============================================================================
create_management_script() {
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
        echo "Starting worker..."
        docker start $CONTAINER_NAME
        echo -e "${GREEN}Worker started${NC}"
        ;;
    
    stop)
        echo "Stopping worker..."
        docker stop $CONTAINER_NAME
        echo -e "${YELLOW}Worker stopped${NC}"
        ;;
    
    restart)
        echo "Restarting worker..."
        docker restart $CONTAINER_NAME
        echo -e "${GREEN}Worker restarted${NC}"
        ;;
    
    logs)
        docker logs ${2:--f} $CONTAINER_NAME
        ;;
    
    status)
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  Worker Status${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        docker ps -f name=$CONTAINER_NAME --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
        echo ""
        if [ -f "$CONFIG_DIR/config.json" ]; then
            echo -e "${CYAN}Worker Details:${NC}"
            if command -v jq &> /dev/null; then
                cat "$CONFIG_DIR/config.json" | jq -r '"  Worker Name: \(.workerName)\n  Worker ID: \(.workerId)\n  Hostname: \(.hostname)\n  MAC: \(.macAddress)\n  Role: \(.role)"' 2>/dev/null || {
                    echo "  (Config file exists but could not parse)"
                }
            else
                grep -E "workerName|workerId|hostname|macAddress|role" "$CONFIG_DIR/config.json" | sed 's/^/  /'
            fi
        fi
        echo ""
        echo -e "${CYAN}Status Detection:${NC}"
        echo "  Online  = Last heartbeat < 1 minute ago"
        echo "  Idle    = Last heartbeat 1-5 minutes ago"
        echo "  Offline = Last heartbeat > 5 minutes ago"
        ;;
    
    uninstall)
        echo "Uninstalling DistributeX..."
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
        
        if [ "$2" = "--purge" ]; then
            rm -rf "$CONFIG_DIR"
            echo -e "${YELLOW}All data removed${NC}"
        else
            echo -e "${YELLOW}Worker removed (config preserved)${NC}"
            echo "To remove all data: $0 uninstall --purge"
        fi
        echo "Done!"
        ;;
    
    *)
        echo "DistributeX Worker Management"
        echo ""
        echo "Usage: $0 {command}"
        echo ""
        echo "Commands:"
        echo "  start       Start the worker"
        echo "  stop        Stop the worker"
        echo "  restart     Restart the worker"
        echo "  logs        View worker logs (add -f for follow)"
        echo "  status      Show worker status"
        echo "  uninstall   Remove worker (--purge to remove all data)"
        echo ""
        exit 1
        ;;
esac
MGMT_EOF
    
    chmod +x "$CONFIG_DIR/manage.sh"
    log "Management script created at: $CONFIG_DIR/manage.sh"
}

# ============================================================================
# SAVE CONFIGURATION
# ============================================================================
save_config() {
    section "Saving Configuration"
    
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "version": "$VERSION",
  "role": "$USER_ROLE",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "macAddress": "$MAC_ADDRESS",
  "hostname": "$HOSTNAME",
  "workerId": "$(cat $CONFIG_DIR/worker_id 2>/dev/null || echo '')",
  "workerName": "Worker-$MAC_ADDRESS",
  "system": {
    "os": "$OS",
    "arch": "$ARCH",
    "cpuCores": $CPU_CORES,
    "cpuModel": "$CPU_MODEL",
    "ramTotal": $RAM_TOTAL,
    "storageTotal": $STORAGE_TOTAL,
    "gpuAvailable": $GPU_AVAILABLE,
    "gpuModel": "$GPU_MODEL",
    "gpuMemory": $GPU_MEMORY,
    "gpuCount": $GPU_COUNT
  },
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    chmod 600 "$CONFIG_DIR/config.json"
    log "Configuration saved to: $CONFIG_DIR/config.json"
    echo ""
}

# ============================================================================
# COMPLETION MESSAGE
# ============================================================================
show_completion() {
    section "Installation Complete! 🎉"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     DistributeX Successfully Installed! v$VERSION     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Installation Mode: $USER_ROLE"
    
    if [ "$USER_ROLE" = "contributor" ]; then
        echo ""
        echo -e "${CYAN}${BOLD}Contributor Details:${NC}"
        log "Worker Name: Worker-$MAC_ADDRESS"
        log "Hostname: $HOSTNAME"
        log "MAC Address: $MAC_ADDRESS"
        [ -f "$CONFIG_DIR/worker_id" ] && log "Worker ID: $(cat $CONFIG_DIR/worker_id)"
        
        echo ""
        echo -e "${CYAN}${BOLD}Management Commands:${NC}"
        echo "  $CONFIG_DIR/manage.sh status    # Check worker status"
        echo "  $CONFIG_DIR/manage.sh logs      # View real-time logs"
        echo "  $CONFIG_DIR/manage.sh restart   # Restart the worker"
        echo "  $CONFIG_DIR/manage.sh stop      # Stop temporarily"
        echo "  $CONFIG_DIR/manage.sh uninstall # Remove worker"
        
        echo ""
        echo -e "${CYAN}${BOLD}Worker Features:${NC}"
        echo "  ✓ Automatic heartbeat every 60 seconds"
        echo "  ✓ Smart status detection:"
        echo "    • ${GREEN}Online${NC}  = Last heartbeat < 1 minute"
        echo "    • ${YELLOW}Idle${NC}    = Last heartbeat 1-5 minutes"
        echo "    • ${RED}Offline${NC} = Last heartbeat > 5 minutes"
        echo "  ✓ Auto-restart on failure"
        echo "  ✓ Survives system reboots"
        
        echo ""
        echo -e "${CYAN}${BOLD}Resource Sharing:${NC}"
        echo "  • CPU: 90% of $CPU_CORES cores"
        echo "  • RAM: 80% of ${RAM_TOTAL}MB"
        [ "$GPU_AVAILABLE" = "true" ] && echo "  • GPU: 70% of $GPU_COUNT GPU(s)"
        echo "  • Storage: 50% of ${STORAGE_TOTAL_GB}GB"
        
    else
        echo ""
        echo -e "${CYAN}${BOLD}Developer Access:${NC}"
        log "API Key: ${API_TOKEN:0:30}..."
        log "Config Location: $CONFIG_DIR/api-key"
        
        echo ""
        echo -e "${CYAN}${BOLD}Quick Start:${NC}"
        echo ""
        echo -e "${GREEN}Python:${NC}"
        echo "  pip install distributex-cloud"
        echo "  from distributex import DistributeX"
        echo "  dx = DistributeX(api_key='$API_TOKEN')"
        echo "  result = dx.run(my_function, args=(data,))"
        
        echo ""
        echo -e "${BLUE}JavaScript:${NC}"
        echo "  npm install distributex-cloud"
        echo "  const dx = new DistributeX('$API_TOKEN');"
        echo "  const result = await dx.run(myFunction);"
        
        echo ""
        echo -e "${CYAN}${BOLD}Resources:${NC}"
        echo "  • API Documentation: $DISTRIBUTEX_API_URL/docs"
        echo "  • Developer Dashboard: $DISTRIBUTEX_API_URL/dashboard"
        echo "  • Code Examples: github.com/DistributeX-Cloud/examples"
    fi
    
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}💡 Tip: Change your role anytime by running this installer again${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}${BOLD}Thank you for joining DistributeX! 🚀${NC}"
    echo ""
    echo ""
}

# ============================================================================
# MAIN INSTALLATION FLOW
# ============================================================================
main() {
    show_banner
    check_requirements
    authenticate_user
    select_role
    detect_system
    
    if [ "$USER_ROLE" = "contributor" ]; then
        start_contributor
        create_management_script
    else
        setup_developer
    fi
    
    save_config
    show_completion
}

# ============================================================================
# ERROR HANDLER
# ============================================================================
trap 'echo -e "\n${RED}Installation failed. Check the error above.${NC}\nFor help: support@distributex.io" >&2' ERR

# ============================================================================
# RUN
# ============================================================================
main "$@"
