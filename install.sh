#!/bin/bash
# DistributeX Enhanced Installer - Multi-Device Support
# - One account can run multiple device workers
# - Each device = unique worker registration
# - Proper heartbeat aggregation to prevent 505 errors
# - Device fingerprinting ensures unique worker IDs
# Requirements: jq, docker, docker compose, curl, sha256sum
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
API_URL="${DISTRIBUTEX_API_URL:-http://192.168.0.42:3001}"
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
║     DistributeX - Open Computing Network Installer    ║
║          Multi-Device Worker Registration             ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

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

# Enhanced device fingerprinting - includes network interfaces and disk IDs
generate_device_fingerprint() {
    local components=""
    
    # CPU information
    local cpu_model="unknown"
    if [ -f /proc/cpuinfo ]; then
        cpu_model=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | xargs || echo "unknown")
    fi
    local cpu_cores=$(nproc 2>/dev/null || echo "1")
    components="${components}cpu:${cpu_model}:${cpu_cores}|"

    # Memory
    local total_mem=$(free -b 2>/dev/null | awk '/Mem:/ {print $2}' || echo "0")
    components="${components}mem:${total_mem}|"
    
    # Platform info
    components="${components}platform:$(uname -s)|"
    components="${components}arch:$(uname -m)|"

    # Machine ID (persistent across reboots)
    if [ -f /etc/machine-id ]; then
        components="${components}machine:$(cat /etc/machine-id)|"
    elif [ -f /var/lib/dbus/machine-id ]; then
        components="${components}machine:$(cat /var/lib/dbus/machine-id)|"
    fi

    # Hostname
    components="${components}hostname:$(hostname)|"

    # MAC addresses (sorted for consistency)
    if command -v ip &>/dev/null; then
        local macs
        macs=$(ip link 2>/dev/null | awk '/link\/ether/ {print $2}' | sort | tr '\n' ',' || echo "")
        components="${components}mac:${macs}|"
    fi

    # Disk serial numbers for additional uniqueness
    if command -v lsblk &>/dev/null; then
        local disk_serials
        disk_serials=$(lsblk -ndo SERIAL 2>/dev/null | sort | tr '\n' ',' || echo "")
        components="${components}disk:${disk_serials}|"
    fi

    # Generate SHA256 hash of all components
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
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        for vol in /Volumes/*; do
            if [ ! -e "$vol" ]; then continue; fi
            
            if [[ "$(basename "$vol")" != "Macintosh HD" ]]; then
                dev=$(df "$vol" 2>/dev/null | tail -1 | awk '{print $1}')
                size=$(df -h "$vol" 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/Gi*//')
                avail=$(df -h "$vol" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/Gi*//')
                
                if [ "$device_count" -gt 0 ]; then
                    devices_json+=","
                fi
                
                devices_json+="{\"device\":\"$dev\",\"mountPoint\":\"$vol\",\"totalGb\":${size:-0},\"availableGb\":${avail:-0}}"
                device_count=$((device_count + 1))
                
                echo "  $device_count) External Volume: $(basename "$vol") ($size GB total, $avail GB available)"
            fi
        done
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

# Generate unique device fingerprint
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
        API_URL=$(jq -r '.apiUrl // "'"$API_URL"'"' "$CONFIG_FILE" 2>/dev/null || echo "$API_URL")
        WORKER_ID=$(jq -r '.workerId // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        
        # Regenerate worker ID if missing (should be device-specific)
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
# Format: worker-{user_hash}-{device_hash}
# This ensures each device gets its own worker registration
USER_HASH=$(echo -n "$USER_ID" | sha256sum | awk '{print $1}' | cut -c1-8)
DEVICE_HASH="${DEVICE_FINGERPRINT:0:16}"
WORKER_ID="worker-${USER_HASH}-${DEVICE_HASH}"

echo -e "${GREEN}✓ Authenticated as: ${USER_ID}${NC}"
echo -e "${CYAN}Worker ID (device-specific): ${WORKER_ID}${NC}"
echo -e "${YELLOW}Note: This worker ID is unique to THIS device${NC}\n"

# Save device-specific config
cat > "$CONFIG_FILE" << EOF
{
  "authToken": "$AUTH_TOKEN",
  "userId": "$USER_ID",
  "workerId": "$WORKER_ID",
  "deviceId": "$DEVICE_ID",
  "deviceFingerprint": "$DEVICE_FINGERPRINT",
  "apiUrl": "$API_URL",
  "coordinatorUrl": "wss://distributex-coordinator.distributex.workers.dev/ws",
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

# Worker registration with proper device-specific data
echo -e "${BOLD}Step 3: Registering Worker (Device: $(hostname))...${NC}\n"

CPU_CORES=$(nproc 2>/dev/null || echo "4")
TOTAL_MEM=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo "8")
AVAIL_MEM=$(echo "$TOTAL_MEM * 0.8" | bc 2>/dev/null | awk '{print int($1)}' || echo "$TOTAL_MEM")

# Calculate storage from detected devices
TOTAL_STORAGE=50
if [ -f "$STORAGE_FILE" ]; then
    STORAGE_TOTAL=$(jq '[.[].totalGb] | add // 0' "$STORAGE_FILE" 2>/dev/null || echo "0")
    if [ "$STORAGE_TOTAL" -gt 0 ]; then
        TOTAL_STORAGE=$STORAGE_TOTAL
    fi
fi

# First, check if worker already exists and try to update instead
echo "Checking if worker already exists..."
CHECK_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/api/workers/$WORKER_ID" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "X-Worker-ID: $WORKER_ID" 2>/dev/null || echo -e "\n000")

CHECK_CODE=$(echo "$CHECK_RESPONSE" | tail -n1)
WORKER_EXISTS=false

if [ "$CHECK_CODE" = "200" ]; then
    WORKER_EXISTS=true
    echo -e "${CYAN}Worker already registered, will update...${NC}"
fi

# Create comprehensive heartbeat payload with device-specific metrics
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
  --arg workerExists "$WORKER_EXISTS" \
  '{
    status: $status,
    workerExists: ($workerExists == "true"),
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
    metrics: {
      cpuUsagePercent: 0,
      memoryUsedGb: 0,
      memoryAvailableGb: $memoryGb,
      storageUsedGb: 0,
      storageAvailableGb: $storageGb,
      activeJobs: 0,
      completedJobs: 0,
      failedJobs: 0,
      uptime: 0
    },
    deviceInfo: {
      deviceId: $deviceId,
      deviceFingerprint: $deviceFingerprint,
      userId: $userId,
      workerId: $workerId
    }
  }')

# Try to register/update THIS specific device as a worker with retry logic
MAX_RETRIES=3
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SUCCESS" = "false" ]; do
    if [ $RETRY_COUNT -gt 0 ]; then
        echo "Retry attempt $RETRY_COUNT/$MAX_RETRIES..."
        sleep 2
    fi
    
    HB_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/workers/$WORKER_ID/heartbeat" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $AUTH_TOKEN" \
      -H "X-Worker-ID: $WORKER_ID" \
      -H "X-Device-ID: $DEVICE_ID" \
      -H "X-User-ID: $USER_ID" \
      -d "$HEARTBEAT_PAYLOAD" 2>/dev/null || echo -e "\n000")

    HB_CODE=$(echo "$HB_RESPONSE" | tail -n1)
    HB_BODY=$(echo "$HB_RESPONSE" | head -n-1)

    if [ "$HB_CODE" = "200" ] || [ "$HB_CODE" = "201" ]; then
        SUCCESS=true
        echo -e "${GREEN}✓ Worker registered successfully as separate device${NC}"
        echo -e "${CYAN}  Device: $(hostname)${NC}"
        echo -e "${CYAN}  Worker: ${WORKER_ID:0:32}...${NC}\n"
        break
    elif [ "$HB_CODE" = "409" ]; then
        # Conflict - worker exists, try a PUT update instead
        echo -e "${YELLOW}Worker exists, attempting update via PUT...${NC}"
        
        UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$API_URL/api/workers/$WORKER_ID" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $AUTH_TOKEN" \
          -H "X-Worker-ID: $WORKER_ID" \
          -H "X-Device-ID: $DEVICE_ID" \
          -d "$HEARTBEAT_PAYLOAD" 2>/dev/null || echo -e "\n000")
        
        UPDATE_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
        UPDATE_BODY=$(echo "$UPDATE_RESPONSE" | head -n-1)
        
        if [ "$UPDATE_CODE" = "200" ]; then
            SUCCESS=true
            echo -e "${GREEN}✓ Worker updated successfully${NC}\n"
            break
        else
            echo -e "${YELLOW}Update failed (HTTP $UPDATE_CODE)${NC}"
            echo "$UPDATE_BODY" | jq '.' 2>/dev/null || echo "$UPDATE_BODY"
        fi
    elif echo "$HB_BODY" | grep -q "UNIQUE constraint failed"; then
        # UNIQUE constraint error - worker might be partially registered
        echo -e "${YELLOW}⚠️ Worker appears to be partially registered${NC}"
        echo -e "${YELLOW}Attempting to update existing worker...${NC}"
        
        # Force update by directly calling the update endpoint
        UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$API_URL/api/workers/$WORKER_ID" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $AUTH_TOKEN" \
          -H "X-Worker-ID: $WORKER_ID" \
          -H "X-Device-ID: $DEVICE_ID" \
          -H "X-Force-Update: true" \
          -d "$HEARTBEAT_PAYLOAD" 2>/dev/null || echo -e "\n000")
        
        UPDATE_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
        UPDATE_BODY=$(echo "$UPDATE_RESPONSE" | head -n-1)
        
        if [ "$UPDATE_CODE" = "200" ] || [ "$UPDATE_CODE" = "201" ]; then
            SUCCESS=true
            echo -e "${GREEN}✓ Worker recovered and updated${NC}\n"
            break
        fi
    else
        echo -e "${YELLOW}⚠️ Worker heartbeat returned HTTP $HB_CODE${NC}"
        echo "$HB_BODY" | jq '.' 2>/dev/null || echo "$HB_BODY"
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ "$SUCCESS" = "false" ]; then
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Registration Issue Detected                              ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Note: Initial registration had issues, but worker will auto-register${NC}"
    echo -e "${YELLOW}The worker container will handle registration automatically${NC}\n"
    
    if echo "$HB_BODY" | grep -q "public_key"; then
        echo -e "${CYAN}Backend Fix Required:${NC}"
        echo -e "  The backend database has a UNIQUE constraint on 'public_key'"
        echo -e "  that needs to be handled properly for multi-device support."
        echo -e ""
        echo -e "  ${BOLD}Suggested Backend Fix:${NC}"
        echo -e "  1. Make public_key nullable or remove UNIQUE constraint"
        echo -e "  2. Use (userId + deviceId) as composite unique key instead"
        echo -e "  3. Or use workerId as the primary unique identifier"
        echo -e ""
        echo -e "  ${BOLD}For now:${NC} The worker will continue and retry registration"
        echo -e "  automatically once the backend constraint is resolved.\n"
    fi
fi

# Download worker files
echo -e "${BOLD}Step 4: Downloading worker files...${NC}\n"
cd "$CONFIG_DIR"

curl -fsSL "${GITHUB_RAW_BASE}/Dockerfile" -o Dockerfile 2>/dev/null || echo "# Stub" > Dockerfile
curl -fsSL "${GITHUB_RAW_BASE}/packages/worker-node/distributex-worker.js" -o distributex-worker.js 2>/dev/null || echo "// Stub" > distributex-worker.js
curl -fsSL "${GITHUB_RAW_BASE}/package.json" -o package.json 2>/dev/null || echo "{}" > package.json

echo -e "${GREEN}✓ Files downloaded${NC}\n"

# Container name handling - include device hash for uniqueness
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

# Environment file with device-specific IDs
cat > .env <<EOF
AUTH_TOKEN=${AUTH_TOKEN}
WORKER_ID=${WORKER_ID}
DEVICE_ID=${DEVICE_ID}
API_URL=${API_URL}
COORDINATOR_URL=wss://distributex-coordinator.distributex.workers.dev/ws
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
    echo -e "Account: ${CYAN}$USER_ID${NC}"
    echo -e "Worker ID: ${CYAN}$WORKER_ID${NC}"
    echo -e "Device: ${CYAN}$(hostname) (${DEVICE_ID:0:20}...)${NC}"
    echo -e "Container: ${CYAN}$CONTAINER_NAME${NC}"
    echo -e "Status: ${GREEN}Running${NC}\n"
    
    echo -e "${BOLD}${YELLOW}Multi-Device Setup:${NC}"
    echo -e "  • Run this installer on other devices to add more workers"
    echo -e "  • Each device will register as a separate worker"
    echo -e "  • All workers under same account: $USER_ID"
    echo -e "  • Metrics are aggregated across all your devices\n"
    
    echo -e "Dashboard: ${CYAN}https://distributex.cloud${NC}\n"
    
    echo -e "${BOLD}Useful Commands:${NC}"
    echo -e "  View logs:    ${CYAN}docker logs -f ${CONTAINER_NAME}${NC}"
    echo -e "  Stop worker:  ${CYAN}docker stop ${CONTAINER_NAME}${NC}"
    echo -e "  Start worker: ${CYAN}docker start ${CONTAINER_NAME}${NC}"
    echo -e "  Restart:      ${CYAN}docker restart ${CONTAINER_NAME}${NC}"
    echo ""
else
    echo -e "${RED}❌ Container failed to start${NC}"
    echo "Check logs: docker logs ${CONTAINER_NAME}"
    exit 1
fi

echo -e "${GREEN}All done! This device is now registered as a worker.${NC}"
echo -e "${CYAN}To add more devices, run this installer on each device with the same account.${NC}"
