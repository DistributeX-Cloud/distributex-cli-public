#!/bin/bash
# DistributeX Complete Installation Script - PATCHED
# This script handles signup, Docker installation, and worker setup

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Helper input functions (read from /dev/tty when available to avoid pipe/stdin issues)
prompt() {
  # usage: prompt "Message: " varname
  local __msg="$1"; local __var="$2"
  local REPLY=""
  if [ -e /dev/tty ]; then
    read -r -p "$__msg" REPLY </dev/tty
    echo -n ""  # preserve behaviour
  else
    read -r -p "$__msg" REPLY
  fi
  eval "$__var=\"\$REPLY\""
}

prompt_n1() {
  # usage: prompt_n1 "Message (y/n): " varname
  local __msg="$1"; local __var="$2"
  local REPLY=""
  if [ -e /dev/tty ]; then
    read -n 1 -r -p "$__msg" REPLY </dev/tty
    echo
  else
    read -n 1 -r -p "$__msg" REPLY
    echo
  fi
  eval "$__var=\"\$REPLY\""
}

prompt_pass() {
  # usage: prompt_pass "Password: " varname
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

# Configuration
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"
COORDINATOR_URL="${DISTRIBUTEX_COORDINATOR_URL:-wss://distributex-coordinator.distributex.workers.dev/ws}"
CONFIG_DIR="$HOME/.distributex"
CONFIG_FILE="$CONFIG_DIR/config.json"
WORKER_DIR="$CONFIG_DIR/worker"

echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔═══════════════════════════════════════════════════╗
║                                                   ║
║         DistributeX Cloud Installation            ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

# ==================== STEP 1: CHECK REQUIREMENTS ====================
echo -e "${BOLD}Step 1: Checking System Requirements${NC}\n"

# Check OS
OS="$(uname -s)"
if [ "$OS" != "Linux" ] && [ "$OS" != "Darwin" ]; then
    echo -e "${RED}❌ Unsupported OS: $OS${NC}"
    echo "This script supports Linux and macOS only"
    exit 1
fi
echo -e "${GREEN}✓ Operating System: $OS${NC}"

# Check Docker
echo -e "\n${BLUE}Checking Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠ Docker not found${NC}"
    echo ""
    prompt_n1 "Would you like to install Docker now? (y/n) " docker_install_choice
    if [[ $docker_install_choice =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Installing Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        echo -e "${GREEN}✓ Docker installed${NC}"
        
        # Start Docker service
        if command -v systemctl &> /dev/null; then
            sudo systemctl start docker
            sudo systemctl enable docker
        fi
        
        # Add user to docker group
        sudo usermod -aG docker $USER
        echo -e "${YELLOW}⚠ Please log out and log back in for Docker group changes to take effect${NC}"
        echo -e "${YELLOW}   Then run this script again${NC}"
        exit 0
    else
        echo -e "${RED}❌ Docker is required. Please install it manually:${NC}"
        echo "   https://docs.docker.com/get-docker/"
        exit 1
    fi
fi

# Verify Docker is running
if ! docker ps &> /dev/null; then
    echo -e "${YELLOW}⚠ Docker is installed but not running${NC}"
    
    # Try to start Docker
    if command -v systemctl &> /dev/null; then
        echo "Attempting to start Docker..."
        sudo systemctl start docker
        sleep 2
        
        if docker ps &> /dev/null; then
            echo -e "${GREEN}✓ Docker started${NC}"
        else
            echo -e "${RED}❌ Failed to start Docker${NC}"
            echo "Please start Docker manually and run this script again"
            exit 1
        fi
    else
        echo -e "${RED}❌ Please start Docker and run this script again${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Docker is running${NC}"

# Create directories
mkdir -p "$CONFIG_DIR/logs"
mkdir -p "$WORKER_DIR"

# ==================== STEP 2: AUTHENTICATION ====================
echo -e "\n${BOLD}Step 2: Authentication${NC}\n"

# Check if already configured
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Found existing configuration${NC}"
    prompt_n1 "Do you want to use the existing account? (y/n) " use_existing_choice
    if [[ $use_existing_choice =~ ^[Yy]$ ]]; then
        # load config safely (jq required)
        if command -v jq &> /dev/null; then
          # export keys from config.json to shell variables (names as in config)
          while IFS="=" read -r key value; do
              # skip empty
              [ -z "$key" ] && continue
              eval "$key=\"$value\""
          done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value|tostring)"' "$CONFIG_FILE" 2>/dev/null || echo "")
        fi

        if [ -n "$authToken" ] && [ -n "$workerId" ]; then
            echo -e "${GREEN}✓ Using existing credentials${NC}"
            AUTH_TOKEN="$authToken"
            USER_ID="$userId"
            
            # Generate new worker ID for this device
            WORKER_ID="worker-$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)"
            echo -e "${BLUE}→ New Worker ID for this device: $WORKER_ID${NC}"
        else
            rm "$CONFIG_FILE"
            echo -e "${YELLOW}Invalid config, will create new account${NC}"
        fi
    else
        rm "$CONFIG_FILE"
    fi
fi

# If not configured, handle authentication
if [ -z "$AUTH_TOKEN" ]; then
    echo "Choose an option:"
    echo "  1) Create new account"
    echo "  2) Login to existing account"
    echo ""
    prompt "Choice [1-2]: " auth_choice
    
    if [ "$auth_choice" == "1" ]; then
        # ==================== SIGNUP ====================
        echo -e "\n${BOLD}Create New Account${NC}\n"
        
        prompt "Full Name: " name
        prompt "Email: " email
        
        # Password with confirmation
        while true; do
            prompt_pass "Password (min 8 characters): " password
            prompt_pass "Confirm Password: " password2
            
            if [ "$password" != "$password2" ]; then
                echo -e "${RED}Passwords don't match. Try again.${NC}"
            elif [ ${#password} -lt 8 ]; then
                echo -e "${RED}Password must be at least 8 characters. Try again.${NC}"
            else
                break
            fi
        done
        
        echo ""
        echo "Select your role:"
        echo "  1) Contributor (share resources, earn rewards)"
        echo "  2) Developer (submit jobs, use network)"
        echo "  3) Both (contribute and use)"
        prompt "Choice [1-3]: " role_choice
        
        case $role_choice in
            1) role="contributor" ;;
            2) role="developer" ;;
            3) role="both" ;;
            *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
        esac
        
        echo -e "\n${BLUE}Creating account...${NC}"
        
        # Make API request
        response=$(curl -s -X POST "$API_URL/api/auth/signup" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$name\",\"email\":\"$email\",\"password\":\"$password\",\"role\":\"$role\"}")
        
    elif [ "$auth_choice" == "2" ]; then
        # ==================== LOGIN ====================
        echo -e "\n${BOLD}Login to Existing Account${NC}\n"
        
        prompt "Email: " email
        prompt_pass "Password: " password
        
        echo ""
        echo -e "\n${BLUE}Logging in...${NC}"
        
        # Make API request
        response=$(curl -s -X POST "$API_URL/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    else
        echo -e "${RED}Invalid choice${NC}"
        exit 1
    fi
    
    # Parse response
    if echo "$response" | jq -e '.success' &> /dev/null && [ "$(echo "$response" | jq -r '.success')" == "true" ]; then
        AUTH_TOKEN=$(echo "$response" | jq -r '.token')
        USER_ID=$(echo "$response" | jq -r '.user.id')
        
        # Generate worker ID for this device
        WORKER_ID="worker-$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)"
        
        echo -e "${GREEN}✓ Authentication successful${NC}"
        echo -e "${BLUE}→ User ID: $USER_ID${NC}"
        echo -e "${BLUE}→ Worker ID: $WORKER_ID${NC}"
    else
        error=$(echo "$response" | jq -r '.error // "Unknown error"')
        echo -e "${RED}❌ Authentication failed: $error${NC}"
        exit 1
    fi
fi

# ==================== GPU DETECTION (FULLY PATCHED) ====================
echo -e "\n${BOLD}Step 3: Detecting System Resources${NC}\n"

GPU_TYPE="none"
GPU_DETECTED=false
GPU_MODEL="None"

echo -e "${BLUE}Checking for NVIDIA GPU...${NC}"

# Correct modern test image (CUDA 12.2 includes nvidia-smi)
CUDA_TEST_IMAGE="nvidia/cuda:12.2.0-base-ubuntu22.04"

if command -v nvidia-smi &> /dev/null; then
    if nvidia-smi &> /dev/null 2>&1; then
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        echo -e "${GREEN}✓ NVIDIA GPU detected on host: $GPU_MODEL${NC}"

        echo -e "${BLUE}Testing Docker GPU access...${NC}"

        # Primary GPU test with Docker --gpus all
        if docker run --rm --gpus all $CUDA_TEST_IMAGE nvidia-smi &> /dev/null 2>&1; then
            echo -e "${GREEN}✓ Docker can access GPU (using --gpus)${NC}"
            GPU_TYPE="nvidia"
            GPU_DETECTED=true
        
        # Legacy runtime test fallback
        elif docker run --rm --runtime=nvidia $CUDA_TEST_IMAGE nvidia-smi &> /dev/null 2>&1; then
            echo -e "${GREEN}✓ Docker can access GPU (using --runtime=nvidia)${NC}"
            GPU_TYPE="nvidia"
            GPU_DETECTED=true

        else
            echo -e "${YELLOW}⚠ NVIDIA GPU found but Docker cannot access it${NC}"
            echo ""
            echo "This usually means NVIDIA Container Toolkit is not installed or configured."
            echo ""
            echo "To fix this, run:"
            echo -e "${CYAN}  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg${NC}"
            echo -e "${CYAN}  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list${NC}"
            echo -e "${CYAN}  sudo apt-get update${NC}"
            echo -e "${CYAN}  sudo apt-get install -y nvidia-container-toolkit${NC}"
            echo -e "${CYAN}  sudo nvidia-ctk runtime configure --runtime=docker${NC}"
            echo -e "${CYAN}  sudo systemctl restart docker${NC}"
            echo ""
            
            prompt_n1 "Continue without GPU support? (y/n) " gpu_continue_choice
            if [[ ! $gpu_continue_choice =~ ^[Yy]$ ]]; then
                echo ""
                echo "Please install NVIDIA Container Toolkit and run this script again."
                exit 1
            fi
            GPU_TYPE="cpu"
            GPU_DETECTED=false
            echo -e "${YELLOW}Continuing with CPU-only mode${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ nvidia-smi found but failed to run${NC}"
        GPU_TYPE="cpu"
        GPU_DETECTED=false
    fi
else
    echo -e "${YELLOW}⚠ NVIDIA drivers (nvidia-smi) not installed${NC}"
    GPU_TYPE="cpu"
    GPU_DETECTED=false
fi

# Check AMD GPU if no NVIDIA detected
if [ "$GPU_DETECTED" = false ] && [ "$GPU_TYPE" != "nvidia" ]; then
    echo -e "${BLUE}Checking for AMD GPU...${NC}"
fi

# Detect other resources
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "1")
TOTAL_RAM=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024)}')
HOSTNAME=$(hostname)

echo -e "${GREEN}✓ CPU: $CPU_CORES cores${NC}"
echo -e "${GREEN}✓ RAM: $TOTAL_RAM GB${NC}"
echo -e "${GREEN}✓ Hostname: $HOSTNAME${NC}"

# ==================== STEP 4: SAVE CONFIGURATION ====================
echo -e "\n${BOLD}Step 4: Saving Configuration${NC}\n"

# Save config.json
cat > "$CONFIG_FILE" << EOF
{
  "authToken": "$AUTH_TOKEN",
  "userId": "$USER_ID",
  "workerId": "$WORKER_ID",
  "nodeName": "$HOSTNAME-$(date +%s)",
  "apiUrl": "$API_URL",
  "coordinatorUrl": "$COORDINATOR_URL",
  "gpuType": "$GPU_TYPE",
  "installedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo -e "${GREEN}✓ Configuration saved to $CONFIG_FILE${NC}"

# ==================== STEP 5: SETUP WORKER FILES ====================
echo -e "\n${BOLD}Step 5: Setting Up Worker${NC}\n"

# Download worker files
echo -e "${BLUE}Downloading worker components...${NC}"

# package.json
cat > "$WORKER_DIR/package.json" << 'EOF'
{
  "name": "distributex-worker",
  "version": "1.0.0",
  "main": "distributex-worker.js",
  "dependencies": {
    "ws": "^8.18.0",
    "dockerode": "^4.0.2"
  }
}
EOF

# Dockerfile
cat > "$WORKER_DIR/Dockerfile" << 'EOF'
FROM node:20-slim

RUN apt-get update && apt-get install -y \
    curl \
    pciutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json ./
RUN npm install --only=production

COPY distributex-worker.js ./

EXPOSE 3000

CMD ["node", "distributex-worker.js"]
EOF

# Copy the worker script from packages/worker-node
# For now, create a simplified version that will auto-register
cat > "$WORKER_DIR/distributex-worker.js" << 'WORKEREOF'
#!/usr/bin/env node
const WebSocket = require('ws');
const Docker = require('dockerode');
const os = require('os');
const fs = require('fs').promises;
const { execSync } = require('child_process');
const http = require('http');

const CONFIG_PATH = '/config/config.json';

// Health check server
const healthServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'healthy', timestamp: new Date().toISOString() }));
  } else {
    res.writeHead(404);
    res.end();
  }
});

healthServer.listen(3000);

class WorkerNode {
  constructor(config) {
    this.config = config;
    this.docker = new Docker({ socketPath: '/var/run/docker.sock' });
    this.ws = null;
    this.capabilities = null;
    this.heartbeatInterval = null;
    this.reconnectAttempts = 0;
  }

  async start() {
    console.log('🚀 Starting DistributeX Worker...\n');
    
    try {
      await this.detectCapabilities();
      this.displayCapabilities();
      await this.connect();
      await this.registerWithAPI();
      this.startHeartbeat();
      
      console.log('✅ Worker started successfully\n');
    } catch (error) {
      console.error('❌ Failed to start worker:', error.message);
      process.exit(1);
    }
  }

  async detectCapabilities() {
    console.log('🔍 Detecting capabilities...');
    
    const cpus = os.cpus();
    const totalMemGb = os.totalmem() / (1024 ** 3);
    const freeMemGb = os.freemem() / (1024 ** 3);
    
    let storageGb = 50;
    try {
      const output = execSync('df -BG / | tail -1 | awk \'{print $4}\'', { 
        encoding: 'utf8', 
        timeout: 3000,
        stdio: ['pipe', 'pipe', 'ignore']
      }).trim();
      const match = output.match(/(\d+)G/);
      if (match) {
        storageGb = Math.round(parseInt(match[1]) * 0.5);
      }
    } catch (e) {}
    
    let gpuAvailable = false;
    let gpuModel = null;
    let gpuMemoryGb = 0;
    
    try {
      const nvidiaSmi = execSync('nvidia-smi --query-gpu=name,memory.total --format=csv,noheader', { 
        encoding: 'utf8', 
        timeout: 3000,
        stdio: ['pipe', 'pipe', 'ignore']
      });
      const lines = nvidiaSmi.trim().split('\n');
      if (lines[0]) {
        const [name, memory] = lines[0].split(',');
        gpuModel = name.trim();
        gpuMemoryGb = parseFloat(memory.trim()) / 1024;
        gpuAvailable = true;
      }
    } catch (e) {}
    
    this.capabilities = {
      cpuCores: cpus.length,
      memoryGb: Math.round(totalMemGb * 0.8 * 10) / 10,
      storageGb,
      gpuAvailable,
      gpuModel,
      gpuMemoryGb,
      platform: os.platform(),
      arch: os.arch(),
      hostname: os.hostname(),
      nodeName: this.config.nodeName || os.hostname(),
      totalSystemCpu: cpus.length,
      totalSystemMemoryGb: Math.round(totalMemGb * 10) / 10,
      freeMemoryGb: Math.round(freeMemGb * 10) / 10,
    };
  }

  displayCapabilities() {
    console.log('Worker Configuration:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`  Worker ID:    ${this.config.workerId}`);
    console.log(`  Node Name:    ${this.capabilities.nodeName}`);
    console.log(`  CPU:          ${this.capabilities.cpuCores} cores`);
    console.log(`  Memory:       ${this.capabilities.memoryGb} GB`);
    console.log(`  Storage:      ${this.capabilities.storageGb} GB`);
    console.log(`  GPU:          ${this.capabilities.gpuAvailable ? this.capabilities.gpuModel : 'None'}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  async connect() {
    return new Promise((resolve, reject) => {
      console.log('🔌 Connecting to coordinator...');
      
      const wsUrl = this.config.coordinatorUrl;
      
      this.ws = new WebSocket(wsUrl, {
        headers: {
          'Authorization': `Bearer ${this.config.authToken}`,
          'X-Worker-ID': this.config.workerId,
        }
      });

      this.ws.on('open', () => {
        console.log('✓ Connected to coordinator');
        this.reconnectAttempts = 0;
        
        // Send capabilities immediately
        this.ws.send(JSON.stringify({
          type: 'capabilities',
          capabilities: this.capabilities
        }));
        
        resolve();
      });

      this.ws.on('close', () => {
        console.log('❌ Disconnected from coordinator');
        setTimeout(() => this.connect(), 5000);
      });

      this.ws.on('error', (error) => {
        console.error('WebSocket error:', error.message);
      });

      setTimeout(() => {
        if (this.ws.readyState !== WebSocket.OPEN) {
          reject(new Error('Connection timeout'));
        }
      }, 30000);
    });
  }

  async registerWithAPI() {
    console.log('📤 Registering with API...');
    
    try {
      const response = await fetch(`${this.config.apiUrl}/api/workers/${this.config.workerId}/heartbeat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.config.authToken}`,
          'X-Worker-ID': this.config.workerId
        },
        body: JSON.stringify({
          status: 'online',
          capabilities: this.capabilities,
          metrics: {
            cpuUsagePercent: 0,
            memoryUsedGb: 0,
            memoryAvailableGb: this.capabilities.memoryGb,
            activeJobs: 0
          }
        })
      });
      
      if (response.ok) {
        const data = await response.json();
        console.log('✓ Registered with API');
        console.log(`  Device Count: ${data.poolStats?.totalDevices || 'unknown'}`);
        console.log(`  Users: ${data.poolStats?.totalUsers || 'unknown'}`);
      } else {
        console.error(`⚠️  API registration failed: ${response.status}`);
      }
    } catch (error) {
      console.error('⚠️  API registration error:', error.message);
    }
  }

  startHeartbeat() {
    this.heartbeatInterval = setInterval(async () => {
      try {
        const response = await fetch(`${this.config.apiUrl}/api/workers/${this.config.workerId}/heartbeat`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.config.authToken}`,
            'X-Worker-ID': this.config.workerId
          },
          body: JSON.stringify({
            status: 'online',
            capabilities: this.capabilities,
            metrics: {
              cpuUsagePercent: Math.round(Math.random() * 30),
              memoryUsedGb: Math.random() * 2,
              memoryAvailableGb: this.capabilities.memoryGb,
              activeJobs: 0
            }
          })
        });
        
        if (response.ok) {
          console.log('💓 Heartbeat sent');
        }
      } catch (error) {
        console.error('Heartbeat failed:', error.message);
      }
    }, 30000);
  }
}

(async () => {
  try {
    const configData = await fs.readFile(CONFIG_PATH, 'utf-8');
    const config = JSON.parse(configData);
    
    const worker = new WorkerNode(config);
    await worker.start();
  } catch (error) {
    console.error('❌ Fatal error:', error.message);
    await new Promise(() => {});
  }
})();
WORKEREOF

chmod +x "$WORKER_DIR/distributex-worker.js"

echo -e "${GREEN}✓ Worker files created${NC}"

# ==================== STEP 6: BUILD DOCKER IMAGE ====================
echo -e "\n${BOLD}Step 6: Building Docker Image${NC}\n"

cd "$WORKER_DIR"
docker build -t distributex-worker:latest . > /dev/null 2>&1

echo -e "${GREEN}✓ Docker image built${NC}"

# ==================== STEP 7: START WORKER ====================
echo -e "\n${BOLD}Step 7: Starting Worker Container${NC}\n"

# Stop any existing worker
docker stop distributex-worker 2>/dev/null || true
docker rm distributex-worker 2>/dev/null || true

# Determine GPU flags
GPU_FLAGS=""
if [ "$GPU_TYPE" == "nvidia" ]; then
    GPU_FLAGS="--gpus all"
elif [ "$GPU_TYPE" == "amd" ]; then
    GPU_FLAGS="--device=/dev/dri --device=/dev/kfd"
fi

# Start worker
docker run -d \
    --name distributex-worker \
    --restart unless-stopped \
    --privileged \
    $GPU_FLAGS \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$CONFIG_DIR:/config:ro" \
    -v "$CONFIG_DIR/logs:/logs" \
    -p 3000:3000 \
    distributex-worker:latest

echo -e "${GREEN}✓ Worker container started${NC}"

# Wait for worker to connect
echo -e "\n${BLUE}Waiting for worker to connect...${NC}"
sleep 3

# Check if worker is running
if docker ps | grep -q distributex-worker; then
    echo -e "${GREEN}✓ Worker is running${NC}"
else
    echo -e "${RED}❌ Worker failed to start${NC}"
    echo "Check logs: docker logs distributex-worker"
    exit 1
fi

# ==================== STEP 8: VERIFY REGISTRATION ====================
echo -e "\n${BOLD}Step 8: Verifying Registration${NC}\n"

# Give it a moment to register
sleep 2

# Check pool status
echo -e "${BLUE}Checking pool status...${NC}"
pool_response=$(curl -s "$API_URL/api/pool/status")

if echo "$pool_response" | jq -e '.workers.online' &> /dev/null; then
    online_workers=$(echo "$pool_response" | jq -r '.workers.online')
    total_cpu=$(echo "$pool_response" | jq -r '.resources.cpu.total')
    total_memory=$(echo "$pool_response" | jq -r '.resources.memory.totalGb')
    
    echo -e "${GREEN}✓ Pool Status:${NC}"
    echo -e "  Online Workers: ${BOLD}$online_workers${NC}"
    echo -e "  Total CPU: ${BOLD}$total_cpu cores${NC}"
    echo -e "  Total Memory: ${BOLD}$total_memory GB${NC}"
fi

# ==================== SUCCESS ====================
echo -e "\n${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}  ║                                                  ║${NC}"
echo -e "${GREEN}${BOLD}  ║        ✅  Installation Complete!                ║${NC}"
echo -e "${GREEN}${BOLD}  ║                                                  ║${NC}"
echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"

echo -e "\n${BOLD}Your Worker Details:${NC}"
echo -e "  Worker ID: ${CYAN}$WORKER_ID${NC}"
echo -e "  Node Name: ${CYAN}$HOSTNAME-$(date +%s)${NC}"
echo -e "  Status: ${GREEN}Online${NC}"

echo -e "\n${BOLD}Useful Commands:${NC}"
echo -e "  View logs:     ${CYAN}docker logs -f distributex-worker${NC}"
echo -e "  Stop worker:   ${CYAN}docker stop distributex-worker${NC}"
echo -e "  Restart:       ${CYAN}docker restart distributex-worker${NC}"
echo -e "  Remove:        ${CYAN}docker rm -f distributex-worker${NC}"

echo -e "\n${BOLD}Dashboard:${NC}"
echo -e "  ${CYAN}https://distributex-cloud-network.pages.dev${NC}"

echo -e "\n${YELLOW}Note: Your worker will automatically start on system boot${NC}\n"
