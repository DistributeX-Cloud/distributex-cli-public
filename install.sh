#!/bin/bash
# DistributeX Enhanced Installation with Auto Storage Detection
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CONFIG_DIR="$HOME/.distributex"
CONFIG_FILE="$CONFIG_DIR/config.json"
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"

# Helper input functions
prompt() {
  local __msg="$1"; local __var="$2"
  local REPLY=""
  if [ -e /dev/tty ]; then
    read -r -p "$__msg" REPLY </dev/tty
  else
    read -r -p "$__msg" REPLY
  fi
  eval "$__var=\"\$REPLY\""
}

prompt_pass() {
  local __msg="$1"; local __var="$2"
  local REPLY=""
  if [ -e /dev/tty ]; then
    read -r -s -p "$__msg" REPLY </dev/tty
    echo
  else
    read -r -s -p "$__msg" REPLY
    echo
  fi
  eval "$__var=\"\$REPLY\""
}

echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔═══════════════════════════════════════════════════╗
║                                                   ║
║     DistributeX - Open Computing Network          ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

# ==================== DETECT EXTERNAL STORAGE ====================
detect_external_storage() {
    echo -e "${BOLD}Detecting External Storage Devices${NC}\n"
    
    local devices=()
    local mount_points=()
    local device_names=()
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux: Detect USB drives
        while IFS= read -r line; do
            device=$(echo "$line" | awk '{print $1}')
            mount_point=$(echo "$line" | awk '{print $3}')
            
            # Check if it's a removable device
            device_base=$(echo "$device" | sed 's/[0-9]*$//')
            if [ -f "/sys/block/$(basename $device_base)/removable" ]; then
                removable=$(cat "/sys/block/$(basename $device_base)/removable")
                if [ "$removable" == "1" ]; then
                    size=$(df -BG "$mount_point" 2>/dev/null | tail -1 | awk '{print $2}')
                    avail=$(df -BG "$mount_point" 2>/dev/null | tail -1 | awk '{print $4}')
                    
                    devices+=("$device")
                    mount_points+=("$mount_point")
                    device_names+=("USB Drive: $device ($size total, $avail available) at $mount_point")
                fi
            fi
        done < <(df -h | grep -E "^/dev/(sd|nvme)")
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: Detect external volumes
        while IFS= read -r mount_point; do
            device=$(df "$mount_point" | tail -1 | awk '{print $1}')
            size=$(df -h "$mount_point" | tail -1 | awk '{print $2}')
            avail=$(df -h "$mount_point" | tail -1 | awk '{print $4}')
            
            devices+=("$device")
            mount_points+=("$mount_point")
            device_names+=("External Volume: $(basename $mount_point) ($size total, $avail available)")
        done < <(ls /Volumes | grep -v "Macintosh HD" | while read vol; do echo "/Volumes/$vol"; done)
        
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        # Windows: Detect removable drives
        for drive in {D..Z}; do
            if [ -d "/$drive/" ]; then
                drivetype=$(wmic logicaldisk where "DeviceID='$drive:'" get DriveType 2>/dev/null | grep -o '[0-9]')
                if [ "$drivetype" == "2" ]; then  # 2 = Removable
                    size=$(wmic logicaldisk where "DeviceID='$drive:'" get Size 2>/dev/null | grep -o '[0-9]*')
                    free=$(wmic logicaldisk where "DeviceID='$drive:'" get FreeSpace 2>/dev/null | grep -o '[0-9]*')
                    
                    if [ -n "$size" ] && [ "$size" -gt 0 ]; then
                        size_gb=$((size / 1024 / 1024 / 1024))
                        free_gb=$((free / 1024 / 1024 / 1024))
                        
                        devices+=("$drive:")
                        mount_points+=("/$drive")
                        device_names+=("Drive $drive: (${size_gb}GB total, ${free_gb}GB free)")
                    fi
                fi
            fi
        done
    fi
    
    if [ ${#devices[@]} -eq 0 ]; then
        echo -e "${YELLOW}No external storage devices detected${NC}"
        echo ""
        return
    fi
    
    echo -e "${GREEN}Found ${#devices[@]} external storage device(s):${NC}\n"
    
    for i in "${!device_names[@]}"; do
        echo "  $((i+1))) ${device_names[$i]}"
    done
    
    echo ""
    echo "Select devices to use for distributed computing (comma-separated, e.g., 1,2,3)"
    echo "Or press Enter to skip"
    prompt "Selection: " selection
    
    if [ -z "$selection" ]; then
        echo -e "${YELLOW}Skipping external storage${NC}"
        echo "[]" > "$CONFIG_DIR/storage_devices.json"
        return
    fi
    
    # Parse selection
    IFS=',' read -ra SELECTED <<< "$selection"
    selected_devices="["
    
    for idx in "${SELECTED[@]}"; do
        idx=$((idx - 1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#devices[@]} ]; then
            if [ "$selected_devices" != "[" ]; then
                selected_devices+=","
            fi
            
            # Get size info
            mount_point="${mount_points[$idx]}"
            total_gb=$(df -BG "$mount_point" 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//')
            avail_gb=$(df -BG "$mount_point" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
            
            selected_devices+="{\"device\":\"${devices[$idx]}\",\"mountPoint\":\"${mount_points[$idx]}\",\"totalGb\":${total_gb:-0},\"availableGb\":${avail_gb:-0}}"
        fi
    done
    
    selected_devices+="]"
    
    echo "$selected_devices" > "$CONFIG_DIR/storage_devices.json"
    echo -e "${GREEN}✓ External storage configured${NC}\n"
}

# ==================== AUTHENTICATION ====================
echo -e "${BOLD}Step 1: Authentication${NC}\n"

if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Existing configuration found${NC}"
    prompt "Use existing account? (y/n) " use_existing
    if [[ $use_existing =~ ^[Yy]$ ]]; then
        AUTH_TOKEN=$(jq -r '.authToken' "$CONFIG_FILE")
        USER_ID=$(jq -r '.userId' "$CONFIG_FILE")
        WORKER_ID="worker-$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)"
    else
        rm "$CONFIG_FILE"
    fi
fi

if [ -z "$AUTH_TOKEN" ]; then
    echo "1) Create new account"
    echo "2) Login to existing account"
    prompt "Choice [1-2]: " auth_choice
    
    if [ "$auth_choice" == "1" ]; then
        prompt "Full Name: " name
        prompt "Email: " email
        prompt_pass "Password: " password
        
        echo ""
        echo "Select Role:"
        echo "  1) Contributor (share resources, support developers)"
        echo "  2) Developer (submit workloads, use network)"
        echo "  3) Both"
        prompt "Choice [1-3]: " role_choice
        
        case $role_choice in
            1) role="contributor" ;;
            2) role="developer" ;;
            3) role="both" ;;
            *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
        esac
        
        response=$(curl -s -X POST "$API_URL/api/auth/signup" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$name\",\"email\":\"$email\",\"password\":\"$password\",\"role\":\"$role\"}")
    else
        prompt "Email: " email
        prompt_pass "Password: " password
        
        response=$(curl -s -X POST "$API_URL/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    fi
    
    AUTH_TOKEN=$(echo "$response" | jq -r '.token')
    USER_ID=$(echo "$response" | jq -r '.user.id')
    WORKER_ID="worker-$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)"
fi

# ==================== DETECT STORAGE ====================
mkdir -p "$CONFIG_DIR"
detect_external_storage

# ==================== DETECT GPU ====================
echo -e "${BOLD}Step 2: Detecting GPU${NC}\n"

GPU_TYPE="cpu"
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null 2>&1; then
    if docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi &> /dev/null 2>&1; then
        GPU_TYPE="nvidia"
        echo -e "${GREEN}✓ NVIDIA GPU detected and accessible${NC}"
    fi
fi

# ==================== SAVE CONFIG ====================
cat > "$CONFIG_FILE" << EOF
{
  "authToken": "$AUTH_TOKEN",
  "userId": "$USER_ID",
  "workerId": "$WORKER_ID",
  "apiUrl": "$API_URL",
  "coordinatorUrl": "wss://distributex-coordinator.distributex.workers.dev/ws",
  "gpuType": "$GPU_TYPE",
  "installedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

# ==================== BUILD & START WORKER ====================
echo -e "\n${BOLD}Step 3: Starting Worker${NC}\n"

cd "$CONFIG_DIR"

# Create docker-compose.yml
cat > docker-compose.yml << 'DOCKEREOF'
version: '3.8'
services:
  worker:
    build: .
    container_name: distributex-worker
    restart: unless-stopped
    privileged: true
    environment:
      - AUTH_TOKEN=${AUTH_TOKEN}
      - WORKER_ID=${WORKER_ID}
      - API_URL=${API_URL}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./config.json:/config/config.json:ro
      - ./storage_devices.json:/config/storage_devices.json:ro
      - /tmp:/tmp
DOCKEREOF

# Add GPU support if detected
if [ "$GPU_TYPE" == "nvidia" ]; then
    cat >> docker-compose.yml << 'GPUEOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu, compute, utility]
GPUEOF
fi

# Add external storage mounts
if [ -f "$CONFIG_DIR/storage_devices.json" ]; then
    storage_count=$(jq 'length' "$CONFIG_DIR/storage_devices.json")
    if [ "$storage_count" -gt 0 ]; then
        echo "    # External Storage Mounts" >> docker-compose.yml
        jq -r '.[] | "      - \(.mountPoint):/external/storage\(.device | gsub("/dev/"; ""))/"' "$CONFIG_DIR/storage_devices.json" >> docker-compose.yml
    fi
fi

# Detect docker compose command
if command -v docker-compose &>/dev/null; then
    docker-compose up -d --build
elif docker compose version &>/dev/null; then
    docker compose up -d --build
else
    echo "ERROR: Docker Compose not found. Install it with:"
    echo "  sudo apt install docker-compose-plugin"
    exit 1
fi

echo -e "\n${GREEN}${BOLD}✅ Installation Complete!${NC}\n"
echo -e "Worker ID: ${CYAN}$WORKER_ID${NC}"
echo -e "Status: ${GREEN}Running${NC}\n"
echo -e "Dashboard: ${CYAN}https://distributex.cloud${NC}\n"
