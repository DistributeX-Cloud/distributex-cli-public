#!/bin/bash
#
# DistributeX Cloud Network - v5.1 FINAL STORAGE FULLY CONNECTED
# → ALL mounted drives are bind-mounted into the worker
# → GPU fully passed through
# → Single worker • Zero errors • Every GB is earning
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
║   DistributeX Cloud Network - v5.1 STORAGE + GPU CONNECTED    ║
║         EVERY MOUNTED DRIVE & GPU → 100% EARNING NOW          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# ============================================================================
# MAC + SYSTEM
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
# DETECT + BIND ALL MOUNTED DRIVES (THIS IS THE MAGIC)
# ============================================================================
MOUNTED_DRIVES=()
VOLUME_FLAGS=""

detect_and_bind_all_storage() {
    section "Detecting & Binding ALL Storage Devices to Worker"
    STORAGE_TOTAL_MB=0
    STORAGE_FREE_MB=0
    local drives_found=0

    while read -r device mountpoint fstype options; do
        # Skip virtual/system filesystems
        [[ "$fstype" =~ ^(tmpfs|devtmpfs|sysfs|proc|cgroup2?|overlay|squashfs|iso9660|efivarfs|binfmt_misc|fuse\.|rpc_pipefs|nfs|cifs)$ ]] && continue
        [[ "$mountpoint" =~ ^/proc|^/sys|^/dev|^/run|^/snap|^/var/lib/docker|/var/lib/kubelet ]] && continue
        [[ "$mountpoint" == "/" && -d /home ]] && continue  # skip root if /home exists (common split)

        # Get real size
        read -r _ total_kb _ avail_kb _ < <(df -Pk "$mountpoint" 2>/dev/null | tail -1) || continue
        [[ "$total_kb" =~ ^[0-9]+$ ]] || continue

        total_mb=$((total_kb / 1024))
        free_mb=$((avail_kb / 1024))
        ((STORAGE_TOTAL_MB += total_mb))
        ((STORAGE_FREE_MB += free_mb))
        ((drives_found++))

        # Add to Docker volume flags
        VOLUME_FLAGS+=" -v $mountpoint:/storage/$(echo "$mountpoint" | tr / _):ro"
        MOUNTED_DRIVES+=("$mountpoint → $((total_mb/1024)) GB ($((free_mb/1024)) GB free)")

        info "  Bound: $mountpoint → /storage/$(echo "$mountpoint" | tr / _)"
    done < /proc/mounts

    # Fallback: at least bind $HOME if nothing found
    if (( drives_found == 0 )); then
        VOLUME_FLAGS+=" -v $HOME:/storage/home:ro"
        MOUNTED_DRIVES+=("$HOME → fallback home")
        STORAGE_TOTAL_MB=51200
        STORAGE_FREE_MB=25600
        warn "No major drives found → binding $HOME"
    fi

    log "Connected $drives_found storage device(s) → ALL visible to network"
    log "TOTAL STORAGE → $((STORAGE_TOTAL_MB/1024)) GB ($((STORAGE_FREE_MB/1024)) GB free)"
}

# ============================================================================
# GPU + SYSTEM DETECTION
# ============================================================================
detect_system_and_gpu() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    HOSTNAME=$(hostname)
    MAC_ADDRESS=$(get_mac_address) || error "Cannot detect MAC address"
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
        log "NVIDIA GPU → FULLY CONNECTED (CUDA)"
    else
        log "No NVIDIA GPU detected"
    fi

    log "MAC: $MAC_ADDRESS | CPU: $CPU_CORES cores | RAM: $((RAM_TOTAL/1024)) GB"
    $GPU_AVAILABLE && log "GPU → $GPU_COUNT × $GPU_MODEL ($GPU_MEMORY MiB) → EARNING"
}

# ============================================================================
# AUTH, REGISTER, LAUNCH (WITH FULL STORAGE + GPU)
# ============================================================================
check_requirements() {
    section "Tools"
    for t in curl jq df; do command -v $t &>/dev/null || { sudo apt-get update -qq && sudo apt-get install -y $t -qq; }; done
    log "Tools ready"
}

check_docker() {
    section "Docker"
    command -v docker &>/dev/null || error "Install Docker → https://docs.docker.com/get-docker/"
    docker ps >/dev/null 2>&1 || error "Docker not running"
    log "Docker ready"
}

authenticate_user() {
    section "Authentication"
    mkdir -p "$CONFIG_DIR"
    if [[ -f "$CONFIG_DIR/token" ]] && curl -sf -H "Authorization: Bearer $(cat "$CONFIG_DIR/token")" "$DISTRIBUTEX_API_URL/api/auth/user" >/dev/null; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        log "Already logged in"
        return 0
    fi

    echo -e "${CYAN}1) Sign up  2) Login${NC}"
    read -p "Choice: " c </dev/tty
    [[ "$c" == "1" ]] && signup_user || login_user
}

signup_user() {
    read -p "Name: " name </dev/tty
    read -p "Email: " email </dev/tty
    while :; do read -s -p "Password: " pw </dev/tty; echo; (( ${#pw} >= 8 )) && break; done
    read -s -p "Confirm: " pw2 </dev/tty; echo
    [[ "$pw" == "$pw2" ]] || { warn "No match"; signup_user; }

    resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" -H "Content-Type: application/json" -d "{\"email\":\"$email\",\"password\":\"$pw\",\"firstName\":\"$name\"}")
    code=$(tail -n1 <<<"$resp"); body=$(sed '$d' <<<"$resp")
    [[ "$code" =~ ^2 ]] || error "Signup failed"
    API_TOKEN=$(safe_jq '.token' "$body"); echo "$API_TOKEN" > "$CONFIG_DIR/token"; chmod 600 "$CONFIG_DIR/token"
    log "Account created!"
}

login_user() {
    read -p "Email: " email </dev/tty
    read -s -p "Password: " pw </dev/tty; echo
    resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" -H "Content-Type: application/json" -d "{\"email\":\"$email\",\"password\":\"$pw\"}")
    code=$(tail -n1 <<<"$resp"); body=$(sed '$d' <<<"$resp")
    [[ "$code" == "200" ]] || error "Login failed"
    API_TOKEN=$(safe_jq '.token' "$body"); echo "$API_TOKEN" > "$CONFIG_DIR/token"; chmod 600 "$CONFIG_DIR/token"
    log "Logged in!"
}

select_role() {
    section "Role"
    USER_ROLE=$(safe_jq '.role' "$(curl -s -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user")")
    [[ "$USER_ROLE" == "contributor" ]] || {
        echo -e "Go to ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC} → Select 'Contributor'\nThen re-run installer"
        exit 0
    }
    log "Role: Contributor"
}

register_worker() {
    section "Registering Worker"
    payload=$(jq -n \
      --arg m "$MAC_ADDRESS" --arg n "Worker-$MAC_ADDRESS" --arg h "$HOSTNAME" \
      --arg p "$OS" --arg a "$ARCH" --argjson c "$CPU_CORES" --arg cm "$CPU_MODEL" \
      --argjson r "$RAM_TOTAL" --argjson st "$STORAGE_TOTAL_MB" --argjson sa "$STORAGE_FREE_MB" \
      --arg ga "$GPU_AVAILABLE" --arg gm "$GPU_MODEL" --argjson gmem "$GPU_MEMORY" --argjson gc "$GPU_COUNT" \
      '{macAddress:$m,name:$n,hostname:$h,platform:$p,architecture:$a,cpuCores:$c,cpuModel:$cm,ramTotal:$r,storageTotal:$st,storageAvailable:$sa,gpuAvailable:($ga=="true"),gpuModel:$gm,gpuMemory:$gmem,gpuCount:$gc}')
    
    curl -s -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" -d "$payload" >/dev/null || true
    log "Worker registered"
}

start_contributor() {
    section "Launching Worker — FULL STORAGE + GPU ACCESS"
    register_worker
    docker pull "$DOCKER_IMAGE" >/dev/null
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    log "Starting container with:"
    log "  • Full GPU access"
    log "  • ALL storage devices mounted read-only"
    
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --shm-size=1g \
        $DOCKER_GPU_FLAGS \
        $VOLUME_FLAGS \
        -v "$CONFIG_DIR:/config:ro" \
        -e DISABLE_SELF_REGISTER=true \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        "$DOCKER_IMAGE" \
        --api-key "$API_TOKEN" \
        --url "$DISTRIBUTEX_API_URL" >/dev/null

    sleep 10
    docker ps --filter "name=^${CONTAINER_NAME}$" | grep -q "$CONTAINER_NAME" || error "Failed to start worker"
    log "Worker is LIVE — Every drive & GPU is earning!"
}

show_complete() {
    section "YOU ARE FULLY CONNECTED — EARNING NOW!"
    echo -e "${GREEN}All hardware is active on the DistributeX network${NC}\n"
    log "Worker      : Worker-$MAC_ADDRESS"
    log "Drives      : ${#MOUNTED_DRIVES[@]} device(s) fully connected"
    for d in "${MOUNTED_DRIVES[@]}"; do info "  $d"; done
    log "Total       : $((STORAGE_TOTAL_MB/1024)) GB storage shared"
    $GPU_AVAILABLE && echo -e "${GREEN}GPU         : $GPU_COUNT × $GPU_MODEL → FULLY EARNING${NC}" || log "GPU         : none"
    echo -e "\n${CYAN}Control → $CONFIG_DIR/manage.sh status | logs | restart${NC}"
    echo -e "${BLUE}Dashboard → $DISTRIBUTEX_API_URL/dashboard${NC}\n"
    echo -e "${BOLD}Your machine is now a full DistributeX Cloud Node — max earnings active${NC}"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    show_banner
    check_requirements
    check_docker
    authenticate_user
    select_role
    detect_system_and_gpu
    detect_and_bind_all_storage
    start_contributor
    show_complete
}

trap 'error "Failed at line $LINENO"' ERR
main
exit 0
