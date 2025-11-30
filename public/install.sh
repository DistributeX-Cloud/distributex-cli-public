#!/bin/bash
#
# DistributeX Complete Installer - FIXED SINGLE WORKER VERSION
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash
#
# FIXES:
# 1. Only ONE worker registration per device
# 2. Worker name: Worker-{MAC_ADDRESS}
# 3. Hostname: Actual device hostname
# 4. Worker agent disabled from self-registering
set -e

# ============================================================================
# CONFIG
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
log()   { echo -e "${GREEN}[Success]${NC} $1"; }
info()  { echo -e "${CYAN}[Info]${NC} $1"; }
warn()  { echo -e "${YELLOW}[Warning]${NC} $1"; }
error() { echo -e "${RED}[Error]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"; }

# ============================================================================
# BANNER
# ============================================================================
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║     DistributeX Cloud Network - Single Worker v4.3 (FINAL)       ║
║   Real GPU • Real Storage • Zero Errors • Forever Running     ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# ============================================================================
# MAC ADDRESS (12 hex lowercase)
# ============================================================================
get_mac_address() {
    local mac=""
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        mac=$(ip link show 2>/dev/null | awk '/link\/ether/ {print tolower($2); exit}' || true)
        [ -z "$mac" ] && mac=$(cat /sys/class/net/*/address 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]' || true)
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print tolower($2)}' || ifconfig en1 2>/dev/null | awk '/ether/ {print tolower($2)}')
    fi
    mac=${mac//:/}
    [[ "$mac" =~ ^[0-9a-f]{1,12}$ ]] || return 1
    printf "%012s" "$mac" | tr ' ' '0'
}

# ============================================================================
# SYSTEM + GPU + REAL STORAGE DETECTION
# ============================================================================
detect_system() {
    section "Detecting System, GPU & Disk"

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    HOSTNAME=$(hostname)
    MAC_ADDRESS=$(get_mac_address) || error "Cannot detect valid MAC address"
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    CPU_MODEL=$(lscpu 2>/dev/null | grep -m1 "Model name:" | cut -d: -f2 | xargs || echo "Unknown")
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)

    # Real disk storage (MB)
    STORAGE_TOTAL_MB=102400
    STORAGE_FREE_MB=51200
    if command -v df &>/dev/null; then
        line=$(df -k "$HOME" 2>/dev/null | tail -1)
        if [[ -n "$line" ]]; then
            STORAGE_TOTAL_MB=$(awk '{print int($2/1024)}' <<<"$line")   # KB → MB
            STORAGE_FREE_MB=$(awk '{print int($4/1024)}' <<<"$line")
        fi
    fi

    # GPU detection
    GPU_AVAILABLE=false
    GPU_MODEL="none"
    GPU_MEMORY=0
    GPU_COUNT=0
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi --query-gpu=name,memory.total,count --format=csv,noheader,nounits >/dev/null 2>&1; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -n1 | xargs)
            GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
            GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits)
        fi
    fi

    log "MAC         : $MAC_ADDRESS"
    log "Host        : $HOSTNAME"
    log "CPU         : $CPU_CORES cores - $CPU_MODEL"
    log "RAM         : $((RAM_TOTAL/1024)) GB"
    log "Storage     : $((STORAGE_TOTAL_MB/1024)) GB total | $((STORAGE_FREE_MB/1024)) GB free"
    $GPU_AVAILABLE && log "GPU         : $GPU_COUNT × $GPU_MODEL (${GPU_MEMORY} MiB)" || log "GPU         : none"
}

# ============================================================================
# TOOLS
# ============================================================================
check_requirements() {
    section "Tools"
    for t in curl jq df; do
        command -v $t &>/dev/null || {
            warn "Installing $t..."
            if command -v apt-get &>/dev/null; then sudo apt-get update -qq && sudo apt-get install -y $t -qq
            elif command -v yum &>/dev/null; then sudo yum install -y $t
            elif command -v brew &>/dev/null; then brew install $t
            else error "Install $t manually"
            fi
        }
    done
    log "Tools ready"
}

check_docker() {
    section "Docker"
    command -v docker &>/dev/null || error "Docker required → https://docs.docker.com/get-docker/"
    docker ps >/dev/null 2>&1 || error "Docker daemon not running"
    log "Docker ready"
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
            log "Logged in (cached)"
            return 0
        }
        warn "Token expired"
        rm -f "$CONFIG_DIR/token"
    fi

    echo -e "${CYAN}1) Sign up\n2) Login${NC}"
    while :; do
        read -r -p "Choice [1-2]: " choice </dev/tty
        case "$choice" in
            1) signup_user; return 0 ;;
            2) login_user;  return 0 ;;
            *) echo -e "${RED}Enter 1 or 2${NC}" ;;
        esac
    done
}

signup_user() {
    echo -e "\n${BOLD}Create Account${NC}"
    read -r -p "First Name: " name </dev/tty
    read -r -p "Email: " email </dev/tty
    while :; do
        read -s -r -p "Password (≥8 chars): " pw </dev/tty; echo
        (( ${#pw} >= 8 )) && break
        warn "Too short"
    done
    read -s -r -p "Confirm: " pw2 </dev/tty; echo
    [[ "$pw" == "$pw2" ]] || { warn "No match"; signup_user; }

    resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$pw\",\"firstName\":\"$name\"}")
    code=$(tail -n1 <<<"$resp")
    body=$(sed '$d' <<<"$resp")
    [[ "$code" =~ ^2 ]] || error "Signup failed: $(jq -r '.message//' <<<"$body")"
    API_TOKEN=$(jq -r '.token' <<<"$body")
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Account created"
}

login_user() {
    echo -e "\n${BOLD}Login${NC}"
    read -r -p "Email: " email </dev/tty
    read -s -r -p "Password: " pw </dev/tty; echo
    resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$pw\"}")
    code=$(tail -n1 <<<"$resp")
    body=$(sed '$d' <<<"$resp")
    [[ "$code" == 200 ]] || error "Login failed"
    API_TOKEN=$(jq -r '.token' <<<"$body")
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in"
}

select_role() {
    section "Role Check"
    resp=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user")
    USER_ROLE=$(jq -r '.role // empty' <<<"$resp")
    if [[ -z "$USER_ROLE" || "$USER_ROLE" == "null" ]]; then
        warn "No role selected"
        echo -e "Visit ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC} → choose Contributor or Developer"
        echo -e "Then run: ${CYAN}curl -sSL $INSTALL_SCRIPT_URL | bash${NC}\n"
        exit 0
    fi
    log "Role: $USER_ROLE"
}

check_existing_worker() {
    resp=$(curl -s -w "\n%{http_code}" -X GET \
        -H "Authorization: Bearer $API_TOKEN" \
        "$DISTRIBUTEX_API_URL/api/workers/check/$MAC_ADDRESS")
    code=$(tail -n1 <<<"$resp")
    body=$(sed '$d' <<<"$resp")
    [[ "$code" == 200 && $(jq -r '.exists' <<<"$body") == "true" ]]
}

register_worker() {
    section "Registering Worker"
    check_existing_worker && { log "Device already registered"; return 0; }

    # Ensure numeric variables are valid numbers
    CPU_CORES=${CPU_CORES:-0}
    RAM_TOTAL=${RAM_TOTAL:-0}
    STORAGE_TOTAL_MB=${STORAGE_TOTAL_MB:-0}
    STORAGE_FREE_MB=${STORAGE_FREE_MB:-0}
    GPU_MEMORY=${GPU_MEMORY:-0}
    GPU_COUNT=${GPU_COUNT:-0}

    # Ensure numeric values contain only digits
    CPU_CORES=$(printf "%d" "$CPU_CORES" 2>/dev/null || echo 0)
    RAM_TOTAL=$(printf "%d" "$RAM_TOTAL" 2>/dev/null || echo 0)
    STORAGE_TOTAL_MB=$(printf "%d" "$STORAGE_TOTAL_MB" 2>/dev/null || echo 0)
    STORAGE_FREE_MB=$(printf "%d" "$STORAGE_FREE_MB" 2>/dev/null || echo 0)
    GPU_MEMORY=$(printf "%d" "$GPU_MEMORY" 2>/dev/null || echo 0)
    GPU_COUNT=$(printf "%d" "$GPU_COUNT" 2>/dev/null || echo 0)

    payload=$(jq -n \
      --arg m "$MAC_ADDRESS" \
      --arg n "Worker-$MAC_ADDRESS" \
      --arg h "$HOSTNAME" \
      --arg p "$OS" \
      --arg a "$ARCH" \
      --argjson c "$CPU_CORES" \
      --arg cm "$CPU_MODEL" \
      --argjson r "$RAM_TOTAL" \
      --argjson st "$STORAGE_TOTAL_MB" \
      --argjson sa "$STORAGE_FREE_MB" \
      --arg ga "$GPU_AVAILABLE" \
      --arg gm "$GPU_MODEL" \
      --argjson gmem "$GPU_MEMORY" \
      --argjson gc "$GPU_COUNT" \
      '{
        macAddress: $m,
        name: $n,
        hostname: $h,
        platform: $p,
        architecture: $a,
        cpuCores: $c,
        cpuModel: $cm,
        ramTotal: $r,
        storageTotal: $st,
        storageAvailable: $sa,
        gpuAvailable: ($ga == "true"),
        gpuModel: $gm,
        gpuMemory: $gmem,
        gpuCount: $gc
      }')

    resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload")
    code=$(tail -n1 <<<"$resp")
    body=$(sed '$d' <<<"$resp")
    [[ "$code" =~ ^2 ]] || error "Registration failed: $(jq -r '.message//.error//"?"' <<<"$body")"
    log "Worker registered"
    echo "$MAC_ADDRESS" > "$CONFIG_DIR/mac_address"
}

start_contributor() {
    section "Launching Worker"
    register_worker

    docker pull "$DOCKER_IMAGE" >/dev/null
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

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
    docker ps --filter "name=^${CONTAINER_NAME}$" | grep -q "$CONTAINER_NAME" &&
        log "Worker running forever" || error "Failed to start container"
}

create_management_script() {
    cat > "$CONFIG_DIR/manage.sh" <<'EOF'
#!/bin/bash
C="distributex-worker"
echo "DistributeX Worker"
case "$1" in
    status)   docker ps --filter "name=$C" --format "table {{.Names}}\t{{.Status}}" ;;
    logs)     docker logs -f $C ;;
    restart)  docker restart $C ;;
    stop)     docker stop $C ;;
    start)    docker start $C ;;
    uninstall)
        read -p "Uninstall? (yes/no): " yn
        [[ "$yn" == "yes" ]] || exit
        docker stop $C 2>/dev/null
        docker rm $C 2>/dev/null
        echo "Uninstalled"
        ;;
    *) echo "Usage: $0 status|logs|restart|stop|start|uninstall" ;;
esac
EOF
    chmod +x "$CONFIG_DIR/manage.sh"
}

show_contributor_complete() {
    section "Installation Complete!"
    echo -e "${GREEN}Worker is running and will survive reboots${NC}\n"
    log "Name     : Worker-$MAC_ADDRESS"
    log "Storage  : $((STORAGE_TOTAL_MB/1024)) GB total"
    $GPU_AVAILABLE && log "GPU      : $GPU_COUNT × $GPU_MODEL"
    echo -e "\n${CYAN}Control:${NC} $CONFIG_DIR/manage.sh status|logs|restart"
    echo -e "${BLUE}Dashboard:${NC} $DISTRIBUTEX_API_URL/dashboard\n"
}

show_developer_complete() {
    section "Developer Mode"
    echo -e "${GREEN}No worker installed – correct for developers${NC}\n"
    echo -e "API Key:\n${BOLD}$API_TOKEN${NC}\n"
    echo -e "Dashboard → ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC}"
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
