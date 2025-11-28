#!/usr/bin/env node
/**
 * DistributeX Worker Agent - FIXED VERSION
 * 
 * FIXES:
 * - Better error handling and logging
 * - Proper MAC address detection
 * - Detailed error messages for debugging
 * - Graceful fallbacks
 */

const os = require('os');
const https = require('https');
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');
const fsPromises = fs.promises;
const path = require('path');
const crypto = require('crypto');

const execAsync = promisify(exec);

// Configuration
const CONFIG = {
  API_BASE_URL: process.env.DISTRIBUTEX_API_URL || 'https://distributex-cloud-network.pages.dev',
  HEARTBEAT_INTERVAL: 5 * 60 * 1000, // 5 minutes
  RETRY_ATTEMPTS: 3,
  RETRY_DELAY: 5000,
  CACHE_DIR: '/config',
  IS_DOCKER: process.env.DOCKER_CONTAINER === 'true' || fs.existsSync('/.dockerenv')
};

class DistributeXWorker {
  constructor(config) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || CONFIG.API_BASE_URL;
    this.workerId = null;
    this.deviceFingerprint = null;
    this.heartbeatInterval = null;
    this.isRunning = false;
    this.metrics = {
      lastHeartbeat: null,
      failedHeartbeats: 0,
      successfulHeartbeats: 0
    };
  }

  /**
   * Generate consistent device fingerprint using MAC address
   */
  async generateDeviceFingerprint() {
    try {
      const hostname = os.hostname();
      const platform = os.platform();
      const arch = os.arch();
      const cpuModel = os.cpus()[0]?.model || 'unknown';
      
      // Try to get MAC address
      let macAddress = 'unknown';
      try {
        const networkInterfaces = os.networkInterfaces();
        for (const [name, interfaces] of Object.entries(networkInterfaces)) {
          for (const iface of interfaces) {
            if (!iface.internal && iface.mac && iface.mac !== '00:00:00:00:00:00') {
              macAddress = iface.mac;
              break;
            }
          }
          if (macAddress !== 'unknown') break;
        }
      } catch (e) {
        console.warn('⚠️  Could not get MAC address:', e.message);
      }
      
      // Normalize MAC address: lowercase, remove colons/dashes
      macAddress = macAddress.toLowerCase().replace(/[:-]/g, '');
      
      // Validate MAC address format
      if (!/^[0-9a-f]{12}$/.test(macAddress) && macAddress !== 'unknown') {
        console.warn(`⚠️  Invalid MAC format: ${macAddress}, using fallback`);
        macAddress = 'unknown';
      }
      
      console.log('📌 Device Fingerprint Components:');
      console.log('   Hostname:', hostname);
      console.log('   MAC:', macAddress);
      console.log('   CPU:', cpuModel);
      console.log('   Platform:', platform);
      console.log('   Arch:', arch);
      
      return macAddress;
      
    } catch (error) {
      console.error('❌ Error generating fingerprint:', error);
      return 'unknown';
    }
  }

  async getDockerId() {
    try {
      const cgroup = await fsPromises.readFile('/proc/self/cgroup', 'utf8');
      const match = cgroup.match(/docker\/([a-f0-9]+)/i);
      return match ? match[1].substring(0, 12) : null;
    } catch {
      return null;
    }
  }

  async getStableHostname() {
    const dockerId = await this.getDockerId();
    if (dockerId) {
      return `docker-${dockerId}`;
    }
    const h = os.hostname();
    if (h) return h.toLowerCase();
    return 'unknown';
  }

  /**
   * Detect GPU information
   */
  async detectGPU() {
    let gpuInfo = {
      available: false,
      model: null,
      memory: 0,
      count: 0,
      driverVersion: null,
      cudaVersion: null
    };

    try {
      // Try nvidia-smi
      const { stdout } = await execAsync('nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader', {
        timeout: 5000
      });
      
      const lines = stdout.trim().split('\n');
      if (lines.length > 0 && lines[0]) {
        gpuInfo.available = true;
        gpuInfo.count = lines.length;
        
        const [name, memory, driver] = lines[0].split(',').map(s => s.trim());
        gpuInfo.model = name;
        gpuInfo.memory = parseInt(memory) || 0;
        gpuInfo.driverVersion = driver;
      }

      // Try to get CUDA version
      try {
        const { stdout: cudaOut } = await execAsync('nvcc --version', { timeout: 3000 });
        const cudaMatch = cudaOut.match(/release\s+(\d+\.\d+)/i);
        if (cudaMatch) {
          gpuInfo.cudaVersion = cudaMatch[1];
        }
      } catch (e) {
        // CUDA not available
      }
    } catch (error) {
      // No NVIDIA GPU or nvidia-smi not available
      console.log('ℹ️  No NVIDIA GPU detected');
    }

    return gpuInfo;
  }
  
  async detectSystemCapabilities() {
    console.log('🔍 Detecting system capabilities...');
    
    const cpus = os.cpus();
    const totalRam = Math.floor(os.totalmem() / (1024 * 1024));
    const freeRam = Math.floor(os.freemem() / (1024 * 1024));
    
    const gpuInfo = await this.detectGPU();
    const storageInfo = await this.detectStorage();
    
    // Generate MAC address (device fingerprint)
    this.deviceFingerprint = await this.generateDeviceFingerprint();

    const cpuSharePercent = CONFIG.IS_DOCKER ? 80 : (cpus.length >= 8 ? 50 : cpus.length >= 4 ? 40 : 30);
    const ramSharePercent = CONFIG.IS_DOCKER ? 80 : (totalRam >= 16384 ? 30 : totalRam >= 8192 ? 25 : 20);
    const gpuSharePercent = gpuInfo.available ? (CONFIG.IS_DOCKER ? 90 : 50) : 0;
    const storageSharePercent = CONFIG.IS_DOCKER ? 80 : (storageInfo.total >= 200 ? 20 : storageInfo.total >= 100 ? 15 : 10);
  
    const capabilities = {
      name: await this.getStableHostname(),
      hostname: await this.getStableHostname(),
      platform: os.platform(),
      architecture: os.arch(),
      cpuCores: cpus.length,
      cpuModel: cpus[0].model,
      ramTotal: totalRam,
      ramAvailable: freeRam,
      gpuAvailable: gpuInfo.available,
      gpuModel: gpuInfo.model,
      gpuMemory: gpuInfo.memory,
      gpuCount: gpuInfo.count,
      gpuDriverVersion: gpuInfo.driverVersion,
      gpuCudaVersion: gpuInfo.cudaVersion,
      storageTotal: storageInfo.total,
      storageAvailable: storageInfo.available,
      cpuSharePercent,
      ramSharePercent,
      gpuSharePercent,
      storageSharePercent,
      isDocker: CONFIG.IS_DOCKER,
      dockerContainerId: await this.getDockerId(),
      macAddress: this.deviceFingerprint
    };

    return capabilities;
  }

  /**
   * Detect storage
   */
  async detectStorage() {
    let storageInfo = { total: 100, available: 50 };
    
    try {
      const platform = os.platform();
      
      if (platform === 'linux' || platform === 'darwin') {
        const { stdout } = await execAsync('df -BG / | tail -1');
        const parts = stdout.trim().split(/\s+/);
        storageInfo.total = parseInt(parts[1].replace('G', ''));
        storageInfo.available = parseInt(parts[3].replace('G', ''));
      }
    } catch (error) {
      console.log('ℹ️  Storage detection using defaults');
    }

    return storageInfo;
  }

  /**
   * Make HTTP request with detailed error logging
   */
  async makeRequest(method, path, data = null, retries = CONFIG.RETRY_ATTEMPTS) {
    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        return await this._makeRequestOnce(method, path, data);
      } catch (error) {
        console.error(`❌ Request failed (attempt ${attempt}/${retries}):`, error.message);
        
        if (attempt === retries) {
          throw error;
        }
        
        const delay = CONFIG.RETRY_DELAY * attempt;
        console.log(`⏳ Retrying in ${delay}ms...`);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  /**
   * Single HTTP request attempt with detailed error info
   */
  async _makeRequestOnce(method, path, data = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      
      console.log(`🌐 ${method} ${url.toString()}`);
      
      const options = {
        method,
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
          'User-Agent': 'DistributeX-Worker-Fixed/3.1'
        },
        timeout: 30000
      };

      const req = https.request(url, options, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          console.log(`📡 Response ${res.statusCode}: ${body.substring(0, 200)}${body.length > 200 ? '...' : ''}`);
          
          try {
            const json = body ? JSON.parse(body) : {};
            
            if (res.statusCode >= 200 && res.statusCode < 300) {
              resolve(json);
            } else {
              reject(new Error(`HTTP ${res.statusCode}: ${json.message || json.error || body}`));
            }
          } catch (e) {
            reject(new Error(`Failed to parse response (${res.statusCode}): ${body}`));
          }
        });
      });

      req.on('error', (err) => {
        console.error('🔴 Request error:', err);
        reject(err);
      });
      
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Request timeout'));
      });
      
      if (data) {
        const payload = JSON.stringify(data);
        console.log(`📤 Payload: ${payload.substring(0, 200)}${payload.length > 200 ? '...' : ''}`);
        req.write(payload);
      }
      
      req.end();
    });
  }

  /**
   * Register worker with detailed error handling
   */
  async register() {
    console.log('🔍 Detecting system capabilities...');
    const capabilities = await this.detectSystemCapabilities();
    
    // Validate MAC address before sending
    if (!capabilities.macAddress || capabilities.macAddress === 'unknown') {
      throw new Error('Cannot register without valid MAC address. Please check network interfaces.');
    }
    
    console.log('\n📊 System Information:');
    console.log(`  Environment: ${CONFIG.IS_DOCKER ? 'Docker Container' : 'Native'}`);
    console.log(`  MAC Address: ${capabilities.macAddress}`);
    console.log(`  CPU: ${capabilities.cpuCores} cores (${capabilities.cpuModel})`);
    console.log(`  RAM: ${Math.floor(capabilities.ramTotal / 1024)} GB total`);
    
    if (capabilities.gpuAvailable) {
      console.log(`  GPU: ${capabilities.gpuCount}x ${capabilities.gpuModel} (${capabilities.gpuMemory}MB)`);
      if (capabilities.gpuDriverVersion) {
        console.log(`  GPU Driver: ${capabilities.gpuDriverVersion}`);
      }
      if (capabilities.gpuCudaVersion) {
        console.log(`  CUDA: ${capabilities.gpuCudaVersion}`);
      }
    }

    console.log('\n🚀 Registering worker...');
    
    try {
      const worker = await this.makeRequest('POST', '/api/workers/register', capabilities);
      this.workerId = worker.workerId;
      
      console.log(`✅ Worker ${worker.isNew ? 'registered' : 'reconnected'}! ID: ${this.workerId}`);
      if (!worker.isNew) {
        console.log('   (Recognized existing device - no duplicate created)');
      }
      
      return worker;
    } catch (error) {
      console.error('\n❌ Registration failed:', error.message);
      console.error('   API URL:', this.baseUrl);
      console.error('   MAC Address:', capabilities.macAddress);
      console.error('   Please check:');
      console.error('   1. API URL is correct');
      console.error('   2. API key is valid');
      console.error('   3. Database migrations have been run');
      console.error('   4. Network connectivity is working');
      throw error;
    }
  }

  /**
   * Send heartbeat
   */
  async sendHeartbeat() {
    try {
      const freeRam = Math.floor(os.freemem() / (1024 * 1024));
      const storageInfo = await this.detectStorage();

      await this.makeRequest('POST', `/api/workers/${this.workerId}/heartbeat`, {
        macAddress: this.deviceFingerprint,
        ramAvailable: freeRam,
        storageAvailable: storageInfo.available,
        status: 'online',
      }, 1); // Only 1 retry for heartbeat

      this.metrics.lastHeartbeat = new Date();
      this.metrics.successfulHeartbeats++;
      this.metrics.failedHeartbeats = 0;
      
      console.log(`💓 Heartbeat sent at ${this.metrics.lastHeartbeat.toLocaleTimeString()}`);
    } catch (error) {
      this.metrics.failedHeartbeats++;
      console.error(`❌ Heartbeat failed (${this.metrics.failedHeartbeats}):`, error.message);
      
      if (this.metrics.failedHeartbeats >= 3) {
        console.warn('⚠️  Multiple heartbeat failures, attempting re-registration...');
        try {
          await this.register();
          this.metrics.failedHeartbeats = 0;
        } catch (e) {
          console.error('❌ Re-registration failed:', e.message);
        }
      }
    }
  }

  /**
   * Start worker
   */
  async start() {
    try {
      if (!this.apiKey) {
        throw new Error('API key required. Use --api-key YOUR_KEY');
      }

      console.log('🔐 Authenticating...');
      await this.register();
      
      this.isRunning = true;
      
      console.log('💓 Starting heartbeat...');
      await this.sendHeartbeat();
      
      this.heartbeatInterval = setInterval(
        () => this.sendHeartbeat(),
        CONFIG.HEARTBEAT_INTERVAL
      );

      console.log('\n✨ Worker is online and contributing!');
      console.log(`📡 Heartbeat interval: ${CONFIG.HEARTBEAT_INTERVAL / 60000} minutes`);
      console.log('Container will run until stopped\n');

      process.on('SIGINT', () => this.stop());
      process.on('SIGTERM', () => this.stop());

      // Periodic stats
      setInterval(() => {
        console.log('\n📊 Worker Stats:');
        console.log(`  Successful heartbeats: ${this.metrics.successfulHeartbeats}`);
        console.log(`  Last heartbeat: ${this.metrics.lastHeartbeat?.toLocaleString() || 'Never'}`);
        console.log(`  Worker ID: ${this.workerId}`);
        console.log(`  MAC Address: ${this.deviceFingerprint}\n`);
      }, 3600000); // Every hour

    } catch (error) {
      console.error('\n❌ Failed to start worker:', error.message);
      console.error('\nTroubleshooting:');
      console.error('1. Verify your API key is correct');
      console.error('2. Check network connectivity to', this.baseUrl);
      console.error('3. Ensure database migrations have been run');
      console.error('4. Check server logs for details');
      process.exit(1);
    }
  }

  /**
   * Stop worker gracefully
   */
  async stop() {
    console.log('\n🛑 Stopping worker...');
    this.isRunning = false;
    
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }

    if (this.workerId) {
      try {
        await this.makeRequest('DELETE', `/api/workers/${this.workerId}`, null, 1);
        
        console.log('✅ Worker disconnected gracefully');
        console.log(`📊 Total heartbeats sent: ${this.metrics.successfulHeartbeats}`);
      } catch (error) {
        console.warn('⚠️  Failed to send disconnect signal:', error.message);
      }
    }
    
    process.exit(0);
  }
}

// CLI Entry Point
if (require.main === module) {
  const args = process.argv.slice(2);
  
  // Show help
  if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    console.log(`
DistributeX Worker Agent

Usage:
  node worker-agent.js --api-key YOUR_API_KEY [--url API_URL]

Options:
  --api-key    Your DistributeX API key (required)
  --url        API base URL (default: https://distributex-cloud-network.pages.dev)
  --help       Show this help message

Example:
  node worker-agent.js --api-key abc123xyz456

Get your API key at:
  https://distributex-cloud-network.pages.dev/auth
`);
    process.exit(args.includes('--help') || args.includes('-h') ? 0 : 1);
  }
  
  const apiKeyIndex = args.indexOf('--api-key');
  const urlIndex = args.indexOf('--url');
  
  if (apiKeyIndex === -1 || !args[apiKeyIndex + 1]) {
    console.error('❌ Error: --api-key is required');
    console.error('Usage: node worker-agent.js --api-key YOUR_API_KEY');
    console.error('Get your API key at: https://distributex-cloud-network.pages.dev/auth');
    process.exit(1);
  }

  const config = {
    apiKey: args[apiKeyIndex + 1],
    baseUrl: urlIndex !== -1 && args[urlIndex + 1] ? args[urlIndex + 1] : undefined
  };

  console.log('\n╔═════════════════════════════════════════════════════════════════════════════════╗');
  console.log('  ║                        DistributeX Worker Agent v3.1                            ║');
  console.log(`  ║      ${CONFIG.IS_DOCKER ? 'Docker Container Mode 🐳' : 'Native Mode 💻'}        ║`);
  console.log('  ║              FIXED: Better Error Handling & MAC Address Detection               ║');
  console.log('  ╚═════════════════════════════════════════════════════════════════════════════════╝\n');

  const worker = new DistributeXWorker(config);
  worker.start();
}

module.exports = DistributeXWorker;
