#!/bin/bash
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
 

          ─────────────────── Universal Installer v9.1 ───────────────────
                              Get ready to contribute
                        Contribute to provide for developers
          ────────────────────────────────────────────────────────────────
EOF
    echo -e "${BOLD}${CYAN}          Welcome! Let's get your node or dev environment ready in seconds.\n${NC}"
}

get_mac_address() {
    local mac=""
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
        # Linux and Windows/WSL
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
        # Windows fallback
        if [[ -z "$mac" ]] && command -v ipconfig &>/dev/null; then
            mac=$(ipconfig /all | grep -i "Physical Address" | head -1 | awk '{print $NF}' | tr -d ':-' | tr '[:upper:]' '[:lower:]')
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
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
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
        cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
        model=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | xargs || echo "Unknown CPU")
        # Windows fallback
        if [[ -z "$model" || "$model" == "Unknown CPU" ]] && command -v wmic &>/dev/null; then
            model=$(wmic cpu get name 2>/dev/null | grep -v "Name" | head -1 | xargs || echo "Unknown CPU")
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
        model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
    fi
    echo "$cores|$model"
}

detect_ram() {
    local total_mb=0 available_mb=0
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
        total_mb=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 8192)
        available_mb=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "$total_mb")
        # Windows fallback
        if [[ $total_mb -eq 0 ]] && command -v wmic &>/dev/null; then
            total_mb=$(wmic computersystem get totalphysicalmemory 2>/dev/null | grep -v "TotalPhysicalMemory" | awk '{printf "%.0f", $1/1024/1024}')
            available_mb=$(echo "$total_mb * 0.7" | bc -l 2>/dev/null | awk '{printf "%.0f", $1}' || echo "$((total_mb * 7 / 10))")
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        total_mb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 8589934592) / 1024 / 1024 ))
        available_mb=$(echo "$total_mb * 0.7" | bc -l 2>/dev/null | awk '{printf "%.0f", $1}' || echo "$((total_mb * 7 / 10))")
    fi
    [[ $total_mb -eq 0 ]] && total_mb=8192
    [[ $available_mb -eq 0 ]] && available_mb=$(echo "$total_mb * 0.7" | bc -l 2>/dev/null | awk '{printf "%.0f", $1}' || echo "$((total_mb * 7 / 10))")
    echo "$total_mb|$available_mb"
}

detect_gpu() {
    local has="false" model="None" memory=0 count=0 driver="" cuda=""
    if command -v nvidia-smi &>/dev/null; then
        local out=$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "")
        if [[ -n "$out" ]]; then
            has="true"
            count=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | wc -l | xargs)
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
    local total_mb=0
    local available_mb=0
    local drive_count=0
    DETECTED_MOUNT_POINTS=()

    # Send info messages to stderr to avoid capturing them
    echo -e "${CYAN}[i]${NC} Scanning all storage drives..." >&2

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        while IFS= read -r line; do
            set -- $line
            local fs="$1"
            local size_kb="$2"
            local avail_kb="$4"
            local mount_point="${@: -1}"

            [[ "$fs" =~ ^(tmpfs|devtmpfs|udev|overlay|squashfs|efivarfs) ]] && continue
            [[ "$mount_point" =~ ^/proc|^/sys|^/dev|^/run|^/snap ]] && continue
            [[ "$mount_point" == "/boot/efi" ]] && continue

            # Safe numeric defaults
            size_kb=${size_kb:-0}
            avail_kb=${avail_kb:-0}

            # Safe division
            local size_mb=0
            local avail_mb=0
            if [[ $size_kb -gt 0 ]]; then
                size_mb=$((size_kb / 1024))
            fi
            if [[ $avail_kb -gt 0 ]]; then
                avail_mb=$((avail_kb / 1024))
            fi
            
            # Skip small drives
            if [[ $size_mb -lt 1000 ]]; then
                continue
            fi

            total_mb=$((total_mb + size_mb))
            available_mb=$((available_mb + avail_mb))
            drive_count=$((drive_count + 1))
            DETECTED_MOUNT_POINTS+=("$mount_point")

            local size_gb=0
            local avail_gb=0
            if [[ $size_mb -gt 0 ]]; then
                size_gb=$((size_mb / 1024))
            fi
            if [[ $avail_mb -gt 0 ]]; then
                avail_gb=$((avail_mb / 1024))
            fi
            
            # Send to stderr
            echo -e "${CYAN}[i]${NC}  Drive $drive_count: $mount_point → ${size_gb} GB total, ${avail_gb} GB free" >&2
        done < <(df -k --output=source,size,avail,target 2>/dev/null | tail -n +2)
    else
        total_mb=100000
        available_mb=50000
        drive_count=1
        DETECTED_MOUNT_POINTS=("/")
    fi

    # Fallback if nothing detected
    if [[ $total_mb -eq 0 ]]; then
        total_mb=100000
        available_mb=50000
        drive_count=1
        DETECTED_MOUNT_POINTS=("/")
    fi

    local total_gb=0
    local avail_gb=0
    if [[ $total_mb -gt 0 ]]; then
        total_gb=$((total_mb / 1024))
    fi
    if [[ $available_mb -gt 0 ]]; then
        avail_gb=$((available_mb / 1024))
    fi
    
    # Send to stderr
    echo -e "${GREEN}[✓]${NC} Total: $drive_count drive(s), ${total_gb} GB total, ${avail_gb} GB available" >&2
    
    # Only output the pipe-separated values to stdout
    echo "$total_mb|$available_mb|$drive_count"
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
        AMD64)      echo "x64" ;;
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
    
    local ram_total_gb=0
    local ram_avail_gb=0
    if [[ $RAM_TOTAL -gt 0 ]]; then
        ram_total_gb=$((RAM_TOTAL / 1024))
    fi
    if [[ $RAM_AVAILABLE -gt 0 ]]; then
        ram_avail_gb=$((RAM_AVAILABLE / 1024))
    fi
    log "RAM: ${ram_total_gb} GB total (${ram_avail_gb} GB available)"

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

    # Capture storage detection output (functions outputs to stdout, logs to stderr)
    local storage=$(detect_storage)
    STORAGE_TOTAL=$(echo "$storage" | cut -d'|' -f1)
    STORAGE_AVAILABLE=$(echo "$storage" | cut -d'|' -f2)
    DRIVE_COUNT=$(echo "$storage" | cut -d'|' -f3)
    
    # Validate numeric values
    [[ -z "$STORAGE_TOTAL" || ! "$STORAGE_TOTAL" =~ ^[0-9]+$ ]] && STORAGE_TOTAL=0
    [[ -z "$STORAGE_AVAILABLE" || ! "$STORAGE_AVAILABLE" =~ ^[0-9]+$ ]] && STORAGE_AVAILABLE=0
    [[ -z "$DRIVE_COUNT" || ! "$DRIVE_COUNT" =~ ^[0-9]+$ ]] && DRIVE_COUNT=0
    
    local storage_total_gb=0
    if [[ $STORAGE_TOTAL -gt 0 ]]; then
        storage_total_gb=$((STORAGE_TOTAL / 1024))
    fi
    log "Storage: ${storage_total_gb} GB total across $DRIVE_COUNT drive(s)"

    PLATFORM=$(detect_platform)
    ARCH=$(detect_architecture)
    HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

    log "Platform: $PLATFORM / $ARCH"
    log "Hostname: $HOSTNAME"

    echo
}

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

setup_contributor() {
    section "Setting Up Contributor Worker"
    command -v docker &>/dev/null || error "Docker not found → https://docs.docker.com/get-docker/"
    docker ps &>/dev/null || error "Docker daemon not running"
    log "Docker ready"
    detect_full_system

    DETECTED_MOUNT_POINTS=("${DETECTED_MOUNT_POINTS[@]:-}")

    info "Validating API token..."
    local resp=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$API_URL/api/auth/user")
    [[ $(safe_jq '.id' "$resp") == "null" ]] && error "Invalid token"

    docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && {
        info "Removing old worker..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    }

    info "Pulling latest worker image..."
    docker pull "$DOCKER_IMAGE" >/dev/null

    VOLUMES="-v $CONFIG_DIR:/config:ro"
    for mp in "${DETECTED_MOUNT_POINTS[@]}"; do
        safe_name=$(echo "$mp" | tr '/' '_')
        mkdir -p "$mp/.distributex-shared" 2>/dev/null || true
        VOLUMES="$VOLUMES -v $mp/.distributex-shared:/data/host$safe_name:rw"
        log "Attached: $mp → /data/host$safe_name (full access)"
    done

    if [[ "$PLATFORM" == "linux" ]]; then
        echo
        read -p "Attach ENTIRE raw disks (e.g. /dev/sdb)? VERY DANGEROUS - only empty drives! (y/N): " raw </dev/tty
        if [[ "$raw" =~ ^[Yy]$ ]]; then
            echo "Available disks:"
            lsblk -d -o NAME,SIZE,MODEL | grep -v NAME
            read -p "Enter device names (e.g. sdb sdc): " disks </dev/tty
            for d in $disks; do
                if [[ -b "/dev/$d" ]]; then
                    VOLUMES="$VOLUMES --device /dev/$d --cap-add SYS_ADMIN --privileged"
                    log "Attached raw disk: /dev/$d (worker will format & use 100%)"
                fi
            done
        fi
    fi

    info "Starting worker with FULL access to all drives..."

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --dns 8.8.8.8 --dns 8.8.4.4 \
        $VOLUMES \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -e HOSTNAME="$HOSTNAME" \
        -e CPU_CORES="$CPU_CORES" \
        -e RAM_TOTAL_MB="$RAM_TOTAL" \
        -e GPU_AVAILABLE="$GPU_AVAILABLE" \
        -e STORAGE_TOTAL_MB="$STORAGE_TOTAL" \
        -e STORAGE_AVAILABLE_MB="$STORAGE_AVAILABLE" \
        -e DRIVE_COUNT="$DRIVE_COUNT" \
        -e PLATFORM="$PLATFORM" \
        -e ARCH="$ARCH" \
        -e DISABLE_SELF_REGISTER=true \
        --health-cmd="node -e \"console.log('healthy')\"" \
        --health-interval=30s \
        "$DOCKER_IMAGE" \
        --api-key "$API_TOKEN" \
        --url "$API_URL" >/dev/null

    sleep 15
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "Worker failed. Logs:\n$(docker logs $CONTAINER_NAME | tail -50)"
    fi

    log "Worker started with access to ALL your drives!"
    section "SUCCESS - FULL STORAGE CONTRIBUTED"
    echo
    echo -e "${GREEN}Your node now has access to:${NC}"
    for mp in "${DETECTED_MOUNT_POINTS[@]}"; do
        echo "   • $mp (full read/write)"
    done
    echo
    echo -e "${CYAN}Monitor: docker logs -f $CONTAINER_NAME${NC}"
    echo -e "${BLUE}Dashboard: $API_URL/dashboard${NC}"
    echo
}

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
        echo " • ${prefix}********${suffix}"
        echo
        warn "Installer will NOT generate a new key."
        echo "Visit your dashboard to view/manage your full key:"
        echo " $API_URL/api-dashboard"
        echo
        section "Developer Setup Complete (existing key)"
        return 0
    fi
    
    warn "No API key found."
    echo
    echo "Please generate one in your developer dashboard:"
    echo " $API_URL/api-dashboard"
    echo
    echo "Then save it locally (optional):"
    echo " echo \"your-full-api-key-here\" > $CONFIG_DIR/api-key"
    echo " chmod 600 $CONFIG_DIR/api-key"
    echo
    section "Developer Setup Complete — Generate Key in Dashboard"
    return 0
}

check_requirements() {
    section "Checking Requirements"
    local missing=""
    for cmd in curl jq docker; do
        if ! command -v $cmd &>/dev/null; then
            missing="$missing $cmd"
        fi
    done

    if [[ -n "$missing" ]]; then
        warn "Missing dependencies:$missing"
        info "Please install them manually:"
        echo
        echo " • curl & jq: usually pre-installed or via package manager"
        echo " • Docker: https://docs.docker.com/get-docker/"
        echo
        read -p "Press Enter when ready, or Ctrl+C to abort..." </dev/tty
        for cmd in curl jq docker; do
            command -v $cmd &>/dev/null || error "$cmd is required but still not found"
        done
    fi
    log "All requirements satisfied"
}

main() {
    show_banner
    check_requirements
    authenticate_user
    select_role

    if [[ "$USER_ROLE" == "contributor" ]]; then
        setup_contributor
    elif [[ "$USER_ROLE" == "developer" ]]; then
        setup_developer
    else
        error "Unknown role: $USER_ROLE"
    fi

    echo
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║          DistributeX Universal Installer v9.1           ║${NC}"
    echo -e "${BOLD}${GREEN}║                    Installation Complete!               ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "   Dashboard → ${BLUE}$API_URL/dashboard${NC}"
    [[ "$USER_ROLE" == "developer" ]] && echo -e "   API Keys   → ${BLUE}$API_URL/api-dashboard${NC}"
    echo
    echo -e "
    echo
}

trap 'error "Installation interrupted at line $LINENO"' ERR
main "$@"
exit 0
