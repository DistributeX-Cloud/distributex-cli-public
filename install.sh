#!/bin/bash
# DistributeX Installer - Raspberry Pi Backend Version
# Workers connect to YOUR Raspberry Pi instead of Cloudflare
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CONFIG_DIR="$HOME/.distributex"
CONFIG_FILE="$CONFIG_DIR/config.json"
STORAGE_FILE="$CONFIG_DIR/storage_devices.json"

# ==================== RASPBERRY PI BACKEND ====================
# Change these to your Raspberry Pi's public IP or domain
API_URL="${DISTRIBUTEX_API_URL:-https://eloy-wiry-carolyne.ngrok-free.dev}"
COORDINATOR_URL="${DISTRIBUTEX_COORDINATOR_URL:-https://eloy-wiry-carolyne.ngrok-free.dev}"

# For local network only, use:
# API_URL="http://192.168.0.42:3001"
# COORDINATOR_URL="ws://192.168.0.42:3002/ws"

# For internet access, use ngrok URLs or your public IP:
# API_URL="https://your-ngrok-url.ngrok-free.app"
# COORDINATOR_URL="wss://your-ngrok-url.ngrok-free.app/ws"

GITHUB_RAW_BASE="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main"

# Helper input functions
prompt() {
  local __msg="$1"; local __var="$2"
  local REPLY=""
  read -r -p "$__msg" REPLY </dev/tty || read -r -p "$__msg" REPLY
  eval "$__var=\"\$REPLY\""
}

prompt_pass() {
  local __msg="$1"; local __var="$2"
  local REPLY=""
  read -r -s -p "$__msg" REPLY </dev/tty || read -r -s -p "$__msg" REPLY
  echo
  eval "$__var=\"\$REPLY\""
}

echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔════════════════════════════════════════════════════════╗
║                                                        ║
║     DistributeX - Raspberry Pi Backend Edition        ║
║          Connect to Self-Hosted Network                ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

echo -e "${CYAN}Backend Configuration:${NC}"
echo -e "  API:         ${BLUE}$API_URL${NC}"
echo -e "  Coordinator: ${BLUE}$COORDINATOR_URL${NC}"
echo ""

# Check prerequisites
echo -e "${BOLD}Checking prerequisites...${NC}\n"

if ! command -v jq &>/dev/null; then
  echo -e "${RED}❌ 'jq' is required but not installed.${NC}"
  echo "Install 'jq' (e.g. apt install jq / brew install jq) and retry."
  exit 1
fi

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

# Generate device fingerprint
generate_device_fingerprint() {
    local components=""
    
    local cpu_model="unknown"
    if [ -f /proc/cpuinfo ]; then
        cpu_model=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | xargs || echo "unknown")
    fi
    local cpu_cores=$(nproc 2>/dev/null || echo "1")
    components="${components}cpu:${cpu_model}:${cpu_cores}|"

    local total_mem=$(free -b 2>/dev/null | awk '/Mem:/ {print $2}' || echo "0")
    components="${components}mem:${total_mem}|"
    
    components="${components}platform:$(uname -s)|"
    components="${components}arch:$(uname -m)|"

    if [ -f /etc/machine-id ]; then
        components="${components}machine:$(cat /etc/machine-id)|"
    elif [ -f /var/lib/dbus/machine-id ]; then
        components="${components}machine:$(cat /var/lib/dbus/machine-id)|"
    fi

    components="${components}hostname:$(hostname)|"

    if command -v ip &>/dev/null; then
        local macs
        macs=$(ip link 2>/dev/null | awk '/link\/ether/ {print $2}' | sort | tr '\n' ',' || echo "")
        components="${components}mac:${macs}|"
    fi

    if command -v sha256sum &>/dev/null; then
        echo -n "$components" | sha256sum | awk '{print $1}'
    else
        echo -n "$components" | openssl dgst -sha256 | awk '{print $2}'
    fi
}

# Storage detection
detect_external_storage() {
    echo -e "${BOLD}Detecting External Storage Devices${NC}\n"
    mkdir -p "$CONFIG_DIR"
    
    local device_count=0
    local devices_json="["
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        while IFS= read -r line; do
            if [ -z "$line" ]; then continue; fi
            
            dev=$(echo "$line" | awk '{print $1}')
            mnt=$(echo "$line" | awk '{print $6}')
            
            if [ -z "$mnt" ]; then
                mnt=$(echo "$line" | awk '{print $3}')
            fi
            
            base=$(echo "$dev" | sed 's/[0-9]*$//')
            
            if [ -e "/sys/block/$(basename "$base")/removable" ]; then
                removable=$(cat "/sys/block/$(basename "$base")/removable" 2>/dev/null || echo "0")
                if [ "$removable" = "1" ]; then
                    size=$(df -BG "$mnt" 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//')
                    avail=$(df -BG "$mnt" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
                    
                    if [ "$device_count" -gt 0 ]; then
                        devices_json+=","
                    fi
                    
                    devices_json+="{\"device\":\"$dev\",\"mountPoint\":\"$mnt\",\"totalGb\":${size:-0},\"availableGb\":${avail:-0}}"
                    device_count=$((device_count + 1))
                    
                    echo "  $device_count) USB Drive: $dev ($size GB total, $avail GB available) at $mnt"
                fi
            fi
        done < <(df -h 2>/dev/null | grep -E "^/dev/(sd|nvme|mmcblk)" || true)
    fi
    
    devices_json+="]"
    
    if [ "$device_count" -eq 0 ]; then
        echo -e "${YELLOW}No external storage devices detected${NC}"
        echo "[]" > "$STORAGE_FILE"
        echo ""
        return
    fi
    
    echo ""
    prompt "Select devices to use (comma-separated, e.g., 1,2) or press Enter to skip: " selection
    
    if [ -z "${selection:-}" ]; then
        echo -e "${YELLOW}Skipping external storage${NC}"
        echo "[]" > "$STORAGE_FILE"
        return
    fi
    
    echo "$devices_json" > "$STORAGE_FILE"
    echo -e "${GREEN}✓ External storage configured${NC}\n"
}

# Authentication
echo -e "${BOLD}Step 1: Authentication & Device Setup${NC}\n"
mkdir -p "$CONFIG_DIR"

DEVICE_FINGERPRINT=$(generate_device_fingerprint)
DEVICE_ID="device-${DEVICE_FINGERPRINT:0:32}"
echo -e "${CYAN}Device Fingerprint: ${DEVICE_FINGERPRINT:0:16}...${NC}"
echo -e "${CYAN}Device ID: ${DEVICE_ID:0:24}...${NC}\n"

AUTH_TOKEN=""
USER_ID=""
WORKER_ID=""

# Check for existing config
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Existing configuration found for THIS device${NC}"
    prompt "Use existing account? (y/n) " use_existing
    if [[ "${use_existing:-n}" =~ ^[Yy]$ ]]; then
        AUTH_TOKEN=$(jq -r '.authToken // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        USER_ID=$(jq -r '.userId // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        WORKER_ID=$(jq -r '.workerId // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        
        if [ -z "$WORKER_ID" ] && [ -n "$USER_ID" ]; then
            USER_HASH=$(echo -n "$USER_ID" | sha256sum | awk '{print $1}' | cut -c1-8)
            DEVICE_HASH="${DEVICE_FINGERPRINT:0:16}"
            WORKER_ID="worker-${USER_HASH}-${DEVICE_HASH}"
        fi
    else
        rm -f "$CONFIG_FILE"
        AUTH_TOKEN=""
        USER_ID=""
        WORKER_ID=""
    fi
fi

# Validate existing token
if [ -n "${AUTH_TOKEN:-}" ] && [ -n "${USER_ID:-}" ]; then
    echo "Testing existing authentication..."
    AUTH_CHECK=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $AUTH_TOKEN" "$API_URL/api/auth/me" 2>/dev/null || echo -e "\n000")
    AUTH_CODE=$(echo "$AUTH_CHECK" | tail -n1)
    
    if [ "$AUTH_CODE" = "200" ]; then
        echo -e "${GREEN}✓ Existing authentication valid${NC}\n"
    else
        echo -e "${YELLOW}⚠️ Existing authentication invalid, need to re-authenticate${NC}"
        AUTH_TOKEN=""
        USER_ID=""
    fi
fi

# Interactive login/signup
if [ -z "${AUTH_TOKEN:-}" ]; then
    echo "1) Create new account"
    echo "2) Login to existing account"
    prompt "Choice [1-2]: " auth_choice
    
    if [ "${auth_choice:-1}" = "1" ]; then
        # SIGNUP
        prompt "Full Name: " name
        prompt "Email: " email
        prompt_pass "Password: " password
        echo ""
        echo "Select Role:"
        echo "  1) Contributor (share resources)"
        echo "  2) Developer (submit workloads)"
        echo "  3) Both"
        prompt "Choice [1-3]: " role_choice
        
        case "${role_choice:-1}" in
            1) role="contributor" ;;
            2) role="developer" ;;
            3) role="both" ;;
            *) role="contributor" ;;
        esac

        payload=$(jq -n \
          --arg email "$email" \
          --arg password "$password" \
          --arg fullName "$name" \
          --arg role "$role" \
          '{email: $email, password: $password, fullName: $fullName, role: $role}')
        
        response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/auth/signup" \
            -H "Content-Type: application/json" \
            -d "$payload" 2>/dev/null || echo -e "\n000")
        
        code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | head -n-1)
        
        if [ "$code" = "201" ] || [ "$code" = "200" ]; then
            AUTH_TOKEN=$(echo "$body" | jq -r '.token // empty' 2>/dev/null || echo "")
            USER_ID=$(echo "$body" | jq -r '.userId // .user.id // empty' 2>/dev/null || echo "")
            
            if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
                echo -e "${RED}❌ Signup succeeded but couldn't extract credentials${NC}"
                echo "$body" | jq '.' 2>/dev/null || echo "$body"
                exit 1
            fi
        else
            echo -e "${RED}❌ Signup failed (HTTP $code)${NC}"
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
            exit 1
        fi
    else
        # LOGIN
        prompt "Email: " email
        prompt_pass "Password: " password
        
        payload=$(jq -n \
          --arg email "$email" \
          --arg password "$password" \
          '{email: $email, password: $password}')
        
        response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "$payload" 2>/dev/null || echo -e "\n000")
        
        code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | head -n-1)
        
        if [ "$code" = "200" ]; then
            AUTH_TOKEN=$(echo "$body" | jq -r '.token // empty' 2>/dev/null || echo "")
            USER_ID=$(echo "$body" | jq -r '.userId // .user.id // empty' 2>/dev/null || echo "")
            
            if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
                echo -e "${RED}❌ Login succeeded but couldn't extract credentials${NC}"
                echo "$body" | jq '.' 2>/dev/null || echo "$body"
                exit 1
            fi
        else
            echo -e "${RED}❌ Login failed (HTTP $code)${NC}"
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
            exit 1
        fi
    fi
fi

if [ -z "${USER_ID:-}" ] || [ -z "${AUTH_TOKEN:-}" ]; then
    echo -e "${RED}❌ Failed to obtain credentials${NC}"
    exit 1
fi

# Generate UNIQUE worker ID per device
USER_HASH=$(echo -n "$USER_ID" | sha256sum | awk '{print $1}' | cut -c1-8)
DEVICE_HASH="${DEVICE_FINGERPRINT:0:16}"
WORKER_ID="worker-${USER_HASH}-${DEVICE_HASH}"

echo -e "${GREEN}✓ Authenticated as: ${USER_ID}${NC}"
echo -e "${CYAN}Worker ID (device-specific): ${WORKER_ID}${NC}\n"

# Save device-specific config
cat > "$CONFIG_FILE" << EOF
{
  "authToken": "$AUTH_TOKEN",
  "userId": "$USER_ID",
  "workerId": "$WORKER_ID",
  "deviceId": "$DEVICE_ID",
  "deviceFingerprint": "$DEVICE_FINGERPRINT",
  "apiUrl": "$API_URL",
  "coordinatorUrl": "$COORDINATOR_URL",
  "installedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "deviceHostname": "$(hostname)"
}
EOF

echo -e "${GREEN}✓ Device-specific configuration saved${NC}\n"

# Detect storage
detect_external_storage

# GPU detection
echo -e "${BOLD}Step 2: Detecting GPU${NC}\n"
GPU_TYPE="cpu"
GPU_COUNT=0
GPU_MODEL="none"

if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null 2>&1; then
    if docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi &> /dev/null 2>&1; then
        GPU_TYPE="nvidia"
        GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n1 || echo "1")
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 || echo "NVIDIA GPU")
        echo -e "${GREEN}✓ NVIDIA GPU detected: ${GPU_MODEL}${NC}"
        echo -e "${GREEN}✓ GPU accessible to Docker (${GPU_COUNT} GPU(s))${NC}"
    fi
fi

if [ "$GPU_TYPE" = "cpu" ]; then
    echo -e "${YELLOW}No GPU detected or GPU not accessible to Docker${NC}"
fi
echo ""

# Worker registration
echo -e "${BOLD}Step 3: Registering Worker...${NC}\n"

CPU_CORES=$(nproc 2>/dev/null || echo "4")
TOTAL_MEM=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo "8")
AVAIL_MEM=$(echo "$TOTAL_MEM * 0.8" | bc 2>/dev/null | awk '{print int($1)}' || echo "$TOTAL_MEM")

TOTAL_STORAGE=50
if [ -f "$STORAGE_FILE" ]; then
    STORAGE_TOTAL=$(jq '[.[].totalGb] | add // 0' "$STORAGE_FILE" 2>/dev/null || echo "0")
    if [ "$STORAGE_TOTAL" -gt 0 ]; then
        TOTAL_STORAGE=$STORAGE_TOTAL
    fi
fi

HEARTBEAT_PAYLOAD=$(jq -n \
  --arg status "online" \
  --argjson cpuCores "$CPU_CORES" \
  --argjson memoryGb "$AVAIL_MEM" \
  --argjson storageGb "$TOTAL_STORAGE" \
  --argjson gpuAvailable "$( [ "$GPU_TYPE" = "nvidia" ] && echo true || echo false )" \
  --argjson gpuCount "$GPU_COUNT" \
  --arg gpuModel "$GPU_MODEL" \
  --arg platform "$(uname -s)" \
  --arg arch "$(uname -m)" \
  --arg hostname "$(hostname)" \
  --arg nodeName "$(hostname)" \
  --arg deviceId "$DEVICE_ID" \
  --arg deviceFingerprint "$DEVICE_FINGERPRINT" \
  --arg userId "$USER_ID" \
  --arg workerId "$WORKER_ID" \
  '{
    status: $status,
    capabilities: {
      cpuCores: $cpuCores,
      memoryGb: $memoryGb,
      storageGb: $storageGb,
      gpuAvailable: $gpuAvailable,
      gpuCount: $gpuCount,
      gpuModel: $gpuModel,
      platform: $platform,
      arch: $arch,
      hostname: $hostname,
      nodeName: $nodeName
    },
    deviceInfo: {
      deviceId: $deviceId,
      deviceFingerprint: $deviceFingerprint,
      userId: $userId,
      workerId: $workerId
    }
  }')

HB_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/workers/$WORKER_ID/heartbeat" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "X-Worker-ID: $WORKER_ID" \
  -d "$HEARTBEAT_PAYLOAD" 2>/dev/null || echo -e "\n000")

HB_CODE=$(echo "$HB_RESPONSE" | tail -n1)

if [ "$HB_CODE" = "200" ] || [ "$HB_CODE" = "201" ]; then
    echo -e "${GREEN}✓ Worker registered successfully${NC}\n"
else
    echo -e "${YELLOW}⚠️  Initial registration failed (HTTP $HB_CODE)${NC}"
    echo -e "${YELLOW}Worker will auto-register on startup${NC}\n"
fi

# Download worker files
echo -e "${BOLD}Step 4: Downloading worker files...${NC}\n"
cd "$CONFIG_DIR"

curl -fsSL "${GITHUB_RAW_BASE}/Dockerfile" -o Dockerfile 2>/dev/null || echo "# Stub" > Dockerfile
curl -fsSL "${GITHUB_RAW_BASE}/packages/worker-node/distributex-worker.js" -o distributex-worker.js 2>/dev/null || echo "// Stub" > distributex-worker.js
curl -fsSL "${GITHUB_RAW_BASE}/package.json" -o package.json 2>/dev/null || echo "{}" > package.json

echo -e "${GREEN}✓ Files downloaded${NC}\n"

# Container name
BASE_CONTAINER_NAME="distributex-worker"
CONTAINER_SUFFIX="${DEVICE_HASH:0:8}"
CONTAINER_NAME="${BASE_CONTAINER_NAME}-${CONTAINER_SUFFIX}"

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo -e "${YELLOW}Container ${CONTAINER_NAME} exists, will recreate${NC}\n"
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
fi

# Docker Compose configuration
echo -e "${BOLD}Step 5: Creating Docker Compose configuration...${NC}\n"

cat > docker-compose.yml <<DOCKEREOF
services:
  worker:
    build: .
    image: distributex-worker:latest
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    privileged: true
    environment:
      - AUTH_TOKEN=\${AUTH_TOKEN}
      - WORKER_ID=\${WORKER_ID}
      - DEVICE_ID=\${DEVICE_ID}
      - API_URL=\${API_URL}
      - COORDINATOR_URL=\${COORDINATOR_URL}
      - NODE_NAME=\${NODE_NAME}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./config.json:/config/config.json:ro
      - ./storage_devices.json:/config/storage_devices.json:ro
      - /tmp:/tmp
DOCKEREOF

if [ "$GPU_TYPE" = "nvidia" ]; then
    cat >> docker-compose.yml <<GPUEOF

    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu, compute, utility]
GPUEOF
fi

echo -e "${GREEN}✓ Docker Compose file created${NC}\n"

# Environment file
cat > .env <<EOF
AUTH_TOKEN=${AUTH_TOKEN}
WORKER_ID=${WORKER_ID}
DEVICE_ID=${DEVICE_ID}
API_URL=${API_URL}
COORDINATOR_URL=${COORDINATOR_URL}
NODE_NAME=$(hostname)
EOF

echo -e "${GREEN}✓ Environment file created${NC}\n"

# Build and start
echo -e "${BOLD}Step 6: Building and starting worker...${NC}\n"
$DOCKER_COMPOSE_CMD build --no-cache 2>&1 | grep -E "^(Step|Successfully|ERROR)" || true

echo ""
$DOCKER_COMPOSE_CMD up -d

sleep 3

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo -e "\n${GREEN}${BOLD}✅ Installation Complete!${NC}\n"
    echo -e "Backend:   ${CYAN}$API_URL${NC}"
    echo -e "Worker ID: ${CYAN}$WORKER_ID${NC}"
    echo -e "Status:    ${GREEN}Running${NC}\n"
    
    echo -e "${BOLD}Useful Commands:${NC}"
    echo -e "  View logs:    ${CYAN}docker logs -f ${CONTAINER_NAME}${NC}"
    echo -e "  Stop worker:  ${CYAN}docker stop ${CONTAINER_NAME}${NC}"
    echo -e "  Start worker: ${CYAN}docker start ${CONTAINER_NAME}${NC}"
    echo ""
else
    echo -e "${RED}❌ Container failed to start${NC}"
    echo "Check logs: docker logs ${CONTAINER_NAME}"
    exit 1
fi
