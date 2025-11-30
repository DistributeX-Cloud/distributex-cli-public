#!/bin/bash
################################################################################
# DistributeX Cloud Network - Complete Installation Script v4.0
################################################################################
# Features:
# - Full authentication & account management
# - Automatic system detection (CPU, RAM, GPU, Storage)
# - Multi-language runtime detection (Python, Node, Java, Go, Rust, Ruby, PHP, Docker)
# - Docker-based worker deployment
# - Role selection (Contributor/Developer)
# - Worker registration with API
# - Auto-start on boot (systemd/launchd)
# - Resource sharing configuration
# - Management tools
################################################################################

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}═══ $1 ═══${NC}\n"; }

# ============================================================================
# BANNER
# ============================================================================
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     ██████╗ ██╗███████╗████████╗██████╗ ██╗██████╗ ██╗   ██╗ ║
║     ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║██╔══██╗██║   ██║ ║
║     ██║  ██║██║███████╗   ██║   ██████╔╝██║██████╔╝██║   ██║ ║
║     ██║  ██║██║╚════██║   ██║   ██╔══██╗██║██╔══██╗██║   ██║ ║
║     ██████╔╝██║███████║   ██║   ██║  ██║██║██████╔╝╚██████╔╝ ║
║     ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝  ║
║                                                               ║
║            DistributeX Cloud Network v4.0                    ║
║         Comprehensive Installation & Setup                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# ============================================================================
# SYSTEM REQUIREMENTS CHECK
# ============================================================================
check_requirements() {
    section "Checking System Requirements"
    
    # OS Detection
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    info "Operating System: $OS"
    info "Architecture: $ARCH"
    
    # Required tools (always needed)
    local required_tools=("curl" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            warn "$tool not found, installing..."
            
            if command -v apt-get &>/dev/null; then
                sudo apt-get update -qq && sudo apt-get install -y "$tool" -qq
            elif command -v yum &>/dev/null; then
                sudo yum install -y "$tool" -q
            elif command -v brew &>/dev/null; then
                brew install "$tool"
            else
                error "Could not install $tool automatically. Please install it manually."
            fi
        fi
    done
    
    log "All requirements satisfied"
}

# ============================================================================
# DOCKER CHECK (Only for Contributors)
# ============================================================================
check_docker() {
    section "Checking Docker"
    
    # Docker check
    if ! command -v docker &>/dev/null; then
        error "Docker is required for contributors but not installed.\nInstall from: https://docs.docker.com/get-docker/"
    fi
    
    if ! docker ps &>/dev/null; then
        error "Docker daemon is not running.\nPlease start Docker and try again."
    fi
    
    log "Docker is installed and running"
}

# ============================================================================
# MAC ADDRESS DETECTION
# ============================================================================
get_mac_address() {
    local mac=""
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        mac=$(ip link show 2>/dev/null | awk '/link\/ether/ {print $2; exit}')
        [ -z "$mac" ] && mac=$(cat /sys/class/net/*/address 2>/dev/null | grep -v '00:00:00:00:00:00' | head -n1)
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2; exit}')
        [ -z "$mac" ] && mac=$(ifconfig en1 2>/dev/null | awk '/ether/ {print $2; exit}')
    fi
    
    # Clean MAC address
    mac=$(echo "$mac" | tr -d ':-' | tr '[:upper:]' '[:lower:]')
    
    if [[ ! "$mac" =~ ^[0-9a-f]{12}$ ]]; then
        error "Could not detect a valid MAC address"
    fi
    
    echo "$mac"
}

# ============================================================================
# SYSTEM DETECTION
# ============================================================================
detect_system() {
    section "Detecting System Capabilities"
    
    # Basic info
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    HOSTNAME=$(hostname)
    MAC_ADDRESS=$(get_mac_address)
    
    # CPU Model
    if [[ "$OS" == "linux" ]]; then
        CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
    elif [[ "$OS" == "darwin" ]]; then
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string)
    fi
    CPU_MODEL=${CPU_MODEL:-"Unknown CPU"}
    
    # RAM
    if [[ "$OS" == "linux" ]]; then
        RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
        RAM_AVAILABLE=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')
    elif [[ "$OS" == "darwin" ]]; then
        RAM_TOTAL=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
        RAM_AVAILABLE=$RAM_TOTAL
    fi
    RAM_TOTAL=${RAM_TOTAL:-8192}
    RAM_AVAILABLE=${RAM_AVAILABLE:-$RAM_TOTAL}
    
    # GPU Detection
    GPU_AVAILABLE="false"
    GPU_COUNT=0
    GPU_MODEL=""
    GPU_MEMORY=0
    GPU_DRIVER=""
    GPU_CUDA=""
    
    if command -v nvidia-smi &>/dev/null; then
        GPU_AVAILABLE="true"
        GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l | xargs)
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1)
        GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1)
        
        if command -v nvcc &>/dev/null; then
            GPU_CUDA=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9.]+' || echo "")
        fi
    fi
    
    # Storage
    if [[ "$OS" == "linux" ]]; then
        STORAGE_TOTAL=$(df -BM / 2>/dev/null | awk 'NR==2 {print $2}' | sed 's/M//')
        STORAGE_AVAILABLE=$(df -BM / 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/M//')
    elif [[ "$OS" == "darwin" ]]; then
        STORAGE_TOTAL=$(df -m / 2>/dev/null | awk 'NR==2 {print $2}')
        STORAGE_AVAILABLE=$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')
    fi
    STORAGE_TOTAL=${STORAGE_TOTAL:-102400}
    STORAGE_AVAILABLE=${STORAGE_AVAILABLE:-51200}
    
    # Display detected info
    log "System: $OS/$ARCH"
    log "Hostname: $HOSTNAME"
    log "MAC Address: $MAC_ADDRESS"
    log "CPU: $CPU_MODEL ($CPU_CORES cores)"
    log "RAM: ${RAM_TOTAL}MB total, ${RAM_AVAILABLE}MB available"
    log "Storage: ${STORAGE_TOTAL}MB total, ${STORAGE_AVAILABLE}MB available"
    
    if [[ "$GPU_AVAILABLE" == "true" ]]; then
        log "GPU: $GPU_MODEL (${GPU_MEMORY}MB)"
        log "GPU Driver: $GPU_DRIVER"
        [[ -n "$GPU_CUDA" ]] && log "CUDA: $GPU_CUDA"
    else
        info "No GPU detected"
    fi
}

# ============================================================================
# RUNTIME DETECTION
# ============================================================================
detect_runtimes() {
    section "Detecting Available Runtimes"
    
    declare -A RUNTIMES
    
    # Python
    if command -v python3 &>/dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        RUNTIMES[python]="$PYTHON_VERSION"
        log "Python: $PYTHON_VERSION"
    elif command -v python &>/dev/null; then
        PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
        RUNTIMES[python]="$PYTHON_VERSION"
        log "Python: $PYTHON_VERSION"
    fi
    
    # Node.js
    if command -v node &>/dev/null; then
        NODE_VERSION=$(node --version | sed 's/v//')
        RUNTIMES[node]="$NODE_VERSION"
        log "Node.js: $NODE_VERSION"
    fi
    
    # Java
    if command -v java &>/dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        RUNTIMES[java]="$JAVA_VERSION"
        log "Java: $JAVA_VERSION"
    fi
    
    # Go
    if command -v go &>/dev/null; then
        GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        RUNTIMES[go]="$GO_VERSION"
        log "Go: $GO_VERSION"
    fi
    
    # Rust
    if command -v rustc &>/dev/null; then
        RUST_VERSION=$(rustc --version | awk '{print $2}')
        RUNTIMES[rust]="$RUST_VERSION"
        log "Rust: $RUST_VERSION"
    fi
    
    # Ruby
    if command -v ruby &>/dev/null; then
        RUBY_VERSION=$(ruby --version | awk '{print $2}')
        RUNTIMES[ruby]="$RUBY_VERSION"
        log "Ruby: $RUBY_VERSION"
    fi
    
    # PHP
    if command -v php &>/dev/null; then
        PHP_VERSION=$(php --version | head -n1 | awk '{print $2}')
        RUNTIMES[php]="$PHP_VERSION"
        log "PHP: $PHP_VERSION"
    fi
    
    # Docker
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        RUNTIMES[docker]="$DOCKER_VERSION"
        log "Docker: $DOCKER_VERSION"
    fi
    
    # Export for later use
    declare -g -A DETECTED_RUNTIMES
    for runtime in "${!RUNTIMES[@]}"; do
        DETECTED_RUNTIMES[$runtime]="${RUNTIMES[$runtime]}"
    done
    
    if [ ${#RUNTIMES[@]} -eq 0 ]; then
        warn "No runtimes detected (this is OK, Docker will handle execution)"
    fi
}

# ============================================================================
# AUTHENTICATION
# ============================================================================
authenticate_user() {
    section "Authentication"
    
    mkdir -p "$CONFIG_DIR"
    
    # Check for existing token
    if [ -f "$CONFIG_DIR/token" ]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        
        # Verify token
        if curl -sf -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user" &>/dev/null; then
            log "Using existing authentication"
            return 0
        else
            warn "Existing token expired, re-authenticating..."
            rm -f "$CONFIG_DIR/token"
        fi
    fi
    
    # New authentication
    echo -e "\n${CYAN}${BOLD}Account Options:${NC}"
    echo "  1) Sign up (Create new account)"
    echo "  2) Login (Existing account)"
    echo ""
    
    while true; do
        read -r -p "Choice [1-2]: " choice </dev/tty
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
    read -r -p "First Name: " first_name </dev/tty
    read -r -p "Email: " email </dev/tty
    
    while true; do
        read -s -r -p "Password (min 8 characters): " password </dev/tty
        echo ""
        
        if [ ${#password} -lt 8 ]; then
            echo -e "${RED}Password must be at least 8 characters${NC}"
            continue
        fi
        
        read -s -r -p "Confirm Password: " password_confirm </dev/tty
        echo ""
        
        if [ "$password" != "$password_confirm" ]; then
            echo -e "${RED}Passwords do not match${NC}"
            continue
        fi
        
        break
    done
    
    # Sign up request
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
        ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Unknown error"')
        error "Signup failed: $ERROR_MSG"
    fi
    
    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No authentication token received"
    fi
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    
    log "Account created successfully!"
}

login_user() {
    echo ""
    read -r -p "Email: " email </dev/tty
    read -s -r -p "Password: " password </dev/tty
    echo ""
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" != "200" ]; then
        ERROR_MSG=$(echo "$HTTP_BODY" | jq -r '.message // "Unknown error"')
        error "Login failed: $ERROR_MSG"
    fi
    
    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No authentication token received"
    fi
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    
    log "Logged in successfully!"
}

# ============================================================================
# ROLE SELECTION - Fetch from API (set on website)
# ============================================================================
select_role() {
    section "Role Selection"
    
    # FIX: Create config directory first
    mkdir -p "$CONFIG_DIR"
    
    # Fetch user's current role from API
    ROLE_RESPONSE=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user" || echo "{}")
    CURRENT_ROLE=$(echo "$ROLE_RESPONSE" | jq -r '.role // "none"')
    USER_EMAIL=$(echo "$ROLE_RESPONSE" | jq -r '.email // "unknown"')
    
    # If role is not set, redirect to website
    if [ "$CURRENT_ROLE" = "none" ] || [ "$CURRENT_ROLE" = "null" ] || [ -z "$CURRENT_ROLE" ]; then
        echo ""
        warn "No role selected for account: $USER_EMAIL"
        echo ""
        echo -e "${YELLOW}Please select your role on the website:${NC}"
        echo -e "${BLUE}${BOLD}$DISTRIBUTEX_API_URL/dashboard${NC}"
        echo ""
        echo "Choose either:"
        echo "  • ${GREEN}Contributor${NC} - Share your computing resources"
        echo "  • ${BLUE}Developer${NC} - Use distributed computing for your tasks"
        echo ""
        echo "After selecting your role, run this script again:"
        echo "  ${CYAN}curl -sSL $INSTALL_SCRIPT_URL | bash${NC}"
        echo ""
        exit 0
    fi
    
    USER_ROLE="$CURRENT_ROLE"
    log "Account role: $USER_ROLE"
    echo "$USER_ROLE" > "$CONFIG_DIR/role"
}
    
    # Update role via API
    info "Setting role to: $USER_ROLE"
    
    UPDATE_RESP=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/update-role" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"role\":\"$USER_ROLE\"}")
    
    UPDATE_BODY=$(echo "$UPDATE_RESP" | head -n -1)
    UPDATE_CODE=$(echo "$UPDATE_RESP" | tail -n1)
    
    if [ "$UPDATE_CODE" = "200" ]; then
        # Get new token if provided
        NEW_TOKEN=$(echo "$UPDATE_BODY" | jq -r '.token // empty')
        if [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "null" ]; then
            echo "$NEW_TOKEN" > "$CONFIG_DIR/token"
            API_TOKEN="$NEW_TOKEN"
        fi
        
        log "Role set to: $USER_ROLE"
    else
        warn "Role update returned code $UPDATE_CODE"
    fi
    
    echo "$USER_ROLE" > "$CONFIG_DIR/role"
}

# ============================================================================
# BUILD RUNTIME JSON
# ============================================================================
build_runtime_json() {
    local json="{"
    local first=true
    
    for runtime in "${!DETECTED_RUNTIMES[@]}"; do
        if [ "$first" = false ]; then
            json+=","
        fi
        first=false
        
        local version="${DETECTED_RUNTIMES[$runtime]}"
        json+="\"$runtime\":{\"available\":true,\"version\":\"$version\",\"command\":\"$runtime\"}"
    done
    
    json+="}"
    echo "$json"
}

# ============================================================================
# WORKER REGISTRATION
# ============================================================================
register_worker() {
    section "Registering Worker"
    
    local runtimes_json=$(build_runtime_json)
    
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
            \"gpuDriverVersion\": \"$GPU_DRIVER\",
            \"gpuCudaVersion\": \"$GPU_CUDA\",
            \"storageTotal\": $STORAGE_TOTAL,
            \"storageAvailable\": $STORAGE_AVAILABLE,
            \"isDocker\": true,
            \"runtimes\": $runtimes_json
        }")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        WORKER_ID=$(echo "$HTTP_BODY" | jq -r '.workerId')
        IS_NEW=$(echo "$HTTP_BODY" | jq -r '.isNew')
        
        echo "$WORKER_ID" > "$CONFIG_DIR/worker_id"
        echo "$MAC_ADDRESS" > "$CONFIG_DIR/mac_address"
        
        if [ "$IS_NEW" = "true" ]; then
            log "Worker registered: $WORKER_ID"
        else
            log "Worker reconnected: $WORKER_ID"
        fi
    else
        warn "Worker registration returned code $HTTP_CODE"
        warn "Body: $HTTP_BODY"
    fi
}

# ============================================================================
# START CONTRIBUTOR (DOCKER WORKER)
# ============================================================================
start_contributor() {
    section "Starting Worker Container"
    
    info "Pulling latest worker image..."
    if ! docker pull "$DOCKER_IMAGE" 2>&1 | grep -q "Downloaded\|up to date"; then
        warn "Failed to pull latest image, using local if available"
    fi
    
    info "Stopping existing container (if any)..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    
    info "Starting worker container..."
    
    # GPU support
    local gpu_flag=""
    if [ "$GPU_AVAILABLE" = "true" ]; then
        gpu_flag="--gpus all"
    fi
    
    # Start container
    if docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        $gpu_flag \
        -e DISTRIBUTEX_API_URL="$DISTRIBUTEX_API_URL" \
        -e DISABLE_SELF_REGISTER=true \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -v "$CONFIG_DIR:/config:ro" \
        "$DOCKER_IMAGE" \
        --api-key "$API_TOKEN" \
        --url "$DISTRIBUTEX_API_URL" &>/dev/null; then
        
        sleep 3
        
        if docker ps | grep -q "$CONTAINER_NAME"; then
            log "Worker container started successfully"
        else
            error "Worker container failed to start"
        fi
    else
        error "Failed to start worker container"
    fi
}

# ============================================================================
# AUTO-START SETUP
# ============================================================================
setup_autostart() {
    section "Setting Up Auto-Start"
    
    if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null; then
        # Systemd
        info "Creating systemd service..."
        
        sudo tee /etc/systemd/system/distributex-worker.service > /dev/null << EOF
[Unit]
Description=DistributeX Worker Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start $CONTAINER_NAME
ExecStop=/usr/bin/docker stop $CONTAINER_NAME
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        
        sudo systemctl daemon-reload
        sudo systemctl enable distributex-worker.service
        log "Systemd service created and enabled"
        
    elif [[ "$OS" == "darwin" ]]; then
        # Launchd
        info "Creating launchd service..."
        
        cat > ~/Library/LaunchAgents/com.distributex.worker.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.distributex.worker</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/docker</string>
        <string>start</string>
        <string>$CONTAINER_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
        
        launchctl load ~/Library/LaunchAgents/com.distributex.worker.plist 2>/dev/null || true
        log "Launchd service created"
    else
        warn "Auto-start not configured (unsupported init system)"
    fi
}

# ============================================================================
# MANAGEMENT SCRIPT
# ============================================================================
create_management_script() {
    section "Creating Management Tools"
    
    cat > "$CONFIG_DIR/manage.sh" << 'MGMT_EOF'
#!/bin/bash
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

case "$1" in
    status)
        echo "DistributeX Worker Status"
        echo "========================="
        if docker ps | grep -q "$CONTAINER_NAME"; then
            echo "Status: Running"
            docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Status}}\t{{.Ports}}"
        else
            echo "Status: Stopped"
        fi
        ;;
    logs)
        docker logs -f "$CONTAINER_NAME"
        ;;
    restart)
        echo "Restarting worker..."
        docker restart "$CONTAINER_NAME"
        echo "Worker restarted"
        ;;
    stop)
        echo "Stopping worker..."
        docker stop "$CONTAINER_NAME"
        echo "Worker stopped"
        ;;
    start)
        echo "Starting worker..."
        docker start "$CONTAINER_NAME"
        echo "Worker started"
        ;;
    uninstall)
        echo "Are you sure you want to uninstall DistributeX? (yes/no)"
        read -r confirm
        if [ "$confirm" = "yes" ]; then
            docker stop "$CONTAINER_NAME" 2>/dev/null || true
            docker rm "$CONTAINER_NAME" 2>/dev/null || true
            docker rmi distributexcloud/worker 2>/dev/null || true
            
            if [ -f "/etc/systemd/system/distributex-worker.service" ]; then
                sudo systemctl stop distributex-worker.service 2>/dev/null || true
                sudo systemctl disable distributex-worker.service 2>/dev/null || true
                sudo rm /etc/systemd/system/distributex-worker.service 2>/dev/null || true
            fi
            
            if [ -f "$HOME/Library/LaunchAgents/com.distributex.worker.plist" ]; then
                launchctl unload "$HOME/Library/LaunchAgents/com.distributex.worker.plist" 2>/dev/null || true
                rm "$HOME/Library/LaunchAgents/com.distributex.worker.plist" 2>/dev/null || true
            fi
            
            echo "Keep configuration files? (yes/no)"
            read -r keep_config
            if [ "$keep_config" != "yes" ]; then
                rm -rf "$CONFIG_DIR"
                echo "Configuration deleted"
            fi
            
            echo ""
            echo "✅ DistributeX has been completely removed from your system"
            echo ""
        else
            echo ""
            echo "❌ Uninstall cancelled"
            echo ""
        fi
        ;;
    *)
        echo "Usage: $0 {status|logs|restart|stop|start|uninstall}"
        exit 1
        ;;
esac
MGMT_EOF
    
    chmod +x "$CONFIG_DIR/manage.sh"
    log "Management script created at: $CONFIG_DIR/manage.sh"
}

# ============================================================================
# FINAL STEPS
# ============================================================================
show_completion_message() {
    section "Installation Complete!"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          🎉 Installation Successful! 🎉                   ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Worker is running and sharing resources!"
    echo ""
    
    echo -e "${CYAN}${BOLD}Your Contribution:${NC}"
    echo "  • CPU: $CPU_CORES cores"
    echo "  • RAM: ${RAM_TOTAL}MB"
    if [[ "$GPU_AVAILABLE" == "true" ]]; then
        echo "  • GPU: $GPU_MODEL (${GPU_MEMORY}MB)"
    fi
    echo "  • Storage: ${STORAGE_TOTAL}MB"
    echo ""
    
    echo -e "${CYAN}${BOLD}Management Commands:${NC}"
    echo "  Check status:  $CONFIG_DIR/manage.sh status"
    echo "  View logs:     $CONFIG_DIR/manage.sh logs"
    echo "  Restart:       $CONFIG_DIR/manage.sh restart"
    echo "  Stop:          $CONFIG_DIR/manage.sh stop"
    echo "  Uninstall:     $CONFIG_DIR/manage.sh uninstall"
    echo ""
    
    echo -e "${CYAN}${BOLD}Dashboard:${NC}"
    echo "  View your stats at:"
    echo "  ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC}"
    echo ""
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Thank you for contributing to DistributeX! 🌟"
    echo ""
}

# ============================================================================
# MAIN EXECUTION FLOW
# ============================================================================
main() {
    show_banner
    
    # System checks (always needed)
    check_requirements
    
    # Authentication first
    authenticate_user
    
    # Get role from website
    select_role
    
    # Only check Docker if contributor
    if [[ "$USER_ROLE" == "contributor" ]]; then
        check_docker
        detect_system
        detect_runtimes
        register_worker
        start_contributor
        setup_autostart
        create_management_script
        show_completion_message
    else
        # Developer path - no Docker needed
        echo ""
        log "Developer account detected"
        echo ""
        echo -e "${CYAN}${BOLD}Next Steps for Developers:${NC}"
        echo ""
        echo "1. Your API key (save this securely):"
        echo "   ${GREEN}${BOLD}$API_TOKEN${NC}"
        echo ""
        echo "2. Install the SDK:"
        echo "   ${YELLOW}# Python${NC}"
        echo "   pip install distributex-cloud"
        echo ""
        echo "   ${YELLOW}# JavaScript/Node.js${NC}"
        echo "   npm install distributex-cloud"
        echo ""
        echo "3. Start building:"
        echo "   ${YELLOW}# Python${NC}"
        echo "   from distributex import DistributeX"
        echo "   dx = DistributeX(api_key='$API_TOKEN')"
        echo "   result = dx.run(my_function, workers=4, gpu=True)"
        echo ""
        echo "   ${YELLOW}# JavaScript${NC}"
        echo "   const DistributeX = require('distributex-cloud');"
        echo "   const dx = new DistributeX('$API_TOKEN');"
        echo "   const result = await dx.run(myFunction, { workers: 4 });"
        echo ""
        echo "Dashboard: ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC}"
        echo "Documentation: ${BLUE}https://distributex.io/docs${NC}"
        echo ""
    fi
}

# ============================================================================
# ERROR HANDLING
# ============================================================================
trap 'error "Installation failed at line $LINENO. Please check the logs above."' ERR

# ============================================================================
# RUN INSTALLATION
# ============================================================================
main "$@"

exit 0
