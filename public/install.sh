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
 

          ─────────────────── Universal Installer v9.0 ───────────────────
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
            available_mb=$((total_mb * 7 / 10))
        fi
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
    
    info "Scanning all storage drives..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # ===== LINUX: Detect all mounted filesystems =====
        while IFS= read -r line; do
            local mount_point=$(echo "$line" | awk '{print $6}')
            local size_mb=$(echo "$line" | awk '{print $2}')
            local avail_mb=$(echo "$line" | awk '{print $4}')
            local device=$(echo "$line" | awk '{print $1}')
            
            # Skip special filesystems
            if [[ "$mount_point" == "/dev"* ]] || \
               [[ "$mount_point" == "/sys"* ]] || \
               [[ "$mount_point" == "/proc"* ]] || \
               [[ "$mount_point" == "/run"* ]] || \
               [[ "$device" == "tmpfs" ]] || \
               [[ "$device" == "devtmpfs" ]]; then
                continue
            fi
            
            total_mb=$((total_mb + size_mb))
            available_mb=$((available_mb + avail_mb))
            drive_count=$((drive_count + 1))
            
            info "  Drive $drive_count: $mount_point → $((size_mb/1024)) GB total, $((avail_mb/1024)) GB free"
        done < <(df -m 2>/dev/null | tail -n +2)
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # ===== macOS: Detect all volumes =====
        while IFS= read -r line; do
            local mount_point=$(echo "$line" | awk '{print $9}')
            local size_mb=$(echo "$line" | awk '{print $2}')
            local avail_mb=$(echo "$line" | awk '{print $4}')
            local device=$(echo "$line" | awk '{print $1}')
            
            # Skip special filesystems
            if [[ "$mount_point" == "/dev"* ]] || \
               [[ "$mount_point" == "/System"* ]] || \
               [[ "$mount_point" == "/private"* ]] || \
               [[ "$device" == "map"* ]] || \
               [[ "$device" == "devfs" ]]; then
                continue
            fi
            
            total_mb=$((total_mb + size_mb))
            available_mb=$((available_mb + avail_mb))
            drive_count=$((drive_count + 1))
            
            info "  Drive $drive_count: $mount_point → $((size_mb/1024)) GB total, $((avail_mb/1024)) GB free"
        done < <(df -m 2>/dev/null | tail -n +2)
        
    elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
        # ===== WINDOWS (Git Bash/WSL): Detect all drives =====
        if command -v wmic &>/dev/null; then
            # Use WMIC to get all logical drives
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                [[ "$line" == "DeviceID"* ]] && continue
                
                local drive_letter=$(echo "$line" | awk '{print $1}' | tr -d ':')
                [[ -z "$drive_letter" ]] && continue
                
                local size_bytes=$(wmic logicaldisk where "DeviceID='${drive_letter}:'" get Size 2>/dev/null | grep -v "Size" | xargs)
                local free_bytes=$(wmic logicaldisk where "DeviceID='${drive_letter}:'" get FreeSpace 2>/dev/null | grep -v "FreeSpace" | xargs)
                
                if [[ -n "$size_bytes" ]] && [[ "$size_bytes" != "0" ]]; then
                    local size_mb=$((size_bytes / 1024 / 1024))
                    local free_mb=$((free_bytes / 1024 / 1024))
                    
                    total_mb=$((total_mb + size_mb))
                    available_mb=$((available_mb + free_mb))
                    drive_count=$((drive_count + 1))
                    
                    info "  Drive $drive_count: ${drive_letter}: → $((size_mb/1024)) GB total, $((free_mb/1024)) GB free"
                fi
            done < <(wmic logicaldisk get DeviceID 2>/dev/null)
        else
            # Fallback for WSL
            while IFS= read -r line; do
                local mount_point=$(echo "$line" | awk '{print $6}')
                local size_mb=$(echo "$line" | awk '{print $2}')
                local avail_mb=$(echo "$line" | awk '{print $4}')
                
                # Skip special mounts
                [[ "$mount_point" == "/mnt/wsl"* ]] && continue
                [[ "$mount_point" == "/dev"* ]] && continue
                [[ "$mount_point" == "/sys"* ]] && continue
                [[ "$mount_point" == "/proc"* ]] && continue
                
                total_mb=$((total_mb + size_mb))
                available_mb=$((available_mb + avail_mb))
                drive_count=$((drive_count + 1))
                
                info "  Drive $drive_count: $mount_point → $((size_mb/1024)) GB total, $((avail_mb/1024)) GB free"
            done < <(df -m 2>/dev/null | tail -n +2)
        fi
    fi
    
    # Fallback if no drives detected
    if [[ $total_mb -eq 0 ]]; then
        warn "Could not detect drives, using defaults"
        total_mb=102400
        available_mb=51200
        drive_count=1
    fi
    
    log "Total: $drive_count drive(s), $((total_mb/1024)) GB total, $((available_mb/1024)) GB available"
    
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
        AMD64)      echo "x64" ;;  # Windows
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

    # ===== MULTI-DRIVE DETECTION (NEW!) =====
    local storage=$(detect_storage)
    STORAGE_TOTAL=$(echo "$storage" | cut -d'|' -f1)
    STORAGE_AVAILABLE=$(echo "$storage" | cut -d'|' -f2)
    DRIVE_COUNT=$(echo "$storage" | cut -d'|' -f3)
    
    log "Storage: $((STORAGE_TOTAL/1024)) GB total across $DRIVE_COUNT drive(s)"

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

    # === NEW: Let user select full drives to contribute ===
    EXTRA_VOLUMES=""
    EXTRA_DEVICES=""

    if [[ "$PLATFORM" == "linux" ]]; then
        info "Do you want to contribute ENTIRE RAW DISKS (e.g. secondary HDD/SSD)? This gives maximum storage."
        echo -e "${YELLOW}WARNING: Only select drives with NO important data!${NC}"
        echo
        read -p "Contribute full raw drives? (y/N): " contribute_raw </dev/tty
        if [[ "$contribute_raw" =~ ^[Yy]$ ]]; then
            echo
            info "Available block devices (be VERY careful):"
            echo
            lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v loop | grep disk || true
            echo
            echo -e "${YELLOW}Enter device names separated by space (e.g. sdb sdc nvme0n1)${NC}"
            echo -e "${RED}   DOUBLE-CHECK! Wrong device = DATA LOSS!${NC}"
            read -p "Devices to contribute (or press Enter to skip): " raw_devices </dev/tty

            if [[ -n "$raw_devices" ]]; then
                for dev in $raw_devices; do
                    dev_path="/dev/$dev"
                    if [[ -b "$dev_path" ]]; then
                        log "Adding full raw disk: $dev_path"
                        EXTRA_DEVICES="$EXTRA_DEVICES --device $dev_path "
                        # Also allow read/write inside container
                        EXTRA_VOLUMES="$EXTRA_VOLUMES -v /mnt/distributex-$dev:/data/$dev:rw "
                        mkdir -p "/mnt/distributex-$dev"
                    else
                        warn "Device $dev_path not found. Skipping."
                    fi
                done
            fi
        fi

        # Optional: Also bind-mount large directories (safer fallback)
        info "You can also contribute large folders (e.g. /mnt/data, /home/user/storage)"
        read -p "Extra folders to share? (space-separated, or Enter to skip): " extra_dirs </dev/tty
        if [[ -n "$extra_dirs" ]]; then
            for dir in $extra_dirs; do
                dir=$(realpath "$dir" 2>/dev/null || echo "$dir")
                if [[ -d "$dir" ]]; then
                    log "Bind-mounting folder: $dir"
                    EXTRA_VOLUMES="$EXTRA_VOLUMES -v $dir:/data/host$(echo $dir | tr '/' '_'):rw "
                else
                    warn "Directory $dir not found. Skipping."
                fi
            done
        fi
    else
        warn "Raw disk contribution is only supported on Linux. Using detected mounted storage only."
    fi

    # Validate token
    info "Validating API token..."
    local validate_resp=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$API_URL/api/auth/user" 2>/dev/null || echo "{}")
    [[ $(safe_jq '.id' "$validate_resp") == "null" ]] && error "Invalid or expired token"

    # Stop old container
    docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && {
        info "Stopping and removing old worker..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    }

    info "Pulling latest worker image..."
    docker pull "$DOCKER_IMAGE"

    info "Starting worker with full storage access..."

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --dns 8.8.8.8 --dns 8.8.4.4 \
        --cap-add SYS_ADMIN --cap-add DAC_OVERRIDE \
        --privileged \
        -v "$CONFIG_DIR:/config:ro" \
        $EXTRA_VOLUMES \
        $EXTRA_DEVICES \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -e HOSTNAME="$HOSTNAME" \
        -e CPU_CORES="$CPU_CORES" \
        -e CPU_MODEL="$CPU_MODEL" \
        -e RAM_TOTAL_MB="$RAM_TOTAL" \
        -e GPU_AVAILABLE="$GPU_AVAILABLE" \
        -e GPU_MODEL="$GPU_MODEL" \
        -e GPU_MEMORY_MB="$GPU_MEMORY" \
        -e GPU_COUNT="$GPU_COUNT" \
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
        --url "$API_URL" || error "Failed to start container"

    sleep 15
    if ! docker ps --filter "name=^${CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        error "Worker crashed. Logs:\n$(docker logs $CONTAINER_NAME 2>&1 | tail -50)"
    fi

    log "Worker started successfully with MAXIMUM storage access!"
    section "Contributor Setup Complete!"
    echo
    echo -e "${GREEN}Your node is now contributing FULL drives!${NC}"
    echo "   Storage: $((STORAGE_TOTAL/1024)) GB detected + any raw disks added"
    [[ -n "$EXTRA_DEVICES" ]] && echo -e "   ${GREEN}Raw disks attached!${NC}"
    echo
    echo -e "${CYAN}Monitor:${NC} docker logs -f $CONTAINER_NAME"
    echo -e "${BLUE}Dashboard:${NC} $API_URL/dashboard"
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
        # Re-check
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
    echo -e "${BOLD}${GREEN}║          DistributeX Universal Installer v9.0           ║${NC}"
    echo -e "${BOLD}${GREEN}║                    Installation Complete!               ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "   Dashboard → ${BLUE}$API_URL/dashboard${NC}"
    [[ "$USER_ROLE" == "developer" ]] && echo -e "   API Keys   → ${BLUE}$API_URL/api-dashboard${NC}"
    echo
    echo -e "   Support: ${CYAN}https://discord.gg/distributex${NC}"
    echo
}

trap 'error "Installation interrupted at line $LINENO"' ERR
main "$@"
exit 0
