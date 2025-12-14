#!/bin/bash
# DistributeX Universal Installer v8.2 - FIXED DNS RESOLUTION
# Key fixes:
# 1. Removed --network host (causes DNS issues)
# 2. Added proper DNS configuration
# 3. Better error handling

set -e

# CONFIG
API_URL="${DISTRIBUTEX_API_URL:-https://distributex.cloud}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"; }
safe_jq() { echo "$2" | jq -r "$1" 2>/dev/null || echo ""; }

# ============================================================================
# BANNER
# ============================================================================
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"

 ██████╗ ██╗███████╗████████╗██████╗ ██╗██████╗ ██╗   ██╗████████╗███████╗██╗  ██╗
 ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║██╔══██╗██║   ██║╚══██╔══╝██╔════╝╚██╗██╔╝
 ██║  ██║██║███████╗   ██║   ██████╔╝██║██████╔╝██║   ██║   ██║   █████╗   ╚███╔╝ 
 ██║  ██║██║╚════██║   ██║   ██╔══██╗██║██╔══██╗██║   ██║   ██║   ██╔══╝   ██╔██╗ 
 ██████╔╝██║███████║   ██║   ██║  ██║██║██████╔╝╚██████╔╝   ██║   ███████╗██╔╝ ██╗
 ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝    ╚═╝   ╚══════╝╚═╝  ╚═╝
 

          ─────────────────── Universal Installer v8.1 ───────────────────
              Smart Role Detection → Contributor or Developer
          ────────────────────────────────────────────────────────────────
EOF
    echo -e "${BOLD}${CYAN}          Welcome! Let's get your node or dev environment ready in seconds.\n${NC}"
}

# ============================================================================
# SYSTEM DETECTION FUNCTIONS
# ============================================================================
get_mac_address() {
    local mac=""
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        mac=$(ip link show 2>/dev/null | awk '/link\/ether/ {gsub(/:/,""); print tolower($2); exit}')
        if [[ -z "$mac" ]]; then
            for iface in /sys/class/net/*; do
                [[ -f "$iface/address" ]] || continue
                local addr=$(cat "$iface/address" | tr -d ':' | tr '[:upper:]' '[:lower:]')
                if [[ "$addr" =~ ^[0-9a-f]{12}$ ]] && [[ "$addr" != "000000000000" ]]; then
                    mac="$addr"
                    break
                fi
            done
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        for iface in en0 en1 en2; do
            mac=$(ifconfig $iface 2>/dev/null | awk '/ether/ {gsub(/:/,""); print tolower($2)}')
            [[ -n "$mac" ]] && [[ "$mac" != "000000000000" ]] && break
        done
    fi

    if [[ ! "$mac" =~ ^[0-9a-f]{12}$ ]] || [[ "$mac" == "000000000000" ]]; then
        error "Cannot detect valid MAC address"
    fi
    echo "$mac"
}

detect_cpu() {
    local cores=0
    local model="Unknown CPU"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
        model=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | xargs || echo "Unknown CPU")
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
        model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
    fi
    echo "$cores|$model"
}

detect_ram() {
    local total_mb=0 available_mb=0
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        total_mb=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
        available_mb=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo || echo "$total_mb")
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        total_mb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
        available_mb=$((total_mb * 7 / 10))
    fi
    [[ $total_mb -eq 0 ]] && total_mb=8192
    echo "$total_mb|$available_mb"
}

detect_gpu() {
    local has="false" model="None" memory=0 count=0 driver="" cuda=""
    if command -v nvidia-smi &>/dev/null; then
        local out=$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "")
        if [[ -n "$out" ]]; then
            has="true"
            count=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | wc -l | xargs)
            model=$(echo "$out" | cut -d',' -f1 | xargs)
            memory=$(echo "$out" | cut -d',' -f2 | xargs)
            driver=$(echo "$out" | cut -d',' -f3 | xargs)
            cuda=$(nvcc --version 2>/dev/null | grep "release" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "")
        fi
    elif command -v rocm-smi &>/dev/null; then
        has="true"
        model="AMD ROCm GPU"
        count=1
    fi
    echo "$has|$model|$memory|$count|$driver|$cuda"
}

detect_storage() {
    local total_mb=0 available_mb=0
    if df -m / &>/dev/null; then
        read total_mb available_mb <<< $(df -m / | awk 'NR==2 {print $2" "$4}')
    else
        total_mb=102400
        available_mb=51200
    fi
    echo "$total_mb|$available_mb"
}

detect_platform() {
    case "$OSTYPE" in
        linux-gnu*) echo "linux" ;;
        darwin*)    echo "darwin" ;;
        msys*|cygwin*) echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

detect_architecture() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)     echo "x64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l)     echo "armv7" ;;
        *)          echo "$arch" ;;
    esac
}

detect_full_system() {
    section "Detecting System Resources"

    MAC_ADDRESS=$(get_mac_address)
    log "MAC Address: $MAC_ADDRESS"

    local cpu=$(detect_cpu)
    CPU_CORES=$(echo "$cpu" | cut -d'|' -f1)
    CPU_MODEL=$(echo "$cpu" | cut -d'|' -f2)
    log "CPU: $CPU_CORES cores — $CPU_MODEL"

    local ram=$(detect_ram)
    RAM_TOTAL=$(echo "$ram" | cut -d'|' -f1)
    RAM_AVAILABLE=$(echo "$ram" | cut -d'|' -f2)
    log "RAM: $((RAM_TOTAL/1024)) GB total ($((RAM_AVAILABLE/1024)) GB available)"

    local gpu=$(detect_gpu)
    GPU_AVAILABLE=$(echo "$gpu" | cut -d'|' -f1)
    GPU_MODEL=$(echo "$gpu" | cut -d'|' -f2)
    GPU_MEMORY=$(echo "$gpu" | cut -d'|' -f3)
    GPU_COUNT=$(echo "$gpu" | cut -d'|' -f4)
    GPU_DRIVER=$(echo "$gpu" | cut -d'|' -f5)
    GPU_CUDA=$(echo "$gpu" | cut -d'|' -f6)

    if [[ "$GPU_AVAILABLE" == "true" ]]; then
        log "GPU: $GPU_COUNT× $GPU_MODEL (${GPU_MEMORY} MB VRAM)"
        [[ -n "$GPU_DRIVER" ]] && info "Driver: $GPU_DRIVER"
        [[ -n "$GPU_CUDA" ]] && info "CUDA: $GPU_CUDA"
    else
        info "No supported GPU detected"
    fi

    local storage=$(detect_storage)
    STORAGE_TOTAL=$(echo "$storage" | cut -d'|' -f1)
    STORAGE_AVAILABLE=$(echo "$storage" | cut -d'|' -f2)
    log "Storage: $((STORAGE_TOTAL/1024)) GB total ($((STORAGE_AVAILABLE/1024)) GB free)"

    PLATFORM=$(detect_platform)
    ARCH=$(detect_architecture)
    HOSTNAME=$(hostname || echo "unknown")

    log "Platform: $PLATFORM / $ARCH"
    log "Hostname: $HOSTNAME"

    echo
}

# ============================================================================
# AUTHENTICATION
# ============================================================================
authenticate_user() {
    section "Authentication"
    mkdir -p "$CONFIG_DIR"

    if [[ -f "$CONFIG_DIR/token" ]]; then
        local token=$(cat "$CONFIG_DIR/token")
        local resp=$(curl -s -H "Authorization: Bearer $token" "$API_URL/api/auth/user" 2>/dev/null || echo "{}")
        local user_id=$(safe_jq '.id' "$resp")

        if [[ -n "$user_id" && "$user_id" != "null" ]]; then
            API_TOKEN="$token"
            USER_EMAIL=$(safe_jq '.email' "$resp")
            USER_ROLE=$(safe_jq '.role' "$resp")
            log "Already logged in as: $USER_EMAIL ($USER_ROLE)"
            return 0
        fi
    fi

    echo -e "${CYAN}1) Login  2) Sign up${NC}"
    read -p "Choice: " choice </dev/tty

    if [[ "$choice" == "1" ]]; then
        login_user
    else
        signup_user
    fi
}

login_user() {
    read -p "Email: " email </dev/tty
    read -s -p "Password: " password </dev/tty
    echo

    local resp=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")

    local code=$(tail -n1 <<<"$resp")
    local body=$(sed '$d' <<<"$resp")

    [[ "$code" != "200" ]] && error "Login failed: $(safe_jq '.message' "$body")"

    API_TOKEN=$(safe_jq '.token' "$body")
    USER_EMAIL=$(safe_jq '.user.email' "$body")
    USER_ROLE=$(safe_jq '.user.role' "$body")

    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in as: $USER_EMAIL"
}

signup_user() {
    read -p "First Name: " first_name </dev/tty
    read -p "Last Name: " last_name </dev/tty
    read -p "Email: " email </dev/tty

    while :; do
        read -s -p "Password (min 8 chars): " password </dev/tty
        echo
        (( ${#password} >= 8 )) && break
        warn "Password too short"
    done

    read -s -p "Confirm password: " password2 </dev/tty
    echo
    [[ "$password" == "$password2" ]] || error "Passwords don't match"

    local resp=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\"}")

    local code=$(tail -n1 <<<"$resp")
    local body=$(sed '$d' <<<"$resp")

    [[ ! "$code" =~ ^2 ]] && error "Signup failed: $(safe_jq '.message' "$body")"

    API_TOKEN=$(safe_jq '.token' "$body")
    USER_EMAIL="$email"
    USER_ROLE=$(safe_jq '.user.role' "$body")

    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Account created and logged in: $USER_EMAIL"
}

# ============================================================================
# ROLE SELECTION
# ============================================================================
select_role() {
    section "Select Your Role"

    if [[ -n "$USER_ROLE" && "$USER_ROLE" != "null" ]]; then
        log "Current role: $USER_ROLE"
        read -p "Change role? (y/N): " change </dev/tty
        [[ "$change" =~ ^[Yy]$ ]] || return 0
    fi

    echo -e "${BOLD}Choose your role:${NC}"
    echo
    echo -e "${GREEN}1) Contributor${NC}   → Share resources & earn"
    echo -e "${BLUE}2) Developer${NC}     → Use the network in your apps"
    echo

    while :; do
        read -p "Enter choice (1 or 2): " role_choice </dev/tty
        case "$role_choice" in
            1) NEW_ROLE="contributor"; break ;;
            2) NEW_ROLE="developer";   break ;;
            *) warn "Please enter 1 or 2" ;;
        esac
    done

    local resp=$(curl -s -X POST "$API_URL/api/auth/update-role" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"role\":\"$NEW_ROLE\"}")

    [[ $(safe_jq '.success' "$resp") != "true" ]] && error "Failed to set role"

    USER_ROLE="$NEW_ROLE"
    local new_token=$(safe_jq '.token' "$resp")
    [[ -n "$new_token" && "$new_token" != "null" ]] && API_TOKEN="$new_token" && echo "$API_TOKEN" > "$CONFIG_DIR/token"

    log "Role set to: $USER_ROLE"
}

# ============================================================================
# CONTRIBUTOR SETUP - FIXED FOR STABILITY
# ============================================================================
setup_contributor() {
    section "Setting Up Contributor Worker"

    # Verify Docker
    command -v docker &>/dev/null || error "Docker not found → https://docs.docker.com/get-docker/"
    docker ps &>/dev/null || error "Docker daemon not running"
    log "Docker ready"

    # Detect system
    detect_full_system

    # Validate API token
    info "Validating API token..."
    local validate_resp=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$API_URL/api/auth/user" 2>/dev/null || echo "{}")
    local validate_id=$(safe_jq '.id' "$validate_resp")
    
    if [[ -z "$validate_id" || "$validate_id" == "null" ]]; then
        error "API token validation failed. Token may be invalid or expired."
    fi
    log "API token validated for user: $validate_id"

    # Stop existing container
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        info "Stopping existing worker..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
        log "Existing container removed"
    fi

    # Pull latest image
    info "Pulling latest worker image..."
    docker pull "$DOCKER_IMAGE" 2>&1 | grep -q "up to date\|Downloaded" || warn "Image pull had issues"

    # ✅ FIX: Remove --network host, use bridge with proper DNS
    info "Starting worker container..."
    
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --dns 8.8.8.8 \
        --dns 8.8.4.4 \
        -v "$CONFIG_DIR:/config:ro" \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -e HOSTNAME="$HOSTNAME" \
        -e CPU_CORES="$CPU_CORES" \
        -e CPU_MODEL="$CPU_MODEL" \
        -e RAM_TOTAL_MB="$RAM_TOTAL" \
        -e GPU_AVAILABLE="$GPU_AVAILABLE" \
        -e GPU_MODEL="$GPU_MODEL" \
        -e GPU_MEMORY_MB="$GPU_MEMORY" \
        -e GPU_COUNT="$GPU_COUNT" \
        -e GPU_DRIVER="$GPU_DRIVER" \
        -e GPU_CUDA_VERSION="$GPU_CUDA" \
        -e STORAGE_AVAILABLE_MB="$STORAGE_AVAILABLE" \
        -e PLATFORM="$PLATFORM" \
        -e ARCH="$ARCH" \
        -e DISABLE_SELF_REGISTER=true \
        --health-cmd="node -e \"console.log('healthy')\"" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        --health-start-period=60s \
        "$DOCKER_IMAGE" \
        --api-key "$API_TOKEN" \
        --url "$API_URL" >/dev/null 2>&1 || error "Failed to start container"

    # Wait and verify
    info "Waiting for worker to initialize..."
    sleep 15

    # Check if container is still running
    if ! docker ps --filter "name=^${CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo
        error "Worker failed to start. Showing last logs:\n$(docker logs --tail 50 $CONTAINER_NAME 2>&1)"
    fi

    # Test DNS resolution inside container
    info "Testing network connectivity..."
    if docker exec "$CONTAINER_NAME" nslookup distributex.cloud >/dev/null 2>&1 || \
       docker exec "$CONTAINER_NAME" ping -c 1 distributex.cloud >/dev/null 2>&1; then
        log "Network connectivity confirmed"
    else
        warn "DNS resolution test failed, but container is running"
        info "This may resolve itself. Check logs with: docker logs -f $CONTAINER_NAME"
    fi

    # Check logs for errors
    local logs=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -30)
    
    if echo "$logs" | grep -qi "error.*registration\|failed.*register\|invalid.*token\|EAI_AGAIN"; then
        echo
        warn "Worker may have registration or network issues. Recent logs:"
        echo "$logs"
        echo
        read -p "Container is running but may have issues. Continue? (y/N): " continue_choice </dev/tty
        [[ ! "$continue_choice" =~ ^[Yy]$ ]] && error "Installation aborted. Fix errors and try again."
    fi

    log "Worker started successfully!"

    section "Contributor Setup Complete!"
    echo
    echo -e "${GREEN}✅ Your worker is live and contributing!${NC}"
    echo
    echo "Worker ID:    Worker-$MAC_ADDRESS"
    echo "Resources:    $CPU_CORES cores • $((RAM_TOTAL/1024)) GB RAM"
    [[ "$GPU_AVAILABLE" == "true" ]] && echo "GPU:          $GPU_COUNT× $GPU_MODEL"
    echo
    echo -e "${CYAN}Monitor your worker:${NC}"
    echo "  docker logs -f $CONTAINER_NAME"
    echo
    echo -e "${CYAN}Test connectivity:${NC}"
    echo "  docker exec $CONTAINER_NAME ping -c 3 distributex.cloud"
    echo
    echo -e "${CYAN}Check status:${NC}"
    echo "  docker ps | grep $CONTAINER_NAME"
    echo
    echo -e "${BLUE}Dashboard: $API_URL/dashboard${NC}"
    echo
}

# ============================================================================
# DEVELOPER SETUP
# ============================================================================
setup_developer() {
    section "Setting Up Developer Access"

    info "Checking for an existing API key..."

    raw=$(curl -s -w "\n%{http_code}" --max-time 20 \
        "$API_URL/api/developer/api-key/info" \
        -H "Authorization: Bearer $API_TOKEN")

    http_code=$(echo "$raw" | tail -n1)
    body=$(echo "$raw" | sed '$d')

    if [[ "$http_code" != "200" ]] || ! echo "$body" | jq -e . >/dev/null 2>&1; then
        warn "Could not check existing API key (HTTP $http_code)"
        warn "Please generate one from your dashboard:"
        echo "   $API_URL/api-dashboard"
        section "Developer Setup Incomplete"
        return 0
    fi

    has_key=$(echo "$body" | jq -r '.hasKey // false')

    if [[ "$has_key" == "true" ]]; then
        prefix=$(echo "$body" | jq -r '.prefix // "xxxx"')
        suffix=$(echo "$body" | jq -r '.suffix // "xxxx"')

        info "Existing API key detected:"
        echo "   • ${prefix}********${suffix}"
        echo
        warn "Installer will NOT generate a new key."
        echo "Visit your dashboard to view your full key:"
        echo "   $API_URL/api-dashboard"
        echo
        section "Developer Setup Complete (existing key)"
        return 0
    fi

    warn "No API key found."
    echo
    echo "Please generate one in your developer dashboard:"
    echo "   $API_URL/api-dashboard"
    echo
    echo "Then save it locally:"
    echo "   echo \"your-api-key\" > $CONFIG_DIR/api-key"
    echo "   chmod 600 $CONFIG_DIR/api-key"
    echo
    section "Developer Setup Pending"
    return 0
}

# ============================================================================
# REQUIREMENTS CHECK
# ============================================================================
check_requirements() {
    section "Checking Requirements"
    for cmd in curl jq; do
        command -v $cmd &>/dev/null && continue
        info "Installing $cmd..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y $cmd -qq
        elif command -v brew &>/dev/null; then
            brew install $cmd
        else
            error "$cmd is required but could not be installed automatically"
        fi
    done
    log "All requirements satisfied"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    show_banner
    check_requirements
    authenticate_user
    select_role

    case "$USER_ROLE" in
        contributor) setup_contributor ;;
        developer)   setup_developer   ;;
        *)           error "Unknown role: $USER_ROLE" ;;
    esac

    echo -e "${BOLD}${GREEN}Installation complete! 🎉${NC}\n"
}

trap 'error "Installation failed at line $LINENO"' ERR
main
exit 0
