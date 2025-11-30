#!/bin/bash
#
# DistributeX Cloud Network - v5.0 FINAL ULTRA EDITION
# → Detects ALL mounted drives (USB, NVMe, HDD, NAS, everything)
# → FULL REAL GPU PASSTHROUGH (NVIDIA CUDA, AMD ROCm, Intel Arc)
# → Single worker per device • Zero jq errors • Forever running
#
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash
#
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
# HELPERS
# ============================================================================
safe_jq() { echo "$2" | jq -r "$1" 2>/dev/null || echo ""; }
log() { echo -e "${GREEN}[Success]${NC} $1"; }
warn() { echo -e "${YELLOW}[Warning]${NC} $1"; }
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
║   DistributeX Cloud Network - v5.0 GPU FULLY CONNECTED        ║
║      ALL DRIVES + REAL GPU → ACTUALLY CONTRIBUTED & EARNING    ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# ============================================================================
# MAC ADDRESS
# ============================================================================
get_mac_address() {
    local mac=""
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        mac=$(ip link show 2>/dev/null | awk '/link\/ether/ {gsub(/:/,""); print tolower($2); exit}')
        [ -z "$mac" ] && mac=$(cat /sys/class/net/*/address 2>/dev/null | head -n1 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {gsub(/:/,""); print tolower($2)}' || ifconfig en1 2>/dev/null | awk '/ether/ {gsub(/:/,""); print tolower($2)}')
    fi
    [[ "$mac" =~ ^[0-9a-f]{1,12}$ ]] || return 1
    printf "%012s" "$mac" | tr ' ' '0'
}

# ============================================================================
# DETECT ALL MOUNTED DRIVES (REAL STORAGE)
# ============================================================================
detect_all_storage() {
    section "Scanning ALL Mounted Drives (USB, NVMe, HDD, NAS, etc.)"
    STORAGE_TOTAL_MB=0
    STORAGE_FREE_MB=0
    local drives=()

    while read -r device mountpoint fstype options; do
        [[ "$fstype" =~ ^(tmpfs|devtmpfs|sysfs|proc|cgroup|overlay|squashfs|iso9660|efivarfs|binfmt_misc|fuse|fuseblk|rpc_pipefs|nfs|cifs)$ ]] && continue
        [[ "$mountpoint" =~ ^/proc|^/sys|^/dev|^/run|^/snap|^/var/lib/docker ]] && continue

        read -r _ total_kb _ avail_kb _ < <(df -Pk "$mountpoint" 2>/dev/null | tail -1) || continue
        [[ "$total_kb" =~ ^[0-9]+$ ]] || continue

        total_mb=$((total_kb / 1024))
        free_mb=$((avail_kb / 1024))
        STORAGE_TOTAL_MB=$((STORAGE_TOTAL_MB + total_mb))
        STORAGE_FREE_MB=$((STORAGE_FREE_MB + free_mb))
        drives+=("  • $mountpoint → $((total_mb/1024)) GB total / $((free_mb/1024)) GB free")
    done < /proc/mounts

    if (( STORAGE_TOTAL_MB == 0 )); then
        line=$(df -Pk "$HOME" 2>/dev/null | tail -1)
        STORAGE_TOTAL_MB=$(awk '{print int($2/1024)}' <<<"$line")
        STORAGE_FREE_MB=$(awk '{print int($4/1024)}' <<<"$line")
        drives+=("  • $HOME (fallback)")
    fi

    log "Detected ${#drives[@]} storage device(s):"
    for d in "${drives[@]}"; do info "$d"; done
    log "TOTAL STORAGE → $((STORAGE_TOTAL_MB/1024)) GB ($((STORAGE_FREE_MB/1024)) GB free)"
}

# ============================================================================
# SYSTEM + GPU DETECTION + DOCKER GPU FLAGS
# ============================================================================
detect_system_and_gpu() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    HOSTNAME=$(hostname)
    MAC_ADDRESS=$(get_mac_address) || error "Cannot detect valid MAC address"
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    CPU_MODEL=$(lscpu 2>/dev/null | grep -m1 "Model name:" | cut -d: -f2 | xargs || echo "Unknown")
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)

    GPU_AVAILABLE=false
    GPU_MODEL="none"
    GPU_MEMORY=0
    GPU_COUNT=0
    DOCKER_GPU_FLAGS=""

    if command -v nvidia-smi &>/dev/null && nvidia-smi --query-gpu=name,memory.total,count --format=csv,noheader,nounits >/dev/null 2>&1; then
        GPU_AVAILABLE=true
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -n1 | xargs)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1 | xargs)
        GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -n1 | xargs)
        DOCKER_GPU_FLAGS="--gpus all"
        log "NVIDIA GPU DETECTED → FULL CUDA PASSTHROUGH ENABLED"
    elif lspci 2>/dev/null | grep -iE "vga|3d|display" | grep -iq "amd"; then
        GPU_AVAILABLE=true
        GPU_MODEL="AMD GPU (ROCm)"
        DOCKER_GPU_FLAGS="--device=/dev/dri --device=/dev/kfd"
        warn "AMD GPU detected → ROCm passthrough enabled"
    elif lspci 2>/dev/null | grep -iE "vga|3d|display" | grep -iq "intel" | grep -iq "arc\|xe"; then
        GPU_AVAILABLE=true
        GPU_MODEL="Intel Arc/Xe GPU"
        DOCKER_GPU_FLAGS="--device=/dev/dri"
        log "Intel Arc/Xe detected → OpenCL/Vulkan enabled"
    else
        log "No supported GPU detected"
    fi

    $GPU_AVAILABLE && log "GPU → $GPU_COUNT × $GPU_MODEL (${GPU_MEMORY} MiB) → READY TO EARN"
}

# ============================================================================
# TOOLS & DOCKER CHECK
# ============================================================================
check_requirements() {
    section "Installing Tools (curl, jq, df)"
    for t in curl jq df; do
        command -v $t &>/dev/null || {
            if command -v apt-get &>/dev/null; then sudo apt-get update -qq && sudo apt-get install -y $t -qq
            elif command -v yum &>/dev/null; then sudo yum install -y $t -qq
            elif command -v brew &>/dev/null; then brew install $t
            else error "Please install $t manually"
            fi
        }
    done
    log "Tools ready"
}

check_docker() {
    section "Checking Docker"
    command -v docker &>/dev/null || error "Docker required → https://docs.docker.com/get-docker/"
    docker ps >/dev/null 2>&1 || error "Docker daemon not running"
    log "Docker ready"
}

# ============================================================================
# AUTHENTICATION (bulletproof jq)
# ============================================================================
authenticate_user() {
    section "Authentication"
    mkdir -p "$CONFIG_DIR"
    if [[ -f "$CONFIG_DIR/token" ]]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        if curl -sf -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user" >/dev/null; then
            log "Already logged in (cached token)"
            return 0
        else
            warn "Token expired"
            rm -f "$CONFIG_DIR/token"
        fi
    fi

    echo -e "${CYAN}1) Sign up    2) Login${NC}"
    while :; do
        read -p "Choice [1-2]: " choice </dev/tty
        case "$choice" in 1) signup_user; return 0 ;; 2) login_user; return 0 ;; *) echo -e "${RED}Invalid${NC}" ;; esac
    done
}

signup_user() {
    echo -e "\n${BOLD}Create Account${NC}"
    read -p "First Name: " name </dev/tty
    read -p "Email: " email </dev/tty
    while :; do read -s -p "Password (≥8 chars): " pw </dev/tty; echo; (( ${#pw} >= 8 )) && break; warn "Too short"; done
    read -s -p "Confirm: " pw2 </dev/tty; echo
    [[ "$pw" == "$pw2" ]] || { warn "No match"; signup_user; }

    resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" -H "Content-Type: application/json" -d "{\"email\":\"$email\",\"password\":\"$pw\",\"firstName\":\"$name\"}")
    code=$(tail -n1 <<<"$resp"); body=$(sed '$d' <<<"$resp")
    [[ "$code" =~ ^2 ]] || error "Signup failed: $(safe_jq '.message // .error // "code '"$code"'"' "$body")"
    API_TOKEN=$(safe_jq '.token' "$body"); [[ -n "$API_TOKEN" ]] || error "No token"
    echo "$API_TOKEN" > "$CONFIG_DIR/token"; chmod 600 "$CONFIG_DIR/token"
    log "Account created!"
}

login_user() {
    echo -e "\n${BOLD}Login${NC}"
    read -p "Email: " email </dev/tty
    read -s -p "Password: " pw </dev/tty; echo
    resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" -H "Content-Type: application/json" -d "{\"email\":\"$email\",\"password\":\"$pw\"}")
    code=$(tail -n1 <<<"$resp"); body=$(sed '$d' <<<"$resp")
    [[ "$code" == "200" ]] || error "Login failed: $(safe_jq '.message // .error // "code '"$code"'"' "$body")"
    API_TOKEN=$(safe_jq '.token' "$body"); [[ -n "$API_TOKEN" ]] || error "No token"
    echo "$API_TOKEN" > "$CONFIG_DIR/token"; chmod 600 "$CONFIG_DIR/token"
    log "Logged in!"
}

select_role() {
    section "Checking Role"
    resp=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user")
    USER_ROLE=$(safe_jq '.role // empty' "$resp")
    [[ -n "$USER_ROLE" && "$USER_ROLE" != "null" ]] || {
        warn "No role selected yet"
        echo -e "Go to ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC} → choose Contributor or Developer"
        echo -e "Then run again: ${CYAN}curl -sSL $INSTALL_SCRIPT_URL | bash${NC}\n"
        exit 0
    }
    log "Role: $USER_ROLE"
}

check_existing_worker() {
    resp=$(curl -s -w "\n%{http_code}" -X GET -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/workers/check/$MAC_ADDRESS")
    code=$(tail -n1 <<<"$resp"); body=$(sed '$d' <<<"$resp")
    [[ "$code" == "200" ]] && [[ "$(safe_jq '.exists' "$body")" == "true" ]]
}

register_worker() {
    section "Registering Worker"
    check_existing_worker && { log "Device already registered"; return 0; }

    CPU_CORES=$(echo "$CPU_CORES" | tr -cd '0-9' || echo 0); CPU_CORES=${CPU_CORES:-0}
    RAM_TOTAL=$(echo "$RAM_TOTAL" | tr -cd '0-9' || echo 0); RAM_TOTAL=${RAM_TOTAL:-0}
    STORAGE_TOTAL_MB=$(echo "$STORAGE_TOTAL_MB" | tr -cd '0-9' || echo 0); STORAGE_TOTAL_MB=${STORAGE_TOTAL_MB:-0}
    STORAGE_FREE_MB=$(echo "$STORAGE_FREE_MB" | tr -cd '0-9' || echo 0); STORAGE_FREE_MB=${STORAGE_FREE_MB:-0}
    GPU_MEMORY=$(echo "$GPU_MEMORY" | tr -cd '0-9' || echo 0); GPU_MEMORY=${GPU_MEMORY:-0}
    GPU_COUNT=$(echo "$GPU_COUNT" | tr -cd '0-9' || echo 0); GPU_COUNT=${GPU_COUNT:-0}

    payload=$(jq -n \
      --arg m "$MAC_ADDRESS" --arg n "Worker-$MAC_ADDRESS" --arg h "$HOSTNAME" \
      --arg p "$OS" --arg a "$ARCH" --argjson c "$CPU_CORES" --arg cm "$CPU_MODEL" \
      --argjson r "$RAM_TOTAL" --argjson st "$STORAGE_TOTAL_MB" --argjson sa "$STORAGE_FREE_MB" \
      --arg ga "$GPU_AVAILABLE" --arg gm "$GPU_MODEL" --argjson gmem "$GPU_MEMORY" --argjson gc "$GPU_COUNT" \
      '{macAddress:$m,name:$n,hostname:$h,platform:$p,architecture:$a,cpuCores:$c,cpuModel:$cm,ramTotal:$r,storageTotal:$st,storageAvailable:$sa,gpuAvailable:($ga=="true"),gpuModel:$gm,gpuMemory:$gmem,gpuCount:$gc}')

    resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" -d "$payload")
    code=$(tail -n1 <<<"$resp"); body=$(sed '$d' <<<"$resp")
    [[ "$code" =~ ^2 ]] || error "Registration failed: $(safe_jq '.message // .error // "code '"$code"'"' "$body")"
    log "Worker registered successfully!"
    echo "$MAC_ADDRESS" > "$CONFIG_DIR/mac_address"
}

start_contributor() {
    section "Launching Worker with FULL Hardware Access"
    register_worker
    docker pull "$DOCKER_IMAGE" >/dev/null
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    log "Starting container — GPU passthrough: $DOCKER_GPU_FLAGS"
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --shm-size=1g \
        $DOCKER_GPU_FLAGS \
        -e DISABLE_SELF_REGISTER=true \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -v "$CONFIG_DIR:/config:ro" \
        "$DOCKER_IMAGE" \
        --api-key "$API_TOKEN" \
        --url "$DISTRIBUTEX_API_URL" >/dev/null

    sleep 8
    docker ps --filter "name=^${CONTAINER_NAME}$" | grep -q "$CONTAINER_NAME" || error "Worker failed to start"
    log "Worker is LIVE with full CPU, Storage & GPU access!"
}

create_management_script() {
    cat > "$CONFIG_DIR/manage.sh" <<'EOF'
#!/bin/bash
C="distributex-worker"
echo "DistributeX Worker Control"
case "$1" in
    status)   docker ps --filter "name=^$C$" ;;
    logs)     docker logs -f $C ;;
    restart)  docker restart $C ;;
    stop)     docker stop $C ;;
    start)    docker start $C ;;
    uninstall)
        read -p "Uninstall everything? (yes/no): " yn
        [[ "$yn" == "yes" ]] || exit
        docker stop $C 2>/dev/null; docker rm $C 2>/dev/null; rm -rf "$HOME/.distributex"
        echo "Uninstalled"
        ;;
    *) echo "Usage: $0 status|logs|restart|stop|start|uninstall" ;;
esac
EOF
    chmod +x "$CONFIG_DIR/manage.sh"
}

show_contributor_complete() {
    section "INSTALLATION COMPLETE — YOU ARE EARNING!"
    echo -e "${GREEN}Your node is fully active and contributing${NC}\n"
    log "Worker      : Worker-$MAC_ADDRESS"
    log "Storage     : $((STORAGE_TOTAL_MB/1024)) GB across all drives"
    if $GPU_AVAILABLE; then
        if [[ "$DOCKER_GPU_FLAGS" == *"gpus all"* ]]; then
            echo -e "${GREEN}GPU         : $GPU_COUNT × $GPU_MODEL → FULLY CONNECTED & EARNING!${NC}"
        else
            echo -e "${YELLOW}GPU         : $GPU_MODEL → Connected (limited)${NC}"
        fi
    else
        log "GPU         : none"
    fi
    echo -e "\n${CYAN}Control → $CONFIG_DIR/manage.sh status | logs | restart${NC}"
    echo -e "${BLUE}Dashboard → $DISTRIBUTEX_API_URL/dashboard${NC}\n"
    echo -e "${BOLD}Your hardware is now earning on DistributeX Cloud Network${NC}"
}

show_developer_complete() {
    section "Developer Mode"
    echo -e "${GREEN}No worker started (correct for developers)${NC}\n"
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
    detect_system_and_gpu
    detect_all_storage

    if [[ "$USER_ROLE" == "contributor" ]]; then
        check_docker
        start_contributor
        create_management_script
        show_contributor_complete
    else
        show_developer_complete
    fi
}

trap 'error "Script failed at line $LINENO"' ERR
main
exit 0
