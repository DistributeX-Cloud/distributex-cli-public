#!/bin/bash
# DistributeX Complete CLI + Worker Installation
# For public repository: distributex-cli-public
# curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/install.sh | bash

set -e

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
VERSION="1.0.0"
INSTALL_DIR="$HOME/.distributex"
BIN_DIR="/usr/local/bin"
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"
COORDINATOR_URL="${DISTRIBUTEX_COORDINATOR_URL:-wss://distributex-coordinator.distributex.workers.dev/ws}"

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
    ____  _      __       _ __          __      _  __
   / __ \(_)____/ /______(_) /_  __  __/ /____| |/ /
  / / / / / ___/ __/ ___/ / __ \/ / / / __/ _ \  / 
 / /_/ / (__  ) /_/ /  / / /_/ / /_/ / /_/  __/ |  
/_____/_/____/\__/_/  /_/_.___/\__,_/\__/\___/_/|_|
                                                    
         Free Distributed Computing Network
EOF
    echo -e "${NC}\n"
}

check_requirements() {
    echo -e "${BOLD}Checking requirements...${NC}"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}✗ Docker required but not found${NC}"
        echo ""
        echo "Install Docker:"
        echo "  Linux: curl -fsSL https://get.docker.com | sh"
        echo "  Mac: brew install --cask docker"
        exit 1
    fi
    
    if ! docker info &> /dev/null 2>&1; then
        echo -e "${RED}✗ Docker not running${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker available${NC}"
    
    # Check Node.js (for worker)
    if ! command -v node &> /dev/null; then
        echo -e "${YELLOW}Installing Node.js...${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install node
        elif [[ -f /etc/debian_version ]]; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
        else
            echo -e "${RED}Please install Node.js manually: https://nodejs.org${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓ Node.js available${NC}"
}

setup_directories() {
    echo ""
    echo -e "${BOLD}Setting up directories...${NC}"
    
    mkdir -p "$INSTALL_DIR"/{bin,logs,config,keys}
    chmod 700 "$INSTALL_DIR"
    chmod 700 "$INSTALL_DIR/keys"
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

install_cli() {
    echo ""
    echo -e "${BOLD}Installing CLI...${NC}"
    
    cat > "$INSTALL_DIR/bin/dxcloud" << 'EOF'
#!/bin/bash
# DistributeX CLI - Complete Implementation
set -e

INSTALL_DIR="$HOME/.distributex"
CONFIG_FILE="$INSTALL_DIR/config/auth.json"
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load config
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        export TOKEN=$(grep '"token"' "$CONFIG_FILE" | cut -d'"' -f4)
        export USER_ID=$(grep '"user_id"' "$CONFIG_FILE" | cut -d'"' -f4)
        export EMAIL=$(grep '"email"' "$CONFIG_FILE" | cut -d'"' -f4)
    fi
}

# Save config
save_config() {
    local token=$1
    local user_id=$2
    local email=$3
    local role=$4
    
    mkdir -p "$INSTALL_DIR/config"
    cat > "$CONFIG_FILE" <<CONF
{
  "token": "$token",
  "user_id": "$user_id",
  "email": "$email",
  "role": "$role",
  "api_url": "$API_URL",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
CONF
    chmod 600 "$CONFIG_FILE"
}

# API request helper
api_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    local headers=(-H "Content-Type: application/json")
    
    if [ -n "$TOKEN" ]; then
        headers+=(-H "Authorization: Bearer $TOKEN")
    fi
    
    if [ -n "$data" ]; then
        curl -s -X "$method" "$API_URL$endpoint" "${headers[@]}" -d "$data"
    else
        curl -s -X "$method" "$API_URL$endpoint" "${headers[@]}"
    fi
}

# Command: signup
cmd_signup() {
    echo -e "${BOLD}Create DistributeX Account${NC}\n"
    
    read -p "$(echo -e ${CYAN}Full Name:${NC} )" name
    read -p "$(echo -e ${CYAN}Email:${NC} )" email
    read -sp "$(echo -e ${CYAN}Password:${NC} )" password
    echo ""
    
    echo ""
    echo -e "${BOLD}Select Role:${NC}"
    echo "  ${CYAN}1)${NC} Developer (submit jobs)"
    echo "  ${CYAN}2)${NC} Contributor (share resources)"
    echo "  ${CYAN}3)${NC} Both"
    read -p "$(echo -e ${CYAN}Choice [1-3]:${NC} )" role_choice
    
    case $role_choice in
        1) role="developer" ;;
        2) role="contributor" ;;
        3) role="both" ;;
        *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
    esac
    
    echo ""
    echo -e "${YELLOW}Creating account...${NC}"
    
    response=$(api_request POST "/api/auth/signup" "{
        \"name\": \"$name\",
        \"email\": \"$email\",
        \"password\": \"$password\",
        \"role\": \"$role\"
    }")
    
    if echo "$response" | grep -q '"success":true'; then
        token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        user_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        save_config "$token" "$user_id" "$email" "$role"
        
        echo ""
        echo -e "${GREEN}✅ Account created successfully!${NC}"
        echo ""
        echo -e "  Email: ${CYAN}$email${NC}"
        echo -e "  Role: ${CYAN}$role${NC}"
        echo ""
        
        if [ "$role" == "contributor" ] || [ "$role" == "both" ]; then
            echo -e "${BOLD}Start worker:${NC}"
            echo -e "  ${CYAN}dxcloud worker start${NC}"
        fi
        
        if [ "$role" == "developer" ] || [ "$role" == "both" ]; then
            echo -e "${BOLD}Submit job:${NC}"
            echo -e "  ${CYAN}dxcloud submit --image python:3.11 --command 'python -c \"print(1+1)\"'${NC}"
        fi
        echo ""
    else
        error=$(echo "$response" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        echo -e "${RED}✗ Signup failed: ${error:-Unknown error}${NC}"
        exit 1
    fi
}

# Command: login
cmd_login() {
    echo -e "${BOLD}Login to DistributeX${NC}\n"
    
    read -p "$(echo -e ${CYAN}Email:${NC} )" email
    read -sp "$(echo -e ${CYAN}Password:${NC} )" password
    echo ""
    echo ""
    
    echo -e "${YELLOW}Logging in...${NC}"
    
    response=$(api_request POST "/api/auth/login" "{
        \"email\": \"$email\",
        \"password\": \"$password\"
    }")
    
    if echo "$response" | grep -q '"success":true'; then
        token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        user_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        role=$(echo "$response" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
        
        save_config "$token" "$user_id" "$email" "$role"
        
        echo ""
        echo -e "${GREEN}✅ Logged in successfully!${NC}"
        echo ""
    else
        error=$(echo "$response" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        echo -e "${RED}✗ Login failed: ${error:-Invalid credentials}${NC}"
        exit 1
    fi
}

# Command: submit
cmd_submit() {
    load_config
    
    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Not logged in. Run: dxcloud login${NC}"
        exit 1
    fi
    
    local image=""
    local command=""
    local cpu=1
    local memory=2
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --image) image="$2"; shift 2 ;;
            --command) command="$2"; shift 2 ;;
            --cpu) cpu="$2"; shift 2 ;;
            --memory) memory="$2"; shift 2 ;;
            *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
        esac
    done
    
    if [ -z "$image" ]; then
        echo -e "${RED}--image required${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Submitting job...${NC}"
    
    response=$(api_request POST "/api/jobs/submit" "{
        \"jobName\": \"job-$(date +%s)\",
        \"jobType\": \"docker\",
        \"containerImage\": \"$image\",
        \"command\": [\"sh\", \"-c\", \"$command\"],
        \"requiredCpuCores\": $cpu,
        \"requiredMemoryGb\": $memory
    }")
    
    if echo "$response" | grep -q '"success":true'; then
        job_id=$(echo "$response" | grep -o '"jobId":"[^"]*"' | cut -d'"' -f4)
        
        echo ""
        echo -e "${GREEN}✅ Job submitted!${NC}"
        echo ""
        echo -e "  Job ID: ${CYAN}$job_id${NC}"
        echo -e "  Image: ${CYAN}$image${NC}"
        echo ""
    else
        error=$(echo "$response" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        echo -e "${RED}✗ Failed: ${error:-Unknown error}${NC}"
        exit 1
    fi
}

# Command: worker start
cmd_worker_start() {
    load_config
    
    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Not logged in. Run: dxcloud login${NC}"
        exit 1
    fi
    
    # Check if worker is already running
    if [ -f "$INSTALL_DIR/worker.pid" ]; then
        pid=$(cat "$INSTALL_DIR/worker.pid")
        if ps -p $pid > /dev/null 2>&1; then
            echo -e "${YELLOW}Worker already running (PID: $pid)${NC}"
            echo "Stop it with: dxcloud worker stop"
            exit 0
        fi
    fi
    
    echo -e "${BOLD}Starting DistributeX Worker...${NC}\n"
    
    # Start worker daemon
    node "$INSTALL_DIR/bin/worker.js" > "$INSTALL_DIR/logs/worker.log" 2>&1 &
    echo $! > "$INSTALL_DIR/worker.pid"
    
    sleep 2
    
    if ps -p $(cat "$INSTALL_DIR/worker.pid") > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Worker started successfully${NC}"
        echo ""
        echo -e "  PID: ${CYAN}$(cat "$INSTALL_DIR/worker.pid")${NC}"
        echo -e "  Logs: ${CYAN}tail -f $INSTALL_DIR/logs/worker.log${NC}"
        echo ""
    else
        echo -e "${RED}✗ Worker failed to start${NC}"
        echo "Check logs: tail $INSTALL_DIR/logs/worker.log"
        exit 1
    fi
}

# Command: worker stop
cmd_worker_stop() {
    if [ ! -f "$INSTALL_DIR/worker.pid" ]; then
        echo -e "${YELLOW}Worker not running${NC}"
        exit 0
    fi
    
    pid=$(cat "$INSTALL_DIR/worker.pid")
    
    if ps -p $pid > /dev/null 2>&1; then
        echo -e "${YELLOW}Stopping worker (PID: $pid)...${NC}"
        kill $pid
        rm "$INSTALL_DIR/worker.pid"
        echo -e "${GREEN}✅ Worker stopped${NC}"
    else
        echo -e "${YELLOW}Worker not running${NC}"
        rm "$INSTALL_DIR/worker.pid"
    fi
}

# Command: worker status
cmd_worker_status() {
    if [ ! -f "$INSTALL_DIR/worker.pid" ]; then
        echo -e "${RED}Worker not running${NC}"
        exit 0
    fi
    
    pid=$(cat "$INSTALL_DIR/worker.pid")
    
    if ps -p $pid > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Worker running (PID: $pid)${NC}"
        echo ""
        echo "View logs: tail -f $INSTALL_DIR/logs/worker.log"
    else
        echo -e "${RED}Worker not running (stale PID file)${NC}"
        rm "$INSTALL_DIR/worker.pid"
    fi
}

# Main dispatcher
case "${1:-help}" in
    signup) cmd_signup ;;
    login) cmd_login ;;
    submit) shift; cmd_submit "$@" ;;
    worker)
        case "${2:-help}" in
            start) cmd_worker_start ;;
            stop) cmd_worker_stop ;;
            status) cmd_worker_status ;;
            *) 
                echo "Usage: dxcloud worker {start|stop|status}"
                exit 1
                ;;
        esac
        ;;
    help|--help|-h)
        echo "DistributeX CLI"
        echo ""
        echo "Commands:"
        echo "  signup              Create account"
        echo "  login               Login"
        echo "  submit              Submit job"
        echo "  worker start        Start worker"
        echo "  worker stop         Stop worker"
        echo "  worker status       Check worker"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'dxcloud help' for usage"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$INSTALL_DIR/bin/dxcloud"
    
    # Create symlink
    if [ -w "$BIN_DIR" ]; then
        ln -sf "$INSTALL_DIR/bin/dxcloud" "$BIN_DIR/dxcloud"
    else
        sudo ln -sf "$INSTALL_DIR/bin/dxcloud" "$BIN_DIR/dxcloud"
    fi
    
    echo -e "${GREEN}✓ CLI installed${NC}"
}

install_worker() {
    echo ""
    echo -e "${BOLD}Installing worker daemon...${NC}"
    
    # Download worker from your CDN or embed it
    # For now, we'll download from the main repo (you'll need to make this file public)
    curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cloud-network/main/packages/worker-node/distributex-worker.js -o "$INSTALL_DIR/bin/worker.js"
    
    chmod +x "$INSTALL_DIR/bin/worker.js"
    
    # Install worker dependencies
    cd "$INSTALL_DIR/bin"
    cat > package.json <<'PKG'
{
  "name": "distributex-worker",
  "version": "1.0.0",
  "dependencies": {
    "ws": "^8.18.0",
    "dockerode": "^4.0.2"
  }
}
PKG
    
    npm install --silent --no-save
    cd - > /dev/null
    
    echo -e "${GREEN}✓ Worker installed${NC}"
}

show_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                                                      ║${NC}"
    echo -e "${GREEN}${BOLD}║          ✅  Installation Complete!                 ║${NC}"
    echo -e "${GREEN}${BOLD}║                                                      ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Quick Start:${NC}"
    echo ""
    echo -e "  1. Create account:  ${CYAN}dxcloud signup${NC}"
    echo -e "  2. Login:           ${CYAN}dxcloud login${NC}"
    echo -e "  3. Start worker:    ${CYAN}dxcloud worker start${NC}"
    echo ""
    echo -e "${BOLD}Or submit jobs:${NC}"
    echo -e "  ${CYAN}dxcloud submit --image python:3.11 --command 'python -c \"print(1+1)\"'${NC}"
    echo ""
    echo -e "${BOLD}Help:${NC}"
    echo -e "  ${CYAN}dxcloud help${NC}"
    echo ""
}

# Main execution
main() {
    show_banner
    check_requirements
    setup_directories
    install_cli
    install_worker
    show_completion
}

main
