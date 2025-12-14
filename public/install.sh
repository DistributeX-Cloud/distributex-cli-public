#!/bin/bash
# ============================================================================
# DistributeX UNIVERSAL Installer v10.1 - FIXED
# ============================================================================

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================
API_URL="${DISTRIBUTEX_API_URL:-https://distributex.cloud}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

# ============================================================================
# COLORS
# ============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"; }
safe_jq() { echo "$2" | jq -r "$1" 2>/dev/null || echo ""; }

# ============================================================================
# OS AND ENVIRONMENT DETECTION
# ============================================================================
detect_os() {
    section "Detecting Operating System"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if grep -qi microsoft /proc/version 2>/dev/null || 
           grep -qi wsl /proc/version 2>/dev/null ||
           [[ -n "${WSL_DISTRO_NAME}" ]]; then
            OS_TYPE="wsl"
            OS_NAME="Windows Subsystem for Linux"
            log "Detected: WSL (Windows Subsystem for Linux)"
        else
            OS_TYPE="linux"
            OS_NAME="Linux"
            log "Detected: Native Linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
        OS_NAME="macOS"
        log "Detected: macOS"
    elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
        OS_TYPE="windows"
        OS_NAME="Windows (Git Bash/MSYS)"
        log "Detected: Windows (Git Bash)"
    else
        OS_TYPE="unknown"
        OS_NAME="Unknown OS"
        warn "Unknown OS type: $OSTYPE"
    fi
    
    export OS_TYPE OS_NAME
}

# ============================================================================
# DRIVE DETECTION - UNIVERSAL
# ============================================================================
detect_all_drives() {
    section "Scanning All Available Drives"
    
    local -a DRIVES=()
    
    case "$OS_TYPE" in
        linux)
            info "Scanning native Linux filesystems..."
            
            while IFS= read -r line; do
                local mountpoint=$(echo "$line" | awk '{print $6}')
                local device=$(echo "$line" | awk '{print $1}')
                local fstype=$(echo "$line" | awk '{print $5}')
                
                # Skip system and virtual mounts
                if [[ "$mountpoint" =~ ^/(proc|sys|dev|run|snap) ]]; then
                    continue
                fi
                
                # Skip root filesystem (can't mount / in Docker)
                if [[ "$mountpoint" == "/" ]]; then
                    info "Skipping root filesystem (not allowed in Docker)"
                    continue
                fi
                
                # Skip tmpfs and devtmpfs
                if [[ "$fstype" =~ ^(tmpfs|devtmpfs|squashfs)$ ]]; then
                    continue
                fi
                
                if [[ -d "$mountpoint" && -r "$mountpoint" ]]; then
                    DRIVES+=("$mountpoint:$mountpoint:rw")
                    log "Found: $mountpoint ($device)"
                fi
            done < <(df -h -t ext4 -t ext3 -t xfs -t btrfs -t ntfs -t vfat 2>/dev/null | tail -n +2)
            
            # Always add user home directory
            if [[ -d "$HOME" && "$HOME" != "/" ]]; then
                DRIVES+=("$HOME:$HOME:rw")
                log "Found: User home ($HOME)"
            fi
            
            # Add common data directories if they exist
            for data_dir in /mnt /media /opt /srv /var/lib /usr/local; do
                if [[ -d "$data_dir" && -r "$data_dir" ]]; then
                    DRIVES+=("$data_dir:$data_dir:rw")
                    log "Found: $data_dir"
                fi
            done
            
            # USB/External drives
            if [[ -d "/media/$USER" ]]; then
                for mount in /media/$USER/*; do
                    if [[ -d "$mount" ]]; then
                        DRIVES+=("$mount:$mount:rw")
                        log "Found external: $mount"
                    fi
                done
            fi
            
            # Alternative mount locations
            for alt_mount in /mnt/* /run/media/$USER/*; do
                if [[ -d "$alt_mount" && ! "$alt_mount" =~ wsl ]]; then
                    DRIVES+=("$alt_mount:$alt_mount:rw")
                    log "Found mounted: $alt_mount"
                fi
            done
            ;;
            
        wsl)
            info "Scanning WSL + Windows drives..."
            
            # Windows drives mounted in WSL (/mnt/c, /mnt/d, etc.)
            for drive in /mnt/*; do
                if [[ -d "$drive" && -r "$drive" ]]; then
                    DRIVES+=("$drive:$drive:rw")
                    log "Found Windows drive: $drive"
                fi
            done
            
            # User home
            DRIVES+=("$HOME:$HOME:rw")
            log "Found: User home ($HOME)"
            ;;
            
        macos)
            info "Scanning macOS volumes..."
            
            # User home
            DRIVES+=("$HOME:$HOME:rw")
            log "Found: User home ($HOME)"
            
            # All /Volumes (external drives, network shares, etc.)
            if [[ -d "/Volumes" ]]; then
                for vol in /Volumes/*; do
                    if [[ -d "$vol" && "$vol" != "/Volumes/Macintosh HD" ]]; then
                        DRIVES+=("$vol:$vol:rw")
                        log "Found volume: $vol"
                    fi
                done
            fi
            ;;
            
        windows)
            info "Scanning Windows drives (Git Bash)..."
            
            # Detect all drive letters
            for drive_letter in {A..Z}; do
                for prefix in "" "/mnt/" "/$drive_letter/"; do
                    local drive_path="${prefix}${drive_letter,,}"
                    
                    if [[ -d "$drive_path" ]]; then
                        local docker_path="/mnt/${drive_letter,,}"
                        DRIVES+=("$drive_path:$docker_path:rw")
                        log "Found: ${drive_letter}: → $docker_path"
                        break
                    fi
                done
            done
            
            # User home
            if [[ -n "$HOME" && -d "$HOME" ]]; then
                DRIVES+=("$HOME:/home/user:rw")
                log "Found: User home ($HOME)"
            fi
            ;;
    esac
    
    # Ensure at least home directory is mounted
    if [[ ${#DRIVES[@]} -eq 0 ]]; then
        warn "No drives detected automatically"
        info "Adding user home directory as fallback"
        DRIVES+=("$HOME:$HOME:rw")
    fi
    
    # Remove duplicates
    local -a UNIQUE_DRIVES=()
    for drive in "${DRIVES[@]}"; do
        local exists=false
        for unique in "${UNIQUE_DRIVES[@]}"; do
            if [[ "$drive" == "$unique" ]]; then
                exists=true
                break
            fi
        done
        if ! $exists; then
            UNIQUE_DRIVES+=("$drive")
        fi
    done
    
    DRIVES=("${UNIQUE_DRIVES[@]}")
    export DETECTED_DRIVES=("${DRIVES[@]}")
    
    echo
    log "Total unique drives detected: ${#DRIVES[@]}"
    echo
}

# ============================================================================
# SYSTEM CAPABILITIES DETECTION
# ============================================================================
get_mac_address() {
    if [[ -n "${HOST_MAC_ADDRESS}" ]]; then
        local mac="${HOST_MAC_ADDRESS,,}"
        mac="${mac//[:-]/}"
        if [[ "$mac" =~ ^[0-9a-f]{12}$ ]]; then
            echo "$mac"
            return 0
        fi
    fi
    
    local mac=""
    
    case "$OS_TYPE" in
        linux|wsl)
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
            ;;
        macos)
            for iface in en0 en1 en2 en3 en4; do
                mac=$(ifconfig $iface 2>/dev/null | awk '/ether/ {gsub(/:/,""); print tolower($2)}')
                [[ -n "$mac" ]] && [[ "$mac" != "000000000000" ]] && break
            done
            ;;
        windows)
            mac=$(ipconfig /all 2>/dev/null | grep "Physical Address" | head -1 | awk '{print $NF}' | tr -d '-' | tr '[:upper:]' '[:lower:]')
            ;;
    esac
    
    if [[ ! "$mac" =~ ^[0-9a-f]{12}$ ]] || [[ "$mac" == "000000000000" ]]; then
        error "Cannot detect valid MAC address"
    fi
    
    echo "$mac"
}

detect_cpu() {
    local cores=0
    local model="Unknown CPU"
    
    if [[ "$OS_TYPE" == "macos" ]]; then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
        model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
    else
        cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
        model=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | xargs || echo "Unknown CPU")
    fi
    
    echo "$cores|$model"
}

detect_ram() {
    local total_mb=0 
    local available_mb=0
    
    if [[ "$OS_TYPE" == "macos" ]]; then
        total_mb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 8589934592) / 1024 / 1024 ))
        available_mb=$((total_mb * 7 / 10))
    else
        total_mb=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 8192)
        available_mb=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "$total_mb")
    fi
    
    [[ $total_mb -eq 0 ]] && total_mb=8192
    
    echo "$total_mb|$available_mb"
}

detect_gpu() {
    local has="false" 
    local model="None" 
    local memory=0 
    local count=0 
    local driver="" 
    local cuda=""
    
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
    fi
    
    echo "$has|$model|$memory|$count|$driver|$cuda"
}

detect_storage() {
    local total_mb=0 
    local available_mb=0
    
    if df -m / &>/dev/null; then
        read total_mb available_mb <<< $(df -m / 2>/dev/null | awk 'NR==2 {print $2" "$4}')
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
        info "No GPU detected"
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
    
    echo
    echo -e "${CYAN}Select your role:${NC}"
    echo "1) Contributor - Share your computer's resources"
    echo "2) Developer - Use the network in your applications"
    read -p "Choice (1 or 2): " role_choice </dev/tty
    
    local role
    case "$role_choice" in
        1) role="contributor" ;;
        2) role="developer" ;;
        *) error "Invalid choice" ;;
    esac
    
    local resp=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\",\"role\":\"$role\"}")
    
    local code=$(tail -n1 <<<"$resp")
    local body=$(sed '$d' <<<"$resp")
    
    [[ ! "$code" =~ ^2 ]] && error "Signup failed: $(safe_jq '.message' "$body")"
    
    API_TOKEN=$(safe_jq '.token' "$body")
    USER_EMAIL="$email"
    USER_ROLE="$role"
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Account created: $USER_EMAIL as $USER_ROLE"
}

# ============================================================================
# DOCKER WORKER SETUP - FIXED
# ============================================================================
setup_contributor() {
    section "Setting Up 24/7 Worker"
    
    if ! command -v docker &>/dev/null; then
        error "Docker not found. Install from: https://docs.docker.com/get-docker/"
    fi
    
    if ! docker ps &>/dev/null; then
        error "Docker daemon not running. Start Docker and try again."
    fi
    
    log "Docker is ready"
    
    detect_full_system
    detect_all_drives
    
    info "Validating credentials..."
    local validate=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$API_URL/api/auth/user" 2>/dev/null || echo "{}")
    local user_id=$(safe_jq '.id' "$validate")
    
    if [[ -z "$user_id" || "$user_id" == "null" ]]; then
        error "Invalid API token"
    fi
    log "Credentials validated"
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        info "Stopping existing worker..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
        log "Removed existing container"
    fi
    
    info "Pulling latest worker image..."
    docker pull "$DOCKER_IMAGE" 2>&1 | grep -q "up to date\|Downloaded" || true
    log "Image ready"
    
    info "Starting worker with ${#DETECTED_DRIVES[@]} mounted drive(s)..."
    
    # Build docker run command with proper array handling
    local DOCKER_ARGS=(
        "run"
        "-d"
        "--name"
        "$CONTAINER_NAME"
        "--restart"
        "unless-stopped"
        "--dns"
        "8.8.8.8"
        "--dns"
        "8.8.4.4"
        "-v"
        "$CONFIG_DIR:/config:ro"
    )
    
    # Add volume mounts
    for drive in "${DETECTED_DRIVES[@]}"; do
        local host=$(echo "$drive" | cut -d':' -f1)
        local container=$(echo "$drive" | cut -d':' -f2)
        local mode=$(echo "$drive" | cut -d':' -f3)
        DOCKER_ARGS+=("-v")
        DOCKER_ARGS+=("$host:$container:$mode")
    done
    
    # Add environment variables
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("HOST_MAC_ADDRESS=$MAC_ADDRESS")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("HOSTNAME=$HOSTNAME")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("CPU_CORES=$CPU_CORES")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("CPU_MODEL=$CPU_MODEL")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("RAM_TOTAL_MB=$RAM_TOTAL")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("GPU_AVAILABLE=$GPU_AVAILABLE")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("GPU_MODEL=$GPU_MODEL")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("GPU_MEMORY_MB=$GPU_MEMORY")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("GPU_COUNT=$GPU_COUNT")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("STORAGE_AVAILABLE_MB=$STORAGE_AVAILABLE")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("PLATFORM=$PLATFORM")
    DOCKER_ARGS+=("-e")
    DOCKER_ARGS+=("ARCH=$ARCH")
    DOCKER_ARGS+=("--health-cmd")
    DOCKER_ARGS+=("node -e 'console.log(\"healthy\")'")
    DOCKER_ARGS+=("--health-interval")
    DOCKER_ARGS+=("30s")
    DOCKER_ARGS+=("--health-timeout")
    DOCKER_ARGS+=("10s")
    DOCKER_ARGS+=("--health-retries")
    DOCKER_ARGS+=("3")
    DOCKER_ARGS+=("--health-start-period")
    DOCKER_ARGS+=("60s")
    DOCKER_ARGS+=("$DOCKER_IMAGE")
    DOCKER_ARGS+=("--api-key")
    DOCKER_ARGS+=("$API_TOKEN")
    DOCKER_ARGS+=("--url")
    DOCKER_ARGS+=("$API_URL")
    
    # Execute docker command with error capture
    echo "Executing docker command..."
    if ! DOCKER_OUTPUT=$(docker "${DOCKER_ARGS[@]}" 2>&1); then
        echo
        echo "❌ Docker command failed!"
        echo "Error output:"
        echo "$DOCKER_OUTPUT"
        echo
        echo "Command attempted:"
        echo "docker ${DOCKER_ARGS[*]}"
        echo
        error "Failed to start container. Check the error above."
    fi
    
    CONTAINER_ID="$DOCKER_OUTPUT"
    log "Container started: ${CONTAINER_ID:0:12}"
    
    info "Initializing worker..."
    sleep 15
    
    if ! docker ps --filter "name=^${CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo
        error "Worker failed to start:\n$(docker logs --tail 30 $CONTAINER_NAME 2>&1)"
    fi
    
    log "Worker started successfully!"
    
    section "✅ Installation Complete - Worker is LIVE 24/7!"
    echo
    echo -e "${GREEN}${BOLD}🎉 Your worker is now part of the DistributeX network!${NC}"
    echo
    echo -e "${CYAN}Worker Details:${NC}"
    echo "  ID:              Worker-$MAC_ADDRESS"
    echo "  Platform:        $OS_NAME"
    echo "  Resources:       $CPU_CORES cores • $((RAM_TOTAL/1024)) GB RAM"
    [[ "$GPU_AVAILABLE" == "true" ]] && echo "  GPU:             $GPU_COUNT× $GPU_MODEL"
    echo "  Mounted Drives:  ${#DETECTED_DRIVES[@]}"
    echo "  Restart Policy:  unless-stopped (TRUE 24/7)"
    echo
    echo -e "${CYAN}Mounted Storage:${NC}"
    for drive in "${DETECTED_DRIVES[@]}"; do
        local host=$(echo "$drive" | cut -d':' -f1)
        local container=$(echo "$drive" | cut -d':' -f2)
        echo "  $host → $container"
    done
    echo
    echo -e "${CYAN}Management Commands:${NC}"
    echo "  View logs:       docker logs -f $CONTAINER_NAME"
    echo "  Check status:    docker ps | grep $CONTAINER_NAME"
    echo "  Restart:         docker restart $CONTAINER_NAME"
    echo "  Stop:            docker stop $CONTAINER_NAME"
    echo
    echo -e "${BLUE}Dashboard: $API_URL/dashboard${NC}"
    echo
}

# ============================================================================
# DEVELOPER SETUP
# ============================================================================
setup_developer() {
    section "Setting Up Developer Access"
    
    info "Checking API key status..."
    
    local resp=$(curl -s "$API_URL/api/developer/api-key/info" \
        -H "Authorization: Bearer $API_TOKEN" 2>/dev/null || echo "{}")
    
    local has_key=$(safe_jq '.hasKey' "$resp")
    
    if [[ "$has_key" == "true" ]]; then
        local prefix=$(safe_jq '.prefix' "$resp")
        local suffix=$(safe_jq '.suffix' "$resp")
        log "Existing API key found: ${prefix}••••${suffix}"
        echo
        echo "Your API key is ready to use!"
        echo "View it in full at: $API_URL/api-dashboard"
    else
        warn "No API key found"
        echo
        echo "Generate your API key at: $API_URL/api-dashboard"
        echo "Then use it in your code:"
        echo
        echo "  Python:  dx = DistributeX(api_key='your_key')"
        echo "  Node.js: const dx = new DistributeX('your_key')"
    fi
    
    echo
    section "✅ Developer Setup Complete!"
    echo "Visit the dashboard to manage your API keys and tasks."
    echo
}

# ============================================================================
# REQUIREMENTS CHECK
# ============================================================================
check_requirements() {
    section "Checking Requirements"
    
    local missing=()
    
    for cmd in curl jq; do
        if ! command -v $cmd &>/dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Installing missing tools: ${missing[*]}"
        
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y "${missing[@]}" -qq
        elif command -v brew &>/dev/null; then
            brew install "${missing[@]}"
        elif command -v yum &>/dev/null; then
            sudo yum install -y "${missing[@]}"
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm "${missing[@]}"
        else
            error "Cannot auto-install: ${missing[*]}. Please install manually."
        fi
    fi
    
    log "All requirements satisfied"
}

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

          ───────────── Universal Installer v10.1 ─────────────────
              Windows • Linux • macOS • WSL • TRUE 24/7
          ─────────────────────────────────────────────────────────
EOF
    echo -e "${NC}"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    show_banner
    detect_os
    check_requirements
    authenticate_user
    
    if [[ "$USER_ROLE" == "contributor" ]]; then
        setup_contributor
    else
        setup_developer
    fi
    
    echo -e "${BOLD}${GREEN}✅ Installation Complete!${NC}\n"
}

# ============================================================================
# ERROR HANDLING
# ============================================================================
trap 'error "Installation failed at line $LINENO"' ERR

# ============================================================================
# ENTRY POINT
# ============================================================================
main "$@"
exit 0
