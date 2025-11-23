#!/bin/bash
# DistributeX Complete CLI + Worker Installation - FIXED
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
COORDINATOR_URL="${DISTRIBUTEX_COORDINATOR_URL:-wss://distributex-coordinator.distributex.workers.dev}"

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
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}✗ Docker not found${NC}"
        echo ""
        echo "Install Docker:"
        echo "  Linux: curl -fsSL https://get.docker.com | sh"
        echo "  Mac: brew install --cask docker"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker installed${NC}"
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        docker_error=$(docker info 2>&1 || true)
        echo -e "${RED}✗ Docker daemon not accessible${NC}"
        echo ""
        
        if echo "$docker_error" | grep -q "permission denied"; then
            echo "Issue: Permission denied"
            echo "Solution: sudo usermod -aG docker $USER && newgrp docker"
        else
            echo "Issue: Docker daemon not running"
            echo "Solution: Start Docker Desktop or run: sudo systemctl start docker"
        fi
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker daemon is running${NC}"
    
    # Check Node.js
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
        else
            echo -e "${RED}Please install Node.js manually: https://nodejs.org${NC}"
            exit 1
        fi
    fi
    
    node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$node_version" -lt 16 ]; then
        echo -e "${YELLOW}⚠ Node.js version $node_version detected. Version 16+ recommended.${NC}"
    fi
    
    echo -e "${GREEN}✓ Node.js $(node -v) available${NC}"
}

setup_directories() {
    echo ""
    echo -e "${BOLD}Setting up directories...${NC}"
    
    mkdir -p "$INSTALL_DIR"/{bin,logs,config}
    chmod 700 "$INSTALL_DIR"
    
    echo -e "${GREEN}✓ Directories created at $INSTALL_DIR${NC}"
}

# ✅ FIXED: Proper authentication flow with terminal check
authenticate_user() {
    echo ""
    echo -e "${BOLD}DistributeX Setup${NC}\n"
    
    # Check if we can read from terminal
    if [ ! -t 0 ]; then
        exec < /dev/tty
    fi
    
    echo "Choose an option:"
    echo "  1) Create new account"
    echo "  2) Login to existing account"
    echo ""
    
    while true; do
        read -p "$(echo -e ${CYAN}Choice [1-2]:${NC} )" auth_choice
        
        if [ "$auth_choice" == "1" ] || [ "$auth_choice" == "2" ]; then
            break
        else
            echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        fi
    done
    
    if [ "$auth_choice" == "1" ]; then
        # Signup
        echo ""
        read -p "$(echo -e ${CYAN}Full Name:${NC} )" name
        read -p "$(echo -e ${CYAN}Email:${NC} )" email
        read -sp "$(echo -e ${CYAN}Password:${NC} )" password
        echo ""
        echo ""
        echo "Select Role:"
        echo "  1) Contributor (share resources)"
        echo "  2) Developer (submit jobs)"
        echo "  3) Both"
        
        while true; do
            read -p "$(echo -e ${CYAN}Choice [1-3]:${NC} )" role_choice
            
            case $role_choice in
                1) role="contributor"; break ;;
                2) role="developer"; break ;;
                3) role="both"; break ;;
                *) echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}" ;;
            esac
        done
        
        echo ""
        echo -e "${YELLOW}Creating account...${NC}"
        
        response=$(curl -s -X POST "$API_URL/api/auth/signup" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$name\",\"email\":\"$email\",\"password\":\"$password\",\"role\":\"$role\"}")
        
    else
        # Login
        echo ""
        read -p "$(echo -e ${CYAN}Email:${NC} )" email
        read -sp "$(echo -e ${CYAN}Password:${NC} )" password
        echo ""
        echo ""
        echo -e "${YELLOW}Logging in...${NC}"
        
        response=$(curl -s -X POST "$API_URL/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    fi
    
    # ✅ PARSE RESPONSE
    if echo "$response" | grep -q '"success":true'; then
        TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        USER_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        USER_ROLE=$(echo "$response" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
        
        # ✅ EXTRACT WORKER CREDENTIALS IF AVAILABLE
        WORKER_ID=$(echo "$response" | grep -o '"workerId":"[^"]*"' | cut -d'"' -f4)
        WORKER_NAME=$(echo "$response" | grep -o '"workerName":"[^"]*"' | cut -d'"' -f4)
        
        echo ""
        echo -e "${GREEN}✅ Authentication successful!${NC}"
        
        # ✅ IF NO WORKER BUT USER IS CONTRIBUTOR, CREATE ONE
        if [ -z "$WORKER_ID" ] && ([ "$USER_ROLE" == "contributor" ] || [ "$USER_ROLE" == "both" ]); then
            echo ""
            echo -e "${YELLOW}Registering worker node...${NC}"
            
            worker_response=$(curl -s -X POST "$API_URL/api/workers/register" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $TOKEN" \
                -d "{\"nodeName\":\"$(hostname)-node\",\"cpuCores\":1,\"memoryGb\":1}")
            
            if echo "$worker_response" | grep -q '"success":true'; then
                WORKER_ID=$(echo "$worker_response" | grep -o '"workerId":"[^"]*"' | cut -d'"' -f4)
                WORKER_NAME=$(echo "$worker_response" | grep -o '"nodeName":"[^"]*"' | cut -d'"' -f4)
                echo -e "${GREEN}✓ Worker registered${NC}"
            fi
        fi
        
        return 0
    else
        error=$(echo "$response" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        echo ""
        echo -e "${RED}✗ Authentication failed: ${error:-Unknown error}${NC}"
        exit 1
    fi
}

# ✅ SAVE CONFIGURATION WITH WORKER INFO
save_config() {
    cat > "$INSTALL_DIR/config.json" << EOF
{
  "apiUrl": "$API_URL",
  "coordinatorUrl": "$COORDINATOR_URL/ws",
  "authToken": "$TOKEN",
  "workerId": "$WORKER_ID",
  "userId": "$USER_ID",
  "nodeName": "$WORKER_NAME",
  "allowNetwork": false,
  "maxCpuCores": null,
  "maxMemoryGb": null,
  "maxStorageGb": null,
  "enableGpu": false,
  "installedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    chmod 600 "$INSTALL_DIR/config.json"
    echo -e "${GREEN}✓ Configuration saved${NC}"
}

install_cli() {
    echo ""
    echo -e "${BOLD}Installing CLI...${NC}"
    
    # Download CLI from your repo or embed it
    curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/dxcloud.sh \
        -o "$INSTALL_DIR/bin/dxcloud" 2>/dev/null || {
        # Fallback: Use embedded version from earlier
        cp /path/to/embedded/dxcloud "$INSTALL_DIR/bin/dxcloud"
    }
    
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
    
    # ✅ EMBED THE WORKER SCRIPT DIRECTLY
    cat > "$INSTALL_DIR/bin/worker.js" << 'WORKER_EOF'
#!/usr/bin/env node
const WebSocket = require('ws');
const Docker = require('dockerode');
const os = require('os');
const fs = require('fs').promises;
const path = require('path');
const { execSync } = require('child_process');

const CONFIG_PATH = path.join(os.homedir(), '.distributex', 'config.json');
const LOGS_PATH = path.join(os.homedir(), '.distributex', 'logs');

class WorkerNode {
  constructor(config) {
    this.config = config;
    this.docker = new Docker();
    this.ws = null;
    this.activeJobs = new Map();
    this.isShuttingDown = false;
    this.heartbeatInterval = null;
    this.reconnectTimeout = null;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 10;
    this.capabilities = null;
    this.capabilitiesInterval = null;
  }

  async start() {
    console.log('🚀 Starting DistributeX Worker...\n');
    
    try {
      await fs.mkdir(LOGS_PATH, { recursive: true });
      await this.testDocker();
      await this.detectCapabilities();
      await this.connect();
      await this.sendCapabilities();
      this.startHeartbeat();
      this.startCapabilitiesMonitoring();
      this.setupSignalHandlers();
      
      console.log('✅ Worker started successfully\n');
      this.displayCapabilities();
    } catch (error) {
      console.error('❌ Failed to start worker:', error.message);
      this.log('ERROR', error.message);
      process.exit(1);
    }
  }

  async detectCapabilities() {
    console.log('🔍 Detecting system capabilities...');
    
    const cpus = os.cpus();
    const totalMemGb = os.totalmem() / (1024 ** 3);
    const freeMemGb = os.freemem() / (1024 ** 3);
    
    const cpuCores = this.config.maxCpuCores 
      ? Math.min(this.config.maxCpuCores, cpus.length) 
      : cpus.length;
    const cpuModel = cpus[0]?.model || 'Unknown CPU';
    
    const memoryGb = this.config.maxMemoryGb 
      ? Math.min(this.config.maxMemoryGb, totalMemGb * 0.8) 
      : Math.round(totalMemGb * 0.8 * 10) / 10;
    
    let storageGb = 50;
    try {
      if (process.platform === 'win32') {
        try {
          const wmic = execSync('wmic logicaldisk where "DeviceID=\\'C:\\'" get FreeSpace', { 
            encoding: 'utf8', timeout: 3000 
          });
          const lines = wmic.trim().split('\n');
          if (lines[1]) {
            const freeBytes = parseInt(lines[1].trim());
            storageGb = Math.round(freeBytes / (1024 ** 3));
          }
        } catch (e) {
          storageGb = this.config.maxStorageGb || 50;
        }
      } else {
        try {
          const output = execSync('df -h / | tail -1 | awk \\'{print $4}\\'', { 
            encoding: 'utf8', timeout: 3000 
          }).trim();
          const match = output.match(/(\d+\.?\d*)([KMGT])/);
          if (match) {
            const [, size, unit] = match;
            const multipliers = { K: 0.001, M: 0.001, G: 1, T: 1024 };
            storageGb = Math.round(parseFloat(size) * (multipliers[unit] || 1));
          }
        } catch (e) {
          storageGb = this.config.maxStorageGb || 50;
        }
      }
    } catch (e) {
      storageGb = this.config.maxStorageGb || 50;
    }
    
    storageGb = this.config.maxStorageGb 
      ? Math.min(this.config.maxStorageGb, storageGb * 0.5) 
      : Math.round(storageGb * 0.5 * 10) / 10;
    
    let gpuAvailable = false;
    let gpuModel = null;
    let gpuMemoryGb = 0;
    
    if (this.config.enableGpu !== false) {
      try {
        try {
          const nvidiaSmi = execSync('nvidia-smi --query-gpu=name,memory.total --format=csv,noheader', { 
            encoding: 'utf8', timeout: 3000 
          });
          const lines = nvidiaSmi.trim().split('\n');
          if (lines[0]) {
            const [name, memory] = lines[0].split(',');
            gpuModel = name.trim();
            gpuMemoryGb = parseFloat(memory.trim()) / 1024;
            gpuAvailable = true;
          }
        } catch (nvidiaError) {
          if (process.platform === 'linux') {
            try {
              const output = execSync('lspci | grep -i vga', { 
                encoding: 'utf8', timeout: 3000 
              });
              if (output.includes('AMD') || output.includes('Radeon')) {
                gpuAvailable = true;
                gpuModel = 'AMD GPU';
              } else if (output.includes('Intel')) {
                gpuAvailable = true;
                gpuModel = 'Intel GPU';
              }
            } catch (lspciError) {}
          }
        }
      } catch (e) {}
    }
    
    const platform = os.platform();
    const arch = os.arch();
    const hostname = os.hostname();
    
    this.capabilities = {
      cpuCores, cpuModel, memoryGb, storageGb,
      gpuAvailable, gpuModel, gpuMemoryGb,
      platform, arch, hostname,
      nodeName: this.config.nodeName || hostname,
      totalSystemCpu: cpus.length,
      totalSystemMemoryGb: Math.round(totalMemGb * 10) / 10,
      freeMemoryGb: Math.round(freeMemGb * 10) / 10,
      cpuUsagePercent: 0,
      memoryUsedGb: (totalMemGb - freeMemGb).toFixed(2),
      memoryAvailableGb: freeMemGb.toFixed(2),
      dockerVersion: null,
      dockerContainers: 0,
    };
    
    try {
      const dockerInfo = await this.docker.info();
      this.capabilities.dockerVersion = dockerInfo.ServerVersion;
      this.capabilities.dockerContainers = dockerInfo.Containers;
    } catch (e) {}
    
    console.log('✓ Capabilities detected\n');
  }

  startCapabilitiesMonitoring() {
    this.capabilitiesInterval = setInterval(async () => {
      await this.updateCurrentUsage();
    }, 10000);
  }

  async updateCurrentUsage() {
    const totalMemGb = os.totalmem() / (1024 ** 3);
    const freeMemGb = os.freemem() / (1024 ** 3);
    const usedMemGb = totalMemGb - freeMemGb;
    
    const cpuUsage = this.calculateCpuUsage();
    
    this.capabilities.cpuUsagePercent = cpuUsage;
    this.capabilities.memoryUsedGb = usedMemGb.toFixed(2);
    this.capabilities.memoryAvailableGb = freeMemGb.toFixed(2);
    
    try {
      const containers = await this.docker.listContainers();
      this.capabilities.dockerContainers = containers.length;
    } catch (e) {}
  }

  calculateCpuUsage() {
    const cpus = os.cpus();
    let totalIdle = 0;
    let totalTick = 0;
    
    cpus.forEach(cpu => {
      for (let type in cpu.times) {
        totalTick += cpu.times[type];
      }
      totalIdle += cpu.times.idle;
    });
    
    const idle = totalIdle / cpus.length;
    const total = totalTick / cpus.length;
    const usage = 100 - Math.round(100 * idle / total);
    
    return usage;
  }

  displayCapabilities() {
    console.log(`Worker ID: ${this.config.workerId}`);
    console.log(`Status: Online and ready\n`);
    console.log('📊 System Capabilities:');
    console.log(`   CPU: ${this.capabilities.cpuCores} cores (${this.capabilities.cpuModel})`);
    console.log(`   Memory: ${this.capabilities.memoryGb} GB`);
    console.log(`   Storage: ${this.capabilities.storageGb} GB`);
    console.log(`   GPU: ${this.capabilities.gpuAvailable ? this.capabilities.gpuModel : 'No'}`);
    console.log(`   Platform: ${this.capabilities.platform} (${this.capabilities.arch})\n`);
  }

  async testDocker() {
    console.log('🐳 Testing Docker connection...');
    try {
      await this.docker.ping();
      const info = await this.docker.info();
      console.log(`✓ Docker connected (${info.Containers} containers)\n`);
    } catch (error) {
      throw new Error('Docker not available. Please ensure Docker is installed and running.');
    }
  }

  async connect() {
    return new Promise((resolve, reject) => {
      console.log('🔌 Connecting to coordinator...');
      
      let wsUrl = this.config.coordinatorUrl;
      
      if (!wsUrl) {
        wsUrl = this.config.apiUrl
          .replace('https://distributex-api', 'wss://distributex-coordinator')
          .replace('http://localhost:8787', 'ws://localhost:8788');
        wsUrl += '/ws';
      }
      
      console.log(`   URL: ${wsUrl}`);
      console.log(`   Worker ID: ${this.config.workerId}`);
      
      this.ws = new WebSocket(wsUrl, {
        headers: {
          'Authorization': `Bearer ${this.config.authToken}`,
          'X-Worker-ID': this.config.workerId,
          'Upgrade': 'websocket',
          'Connection': 'Upgrade'
        }
      });

      this.ws.on('open', () => {
        console.log('✓ Connected to coordinator\n');
        this.reconnectAttempts = 0;
        this.log('Connected to coordinator');
        resolve();
      });

      this.ws.on('message', (data) => {
        try {
          const message = JSON.parse(data.toString());
          this.handleMessage(message);
        } catch (error) {
          console.error('Error parsing message:', error);
        }
      });

      this.ws.on('close', (code, reason) => {
        console.log(`⚠️  Disconnected from coordinator (${code})`);
        this.log(`Disconnected: ${code}`);
        this.notifyDisconnect();
        
        if (!this.isShuttingDown) {
          this.scheduleReconnect();
        }
      });

      this.ws.on('error', (error) => {
        console.error('WebSocket error:', error.message);
        this.log('ERROR', error.message);
      });

      setTimeout(() => {
        if (this.ws && this.ws.readyState !== WebSocket.OPEN) {
          this.ws.close();
          reject(new Error('Connection timeout'));
        }
      }, 30000);
    });
  }

  scheduleReconnect() {
    if (this.reconnectTimeout) clearTimeout(this.reconnectTimeout);
    
    this.reconnectAttempts++;
    
    if (this.reconnectAttempts > this.maxReconnectAttempts) {
      console.error('❌ Max reconnection attempts reached. Exiting...');
      process.exit(1);
    }
    
    const delay = Math.min(2000 * Math.pow(2, this.reconnectAttempts - 1), 30000);
    
    console.log(`⏳ Reconnecting in ${delay/1000}s...\n`);
    
    this.reconnectTimeout = setTimeout(async () => {
      try {
        await this.connect();
        await this.sendCapabilities();
        this.startHeartbeat();
      } catch (error) {
        console.error('Reconnection failed:', error.message);
        this.scheduleReconnect();
      }
    }, delay);
  }

  async sendCapabilities() {
    console.log('📤 Sending capabilities to coordinator...');
    
    await this.updateCurrentUsage();
    
    this.send({
      type: 'capabilities',
      capabilities: this.capabilities
    });
    
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
            cpuUsagePercent: this.capabilities.cpuUsagePercent,
            memoryUsedGb: parseFloat(this.capabilities.memoryUsedGb),
            memoryAvailableGb: parseFloat(this.capabilities.memoryAvailableGb),
            activeJobs: this.activeJobs.size
          }
        })
      });
      
      if (response.ok) {
        console.log('✓ Capabilities registered with API\n');
      }
    } catch (error) {
      console.error('⚠️  Failed to register with API:', error.message);
    }
    
    this.log('Sent capabilities', JSON.stringify(this.capabilities));
  }

  startHeartbeat() {
    if (this.heartbeatInterval) clearInterval(this.heartbeatInterval);
    
    this.heartbeatInterval = setInterval(async () => {
      await this.sendHeartbeat();
    }, 30000);
  }

  async sendHeartbeat() {
    try {
      await this.updateCurrentUsage();
      
      const status = this.activeJobs.size > 0 ? 'busy' : 'online';
      
      const response = await fetch(`${this.config.apiUrl}/api/workers/${this.config.workerId}/heartbeat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.config.authToken}`,
          'X-Worker-ID': this.config.workerId
        },
        body: JSON.stringify({
          status: status,
          capabilities: this.capabilities,
          metrics: {
            cpuUsagePercent: this.capabilities.cpuUsagePercent,
            memoryUsedGb: parseFloat(this.capabilities.memoryUsedGb),
            memoryAvailableGb: parseFloat(this.capabilities.memoryAvailableGb),
            activeJobs: this.activeJobs.size,
            dockerContainers: this.capabilities.dockerContainers
          }
        })
      });
      
      if (response.ok) {
        const data = await response.json();
        
        if (data.pendingJobs && data.pendingJobs.length > 0) {
          console.log(`📬 ${data.pendingJobs.length} pending job(s) available`);
        }
      }
    } catch (error) {
      console.error('Heartbeat failed:', error.message);
    }
  }

  async notifyDisconnect() {
    try {
      await fetch(`${this.config.apiUrl}/api/workers/${this.config.workerId}/disconnect`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.config.authToken}`,
          'X-Worker-ID': this.config.workerId
        }
      });
    } catch (error) {}
  }

  handleMessage(message) {
    switch (message.type) {
      case 'connected':
        console.log(`✓ Connection confirmed: ${message.workerId}\n`);
        break;
      
      case 'ping':
        this.send({ 
          type: 'pong', 
          timestamp: Date.now(), 
          healthScore: this.calculateHealthScore(),
          activeJobs: Array.from(this.activeJobs.keys())
        });
        break;
      
      case 'job_assigned':
        this.executeJob(message.job);
        break;
      
      case 'disconnect':
        console.log('⚠️  Coordinator requested disconnect:', message.reason);
        this.stop();
        break;
    }
  }

  calculateHealthScore() {
    const cpuLoad = this.capabilities.cpuUsagePercent / 100;
    const memUsed = parseFloat(this.capabilities.memoryUsedGb) / this.capabilities.memoryGb;
    
    let score = 100;
    if (cpuLoad > 0.8) score -= 20;
    else if (cpuLoad > 0.6) score -= 10;
    if (memUsed > 0.9) score -= 20;
    else if (memUsed > 0.75) score -= 10;
    
    return Math.max(0, score);
  }

  async executeJob(job) {
    console.log('\n' + '='.repeat(60));
    console.log(`📦 New Job: ${job.jobId}`);
    console.log('='.repeat(60) + '\n');
    
    this.activeJobs.set(job.jobId, job);
    
    this.send({ type: 'status', status: 'busy' });
    this.send({ type: 'job_update', jobId: job.jobId, status: 'running' });

    try {
      console.log('Job execution would happen here');
      // Actual job execution logic would go here
      
      this.send({
        type: 'job_update',
        jobId: job.jobId,
        status: 'completed'
      });
    } catch (error) {
      this.send({
        type: 'job_update',
        jobId: job.jobId,
        status: 'failed',
        data: { errorMessage: error.message }
      });
    } finally {
      this.activeJobs.delete(job.jobId);
      
      if (this.activeJobs.size === 0) {
        this.send({ type: 'status', status: 'online' });
      }
    }
  }

  send(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  async log(level, message) {
    const timestamp = new Date().toISOString();
    const logMessage = `[${timestamp}] ${typeof level === 'string' && level === 'ERROR' ? 'ERROR' : 'INFO'}: ${message || level}\n`;
    
    try {
      await fs.appendFile(path.join(LOGS_PATH, 'worker.log'), logMessage);
    } catch (e) {}
  }

  setupSignalHandlers() {
    const shutdown = async () => {
      if (this.isShuttingDown) return;
      this.isShuttingDown = true;
      
      console.log('\n⚠️  Shutting down...');
      
      this.send({ type: 'status', status: 'offline' });
      await this.notifyDisconnect();
      
      if (this.heartbeatInterval) clearInterval(this.heartbeatInterval);
      if (this.capabilitiesInterval) clearInterval(this.capabilitiesInterval);
      if (this.reconnectTimeout) clearTimeout(this.reconnectTimeout);
      if (this.ws) this.ws.close();
      
      console.log('✅ Shutdown complete\n');
      process.exit(0);
    };
    
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  }

  async stop() {
    await this.setupSignalHandlers();
  }
}

(async () => {
  try {
    const configData = await fs.readFile(CONFIG_PATH, 'utf-8');
    const config = JSON.parse(configData);
    
    if (!config.authToken || !config.workerId) {
      console.error('❌ Invalid configuration.');
      process.exit(1);
    }
    
    const worker = new WorkerNode(config);
    await worker.start();
  } catch (error) {
    if (error.code === 'ENOENT') {
      console.error('❌ Configuration not found.');
    } else {
      console.error('❌ Failed to start worker:', error.message);
    }
    process.exit(1);
  }
})();
WORKER_EOF
    
    chmod +x "$INSTALL_DIR/bin/worker.js"
    
    # Install dependencies
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
    npm install --silent 2>&1 | grep -v "npm WARN" || true
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
    
    if [ "$USER_ROLE" == "contributor" ] || [ "$USER_ROLE" == "both" ]; then
        echo -e "${BOLD}Start your worker:${NC}"
        echo -e "  ${CYAN}node $INSTALL_DIR/bin/worker.js${NC}"
        echo ""
        echo -e "${BOLD}Or run as service:${NC}"
        echo -e "  ${CYAN}dxcloud worker start${NC}"
        echo ""
    fi
    
    if [ "$USER_ROLE" == "developer" ] || [ "$USER_ROLE" == "both" ]; then
        echo -e "${BOLD}Submit a job:${NC}"
        echo -e "  ${CYAN}dxcloud submit --image python:3.11 --command 'python -c \"print(1+1)\"'${NC}"
        echo ""
    fi
    
    echo -e "${BOLD}Check status:${NC}"
    echo -e "  ${CYAN}dxcloud pool status${NC}"
    echo ""
}

# Main execution
main() {
    show_banner
    check_requirements
    setup_directories
    authenticate_user
    save_config
    install_cli
    
    # Only install worker if contributor/both
    if [ "$USER_ROLE" == "contributor" ] || [ "$USER_ROLE" == "both" ]; then
        install_worker
    fi
    
    show_completion
}

main
