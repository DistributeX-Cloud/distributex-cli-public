#!/bin/bash
#
# DistributeX Universal Installer v7.0
# → Detects role: contributor or developer
# → Contributors: Install Docker worker
# → Developers: Show API token + SDK instructions
#
set -e

# ============================================================================
# CONFIG
# ============================================================================
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

# ============================================================================
# HELPERS
# ============================================================================
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
╔═══════════════════════════════════════════════════════════════╗
║   DistributeX Universal Installer v7.0                        ║
║   Smart Role Detection → Contributor or Developer             ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# ============================================================================
# AUTHENTICATION
# ============================================================================
authenticate_user() {
    section "Authentication"
    mkdir -p "$CONFIG_DIR"
    
    # Check existing session
    if [[ -f "$CONFIG_DIR/token" ]]; then
        local token=$(cat "$CONFIG_DIR/token")
        local resp=$(curl -s -H "Authorization: Bearer $token" "$API_URL/api/auth/user" 2>/dev/null || echo "{}")
        local user_id=$(safe_jq '.id' "$resp")
        
        if [[ -n "$user_id" && "$user_id" != "null" ]]; then
            API_TOKEN="$token"
            USER_EMAIL=$(safe_jq '.email' "$resp")
            USER_ROLE=$(safe_jq '.role' "$resp")
            log "Already logged in as: $USER_EMAIL"
            return 0
        fi
    fi
    
    # Login or signup
    echo -e "${CYAN}1) Login   2) Sign up${NC}"
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
    
    if [[ "$code" != "200" ]]; then
        error "Login failed: $(safe_jq '.message' "$body")"
    fi
    
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
    
    if [[ ! "$code" =~ ^2 ]]; then
        error "Signup failed: $(safe_jq '.message' "$body")"
    fi
    
    API_TOKEN=$(safe_jq '.token' "$body")
    USER_EMAIL="$email"
    USER_ROLE=$(safe_jq '.user.role' "$body")
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    
    log "Account created: $USER_EMAIL"
}

# ============================================================================
# ROLE SELECTION
# ============================================================================
select_role() {
    section "Select Your Role"
    
    # Check if role already set
    if [[ -n "$USER_ROLE" && "$USER_ROLE" != "null" ]]; then
        log "Current role: $USER_ROLE"
        read -p "Change role? (y/N): " change </dev/tty
        [[ "$change" =~ ^[Yy]$ ]] || return 0
    fi
    
    echo ""
    echo -e "${CYAN}${BOLD}Choose your role:${NC}"
    echo ""
    echo -e "${GREEN}1) Contributor${NC}"
    echo "   • Share your computer's resources"
    echo "   • Earn by contributing CPU, RAM, GPU, Storage"
    echo "   • Install Docker worker"
    echo ""
    echo -e "${BLUE}2) Developer${NC}"
    echo "   • Use the distributed network"
    echo "   • Run your code on global resources"
    echo "   • Get API key for SDK"
    echo ""
    
    while :; do
        read -p "Enter choice (1 or 2): " role_choice </dev/tty
        case "$role_choice" in
            1)
                NEW_ROLE="contributor"
                break
                ;;
            2)
                NEW_ROLE="developer"
                break
                ;;
            *)
                warn "Invalid choice. Please enter 1 or 2"
                ;;
        esac
    done
    
    # Update role via API
    local resp=$(curl -s -X POST "$API_URL/api/auth/update-role" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"role\":\"$NEW_ROLE\"}")
    
    local success=$(safe_jq '.success' "$resp")
    
    if [[ "$success" != "true" ]]; then
        error "Failed to set role: $(safe_jq '.message' "$resp")"
    fi
    
    USER_ROLE="$NEW_ROLE"
    
    # Get new token with role
    local new_token=$(safe_jq '.token' "$resp")
    if [[ -n "$new_token" && "$new_token" != "null" ]]; then
        API_TOKEN="$new_token"
        echo "$API_TOKEN" > "$CONFIG_DIR/token"
    fi
    
    log "Role set to: $USER_ROLE"
}

# ============================================================================
# CONTRIBUTOR SETUP (Docker Worker)
# ============================================================================
setup_contributor() {
    section "Setting Up Contributor Worker"
    
    # Check Docker
    if ! command -v docker &>/dev/null; then
        error "Docker not found. Install from: https://docs.docker.com/get-docker/"
    fi
    
    docker ps &>/dev/null || error "Docker daemon not running"
    
    log "Docker is ready"
    
    # Detect system
    info "Detecting system capabilities..."
    
    MAC_ADDRESS=$(get_mac_address)
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 8192)
    
    log "MAC: $MAC_ADDRESS"
    log "CPU: $CPU_CORES cores"
    log "RAM: $((RAM_TOTAL/1024)) GB"
    
    # Pull Docker image
    info "Pulling worker image..."
    docker pull "$DOCKER_IMAGE" >/dev/null 2>&1 || warn "Pull failed, will use existing image"
    
    # Stop existing container
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    
    # Start worker
    info "Starting worker container..."
    
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --network host \
        -v "$CONFIG_DIR:/config:ro" \
        -e HOST_MAC_ADDRESS="$MAC_ADDRESS" \
        -e DISABLE_SELF_REGISTER=true \
        "$DOCKER_IMAGE" \
        --api-key "$API_TOKEN" \
        --url "$API_URL" >/dev/null
    
    sleep 5
    
    if docker ps --filter "name=^${CONTAINER_NAME}$" | grep -q "$CONTAINER_NAME"; then
        log "Worker started successfully!"
    else
        error "Failed to start worker"
    fi
    
    # Show status
    section "Contributor Setup Complete!"
    echo ""
    echo -e "${GREEN}✅ Your worker is now active!${NC}"
    echo ""
    echo "Worker ID: Worker-$MAC_ADDRESS"
    echo "Resources: $CPU_CORES cores, $((RAM_TOTAL/1024)) GB RAM"
    echo ""
    echo -e "${CYAN}Management commands:${NC}"
    echo "  View status:  docker ps -a | grep distributex"
    echo "  View logs:    docker logs $CONTAINER_NAME"
    echo "  Stop worker:  docker stop $CONTAINER_NAME"
    echo "  Start worker: docker start $CONTAINER_NAME"
    echo ""
    echo -e "${BLUE}Dashboard: $API_URL/dashboard${NC}"
    echo ""
}

# ============================================================================
# DEVELOPER SETUP (API Key + Instructions)
# ============================================================================
setup_developer() {
    section "Setting Up Developer Access"
    
    # Get or generate API token
    info "Fetching your personal API key..."
    
    local resp=$(curl -s -X GET "$API_URL/api/developer/api-key" \
        -H "Authorization: Bearer $API_TOKEN")
    
    local api_key=$(safe_jq '.apiKey' "$resp")
    
    if [[ -z "$api_key" || "$api_key" == "null" ]]; then
        # Generate new token
        info "Generating new API key..."
        resp=$(curl -s -X POST "$API_URL/api/developer/api-key/generate" \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"name":"CLI Generated"}')
        
        api_key=$(safe_jq '.apiKey' "$resp")
    fi
    
    if [[ -z "$api_key" || "$api_key" == "null" ]]; then
        error "Failed to get API key"
    fi
    
    # Save API key
    echo "$api_key" > "$CONFIG_DIR/api-key"
    chmod 600 "$CONFIG_DIR/api-key"
    
    # Show developer instructions
    section "Developer Setup Complete!"
    echo ""
    echo -e "${GREEN}✅ Your development environment is ready!${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}Your Personal API Key:${NC}"
    echo ""
    echo -e "${YELLOW}$api_key${NC}"
    echo ""
    echo -e "${RED}⚠️  Save this API key securely - it won't be shown again!${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Quick Start - Python:${NC}"
    echo ""
    echo "  # Install SDK"
    echo "  pip install distributex-cloud"
    echo ""
    echo "  # Use in your code"
    echo "  from distributex import DistributeX"
    echo "  dx = DistributeX(api_key='$api_key')"
    echo "  result = dx.run(my_function, args=(data,), gpu=True)"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Quick Start - JavaScript:${NC}"
    echo ""
    echo "  # Install SDK"
    echo "  npm install distributex-cloud"
    echo ""
    echo "  # Use in your code"
    echo "  const DistributeX = require('distributex-cloud');"
    echo "  const dx = new DistributeX('$api_key');"
    echo "  await dx.runScript('train.py', { gpu: true });"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Environment Variable:${NC}"
    echo ""
    echo "  export DISTRIBUTEX_API_KEY='$api_key'"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}Documentation: $API_URL/docs${NC}"
    echo -e "${BLUE}Dashboard: $API_URL/dashboard${NC}"
    echo -e "${BLUE}API Reference: $API_URL/api-docs${NC}"
    echo ""
    echo -e "${GREEN}Your API key has been saved to: $CONFIG_DIR/api-key${NC}"
    echo ""
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
get_mac_address() {
    local mac=""
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        mac=$(ip link show 2>/dev/null | awk '/link\/ether/ {gsub(/:/,""); print tolower($2); exit}')
        [ -z "$mac" ] && mac=$(cat /sys/class/net/*/address 2>/dev/null | head -n1 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {gsub(/:/,""); print tolower($2)}' || \
              ifconfig en1 2>/dev/null | awk '/ether/ {gsub(/:/,""); print tolower($2)}')
    fi
    [[ "$mac" =~ ^[0-9a-f]{12}$ ]] || error "Cannot detect MAC address"
    echo "$mac"
}

check_requirements() {
    section "Checking Requirements"
    
    for cmd in curl jq; do
        if ! command -v $cmd &>/dev/null; then
            info "Installing $cmd..."
            if command -v apt-get &>/dev/null; then
                sudo apt-get update -qq && sudo apt-get install -y $cmd -qq
            elif command -v brew &>/dev/null; then
                brew install $cmd
            else
                error "$cmd required but cannot install automatically"
            fi
        fi
    done
    
    log "Requirements satisfied"
}

# ============================================================================
# MAIN FLOW
# ============================================================================
main() {
    show_banner
    check_requirements
    authenticate_user
    select_role
    
    echo ""
    
    case "$USER_ROLE" in
        contributor)
            setup_contributor
            ;;
        developer)
            setup_developer
            ;;
        *)
            error "Invalid role: $USER_ROLE"
            ;;
    esac
    
    echo -e "${BOLD}${GREEN}Installation complete! 🎉${NC}\n"
}

# Error handling
trap 'error "Installation failed at line $LINENO"' ERR

# Run
main
exit 0
