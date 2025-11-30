#!/bin/bash
# DistributeX Installer v3.7.0 - Fixed Role Change
set -e

DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

show_banner() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║    DistributeX Cloud Network v3.7.0      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}\n"
}

check_requirements() {
    info "Checking requirements..."
    command -v docker &>/dev/null || error "Docker required: https://docs.docker.com/get-docker/"
    docker ps &>/dev/null || error "Docker daemon not running"
    
    for cmd in curl jq; do
        if ! command -v $cmd &>/dev/null; then
            warn "Installing $cmd..."
            if command -v apt-get &>/dev/null; then
                sudo apt-get update -qq && sudo apt-get install -y $cmd
            elif command -v brew &>/dev/null; then
                brew install $cmd
            fi
        fi
    done
    log "Requirements satisfied"
}

get_mac_address() {
    local mac=""
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        mac=$(ip link show 2>/dev/null | awk '/link\/ether/ {print $2; exit}')
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2; exit}')
        [ -z "$mac" ] && mac=$(ifconfig en1 2>/dev/null | awk '/ether/ {print $2; exit}')
    fi
    mac=$(echo "$mac" | tr -d ':-' | tr '[:upper:]' '[:lower:]')
    [[ "$mac" =~ ^[0-9a-f]{12}$ ]] && echo "$mac" || echo ""
}

detect_system() {
    info "Detecting system..."
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    HOSTNAME=$(hostname)
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 4096)
    MAC_ADDRESS=$(get_mac_address)
    
    [ -z "$MAC_ADDRESS" ] && error "Could not detect MAC address"
    
    GPU_AVAILABLE="false"
    GPU_COUNT=0
    if command -v nvidia-smi &>/dev/null; then
        GPU_AVAILABLE="true"
        GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l | xargs || echo 0)
    fi
    
    log "System detected: $OS/$ARCH, $CPU_CORES cores, ${RAM_TOTAL}MB RAM, GPU: $GPU_AVAILABLE"
}

authenticate_user() {
    info "Authentication..."
    mkdir -p "$CONFIG_DIR"
    
    if [ -f "$CONFIG_DIR/token" ]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        if curl -sf -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/user" &>/dev/null; then
            log "Using existing auth"
            return 0
        fi
        rm -f "$CONFIG_DIR/token"
    fi
    
    echo -e "\n${CYAN}1) Sign up  2) Login${NC}"
    read -r -p "Choice [1-2]: " choice </dev/tty
    
    if [ "$choice" = "1" ]; then
        read -r -p "First Name: " first_name </dev/tty
        read -r -p "Email: " email </dev/tty
        read -s -r -p "Password (min 8): " password </dev/tty
        echo ""
        
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\"}")
    else
        read -r -p "Email: " email </dev/tty
        read -s -r -p "Password: " password </dev/tty
        echo ""
        
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    fi
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ] && error "Auth failed: $(echo "$HTTP_BODY" | jq -r '.message // "Unknown error"')"
    
    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ] && error "No token returned"
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Authenticated successfully"
}

select_role() {
    info "Role selection..."
    
    # Check current role from API
    ROLE_INFO=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$DISTRIBUTEX_API_URL/api/auth/update-role" || echo "{}")
    CURRENT_ROLE=$(echo "$ROLE_INFO" | jq -r '.currentRole // "none"')
    
    if [ "$CURRENT_ROLE" != "none" ] && [ "$CURRENT_ROLE" != "null" ]; then
        echo -e "\n${CYAN}Current: ${GREEN}$CURRENT_ROLE${NC}"
        echo "1) Keep  2) Contributor  3) Developer"
        read -r -p "Choice [1-3]: " choice </dev/tty
        case "$choice" in
            1) USER_ROLE="$CURRENT_ROLE"; log "Keeping $USER_ROLE"; return ;;
            2) USER_ROLE="contributor" ;;
            3) USER_ROLE="developer" ;;
            *) error "Invalid choice" ;;
        esac
    else
        echo -e "\n${CYAN}Select role:${NC}"
        echo "1) Contributor (share resources)"
        echo "2) Developer (use resources)"
        read -r -p "Choice [1-2]: " choice </dev/tty
        [ "$choice" = "1" ] && USER_ROLE="contributor" || USER_ROLE="developer"
    fi
    
    # Update role via API (use POST not PUT)
    info "Updating to $USER_ROLE..."
    UPDATE_RESP=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/update-role" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"role\":\"$USER_ROLE\"}")
    
    UPDATE_BODY=$(echo "$UPDATE_RESP" | head -n -1)
    UPDATE_CODE=$(echo "$UPDATE_RESP" | tail -n1)
    
    if [ "$UPDATE_CODE" = "200" ]; then
        NEW_TOKEN=$(echo "$UPDATE_BODY" | jq -r '.token // empty')
        [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "null" ] && echo "$NEW_TOKEN" > "$CONFIG_DIR/token" && API_TOKEN="$NEW_TOKEN"
        log "Role set to $USER_ROLE"
    else
        warn "Role update failed: $(echo "$UPDATE_BODY" | jq -r '.message // "Unknown"')"
    fi
    
    echo "$USER_ROLE" > "$CONFIG_DIR/role"
}

register_worker() {
    info "Registering worker..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/workers/register" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"macAddress\":\"$MAC_ADDRESS\",\"name\":\"Worker-$MAC_ADDRESS\",\"hostname\":\"$HOSTNAME\",\"platform\":\"$OS\",\"cpuCores\":$CPU_CORES,\"ramTotal\":$RAM_TOTAL,\"gpuAvailable\":$GPU_AVAILABLE,\"gpuCount\":$GPU_COUNT}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        WORKER_ID=$(echo "$HTTP_BODY" | jq -r '.workerId')
        echo "$WORKER_ID" > "$CONFIG_DIR/worker_id"
        log "Worker registered: $WORKER_ID"
    fi
}

start_contributor() {
    info "Starting worker..."
    docker pull $DOCKER_IMAGE &>/dev/null
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
    
    register_worker
    echo "$MAC_ADDRESS" > "$CONFIG_DIR/mac_address"
    
    docker run -d --name $CONTAINER_NAME --restart unless-stopped \
        -e DISTRIBUTEX_API_URL="$DISTRIBUTEX_API_URL" \
        -e DISABLE_SELF_REGISTER=true \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -v "$CONFIG_DIR:/config:ro" \
        $DOCKER_IMAGE --api-key "$API_TOKEN" --url "$DISTRIBUTEX_API_URL" &>/dev/null
    
    sleep 3
    docker ps | grep -q $CONTAINER_NAME && log "Worker running" || error "Failed to start"
}

setup_developer() {
    info "Developer setup..."
    echo "$API_TOKEN" > "$CONFIG_DIR/api-key"
    chmod 600 "$CONFIG_DIR/api-key"
    log "API Key saved to: $CONFIG_DIR/api-key"
    echo -e "\n${GREEN}Your API Key:${NC}\n$API_TOKEN\n"
}

show_completion() {
    echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Installation Complete!             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"
    log "Role: $USER_ROLE"
    
    if [ "$USER_ROLE" = "contributor" ]; then
        echo -e "\n${CYAN}Management:${NC}"
        echo "  docker logs -f $CONTAINER_NAME  # View logs"
        echo "  docker restart $CONTAINER_NAME  # Restart"
        echo "  docker stop $CONTAINER_NAME     # Stop"
    else
        echo -e "\n${CYAN}Get started:${NC}"
        echo "  pip install distributex-cloud"
        echo "  from distributex import DistributeX"
        echo "  dx = DistributeX(api_key='$API_TOKEN')"
    fi
    echo ""
}

main() {
    show_banner
    check_requirements
    authenticate_user
    select_role
    detect_system
    
    [ "$USER_ROLE" = "contributor" ] && start_contributor || setup_developer
    show_completion
}

trap 'echo -e "\n${RED}Installation failed${NC}" >&2' ERR
main "$@"
