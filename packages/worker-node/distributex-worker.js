#!/usr/bin/env node
// distributex-worker.js - COMPLETE FIXED VERSION WITH DEVICE TRACKING

const WebSocket = require('ws');
const Docker = require('dockerode');
const os = require('os');
const fs = require('fs').promises;
const path = require('path');
const { execSync } = require('child_process');
const http = require('http');

const CONFIG_PATH = process.env.CONFIG_PATH || '/config/config.json';
const LOGS_PATH = '/root/.distributex/logs';

// ✅ HEALTH CHECK SERVER
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

  // ==================== COMPREHENSIVE RESOURCE DETECTION ====================
  async detectCapabilities() {
    console.log('🔍 Detecting system capabilities...');
    
    const cpus = os.cpus();
    const totalMemGb = os.totalmem() / (1024 ** 3);
    const freeMemGb = os.freemem() / (1024 ** 3);
    const platform = os.platform();
    const arch = os.arch();
    const hostname = os.hostname();
    
    // ==================== CPU DETECTION ====================
    const totalCpuCores = cpus.length;
    const cpuCores = this.config.maxCpuCores 
      ? Math.min(this.config.maxCpuCores, totalCpuCores) 
      : totalCpuCores;
    const cpuModel = cpus[0]?.model || 'Unknown CPU';
    
    console.log(`   ✓ CPU: ${cpuCores}/${totalCpuCores} cores (${cpuModel})`);
    
    // ==================== MEMORY DETECTION ====================
    const memoryGb = this.config.maxMemoryGb 
      ? Math.min(this.config.maxMemoryGb, totalMemGb * 0.8) 
      : Math.round(totalMemGb * 0.8 * 10) / 10;
    
    console.log(`   ✓ RAM: ${memoryGb.toFixed(1)}/${totalMemGb.toFixed(1)} GB available`);
    
    // ==================== STORAGE DETECTION ====================
    let storageGb = 50;
    let storageDetectionMethod = 'default';
    
    try {
      if (platform === 'win32') {
        try {
          const psCommand = 'Get-PSDrive C | Select-Object -ExpandProperty Free';
          const output = execSync(`powershell -Command "${psCommand}"`, { 
            encoding: 'utf8', 
            timeout: 5000,
            stdio: ['pipe', 'pipe', 'ignore']
          }).trim();
          
          const freeBytes = parseInt(output);
          if (!isNaN(freeBytes) && freeBytes > 0) {
            storageGb = Math.round((freeBytes / (1024 ** 3)) * 0.5);
            storageDetectionMethod = 'powershell';
          }
        } catch (psError) {
          try {
            const wmic = execSync('wmic logicaldisk where "DeviceID=\'C:\'" get FreeSpace', { 
              encoding: 'utf8', 
              timeout: 5000,
              stdio: ['pipe', 'pipe', 'ignore']
            });
            const lines = wmic.trim().split('\n');
            if (lines[1]) {
              const freeBytes = parseInt(lines[1].trim());
              if (!isNaN(freeBytes) && freeBytes > 0) {
                storageGb = Math.round((freeBytes / (1024 ** 3)) * 0.5);
                storageDetectionMethod = 'wmic';
              }
            }
          } catch (wmicError) {
            console.log('   ⚠️  Could not detect storage, using default: 50 GB');
          }
        }
      } else {
        try {
          const output = execSync('df -BG / | tail -1', { 
            encoding: 'utf8', 
            timeout: 5000,
            stdio: ['pipe', 'pipe', 'ignore']
          }).trim();
          
          const parts = output.split(/\s+/);
          const availStr = parts[3];
          
          if (availStr && availStr.endsWith('G')) {
            const availGb = parseInt(availStr.slice(0, -1));
            if (!isNaN(availGb) && availGb > 0) {
              storageGb = Math.round(availGb * 0.5);
              storageDetectionMethod = 'df';
            }
          }
        } catch (dfError) {
          console.log('   ⚠️  Could not detect storage, using default: 50 GB');
        }
      }
    } catch (error) {
      console.log('   ⚠️  Storage detection failed, using default: 50 GB');
    }
    
    if (this.config.maxStorageGb) {
      storageGb = Math.min(this.config.maxStorageGb, storageGb);
    }
    
    console.log(`   ✓ Storage: ${storageGb} GB (detected via ${storageDetectionMethod})`);
    
    // ==================== GPU DETECTION ====================
    let gpuAvailable = false;
    let gpuModel = null;
    let gpuMemoryGb = 0;
    let gpuCount = 0;
    let gpuVendor = 'none';
    
    if (this.config.enableGpu !== false) {
      try {
        const nvidiaSmi = execSync('nvidia-smi --query-gpu=name,memory.total --format=csv,noheader', { 
          encoding: 'utf8', 
          timeout: 5000,
          stdio: ['pipe', 'pipe', 'ignore']
        });
        
        const lines = nvidiaSmi.trim().split('\n').filter(line => line.trim());
        if (lines.length > 0) {
          const [name, memory] = lines[0].split(',');
          gpuModel = name.trim();
          gpuMemoryGb = parseFloat(memory.trim()) / 1024;
          gpuAvailable = true;
          gpuCount = lines.length;
          gpuVendor = 'nvidia';
          
          console.log(`   ✓ GPU: NVIDIA ${gpuModel} (${gpuMemoryGb.toFixed(1)} GB VRAM, ${gpuCount} GPU(s))`);
        }
      } catch (nvidiaError) {
        try {
          const rocmSmi = execSync('rocm-smi --showproductname', { 
            encoding: 'utf8', 
            timeout: 5000,
            stdio: ['pipe', 'pipe', 'ignore']
          });
          
          if (rocmSmi.includes('GPU')) {
            gpuAvailable = true;
            gpuVendor = 'amd';
            gpuCount = 1;
            
            const lines = rocmSmi.trim().split('\n');
            for (const line of lines) {
              if (line.includes('GPU') && line.includes(':')) {
                const match = line.match(/:\s*(.+)/);
                if (match) {
                  gpuModel = match[1].trim();
                  break;
                }
              }
            }
            
            if (!gpuModel) gpuModel = 'AMD GPU (ROCm)';
            
            try {
              const vramInfo = execSync('rocm-smi --showmeminfo vram', { 
                encoding: 'utf8', 
                timeout: 3000,
                stdio: ['pipe', 'pipe', 'ignore']
              });
              const vramMatch = vramInfo.match(/(\d+)\s*MB/);
              if (vramMatch) {
                gpuMemoryGb = parseInt(vramMatch[1]) / 1024;
              }
            } catch (vramError) {
              // Continue without VRAM info
            }
            
            console.log(`   ✓ GPU: AMD ${gpuModel}${gpuMemoryGb > 0 ? ` (${gpuMemoryGb.toFixed(1)} GB VRAM)` : ''}`);
          }
        } catch (rocmError) {
          if (platform === 'linux') {
            try {
              const lspci = execSync('lspci | grep -iE "vga|3d|display"', { 
                encoding: 'utf8', 
                timeout: 3000,
                stdio: ['pipe', 'pipe', 'ignore']
              });
              
              if (lspci.toLowerCase().includes('amd') || lspci.toLowerCase().includes('radeon')) {
                gpuAvailable = true;
                gpuVendor = 'amd';
                gpuCount = (lspci.match(/amd|radeon/gi) || []).length;
                gpuModel = 'AMD GPU (detected via lspci)';
                console.log(`   ✓ GPU: ${gpuModel} (${gpuCount} GPU(s))`);
              } else if (lspci.toLowerCase().includes('intel')) {
                gpuAvailable = true;
                gpuVendor = 'intel';
                gpuCount = 1;
                gpuModel = 'Intel GPU (integrated)';
                console.log(`   ✓ GPU: ${gpuModel}`);
              }
            } catch (lspciError) {
              // No GPU detected
            }
          }
        }
      }
      
      if (!gpuAvailable) {
        console.log(`   ✓ GPU: None detected`);
      }
    } else {
      console.log(`   ✓ GPU: Disabled by configuration`);
    }
    
    console.log(`   ✓ Platform: ${platform} (${arch})`);
    console.log(`   ✓ Hostname: ${hostname}`);
    
    // ==================== DOCKER INFO ====================
    let dockerVersion = null;
    let dockerContainers = 0;
    
    try {
      const dockerInfo = await this.docker.info();
      dockerVersion = dockerInfo.ServerVersion;
      dockerContainers = dockerInfo.Containers;
      console.log(`   ✓ Docker: v${dockerVersion} (${dockerContainers} containers)`);
    } catch (e) {
      console.log('   ⚠️  Docker info not available');
    }
    
    // ==================== ASSEMBLE CAPABILITIES ====================
    this.capabilities = {
      // Core resources
      cpuCores,
      cpuModel,
      memoryGb,
      storageGb,
      gpuAvailable,
      gpuModel,
      gpuMemoryGb,
      gpuCount,
      gpuVendor,
      
      // System info
      platform,
      arch,
      hostname,
      nodeName: this.config.nodeName || hostname,
      
      // Total system resources
      totalSystemCpu: totalCpuCores,
      totalSystemMemoryGb: Math.round(totalMemGb * 10) / 10,
      freeMemoryGb: Math.round(freeMemGb * 10) / 10,
      
      // Current usage (updated every 10s)
      cpuUsagePercent: 0,
      memoryUsedGb: (totalMemGb - freeMemGb).toFixed(2),
      memoryAvailableGb: freeMemGb.toFixed(2),
      
      // Docker info
      dockerVersion,
      dockerContainers,
      
      // Detection metadata
      detectionTimestamp: new Date().toISOString(),
      storageDetectionMethod,
    };
    
    console.log('✓ Capabilities detected\n');
  }

  displayCapabilities() {
    console.log('Worker Configuration:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`  Worker ID:    ${this.config.workerId}`);
    console.log(`  Device ID:    ${this.config.deviceId || 'N/A'}`);
    console.log(`  Node Name:    ${this.capabilities.nodeName}`);
    console.log(`  CPU:          ${this.capabilities.cpuCores} cores`);
    console.log(`  Memory:       ${this.capabilities.memoryGb} GB`);
    console.log(`  Storage:      ${this.capabilities.storageGb} GB`);
    
    if (this.capabilities.gpuAvailable) {
      console.log(`  GPU:          ${this.capabilities.gpuModel}`);
      if (this.capabilities.gpuMemoryGb > 0) {
        console.log(`  GPU Memory:   ${this.capabilities.gpuMemoryGb.toFixed(1)} GB`);
      }
      if (this.capabilities.gpuCount > 1) {
        console.log(`  GPU Count:    ${this.capabilities.gpuCount}`);
      }
    } else {
      console.log(`  GPU:          None`);
    }
    
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
          console.log('⏰ Connection timeout, will retry');
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

  // ==================== FIXED: SEND CAPABILITIES WITH DEVICE INFO ====================
  async sendCapabilities() {
    console.log('📤 Registering capabilities...');
    
    await this.updateCurrentUsage();
    
    // Send to coordinator via WebSocket
    this.send({
      type: 'capabilities',
      capabilities: this.capabilities
    });
    
    // Send to API with full device info
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
          },
          deviceInfo: {
            deviceId: this.config.deviceId || `device-${this.config.workerId}`,
            deviceFingerprint: this.config.deviceFingerprint || '',
            userId: this.config.userId || 'anonymous'
          }
        })
      });
      
      if (response.ok) {
        const data = await response.json();
        console.log('✓ Connection confirmed:', this.config.workerId);
        
        if (data.registered) {
          console.log('🎉 NEW INSTALLATION DETECTED!');
          console.log(`   Device ID: ${data.deviceId}`);
          console.log(`   Worker ID: ${data.workerId}`);
        } else if (data.updated) {
          console.log('✓ Existing worker updated');
        }
        
        if (data.pendingJobs && data.pendingJobs.length > 0) {
          console.log(`📬 ${data.pendingJobs.length} pending job(s)`);
        }
      } else {
        console.error(`⚠️  API registration failed: ${response.status}`);
        const errorText = await response.text();
        console.error(`   Error: ${errorText}`);
      }
    } catch (error) {
      console.error('⚠️  API registration error:', error.message);
      console.error('   This is normal if the API is still initializing');
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

  // ==================== FIXED: SEND HEARTBEAT WITH DEVICE INFO ====================
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
          },
          deviceInfo: {
            deviceId: this.config.deviceId || `device-${this.config.workerId}`,
            deviceFingerprint: this.config.deviceFingerprint || '',
            userId: this.config.userId || 'anonymous'
          }
        })
      });
      
      if (response.ok) {
        const data = await response.json();
        if (data.pendingJobs && data.pendingJobs.length > 0) {
          console.log(`📬 ${data.pendingJobs.length} pending job(s)`);
        }
      } else {
        console.error(`Heartbeat failed: ${response.status}`);
      }
    } catch (error) {
      console.error('Heartbeat error:', error.message);
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
    
    // Job execution logic would go here
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
      console.error('Required: authToken, workerId');
      process.exit(1);
    }
    
    const worker = new WorkerNode(config);
    await worker.start();
  } catch (error) {
    console.error('❌ Fatal error:', error.message);
    console.error('Stack:', error.stack);
    
    // Keep container alive for debugging
    console.log('\n⏳ Keeping container alive for debugging...');
    console.log('Check logs: docker logs distributex-worker');
    await new Promise(() => {}); // Wait forever
  }
})();
