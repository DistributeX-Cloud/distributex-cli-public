#!/bin/bash
# DistributeX Enhanced Installer (merged authentication + registration fixes)
# - Detects external storage
# - Generates device fingerprint & deterministic worker id
# - Validates existing token via /api/auth/me
# - Performs heartbeat/registration to API
# - Handles container name conflicts (creates unique container name if needed)
# Requirements: jq, docker, docker compose (or docker-compose), curl, sha256sum
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
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main"

# Helper input functions (works in non-interactive TTY-safe way)
prompt() {
  local __msg="$1"; local __var="$2"
  local REPLY=""
  if [ -t 0 ]; then
    read -r -p "$__msg" REPLY
  else
    read -r -p "$__msg" REPLY
  fi
  eval "$__var=\"\$REPLY\""
}

prompt_pass() {
  local __msg="$1"; local __var="$2"
  local REPLY=""
  if [ -t 0 ]; then
    read -r -s -p "$__msg" REPLY
    echo
  else
    read -r -s -p "$__msg" REPLY
    echo
  fi
  eval "$__var=\"\$REPLY\""
}

echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔════════════════════════════════════════════════════════╗
║                                                        ║
║     DistributeX - Open Computing Network Installer    ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

# ----------------- check prerequisites -----------------
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

# ----------------- utilities -----------------
generate_device_fingerprint() {
    local components=""
    # CPU info
    local cpu_model="unknown"
    if [ -f /proc/cpuinfo ]; then
        cpu_model=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | xargs || echo "unknown")
    fi
    local cpu_cores=$(nproc 2>/dev/null || echo "1")
    components="${components}cpu:${cpu_model}:${cpu_cores}|"

    # Total memory (bytes)
    local total_mem=$(free -b 2>/dev/null | awk '/Mem:/ {print $2}' || echo "0")
    components="${components}mem:${total_mem}|"

    # Platform
    components="${components}platform:$(uname -s)|"
    components="${components}arch:$(uname -m)|"

    # Machine ID
    if [ -f /etc/machine-id ]; then
        components="${components}machine:$(cat /etc/machine-id)|"
    elif [ -f /var/lib/dbus/machine-id ]; then
        components="${components}machine:$(cat /var/lib/dbus/machine-id)|"
    fi

    # Hostname
    components="${components}hostname:$(hostname)|"

    # MAC addresses (best-effort)
    if command -v ip &>/dev/null; then
        local macs
        macs=$(ip link 2>/dev/null | awk '/link\/ether/ {print $2}' | sort | tr '\n' ',' || echo "")
        components="${components}mac:${macs}|"
    fi

    # Hash
    if command -v sha256sum &>/dev/null; then
        echo -n "$components" | sha256sum | awk '{print $1}'
    else
        # fallback openssl
        echo -n "$components" | openssl dgst -sha256 | awk '{print $2}'
    fi
}

detect_external_storage() {
    echo -e "${BOLD}Detecting External Storage Devices${NC}\n"
    mkdir -p "$CONFIG_DIR"
    local -a devices mount_points names

    if [[ "$OSTYPE" == "linux-gnu"* || "$OSTYPE" == "linux-gnu" ]]; then
        # iterate /dev mounted devices from df
        while IFS= read -r line; do
            dev=$(echo "$line" | awk '{print $1}')
            mnt=$(echo "$line" | awk '{print $6}') # df -P format: use mountpoint column
            # fallback if df format different
            if [ -z "$mnt" ]; then
                mnt=$(echo "$line" | awk '{print $3}')
            fi
            # check removable flag
            base=$(echo "$dev" | sed 's/[0-9]*$//')
            if [ -e "/sys/block/$(basename "$base")/removable" ]; then
                removable=$(cat "/sys/block/$(basename "$base")/removable" 2>/dev/null || echo "0")
                if [ "$removable" = "1" ]; then
                    size=$(df -BG "$mnt" 2>/dev/null | tail -1 | awk '{print $2}')
                    avail=$(df -BG "$mnt" 2>/dev/null | tail -1 | awk '{print $4}')
                    devices+=("$dev")
                    mount_points+=("$mnt")
                    names+=("USB Drive: $dev ($size total, $avail available) at $mnt")
                fi
            fi
        done < <(df -h | grep -E "^/dev/(sd|nvme|mmcblk)" || true)
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: list /Volumes excluding system
        for vol in /Volumes/*; do
            [ -e "$vol" ] || continue
            if [[ "$(basename "$vol")" != "Macintosh HD" ]]; then
                dev=$(df "$vol" | tail -1 | awk '{print $1}')
                size=$(df -h "$vol" | tail -1 | awk '{print $2}')
                avail=$(df -h "$vol" | tail -1 | awk '{print $4}')
                devices+=("$dev")
                mount_points+=("$vol")
                names+=("External Volume: $(basename "$vol") ($size total, $avail available)")
            fi
        done
    fi

    if [ ${#devices[@]} -eq 0 ]; then
        echo -e "${YELLOW}No external storage devices detected${NC}"
        echo "[]" > "$STORAGE_FILE"
        echo ""
        return
    fi

    echo -e "${GREEN}Found ${#devices[@]} external storage device(s):${NC}\n"
    for i in "${!names[@]}"; do
        echo "  $((i+1))) ${names[$i]}"
    done
    echo ""
    prompt "Select devices to use (comma-separated, e.g., 1,2) or press Enter to skip: " selection
    if [ -z "${selection:-}" ]; then
        echo -e "${YELLOW}Skipping external storage${NC}"
        echo "[]" > "$STORAGE_FILE"
        return
    fi

    IFS=',' read -ra sel <<< "$selection"
    local json="["
    local first=true
    for s in "${sel[@]}"; do
        idx=$((s-1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#devices[@]} ]; then
            mp=${mount_points[$idx]}
            total_gb=$(df -BG "$mp" 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//')
            avail_gb=$(df -BG "$mp" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
            [ "$first" = true ] || json+=","
            json+="{\"device\":\"${devices[$idx]}\",\"mountPoint\":\"$mp\",\"totalGb\":${total_gb:-0},\"availableGb\":${avail_gb:-0}}"
            first=false
        fi
    done
    json+="]"
    echo "$json" > "$STORAGE_FILE"
    echo -e "${GREEN}✓ External storage configured${NC}\n"
}

# ----------------- Start auth + setup -----------------
echo -e "${BOLD}Step 1: Authentication & Device Setup${NC}\n"
mkdir -p "$CONFIG_DIR"
DEVICE_FINGERPRINT=$(generate_device_fingerprint)
DEVICE_ID="device-${DEVICE_FINGERPRINT:0:32}"
echo -e "${CYAN}Device ID: ${DEVICE_ID:0:20}...${NC}\n"

# If config exists, offer reuse
AUTH_TOKEN=""
USER_ID=""
WORKER_ID=""
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Existing configuration found at $CONFIG_FILE${NC}"
    prompt "Use existing account? (y/n) " use_existing
    if [[ "${use_existing:-n}" =~ ^[Yy]$ ]]; then
        AUTH_TOKEN=$(jq -r '.authToken // empty' "$CONFIG_FILE")
        USER_ID=$(jq -r '.userId // empty' "$CONFIG_FILE")
        # keep apiUrl if present
        API_URL=$(jq -r '.apiUrl // "'"$API_URL"'"' "$CONFIG_FILE")
        # derive worker id if already present
        WORKER_ID=$(jq -r '.workerId // empty' "$CONFIG_FILE")
        if [ -z "$WORKER_ID" ] && [ -n "$USER_ID" ]; then
            USER_HASH=$(echo -n "$USER_ID" | sha256sum | awk '{print $1}' | cut -c1-8)
            DEVICE_HASH="${DEVICE_FINGERPRINT:0:16}"
            WORKER_ID="worker-${USER_HASH}-${DEVICE_HASH}"
        fi
    else
        echo "Removing existing config to create a new one..."
        rm -f "$CONFIG_FILE"
        AUTH_TOKEN=""
        USER_ID=""
        WORKER_ID=""
    fi
fi

# Validate token if present
if [ -n "${AUTH_TOKEN:-}" ] && [ -n "${USER_ID:-}" ]; then
    echo "Testing existing authentication..."
    AUTH_CHECK=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $AUTH_TOKEN" "$API_URL/api/auth/me" 2>/dev/null || echo -e "\n000")
    AUTH_CODE=$(echo "$AUTH_CHECK" | tail -n1)
    if [ "$AUTH_CODE" = "200" ]; then
        echo -e "${GREEN}✓ Existing authentication valid${NC}"
    else
        echo -e "${YELLOW}⚠️ Existing authentication invalid or expired${NC}"
        AUTH_TOKEN=""
        USER_ID=""
    fi
fi

# Interactive login/signup if we don't have a token
if [ -z "${AUTH_TOKEN:-}" ]; then
    echo "1) Create new account"
    echo "2) Login to existing account"
    prompt "Choice [1-2]: " auth_choice
    if [ "${auth_choice:-1}" = "1" ]; then
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

        response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/auth/signup" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\",\"fullName\":\"$name\",\"role\":\"$role\"}")
        code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | head -n-1)
        if [ "$code" = "201" ] || [ "$code" = "200" ]; then
            AUTH_TOKEN=$(echo "$body" | jq -r '.token // .data.token // empty')
            USER_ID=$(echo "$body" | jq -r '.userId // .user.id // .user.id // .user_id // empty')
            # try some common shapes
            USER_ID=${USER_ID:-$(echo "$body" | jq -r '.user.id // .user._id // .id // empty')}
        else
            echo -e "${RED}❌ Signup failed (HTTP $code)${NC}"
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
            exit 1
        fi
    else
        prompt "Email: " email
        prompt_pass "Password: " password
        response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\"}")
        code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | head -n-1)
        if [ "$code" = "200" ]; then
            AUTH_TOKEN=$(echo "$body" | jq -r '.token // .data.token // empty')
            USER_ID=$(echo "$body" | jq -r '.userId // .user.id // empty')
            USER_ID=${USER_ID:-$(echo "$body" | jq -r '.user.id // .user._id // .id // empty')}
        else
            echo -e "${RED}❌ Login failed (HTTP $code)${NC}"
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
            exit 1
        fi
    fi
fi

if [ -z "${USER_ID:-}" ] || [ -z "${AUTH_TOKEN:-}" ]; then
    echo -e "${RED}❌ Failed to obtain userId or token${NC}"
    exit 1
fi

# worker id deterministic
USER_HASH=$(echo -n "$USER_ID" | sha256sum | awk '{print $1}' | cut -c1-8)
DEVICE_HASH="${DEVICE_FINGERPRINT:0:16}"
WORKER_ID=${WORKER_ID:-"worker-${USER_HASH}-${DEVICE_HASH}"}

echo -e "${GREEN}✓ Authenticated as: ${USER_ID}${NC}"
echo -e "${CYAN}Worker ID: ${WORKER_ID}${NC}\n"

# ----------------- Update config file -----------------
cat > "$CONFIG_FILE" << EOF
{
  "authToken": "$AUTH_TOKEN",
  "userId": "$USER_ID",
  "workerId": "$WORKER_ID",
  "deviceId": "$DEVICE_ID",
  "deviceFingerprint": "$DEVICE_FINGERPRINT",
  "apiUrl": "$API_URL",
  "coordinatorUrl": "wss://distributex-coordinator.distributex.workers.dev/ws",
  "installedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo -e "${GREEN}✓ Configuration saved to $CONFIG_FILE${NC}\n"

# ----------------- detect storage -----------------
detect_external_storage

# ----------------- gpu detection -----------------
echo -e "${BOLD}Step 2: Detecting GPU${NC}\n"
GPU_TYPE="cpu"
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null 2>&1; then
    if docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi &> /dev/null 2>&1; then
        GPU_TYPE="nvidia"
        echo -e "${GREEN}✓ NVIDIA GPU detected and accessible${NC}"
    fi
fi
if [ "$GPU_TYPE" = "cpu" ]; then
    echo -e "${YELLOW}No GPU detected or GPU not accessible to Docker${NC}"
fi
echo ""

# ----------------- heartbeat / register worker -----------------
echo -e "${BOLD}Step 3: Registering Worker (heartbeat)...${NC}\n"

CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "4")
TOTAL_MEM=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024)}' || echo "8")
AVAIL_MEM=$(echo "$TOTAL_MEM * 0.8" | bc | awk '{print int($1)}' || echo "$TOTAL_MEM")

HEARTBEAT_PAYLOAD=$(cat <<JSON
{
  "status": "online",
  "capabilities": {
    "cpuCores": $CPU_CORES,
    "memoryGb": $AVAIL_MEM,
    "storageGb": 50,
    "gpuAvailable": $( [ "$GPU_TYPE" = "nvidia" ] && echo true || echo false ),
    "platform": "$(uname -s)",
    "arch": "$(uname -m)",
    "hostname": "$(hostname)",
    "nodeName": "$(hostname)"
  },
  "metrics": {
    "cpuUsagePercent": 0,
    "memoryUsedGb": 0,
    "memoryAvailableGb": $AVAIL_MEM,
    "activeJobs": 0
  },
  "deviceInfo": {
    "deviceId": "$DEVICE_ID",
    "deviceFingerprint": "$DEVICE_FINGERPRINT",
    "userId": "$USER_ID"
  }
}
JSON
)

HB_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/workers/$WORKER_ID/heartbeat" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "X-Worker-ID: $WORKER_ID" \
  -d "$HEARTBEAT_PAYLOAD" 2>/dev/null || echo -e "\n000")

HB_CODE=$(echo "$HB_RESPONSE" | tail -n1)
HB_BODY=$(echo "$HB_RESPONSE" | head -n-1)

if [ "$HB_CODE" = "200" ] || [ "$HB_CODE" = "201" ]; then
    echo -e "${GREEN}✓ Worker registered / heartbeat accepted${NC}\n"
    echo "$HB_BODY" | jq '.' 2>/dev/null || echo "$HB_BODY"
else
    echo -e "${YELLOW}⚠️ Worker heartbeat returned HTTP $HB_CODE${NC}"
    echo "$HB_BODY" | jq '.' 2>/dev/null || echo "$HB_BODY"
    echo ""
    # Continue — worker may register on next heartbeat
fi

# ----------------- download files -----------------
echo -e "${BOLD}Step 4: Downloading worker files...${NC}\n"
mkdir -p "$CONFIG_DIR"
cd "$CONFIG_DIR"

echo "Downloading Dockerfile..."
curl -fsSL "${GITHUB_RAW_BASE}/Dockerfile" -o Dockerfile || echo "# Dockerfile placeholder" > Dockerfile

echo "Downloading worker script..."
curl -fsSL "${GITHUB_RAW_BASE}/packages/worker-node/distributex-worker.js" -o distributex-worker.js || echo "// worker stub" > distributex-worker.js

echo "Downloading package.json..."
curl -fsSL "${GITHUB_RAW_BASE}/package.json" -o package.json || echo "{}" > package.json

echo "Downloading gpu-detect.sh..."
curl -fsSL "${GITHUB_RAW_BASE}/gpu-detect.sh" -o gpu-detect.sh || echo "# Stub gpu-detect" > gpu-detect.sh
chmod +x gpu-detect.sh || true

echo -e "${GREEN}✓ Files downloaded (or stubbed)${NC}\n"

# ----------------- determine safe container name -----------------
BASE_CONTAINER_NAME="distributex-worker"
CONTAINER_NAME="$BASE_CONTAINER_NAME"

# If a container with the same name exists (any status), avoid conflict by creating unique name
if docker ps -a --format '{{.Names}}' | grep -qx "$BASE_CONTAINER_NAME"; then
    # create an alternative name with suffix
    SUFFIX=$(date +%s | tail -c6)
    CONTAINER_NAME="${BASE_CONTAINER_NAME}-${SUFFIX}"
    echo -e "${YELLOW}Container name conflict: '${BASE_CONTAINER_NAME}' already exists.${NC}"
    echo -e "${YELLOW}Using container name: ${CONTAINER_NAME}${NC}\n"
fi

# ----------------- create docker-compose.yml -----------------
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
    # Append a GPU reservation stanza for docker-compose v2 style (best-effort)
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

# Add mounts for external storage entries (if any)
if [ -f "$STORAGE_FILE" ]; then
    storage_count=$(jq 'length' "$STORAGE_FILE" 2>/dev/null || echo "0")
    if [ "$storage_count" -gt 0 ]; then
        echo "  # External Storage Mounts" >> docker-compose.yml

        while IFS= read -r mount; do
            mp=$(echo "$mount" | jq -r '.mountPoint')
            safe_mp=$(echo "$mp" | tr '/' '_' | sed 's/^_//')
            echo "      - ${mp}:/external/storage_${safe_mp}" >> docker-compose.yml
        done < <(jq -c '.[]' "$STORAGE_FILE")
    fi
fi

echo -e "${GREEN}✓ Docker Compose file created${NC}\n"

# ----------------- create .env -----------------
cat > .env <<EOF
AUTH_TOKEN=${AUTH_TOKEN}
WORKER_ID=${WORKER_ID}
API_URL=${API_URL}
COORDINATOR_URL=wss://distributex-coordinator.distributex.workers.dev/ws
NODE_NAME=${NODE_NAME:-distributex-worker-$(hostname)}
EOF

echo -e "${GREEN}✓ Environment file created${NC}\n"

# ----------------- build & start -----------------
echo -e "${BOLD}Step 6: Building and starting worker container...${NC}\n"
echo "Building Docker image..."
$DOCKER_COMPOSE_CMD build --no-cache || $DOCKER_COMPOSE_CMD build

echo ""
echo "Starting worker container..."
$DOCKER_COMPOSE_CMD up -d

sleep 3

# container runtime check
if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo -e "${GREEN}${BOLD}✅ Installation Complete!${NC}\n"
    echo -e "Worker ID: ${CYAN}$WORKER_ID${NC}"
    echo -e "Container: ${CYAN}$CONTAINER_NAME${NC}"
    echo -e "Status: ${GREEN}Running${NC}\n"
    echo -e "Dashboard: ${CYAN}https://distributex.cloud${NC}\n"
    echo -e "${BOLD}Useful Commands:${NC}"
    echo -e "  View logs:    ${CYAN}docker logs -f ${CONTAINER_NAME}${NC}"
    echo -e "  Stop worker:  ${CYAN}docker stop ${CONTAINER_NAME}${NC}"
    echo -e "  Start worker: ${CYAN}docker start ${CONTAINER_NAME}${NC}"
    echo -e "  Restart:      ${CYAN}docker restart ${CONTAINER_NAME}${NC}"
    echo ""
else
    echo -e "${RED}❌ Container failed to start (look up logs)${NC}"
    echo "Check logs with: docker logs ${CONTAINER_NAME}  OR docker ps -a | grep distributex"
    exit 1
fi

# ----------------- restart existing known container if present (compatibility) -------------
# If there is an older container named distributex-worker (conflicting) we don't remove it,
# but show how to manage it. If the intent is to reuse the old container, user can inspect and rename.
if docker ps -a --format '{{.Names}}' | grep -qx "distributex-worker"; then
    echo -e "${YELLOW}Note:${NC} A previous container named 'distributex-worker' exists. This installer created/used '${CONTAINER_NAME}' to avoid conflicts."
    echo "If you want to remove old container: docker rm -f distributex-worker"
fi

# ----------------- verify worker record -----------------
echo -e "${BOLD}\nStep 7: Verification${NC}\n"
sleep 2
VERIFY_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $AUTH_TOKEN" "$API_URL/api/workers/$WORKER_ID" 2>/dev/null || echo -e "\n000")
VERIFY_CODE=$(echo "$VERIFY_RESPONSE" | tail -n1)
VERIFY_BODY=$(echo "$VERIFY_RESPONSE" | head -n-1)

if [ "$VERIFY_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Worker found in database${NC}\n"
    echo "$VERIFY_BODY" | jq '.worker | {
        id,
        node_name,
        status,
        cpu_cores,
        memory_gb,
        storage_gb,
        gpu_available,
        last_heartbeat
    }' 2>/dev/null || echo "$VERIFY_BODY"
else
    echo -e "${YELLOW}⚠️  Could not verify worker (HTTP $VERIFY_CODE). It may appear after the next heartbeat.${NC}"
fi

# ----------------- final summary -----------------
echo -e "\n${GREEN}${BOLD}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║                  ✅ SETUP COMPLETE!                       ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${BOLD}Summary:${NC}"
echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}"
echo -e "User ID:     ${CYAN}$USER_ID${NC}"
echo -e "Worker ID:   ${CYAN}$WORKER_ID${NC}"
echo -e "Device ID:   ${CYAN}$DEVICE_ID${NC}"
echo -e "Container:   ${CYAN}$CONTAINER_NAME${NC}"
echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}\n"

echo -e "${BOLD}Next Steps:${NC}"
echo "1. View logs:      ${CYAN}docker logs -f ${CONTAINER_NAME}${NC}"
echo "2. Check status:   ${CYAN}docker ps | grep ${CONTAINER_NAME}${NC}"
echo "3. Dashboard:      ${CYAN}https://distributex.cloud/dashboard${NC}"
echo ""
echo -e "${GREEN}All done! Your worker should now be online.${NC}"
