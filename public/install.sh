#!/bin/bash
################################################################################
# DistributeX Cloud Network - Complete Installation Script v4.1
# FULLY COMPATIBLE WITH NEON POSTGRESQL SCHEMA (Single Worker + Heartbeat Only)
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
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================
log()   { echo -e "${GREEN}[✓]${NC} $1"; }
info()  { echo -e "${CYAN}[i]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
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
║ ██████╗ ██╗███████╗████████╗██████╗ ██╗██████╗ ██╗ ██╗   ║
║ ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║██╔══██╗██║ ██║   ║
║ ██║  ██║██║███████╗   ██║   ██████╔╝██║██████╔╝██║ ██║   ║
║ ██║  ██║██║╚════██║   ██║   ██╔══██╗██║██╔══██╗██║ ██║   ║
║ ██████╔╝██║███████║   ██║   ██║  ██║██║██████╔╝╚██████╔╝ ║
║ ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝  ║
║                                                               ║
║       DistributeX Cloud Network - Single Worker Edition       ║
║        One Device = One Worker • Heartbeat Only • Secure       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# ============================================================================
# MAC ADDRESS → exactly 12 lowercase hex chars (matches DB constraint)
# ============================================================================
get_mac_address() {
    local mac=""
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        mac=$(ip link show 2>/dev/null | awk '/link\/ether/ {print $2; exit}' || true)
        [ -z "$mac" ] && mac=$(cat /sys/class/net/*/address 2>/dev/null | grep -v '00:00:00:00:00:00' | head -n1 || true)
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2}' || ifconfig en1 2>/dev/null | awk '/ether/ {print $2}')
    fi
    mac=$(echo "$mac" | tr -d ':' | tr '[:upper:]' '[:lower:]')
    [[ "$mac" =~ ^[0-9a-f]{12}$ ]] && echo "$mac" && return 0
    [[ "$mac" =~ ^[0-9a-f]{1,11}$ ]] && printf "%012s" "$mac" | tr ' ' '0' && return 0
    return 1
}

# ============================================================================
# BASIC REQUIREMENTS
# ============================================================================
check_requirements() {
    section "Checking Requirements"
    for tool in curl jq; do
        command -v "$tool" &>/dev/null || {
            warn "Installing $tool..."
            if command -v apt-get &>/dev/null; then
                sudo apt-get update -qq && sudo apt-get install -y "$tool" -qq
            elif command -v yum &>/dev/null; then
                sudo yum install -y "$tool" -q
            elif command -v brew &>/dev/null; then
                brew install "$tool"
            else
                error "Please install $tool manually"
            fi
        }
    done
    log "curl + jq ready"
}

# ============================================================================
# DOCKER CHECK (Contributor only)
# ============================================================================
check_docker() {
    section "Checking Docker"
    command -v docker &>/dev/null || error "Docker required → https://docs.docker.com/get-docker/"
    docker ps >/dev/null 2>&1 || error "Docker daemon not running"
    log "Docker ready"
}

# ============================================================================
# SYSTEM DETECTION
# ============================================================================
detect_system() {
    section "System Detection"
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    HOSTNAME=$(hostname)
    MAC_ADDRESS=$(get_mac_address) || error "Failed to detect valid MAC address (required for single-worker enforcement)"
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name:" | cut -d: -f2 | xargs || sysctl -n machdep.cpu.brand_string || echo "Unknown")
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)

    GPU_AVAILABLE="false"
    GPU_MODEL=""; GPU_MEMORY=0
    command -v nvidia-smi &>/dev/null && {
        GPU_AVAILABLE="true"
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader -i 0 2>/dev/null | xargs)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits -i 0 2>/dev/null || echo 0)
    }

    log "MAC: $MAC_ADDRESS"
    log "Host: $HOSTNAME | $CPU_CORES cores | ${RAM_TOTAL}MB RAM"
    [ "$GPU_AVAILABLE" = "true" ] && log "GPU: $GPU_MODEL (${GPU_MEMORY} MiB)"
}

# ============================================================================
# AUTHENTICATION
# ============================================================================
authenticate_user() {
    section "Authentication"
    mkdir -p "$CONFIG_DIR"

    if [[ -f "$CONFIG_DIR/token" ]]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        curl -sf -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user" >/dev/null && {
            log "Using existing login"
            return 0
        }
        warn "Token expired"
        rm -f "$CONFIG_DIR/token"
    fi

    echo -e "${CYAN}1) Sign up   2) Login${NC}\n"
    while true; do
        read -r -p "Choice [1-2]: " choice </dev/tty
        case "$choice" in
            1) signup_user; return 0 ;;
            2) login_user;  return 0 ;;
            *) echo -e "${RED}Invalid choice${NC}" ;;
        esac
    done
}

signup_user() {
    echo -e "\n${BOLD}Create Account${NC}"
    read -r -p "First Name: " first_name </dev/tty
    read -r -p "Email: " email </dev/tty
    while true; do
        read -s -r -p "Password (min 8 chars): " pw </dev/tty; echo
        [[ ${#pw} -ge 8 ]] && break
        warn "Too short"
    done
    read -s -r -p "Confirm: " pw2 </dev/tty; echo
    [[ "$pw" == "$pw2" ]] || { warn "Mismatch"; signup_user; return; }

    local resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$pw\",\"firstName\":\"$first_name\"}")
    local code=$(echo "$resp" | tail -n1)
    local body=$(echo "$resp" | head -n -1)

    [[ "$code" == 20* ]] || error "Signup failed: $(echo "$body" | jq -r '.message // "Unknown"')"
    API_TOKEN=$(echo "$body" | jq -r '.token')
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Account created!"
}

login_user() {
    echo -e "\n${BOLD}Login${NC}"
    read -r -p "Email: " email </dev/tty
    read -s -r -p "Password: " pw </dev/tty; echo

    local resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$pw\"}")
    local code=$(echo "$resp" | tail -n1)
    local body=$(echo "$resp" | head -n -1)

    [[ "$code" == 200 ]] || error "Login failed: $(echo "$body" | jq -r '.message // "Invalid"')"
    API_TOKEN=$(echo "$body" | jq -r '.token')
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in!"
}

# ============================================================================
# ROLE FROM WEBSITE (Neon DB compatible)
# ============================================================================
select_role() {
    section "Checking Role"
    local resp=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user")
    USER_ROLE=$(echo "$resp" | jq -r '.role // empty')

    if [[ -z "$USER_ROLE" || "$USER_ROLE" == "null" || "$USER_ROLE" == "none" ]]; then
        warn "No role selected"
        echo -e "Go to: ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC} → Choose Contributor or Developer"
        echo -e "Then re-run: ${CYAN}curl -sSL $INSTALL_SCRIPT_URL | bash${NC}\n"
        exit 0
    fi

    log "Role: $USER_ROLE"
    echo "$USER_ROLE" > "$CONFIG_DIR/role"
}

# ============================================================================
# CHECK IF WORKER EXISTS (critical for single-worker rule)
# ============================================================================
check_existing_worker() {
    local resp=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: Bearer $API_TOKEN" \
        "$DISTRIBUTEX_API_URL/api/workers/check/$MAC_ADDRESS")
    local code=$(echo "$resp" | tail -n1)
    local body=$(echo "$resp" | head -n -1)
    [[ "$code" == "200" && "$(echo "$body" | jq -r '.exists')" == "true" ]]
}

# ============================================================================
# REGISTER WORKER (only once)
# ============================================================================
register_worker() {
    section "Worker Registration"
    if check_existing_worker; then
        log "Device already registered (single-worker mode enforced)"
        return 0
    fi

    info "Registering new worker..."
    local payload=$(cat <<EOF
{
  "macAddress": "$MAC_ADDRESS",
  "name": "Worker-$MAC_ADDRESS",
  "hostname": "$HOSTNAME",
  "platform": "$OS",
  "architecture": "$ARCH",
  "cpuCores": $CPU_CORES,
  "cpuModel": "$CPU_MODEL",
  "ramTotal": $RAM_TOTAL,
  "gpuAvailable": $GPU_AVAILABLE,
  "gpuModel": "$GPU_MODEL",
  "gpuMemory": $GPU_MEMORY,
  "storageTotal": 102400,
  "storageAvailable": 51200
}
EOF
)

    local resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload")
    local code=$(echo "$resp" | tail -n1)
    local body=$(echo "$resp" | head -n -1)

    [[ "$code" == 20* ]] || error "Registration failed: $(echo "$body" | jq -r '.message // .error // "Unknown"')"
    log "Worker registered: Worker-$MAC_ADDRESS"
    echo "$MAC_ADDRESS" > "$CONFIG_DIR/mac_address"
}

# ============================================================================
# START PERSISTENT CONTAINER (heartbeat only, no self-register)
# ============================================================================
start_contributor() {
    section "Launching Persistent Worker"
    register_worker

    info "Pulling latest worker image..."
    docker pull "$DOCKER_IMAGE" >/dev/null

    info "Cleaning old containers..."
    docker rm -f $(docker ps -aq --filter "name=^${CONTAINER_NAME}$") 2>/dev/null || true

    info "Starting worker (runs forever, heartbeat mode)..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --shm-size=1g \
        -e DISABLE_SELF_REGISTER=true \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -v "$CONFIG_DIR:/config:ro" \
        "$DOCKER_IMAGE" \
        --api-key "$API_TOKEN" \
        --url "$DISTRIBUTEX_API_URL" >/dev/null

    sleep 5
    docker ps | grep -q "$CONTAINER_NAME" && log "Worker running permanently" || error "Container failed"
}

# ============================================================================
# MANAGEMENT SCRIPT
# ============================================================================
create_management_script() {
    section "Creating Management Tool"
    cat > "$CONFIG_DIR/manage.sh" <<'EOF'
#!/bin/bash
C="distributex-worker"
echo "DistributeX Worker"
echo "=================="
case "$1" in
    status)   docker ps --filter "name=$C" --format "table {{.Names}}\t{{.Status}}" ;;
    logs)     docker logs -f $C ;;
    restart)  docker restart $C; echo "Restarted" ;;
    stop)     docker stop $C; echo "Stopped" ;;
    start)    docker start $C; echo "Started" ;;
    uninstall)
        read -p "Uninstall? (yes/no): " yn
        [[ "$yn" == "yes" ]] || exit
        docker stop $C 2>/dev/null
        docker rm $C 2>/dev/null
        echo "Uninstalled. Config in $HOME/.distributex"
        ;;
    *) echo "Usage: $0 status|logs|restart|stop|start|uninstall" ;;
esac
EOF
    chmod +x "$CONFIG_DIR/manage.sh"
    log "manage.sh → $CONFIG_DIR/manage.sh"
}

# ============================================================================
# FINAL MESSAGES
# ============================================================================
show_contributor_complete() {
    section "Installation Complete!"
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       DistributeX Worker is Running Forever      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}\n"
    log "Worker: Worker-$MAC_ADDRESS"
    log "Hostname: $HOSTNAME"
    log "Auto-restart: enabled"
    echo -e "${CYAN}Commands:${NC}"
    echo "   $CONFIG_DIR/manage.sh status | logs | restart | stop"
    echo -e "\n${BLUE}Dashboard: $DISTRIBUTEX_API_URL/dashboard${NC}\n"
    echo -e "${BOLD}Thank you for contributing!${NC}\n"
}

show_developer_complete() {
    section "Developer Mode"
    echo -e "${GREEN}No worker installed (correct for developers)${NC}\n"
    echo -e "API Key:\n${BOLD}$API_TOKEN${NC}\n"
    echo -e "Dashboard → ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC}\n"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    show_banner
    check_requirements
    authenticate_user
    select_role
    detect_system

    if [[ "$USER_ROLE" == "contributor" ]]; then
        check_docker
        start_contributor
        create_management_script
        show_contributor_complete
    else
        show_developer_complete
    fi
}

trap 'error "Failed at line $LINENO"' ERR
main
exit 0
