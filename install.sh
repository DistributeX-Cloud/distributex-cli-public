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
    
    # Check Docker installation
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}✗ Docker not found${NC}"
        echo ""
        echo "Install Docker:"
        echo "  Linux: curl -fsSL https://get.docker.com | sh"
        echo "  Mac: brew install --cask docker"
        echo "  Or visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker installed${NC}"
    
    # Check if Docker daemon is running with better error handling
    if ! docker info >/dev/null 2>&1; then
        # Try to get more specific error info
        docker_error=$(docker info 2>&1 || true)
        
        echo -e "${RED}✗ Docker daemon not accessible${NC}"
        echo ""
        
        # Check for common issues
        if echo "$docker_error" | grep -q "permission denied"; then
            echo "Issue: Permission denied"
            echo ""
            echo "Solutions:"
            echo "  1. Add your user to docker group:"
            echo "     sudo usermod -aG docker $USER"
            echo "     newgrp docker"
            echo ""
            echo "  2. Or run with sudo:"
            echo "     curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/install.sh | sudo bash"
        elif echo "$docker_error" | grep -q "Cannot connect"; then
            echo "Issue: Docker daemon not running"
            echo ""
            echo "Start Docker:"
            echo "  Linux (systemd): sudo systemctl start docker"
            echo "  Linux (service): sudo service docker start"
            echo "  Mac: Open Docker Desktop application"
            echo "  Windows: Start Docker Desktop"
        else
            echo "Error details:"
            echo "$docker_error" | head -5
            echo ""
            echo "Please ensure Docker is running and accessible."
        fi
        
        echo ""
        echo "After fixing, run installer again:"
        echo "  curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/install.sh | bash"
        exit 1
    fi
    
    # Verify Docker can actually run containers
    if ! docker ps >/dev/null 2>&1; then
        echo -e "${RED}✗ Cannot list Docker containers${NC}"
        echo "Docker is running but may have permission issues."
        echo "Try: sudo usermod -aG docker $USER && newgrp docker"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker daemon is running${NC}"
    
    # Check Node.js (for worker)
    if ! command -v node >/dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}Node.js not found. Installing...${NC}"
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew >/dev/null 2>&1; then
                brew install node
            else
                echo -e "${RED}Homebrew required. Install from: https://brew.sh${NC}"
                exit 1
            fi
        elif [[ -f /etc/debian_version ]]; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif [[ -f /etc/redhat-release ]]; then
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
            sudo yum install -y nodejs
        else
            echo -e "${RED}Please install Node.js manually: https://nodejs.org${NC}"
            exit 1
        fi
    fi
    
    # Verify Node.js version
    node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$node_version" -lt 16 ]; then
        echo -e "${YELLOW}⚠ Node.js version $node_version detected. Version 16+ recommended.${NC}"
    fi
    
    echo -e "${GREEN}✓ Node.js $(node -v) available${NC}"
    
    # Check npm
    if ! command -v npm >/dev/null 2>&1; then
        echo -e "${RED}✗ npm not found (should come with Node.js)${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ npm $(npm -v) available${NC}"
}

setup_directories() {
    echo ""
    echo -e "${BOLD}Setting up directories...${NC}"
    
    mkdir -p "$INSTALL_DIR"/{bin,logs,config,keys}
    chmod 700 "$INSTALL_DIR"
    chmod 700 "$INSTALL_DIR/keys"
    
    echo -e "${GREEN}✓ Directories created at $INSTALL_DIR${NC}"
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
    
    # Check Docker access
    if ! docker ps >/dev/null 2>&1; then
        echo -e "${RED}✗ Cannot access Docker${NC}"
        echo "Please ensure Docker is running and you have permission."
        echo "Try: sudo usermod -aG docker $USER && newgrp docker"
        exit 1
    fi
    
    # Check if worker is already running
    if [ -f "$INSTALL_DIR/worker.pid" ]; then
        pid=$(cat "$INSTALL_DIR/worker.pid")
        if ps -p $pid >/dev/null 2>&1; then
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
    
    if ps -p $(cat "$INSTALL_DIR/worker.pid") >/dev/null 2>&1; then
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
    
    if ps -p $pid >/dev/null 2>&1; then
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
    
    if ps -p $pid >/dev/null 2>&1; then
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
        echo -e "${YELLOW}Creating symlink requires sudo...${NC}"
        sudo ln -sf "$INSTALL_DIR/bin/dxcloud" "$BIN_DIR/dxcloud"
    fi
    
    echo -e "${GREEN}✓ CLI installed${NC}"
}

install_worker() {
    echo ""
    echo -e "${BOLD}Installing worker daemon...${NC}"
    
    # Try to download worker from repository first
    WORKER_URL="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cloud-network/main/packages/worker-node/distributex-worker.js"
    
    if curl -fsSL "$WORKER_URL" -o "$INSTALL_DIR/bin/worker.js" 2>/dev/null && [ -s "$INSTALL_DIR/bin/worker.js" ]; then
        echo -e "${GREEN}✓ Worker downloaded from repository${NC}"
    else
        echo -e "${YELLOW}⚠ Downloading from repository, using embedded worker...${NC}"
        
        # Embedded worker implementation
        cat > "$INSTALL_DIR/bin/worker.js" << 'WORKER_EOF'
#!/usr/bin/env node
const WebSocket = require('ws');
const Docker = require('dockerode');
const fs = require('fs');
const path = require('path');

const INSTALL_DIR = process.env.HOME + '/.distributex';
const CONFIG_FILE = path.join(INSTALL_DIR, 'config', 'auth.json');
const COORDINATOR_URL = process.env.DISTRIBUTEX_COORDINATOR_URL || 'wss://distributex-coordinator.distributex.workers.dev/ws';

let config = {};
let ws = null;
let docker = new Docker();
let reconnectAttempts = 0;
const MAX_RECONNECT_ATTEMPTS = 10;

// Load config
function loadConfig() {
    try {
        const data = fs.readFileSync(CONFIG_FILE, 'utf8');
        config = JSON.parse(data);
        return true;
    } catch (err) {
        console.error('Failed to load config:', err.message);
        return false;
    }
}

// Connect to coordinator
function connect() {
    if (!loadConfig()) {
        console.error('Cannot connect: No authentication config found');
        process.exit(1);
    }

    console.log('Connecting to coordinator...');
    console.log(`URL: ${COORDINATOR_URL}`);
    
    ws = new WebSocket(COORDINATOR_URL, {
        headers: {
            'Authorization': `Bearer ${config.token}`,
            'User-Agent': 'DistributeX-Worker/1.0.0'
        }
    });

    ws.on('open', () => {
        console.log('✓ Connected to coordinator');
        reconnectAttempts = 0;
        
        // Register worker
        ws.send(JSON.stringify({
            type: 'register',
            workerId: config.user_id,
            capabilities: {
                cpu: require('os').cpus().length,
                memory: Math.floor(require('os').totalmem() / (1024 * 1024 * 1024)),
                docker: true
            }
        }));
    });

    ws.on('message', async (data) => {
        try {
            const message = JSON.parse(data.toString());
            console.log('Received message:', message.type);
            
            if (message.type === 'job_assigned') {
                await handleJob(message.job);
            }
        } catch (err) {
            console.error('Error handling message:', err);
        }
    });

    ws.on('error', (err) => {
        console.error('WebSocket error:', err.message);
    });

    ws.on('close', () => {
        console.log('Disconnected from coordinator');
        
        if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
            reconnectAttempts++;
            const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), 30000);
            console.log(`Reconnecting in ${delay/1000}s... (attempt ${reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS})`);
            setTimeout(connect, delay);
        } else {
            console.error('Max reconnection attempts reached. Exiting.');
            process.exit(1);
        }
    });
}

// Handle job execution
async function handleJob(job) {
    console.log(`\n=== Executing Job ${job.jobId} ===`);
    console.log(`Image: ${job.containerImage}`);
    console.log(`Command: ${job.command.join(' ')}`);
    
    try {
        // Pull image
        console.log('Pulling image...');
        await new Promise((resolve, reject) => {
            docker.pull(job.containerImage, (err, stream) => {
                if (err) return reject(err);
                docker.modem.followProgress(stream, (err, output) => {
                    if (err) return reject(err);
                    resolve(output);
                });
            });
        });
        
        // Create and start container
        console.log('Starting container...');
        const container = await docker.createContainer({
            Image: job.containerImage,
            Cmd: job.command,
            HostConfig: {
                Memory: (job.requiredMemoryGb || 2) * 1024 * 1024 * 1024,
                CpuShares: (job.requiredCpuCores || 1) * 1024,
                AutoRemove: true
            }
        });
        
        await container.start();
        
        // Wait for completion
        const result = await container.wait();
        
        // Get logs
        const logs = await container.logs({
            stdout: true,
            stderr: true
        });
        
        console.log('Job completed with status:', result.StatusCode);
        
        // Report result
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({
                type: 'job_completed',
                jobId: job.jobId,
                status: result.StatusCode === 0 ? 'completed' : 'failed',
                output: logs.toString('utf8')
            }));
        }
        
    } catch (err) {
        console.error('Job execution failed:', err.message);
        
        // Report failure
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({
                type: 'job_failed',
                jobId: job.jobId,
                error: err.message
            }));
        }
    }
}

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\nShutting down worker...');
    if (ws) ws.close();
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('\nShutting down worker...');
    if (ws) ws.close();
    process.exit(0);
});

// Start worker
console.log('DistributeX Worker v1.0.0');
console.log('========================\n');
connect();
WORKER_EOF
    fi
    
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
    
    echo -e "${YELLOW}Installing dependencies...${NC}"
    npm install --silent --no-save 2>&1 | grep -v "npm WARN" || true
    cd - >/dev/null
    
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
    echo -e "${BOLD}Troubleshooting:${NC}"
    echo -e "  Installation dir: ${CYAN}$INSTALL_DIR${NC}"
    echo -e "  Logs location:    ${CYAN}$INSTALL_DIR/logs/${NC}"
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
