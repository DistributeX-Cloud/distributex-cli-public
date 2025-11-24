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
GITHUB_RAW_BASE="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main"

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

# Check prerequisites
echo -e "${BOLD}Checking prerequisites...${NC}\n"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker ps &> /dev/null; then
    echo -e "${RED}❌ Docker daemon is not running${NC}"
    echo "Please start Docker and try again"
    exit 1
fi

echo -e "${GREEN}✓ Docker installed and running${NC}"

# Check for docker compose command
if docker compose version &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}❌ Docker Compose is not installed${NC}"
    echo "Please install Docker Compose"
    exit 1
fi

echo -e "${GREEN}✓ Docker Compose available${NC}\n"

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
        done < <(df -h 2>/dev/null | grep -E "^/dev/(sd|nvme)")
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: Detect external volumes
        while IFS= read -r mount_point; do
            device=$(df "$mount_point" | tail -1 | awk '{print $1}')
            size=$(df -h "$mount_point" | tail -1 | awk '{print $2}')
            avail=$(df -h "$mount_point" | tail -1 | awk '{print $4}')
            
            devices+=("$device")
            mount_points+=("$mount_point")
            device_names+=("External Volume: $(basename $mount_point) ($size total, $avail available)")
        done < <(ls /Volumes 2>/dev/null | grep -v "Macintosh HD" | while read vol; do echo "/Volumes/$vol"; done)
    fi
    
    if [ ${#devices[@]} -eq 0 ]; then
        echo -e "${YELLOW}No external storage devices detected${NC}"
        echo "[]" > "$CONFIG_DIR/storage_devices.json"
        echo ""
        return
    fi
    
    echo -e "${GREEN}Found ${#devices[@]} external storage device(s):${NC}\n"
    
    for i in "${!device_names[@]}"; do
        echo "  $((i+1))) ${device_names[$i]}"
    done
    
    echo ""
    echo "Select devices to use (comma-separated, e.g., 1,2) or press Enter to skip:"
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

# ==================== DEVICE FINGERPRINTING ====================
generate_device_fingerprint() {
    local components=""
    
    # CPU info
    local cpu_model=$(cat /proc/cpuinfo 2>/dev/null | grep "model name" | head -1 | cut -d: -f2 | xargs || echo "unknown")
    local cpu_cores=$(nproc 2>/dev/null || echo "1")
    components="${components}cpu:${cpu_model}:${cpu_cores}|"
    
    # Total memory
    local total_mem=$(free -b 2>/dev/null | grep Mem | awk '{print $2}' || echo "0")
    components="${components}mem:${total_mem}|"
    
    # Platform
    components="${components}platform:$(uname -s)|"
    components="${components}arch:$(uname -m)|"
    
    # Machine ID (most reliable)
    if [ -f /etc/machine-id ]; then
        local machine_id=$(cat /etc/machine-id)
        components="${components}machine:${machine_id}|"
    elif [ -f /var/lib/dbus/machine-id ]; then
        local machine_id=$(cat /var/lib/dbus/machine-id)
        components="${components}machine:${machine_id}|"
    fi
    
    # Hostname
    components="${components}hostname:$(hostname)|"
    
    # MAC addresses
    local macs=$(ip link 2>/dev/null | grep "link/ether" | awk '{print $2}' | sort | tr '\n' ',' || echo "")
    if [ -n "$macs" ]; then
        components="${components}mac:${macs}|"
    fi
    
    # Generate hash
    local fingerprint=$(echo -n "$components" | sha256sum | awk '{print $1}')
    echo "$fingerprint"
}

# ==================== AUTHENTICATION ====================
echo -e "${BOLD}Step 1: Authentication${NC}\n"

mkdir -p "$CONFIG_DIR"

# Generate device fingerprint
DEVICE_FINGERPRINT=$(generate_device_fingerprint)
DEVICE_ID="device-${DEVICE_FINGERPRINT:0:32}"

echo -e "${CYAN}Device ID: ${DEVICE_ID:0:20}...${NC}\n"

if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Existing configuration found${NC}"
    prompt "Use existing account? (y/n) " use_existing
    if [[ $use_existing =~ ^[Yy]$ ]]; then
        AUTH_TOKEN=$(jq -r '.authToken' "$CONFIG_FILE")
        USER_ID=$(jq -r '.userId' "$CONFIG_FILE")
        
        # Generate worker ID based on user + device
        USER_HASH=$(echo -n "$USER_ID" | sha256sum | awk '{print $1}' | cut -c1-8)
        DEVICE_HASH="${DEVICE_FINGERPRINT:0:16}"
        WORKER_ID="worker-${USER_HASH}-${DEVICE_HASH}"
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
    
    # Generate worker ID based on user + device
    USER_HASH=$(echo -n "$USER_ID" | sha256sum | awk '{print $1}' | cut -c1-8)
    DEVICE_HASH="${DEVICE_FINGERPRINT:0:16}"
    WORKER_ID="worker-${USER_HASH}-${DEVICE_HASH}"
fi

echo -e "${GREEN}✓ Worker ID: ${WORKER_ID}${NC}\n"

# ==================== DETECT STORAGE ====================
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

if [ "$GPU_TYPE" == "cpu" ]; then
    echo -e "${YELLOW}No GPU detected or GPU not accessible to Docker${NC}"
fi

echo ""

# ==================== SAVE CONFIG ====================
cat > "$CONFIG_FILE" << EOF
{
  "authToken": "$AUTH_TOKEN",
  "userId": "$USER_ID",
  "workerId": "$WORKER_ID",
  "deviceId": "$DEVICE_ID",
  "deviceFingerprint": "$DEVICE_FINGERPRINT",
  "apiUrl": "$API_URL",
  "coordinatorUrl": "wss://distributex-coordinator.distributex.workers.dev/ws",
  "gpuType": "$GPU_TYPE",
  "installedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo -e "${GREEN}✓ Configuration saved${NC}\n"

# ==================== DOWNLOAD REQUIRED FILES ====================
echo -e "${BOLD}Step 3: Downloading worker files...${NC}\n"

cd "$CONFIG_DIR"

# Download Dockerfile
echo "Downloading Dockerfile..."
curl -fsSL "${GITHUB_RAW_BASE}/Dockerfile" -o Dockerfile

# Download worker script
echo "Downloading worker script..."
curl -fsSL "${GITHUB_RAW_BASE}/packages/worker-node/distributex-worker.js" -o distributex-worker.js

# Download package.json
echo "Downloading package.json..."
curl -fsSL "${GITHUB_RAW_BASE}/package.json" -o package.json

# Download gpu-detect.sh (optional but referenced in Dockerfile)
echo "Downloading gpu-detect.sh..."
curl -fsSL "${GITHUB_RAW_BASE}/gpu-detect.sh" -o gpu-detect.sh || echo "# Stub file" > gpu-detect.sh

echo -e "${GREEN}✓ Files downloaded${NC}\n"

# ==================== CREATE DOCKER COMPOSE FILE ====================
echo -e "${BOLD}Step 4: Creating Docker Compose configuration...${NC}\n"

cat > docker-compose.yml << 'DOCKEREOF'
services:
  worker:
    build: .
    image: distributex-worker:latest
    container_name: distributex-worker
    restart: unless-stopped
    privileged: true
    environment:
      - AUTH_TOKEN=${AUTH_TOKEN}
      - WORKER_ID=${WORKER_ID}
      - API_URL=${API_URL}
      - COORDINATOR_URL=${COORDINATOR_URL}
      - NODE_NAME=${NODE_NAME:-distributex-worker}
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
    storage_count=$(jq 'length' "$CONFIG_DIR/storage_devices.json" 2>/dev/null || echo "0")
    if [ "$storage_count" -gt 0 ]; then
        echo "    # External Storage Mounts" >> docker-compose.yml
        jq -r '.[] | "      - \(.mountPoint):/external/storage\(.device | gsub("/dev/"; ""))/"' "$CONFIG_DIR/storage_devices.json" >> docker-compose.yml
    fi
fi

echo -e "${GREEN}✓ Docker Compose file created${NC}\n"

# ==================== CREATE .ENV FILE ====================
cat > .env << EOF
AUTH_TOKEN=$AUTH_TOKEN
WORKER_ID=$WORKER_ID
API_URL=$API_URL
COORDINATOR_URL=wss://distributex-coordinator.distributex.workers.dev/ws
NODE_NAME=distributex-worker-$(hostname)
EOF

echo -e "${GREEN}✓ Environment file created${NC}\n"

# ==================== BUILD & START WORKER ====================
echo -e "${BOLD}Step 5: Building and starting worker...${NC}\n"

echo "Building Docker image (this may take a few minutes)..."
$DOCKER_COMPOSE_CMD build

echo ""
echo "Starting worker container..."
$DOCKER_COMPOSE_CMD up -d

echo ""

# Wait for container to start
sleep 3

# Check if container is running
if docker ps | grep -q distributex-worker; then
    echo -e "${GREEN}${BOLD}✅ Installation Complete!${NC}\n"
    echo -e "Worker ID: ${CYAN}$WORKER_ID${NC}"
    echo -e "Status: ${GREEN}Running${NC}\n"
    echo -e "Dashboard: ${CYAN}https://distributex.cloud${NC}\n"
    echo -e "${BOLD}Useful Commands:${NC}"
    echo -e "  View logs:    ${CYAN}docker logs -f distributex-worker${NC}"
    echo -e "  Stop worker:  ${CYAN}docker stop distributex-worker${NC}"
    echo -e "  Start worker: ${CYAN}docker start distributex-worker${NC}"
    echo -e "  Restart:      ${CYAN}docker restart distributex-worker${NC}"
    echo ""
else
    echo -e "${RED}❌ Container failed to start${NC}"
    echo "Check logs with: docker logs distributex-worker"
    exit 1
fi
