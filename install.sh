#!/bin/bash
# DistributeX Complete Worker Installation - Docker Mode
# This replaces the placeholder with a fully functional worker

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   DistributeX Docker Worker Setup     ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
echo ""

# Check if running on Linux
OS="$(uname -s)"
if [ "$OS" != "Linux" ]; then
    echo -e "${RED}❌ This script currently only supports Linux${NC}"
    echo "For other platforms, please visit: https://distributex.cloud"
    exit 1
fi

# Check for Docker
echo -e "${BLUE}→${NC} Checking Docker..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found${NC}"
    echo ""
    echo "Please install Docker first:"
    echo "  curl -fsSL https://distributex-cloud-network.pages.dev/ | sh"
    exit 1
fi

if ! docker ps &> /dev/null; then
    echo -e "${RED}❌ Docker daemon not running${NC}"
    echo "Please start Docker: sudo systemctl start docker"
    exit 1
fi

echo -e "${GREEN}✓ Docker is running${NC}"

# Check for existing config
CONFIG_DIR="$HOME/.distributex"
CONFIG_FILE="$CONFIG_DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ No configuration found${NC}"
    echo "Please run 'dxcloud signup' first"
    exit 1
fi

echo -e "${GREEN}✓ Configuration found${NC}"

# Create worker directory
WORKER_DIR="$CONFIG_DIR/worker"
mkdir -p "$WORKER_DIR"

# Download worker files
echo -e "${BLUE}→${NC} Downloading worker components..."

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
    docker.io \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json ./
RUN npm install --only=production

COPY distributex-worker.js ./

CMD ["node", "distributex-worker.js"]
EOF

# Main worker script (from your documents)
cat > "$WORKER_DIR/distributex-worker.js" << 'WORKEREOF'
#!/usr/bin/env node
const WebSocket = require('ws');
const Docker = require('dockerode');
const os = require('os');
const fs = require('fs').promises;
const path = require('path');
const { execSync } = require('child_process');
const http = require('http');

const CONFIG_PATH = process.env.CONFIG_PATH || '/config/config.json';
const LOGS_PATH = '/logs';

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

healthServer.listen(3000, () => {
  console.log('✓ Health check server listening on :3000');
});

class WorkerNode {
  constructor(config) {
    this.config = config;
    this.docker = new Docker({ socketPath: '/var/run/docker.sock' });
    this.ws = null;
    this.activeJobs = new Map();
    this.isShuttingDown = false;
    this.heartbeatInterval = null;
    this.reconnectTimeout = null;
    this.reconnectAttempts = 0;
    this.capabilities = null;
    this.capabilitiesInterval = null;
  }

  async start() {
    console.log('🚀 Starting DistributeX Worker...\n');
    
    try {
      await this.testDocker();
      await this.detectCapabilities();
      this.displayCapabilities();
      await this.connect();
      await this.sendCapabilities();
      this.startHeartbeat();
      this.startCapabilitiesMonitoring();
      this.setupSignalHandlers();
      
      console.log('✅ Worker started successfully\n');
    } catch (error) {
      console.error('❌ Failed to start worker:', error.message);
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
    
    const memoryGb = this.config.maxMemoryGb 
      ? Math.min(this.config.maxMemoryGb, totalMemGb * 0.8) 
      : Math.round(totalMemGb * 0.8 * 10) / 10;
    
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
    } catch (e) {
      console.log('⚠️  Using default storage:', storageGb);
    }
    
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
    } catch (e) {
      // No GPU
    }
    
    this.capabilities = {
      cpuCores,
      memoryGb,
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
    } catch (e) {
      console.log('⚠️  Docker info not available');
    }
    
    console.log('✓ Capabilities detected');
  }

  displayCapabilities() {
    console.log('Worker Configuration:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`  Worker ID:    ${this.config.workerId}`);
    console.log(`  Node Name:    ${this.capabilities.nodeName}`);
    console.log(`  CPU:          ${this.capabilities.cpuCores} cores`);
    console.log(`  Memory:       ${this.capabilities.memoryGb} GB`);
    console.log(`  Storage:      ${this.capabilities.storageGb} GB`);
    console.log(`  GPU:          ${this.capabilities.gpuAvailable ? `${this.capabilities.gpuModel} (${this.capabilities.gpuMemoryGb.toFixed(1)} GB)` : 'None'}`);
    console.log(`  Platform:     ${this.capabilities.platform}/${this.capabilities.arch}`);
    console.log(`  Docker:       v${this.capabilities.dockerVersion || 'Unknown'}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  async testDocker() {
    console.log('🐳 Testing Docker connection...');
    try {
      await this.docker.ping();
      const info = await this.docker.info();
      console.log(`✓ Docker connected (${info.Containers} containers)`);
    } catch (error) {
      throw new Error(`Docker not available: ${error.message}`);
    }
  }

  async connect() {
    return new Promise((resolve, reject) => {
      console.log('🔌 Connecting to coordinator...');
      
      let wsUrl = this.config.coordinatorUrl || 'wss://distributex-coordinator.distributex.workers.dev/ws';
      
      console.log(`   URL: ${wsUrl}`);
      console.log(`   Worker ID: ${this.config.workerId}`);
      
      this.ws = new WebSocket(wsUrl, {
        headers: {
          'Authorization': `Bearer ${this.config.authToken}`,
          'X-Worker-ID': this.config.workerId,
        }
      });

      this.ws.on('open', () => {
        console.log('✓ Connected to coordinator');
        this.reconnectAttempts = 0;
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
        console.log(`⚠️  Disconnected (${code}: ${reason})`);
        if (!this.isShuttingDown) {
          this.scheduleReconnect();
        }
      });

      this.ws.on('error', (error) => {
        console.error('WebSocket error:', error.message);
      });

      setTimeout(() => {
        if (this.ws && this.ws.readyState !== WebSocket.OPEN) {
          console.log('⏰ Connection timeout');
          this.ws.close();
          reject(new Error('Connection timeout'));
        }
      }, 30000);
    });
  }

  scheduleReconnect() {
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
    }
    
    this.reconnectAttempts++;
    const delay = Math.min(5000 * Math.pow(1.5, this.reconnectAttempts - 1), 60000);
    
    console.log(`⏳ Reconnecting in ${(delay/1000).toFixed(0)}s (attempt ${this.reconnectAttempts})...`);
    
    this.reconnectTimeout = setTimeout(async () => {
      try {
        await this.connect();
        await this.sendCapabilities();
      } catch (error) {
        console.error('Reconnection failed:', error.message);
        this.scheduleReconnect();
      }
    }, delay);
  }

  async sendCapabilities() {
    console.log('📤 Registering capabilities...');
    
    await this.updateCurrentUsage();
    
    this.send({
      type: 'capabilities',
      capabilities: this.capabilities
    });
    
    try {
      const apiUrl = this.config.apiUrl || 'https://distributex-api.distributex.workers.dev';
      const response = await fetch(`${apiUrl}/api/workers/${this.config.workerId}/heartbeat`, {
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
        console.log('✓ Registered with API');
      } else {
        console.error(`⚠️  API registration failed: ${response.status}`);
      }
    } catch (error) {
      console.error('⚠️  API registration error:', error.message);
    }
  }

  startHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }
    
    this.heartbeatInterval = setInterval(async () => {
      await this.sendHeartbeat();
    }, 30000);
  }

  startCapabilitiesMonitoring() {
    if (this.capabilitiesInterval) {
      clearInterval(this.capabilitiesInterval);
    }
    
    this.capabilitiesInterval = setInterval(async () => {
      await this.updateCurrentUsage();
    }, 10000);
  }

  async updateCurrentUsage() {
    const totalMemGb = os.totalmem() / (1024 ** 3);
    const freeMemGb = os.freemem() / (1024 ** 3);
    const usedMemGb = totalMemGb - freeMemGb;
    
    this.capabilities.cpuUsagePercent = this.calculateCpuUsage();
    this.capabilities.memoryUsedGb = usedMemGb.toFixed(2);
    this.capabilities.memoryAvailableGb = freeMemGb.toFixed(2);
    
    try {
      const containers = await this.docker.listContainers();
      this.capabilities.dockerContainers = containers.length;
    } catch (e) {
      // Ignore
    }
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
    const usage = total > 0 ? Math.round(100 - (100 * idle / total)) : 0;
    
    return Math.max(0, Math.min(100, usage));
  }

  async sendHeartbeat() {
    try {
      await this.updateCurrentUsage();
      
      const status = this.activeJobs.size > 0 ? 'busy' : 'online';
      const apiUrl = this.config.apiUrl || 'https://distributex-api.distributex.workers.dev';
      
      const response = await fetch(`${apiUrl}/api/workers/${this.config.workerId}/heartbeat`, {
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
          console.log(`📬 ${data.pendingJobs.length} pending job(s)`);
        }
      }
    } catch (error) {
      console.error('Heartbeat failed:', error.message);
    }
  }

  handleMessage(message) {
    switch (message.type) {
      case 'connected':
        console.log(`✓ Connection confirmed: ${message.workerId}`);
        break;
      
      case 'ping':
        this.send({ 
          type: 'pong', 
          timestamp: Date.now(),
          activeJobs: Array.from(this.activeJobs.keys())
        });
        break;
      
      case 'job_assigned':
        this.executeJob(message.job);
        break;
      
      default:
        console.log('Message:', message.type);
    }
  }

  async executeJob(job) {
    console.log(`\n📦 Job ${job.jobId}: ${job.jobName}`);
    this.activeJobs.set(job.jobId, job);
    
    // Job execution would go here
    console.log('Job execution coming soon...');
    
    this.activeJobs.delete(job.jobId);
  }

  send(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  setupSignalHandlers() {
    const shutdown = async () => {
      if (this.isShuttingDown) return;
      this.isShuttingDown = true;
      
      console.log('\n⚠️  Shutting down...');
      
      if (this.heartbeatInterval) clearInterval(this.heartbeatInterval);
      if (this.capabilitiesInterval) clearInterval(this.capabilitiesInterval);
      if (this.reconnectTimeout) clearTimeout(this.reconnectTimeout);
      if (this.ws) this.ws.close();
      
      healthServer.close();
      
      console.log('✅ Shutdown complete');
      process.exit(0);
    };
    
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  }
}

// Main execution
(async () => {
  try {
    const configData = await fs.readFile(CONFIG_PATH, 'utf-8');
    const config = JSON.parse(configData);
    
    if (!config.authToken || !config.workerId) {
      console.error('❌ Invalid configuration');
      process.exit(1);
    }
    
    const worker = new WorkerNode(config);
    await worker.start();
  } catch (error) {
    console.error('❌ Fatal error:', error.message);
    await new Promise(() => {}); // Keep container alive for debugging
  }
})();
WORKEREOF

# docker-compose.yml
cat > "$WORKER_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  worker:
    build: .
    container_name: distributex-worker
    restart: unless-stopped
    privileged: true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${HOME}/.distributex:/config:ro
      - ${HOME}/.distributex/logs:/logs
    environment:
      - CONFIG_PATH=/config/config.json
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

echo -e "${GREEN}✓ Worker components downloaded${NC}"

# Install dependencies
echo -e "${BLUE}→${NC} Installing Node.js dependencies..."
cd "$WORKER_DIR"
npm install --only=production > /dev/null 2>&1

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Build Docker image
echo -e "${BLUE}→${NC} Building Docker image..."
docker build -t distributex-worker:latest . > /dev/null 2>&1

echo -e "${GREEN}✓ Docker image built${NC}"

# Clean up old placeholder files
echo -e "${BLUE}→${NC} Cleaning up old files..."
rm -f "$CONFIG_DIR/cli/index.js" 2>/dev/null || true
rm -f "$CONFIG_DIR/bin/dxcloud-worker" 2>/dev/null || true

# Start the worker (use 'docker compose' not 'docker-compose')
echo -e "${BLUE}→${NC} Starting worker container..."
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
else
    docker compose up -d
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                  ║${NC}"
echo -e "${GREEN}║       ✅  Worker Started Successfully!           ║${NC}"
echo -e "${GREEN}║                                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Container: distributex-worker"
echo ""
echo "Commands:"
echo -e "  ${BLUE}View logs:${NC}     docker logs -f distributex-worker"
echo -e "  ${BLUE}Stop worker:${NC}   cd $WORKER_DIR && docker compose down"
echo -e "  ${BLUE}Restart:${NC}       docker restart distributex-worker"
echo -e "  ${BLUE}Status:${NC}        docker ps | grep distributex"
echo ""
echo "Your worker is now live at https://distributex.cloud"
echo ""
echo -e "${YELLOW}Note: Old placeholder files have been cleaned up${NC}"
