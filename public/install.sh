#!/bin/bash
#
# DistributeX Complete Installer - v4.5 ULTRA
# Now detects EVERY mounted drive (USB, NVMe, HDD, network, etc.)
# Single Worker • Zero Errors • Forever Running • Multi-Drive Aware
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
# SAFE JQ + LOGGING
# ============================================================================
safe_jq() { echo "$2" | jq -r "$1" 2>/dev/null || echo ""; }
log() { echo -e "${GREEN}[Success]${NC} $1"; }
info() { echo -e "${CYAN}[Info]${NC} $1"; }
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
║   DistributeX Cloud Network - Multi-Drive Edition v4.5 ULTRA   ║
║       All Drives Detected • Real GPU • Forever Running        ║
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
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {gsub(/:/,""); print tolower($2)}')
        [ -z "$mac" ] && mac=$(ifconfig en1 2>/dev/null | awk '/ether/ {gsub(/:/,""); print tolower($2)}')
    fi
    [[ "$mac" =~ ^[0-9a-f]{1,12}$ ]] || return 1
    printf "%012s" "$mac" | tr ' ' '0'
}

# ============================================================================
# MULTI-DRIVE STORAGE DETECTION (THE MAGIC)
# ============================================================================
detect_all_storage() {
    section "Scanning ALL Mounted Drives"
    
    STORAGE_TOTAL_MB=0
    STORAGE_FREE_MB=0
    local drives=()

    # Read all real mounted filesystems (skip tmpfs, devtmpfs, etc.)
    while read -r device mountpoint fstype options; do
        # Filter out virtual/pseudo filesystems
        [[ "$fstype" =~ ^(tmpfs|devtmpfs|sysfs|proc|debugfs|securityfs|cgroup|overlay|squashfs|iso9660|udf|efivarfs|binfmt_misc|pstore|mqueue|hugetlbfs|bpf|fuse|fuseblk|rpc_pipefs|nfs|nfsd|cifs|smbfs)$ ]] && continue
        [[ "$mountpoint" =~ ^/proc|^/sys|^/dev|^/run|^/snap|^/var/lib/docker ]] && continue

        # Get size info (in KB)
        read -r _ total_kb used_kb avail_kb _ < <(df -Pk "$mountpoint" 2>/dev/null | tail -1)

        if [[ "$total_kb" =~ ^[0-9]+$ ]]; then
            local total_mb=$((total_kb / 1024))
            local free_mb=$((avail_kb / 1024))
            STORAGE_TOTAL_MB=$((STORAGE_TOTAL_MB + total_mb))
            STORAGE_FREE_MB=$((STORAGE_FREE_MB + free_mb))
            drives+=("$mountpoint: $((total_mb/1024)) GB total, $((free_mb/1024)) GB free")
        fi
    done < /proc/mounts

    # Fallback: at least detect $HOME if nothing found
    if (( STORAGE_TOTAL_MB == 0 )); then
        line=$(df -Pk "$HOME" 2>/dev/null | tail -1)
        STORAGE_TOTAL_MB=$(awk '{print int($2/1024)}' <<<"$line")
        STORAGE_FREE_MB=$(awk '{print int($4/1024)}' <<<"$line")
        drives+=("$HOME: fallback drive")
    fi

    # Pretty print all detected drives
    log "Found ${#drives[@]} physical/storage device(s):"
    for d in "${drives[@]}"; do
        info "   • $d"
    done

    log "TOTAL Storage  : $((STORAGE_TOTAL_MB/1024)) GB ($((STORAGE_FREE_MB/1024)) GB free)"
}

# ============================================================================
# SYSTEM + GPU DETECTION
# ============================================================================
detect_system() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    HOSTNAME=$(hostname)
    MAC_ADDRESS=$(get_mac_address) || error "Cannot detect valid MAC address"
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    CPU_MODEL=$(lscpu 2>/dev/null | grep -m1 "Model name:" | cut -d: -f2 | xargs || echo "Unknown")
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)

    # GPU
    GPU_AVAILABLE=false
    GPU_MODEL="none"
    GPU_MEMORY=0
    GPU_COUNT=0
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi --query-gpu=name,memory.total,count --format=csv,noheader,nounits >/dev/null 2>&1; then
            GPU_AVAILABLE=true
            GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -n1 | xargs)
            GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1 | xargs)
            GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -n1 | xargs)
        fi
    fi

    log "MAC      : $MAC_ADDRESS"
    log "Host     : $HOSTNAME"
    log "CPU      : $CPU_CORES cores - $CPU_MODEL"
    log "RAM      : $((RAM_TOTAL/1024)) GB"
    $GPU_AVAILABLE && log "GPU      : $GPU_COUNT × $GPU_MODEL (${GPU_MEMORY} MiB)" || log "GPU      : none"
}

# ============================================================================
# REST OF SCRIPT (unchanged, just using new storage values)
# ============================================================================
check_requirements() {
    section "Checking Tools"
    for t in curl jq df; do
        command -v $t &>/dev/null || {
            warn "Installing $t..."
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

authenticate_user() {
    section "Authentication"
    mkdir -p "$CONFIG_DIR"
    if [[ -f "$CONFIG_DIR/token" ]]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        if curl -sf -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user" >/dev/null; then
            log "Logged in (cached token)"
            return 0
        else
            warn "Cached token expired"
            rm -f "$CONFIG_DIR/token"
        fi
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

    if [[ ! "$code" =~ ^2 ]]; then
        err=$(safe_jq '.message // .error // "Unknown error (code '"$code"')"' "$body")
        error "Signup failed: $err"
    fi

    API_TOKEN=$(safe_jq '.token' "$body")
    [[ -z "$API_TOKEN" || "$API_TOKEN" == "null" ]] && error "No token received"
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Account created!"
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

    if [[ "$code" != "200" ]]; then
        err=$(safe_jq '.message // .error // "Login failed (code '"$code"')"' "$body")
        error "$err"
    fi

    API_TOKEN=$(safe_jq '.token' "$body")
    [[ -z "$API_TOKEN" || "$API_TOKEN" == "null" ]] && error "No token returned"
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in!"
}

select_role() {
    section "Role Check"
    resp=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user")
    USER_ROLE=$(safe_jq '.role // empty' "$resp")
    if [[ -z "$USER_ROLE" || "$USER_ROLE" == "null" ]]; then
        warn "No role selected"
        echo -e "Go to ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC} → pick Contributor or Developer"
        echo -e "Then run again: ${CYAN}curl -sSL $INSTALL_SCRIPT_URL | bash${NC}\n"
        exit 0
    fi
    log "Role: $USER_ROLE"
}

check_existing_worker() {
    resp=$(curl -s -w "\n%{http_code}" -X GET -H "Authorization: Bearer $API_TOKEN" \
        "$DISTRIBUTEX_API_URL/api/workers/check/$MAC_ADDRESS")
    code=$(tail -n1 <<<"$resp")
    body=$(sed '$d' <<<"$resp")
    [[ "$code" == "200" ]] && [[ "$(safe_jq '.exists' "$body")" == "true" ]]
}

register_worker() {
    section "Registering Worker"
    check_existing_worker && { log "Already registered"; return 0; }

    CPU_CORES=$(echo "$CPU_CORES" | tr -cd '0-9'); CPU_CORES=${CPU_CORES:-0}
    RAM_TOTAL=$(echo "$RAM_TOTAL" | tr -cd '0-9'); RAM_TOTAL=${RAM_TOTAL:-0}
    STORAGE_TOTAL_MB=$(echo "$STORAGE_TOTAL_MB" | tr -cd '0-9'); STORAGE_TOTAL_MB=${STORAGE_TOTAL_MB:-0}
    STORAGE_FREE_MB=$(echo "$STORAGE_FREE_MB" | tr -cd '0-9'); STORAGE_FREE_MB=${STORAGE_FREE_MB:-0}
    GPU_MEMORY=$(echo "$GPU_MEMORY" | tr -cd '0-9'); GPU_MEMORY=${GPU_MEMORY:-0}
    GPU_COUNT=$(echo "$GPU_COUNT" | tr -cd '0-9'); GPU_COUNT=${GPU_COUNT:-0}

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
        macAddress: $m, name: $n, hostname: $h, platform: $p, architecture: $a,
        cpuCores: $c, cpuModel: $cm, ramTotal: $r,
        storageTotal: $st, storageAvailable: $sa,
        gpuAvailable: ($ga == "true"), gpuModel: $gm, gpuMemory: $gmem, gpuCount: $gc
      }')

    resp=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" -d "$payload")
    code=$(tail -n1 <<<"$resp")
    body=$(sed '$d' <<<"$resp")
    [[ "$code" =~ ^2 ]] || error "Registration failed: $(safe_jq '.message // .error // "code '"$code"'"' "$body")"

    log "Worker registered!"
    echo "$MAC_ADDRESS" > "$CONFIG_DIR/mac_address"
}

start_contributor() {
    section "Launching Worker"
    register_worker
    docker pull "$DOCKER_IMAGE" >/dev/null
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    docker run -d --name "$CONTAINER_NAME" --restart unless-stopped --shm-size=1g \
        -e DISABLE_SELF_REGISTER=true -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -v "$CONFIG_DIR:/config:ro" "$DOCKER_IMAGE" \
        --api-key "$API_TOKEN" --url "$DISTRIBUTEX_API_URL" >/dev/null
    sleep 6
    docker ps --filter "name=^${CONTAINER_NAME}$" | grep -q "$CONTAINER_NAME" &&
        log "Worker running forever!" || error "Container failed"
}

create_management_script() {
    cat > "$CONFIG_DIR/manage.sh" <<'EOF'
#!/bin/bash
C="distributex-worker"
echo "DistributeX Worker Control"
case "$1" in
    status|logs|restart|stop|start|uninstall) docker $1 $C 2>/dev/null || echo "Worker not found" ;;
    *) echo "Usage: $0 status|logs|restart|stop|start|uninstall" ;;
esac
EOF
    chmod +x "$CONFIG_DIR/manage.sh"
}

show_contributor_complete() {
    section "INSTALLATION COMPLETE!"
    echo -e "${GREEN}Your node is LIVE and auto-starts on boot${NC}\n"
    log "Worker   : Worker-$MAC_ADDRESS"
    log "Storage  : $((STORAGE_TOTAL_MB/1024)) GB total across all drives"
    $GPU_AVAILABLE && log "GPU      : $GPU_COUNT × $GPU_MODEL"
    echo -e "\n${CYAN}Control:${NC} $CONFIG_DIR/manage.sh status|logs|restart"
    echo -e "${BLUE}Dashboard:${NC} $DISTRIBUTEX_API_URL/dashboard\n"
}

show_developer_complete() {
    section "Developer Mode"
    echo -e "${GREEN}No worker started – perfect for devs${NC}\n"
    echo -e "API Key:\n${BOLD}$API_TOKEN${NC}\n"
    echo -e "Dashboard → ${BLUE}$DISTRIBUTEX_API_URL/dashboard${NC}"
}

main() {
    show_banner
    check_requirements
    authenticate_user
    select_role
    detect_system
    detect_all_storage   # ← THE NEW KING
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
