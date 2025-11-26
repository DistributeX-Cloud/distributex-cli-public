#!/usr/bin/env node
/**
 * DistributeX Worker Agent - Docker Optimized
 * 
 * Optimized for running inside Docker containers
 */

const os = require('os');
const https = require('https');
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');

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
    this.heartbeatInterval = null;
    this.isRunning = false;
    this.metrics = {
      lastHeartbeat: null,
      failedHeartbeats: 0,
      successfulHeartbeats: 0
    };
  }

  /**
   * Detect system capabilities (Docker-aware)
   */
  async detectSystemCapabilities() {
    console.log('🔍 Detecting system capabilities...');
    
    const cpus = os.cpus();
    const totalRam = Math.floor(os.totalmem() / (1024 * 1024)); // MB
    const freeRam = Math.floor(os.freemem() / (1024 * 1024)); // MB
    
    // GPU Detection
    let gpuInfo = await this.detectGPU();
    
    // Storage Detection  
    let storageInfo = await this.detectStorage();

    // In Docker, use more conservative sharing percentages
    const cpuSharePercent = CONFIG.IS_DOCKER ? 80 : (cpus.length >= 8 ? 50 : cpus.length >= 4 ? 40 : 30);
    const ramSharePercent = CONFIG.IS_DOCKER ? 80 : (totalRam >= 16384 ? 30 : totalRam >= 8192 ? 25 : 20);
    const gpuSharePercent = gpuInfo.available ? (CONFIG.IS_DOCKER ? 90 : 50) : 0;
    const storageSharePercent = CONFIG.IS_DOCKER ? 80 : (storageInfo.total >= 200 ? 20 : storageInfo.total >= 100 ? 15 : 10);

    const capabilities = {
      name: os.hostname(),
      hostname: os.hostname(),
      platform: os.platform(),
      architecture: os.arch(),
      cpuCores: cpus.length,
      cpuModel: cpus[0].model,
      ramTotal: totalRam,
      ramAvailable: freeRam,
      gpuAvailable: gpuInfo.available,
      gpuModel: gpuInfo.model,
      gpuMemory: gpuInfo.memory,
      storageTotal: storageInfo.total,
      storageAvailable: storageInfo.available,
      cpuSharePercent,
      ramSharePercent,
      gpuSharePercent,
      storageSharePercent,
    };

    return capabilities;
  }

  /**
   * Detect GPU
   */
  async detectGPU() {
    let gpuInfo = { available: false, model: null, memory: null };
    
    try {
      const platform = os.platform();
      
      if (platform === 'linux') {
        try {
          const { stdout } = await execAsync('nvidia-smi --query-gpu=name,memory.total --format=csv,noheader');
          const lines = stdout.trim().split('\n');
          if (lines.length > 0) {
            const [name, memory] = lines[0].split(',');
            gpuInfo.available = true;
            gpuInfo.model = name.trim();
            gpuInfo.memory = parseInt(memory.trim());
          }
        } catch (e) {
          // No GPU or drivers not installed
        }
      }
    } catch (error) {
      // GPU detection failed
    }

    return gpuInfo;
  }

  /**
   * Detect storage
   */
  async detectStorage() {
    let storageInfo = { total: 100, available: 50 }; // Defaults in GB
    
    try {
      const platform = os.platform();
      
      if (platform === 'linux' || platform === 'darwin') {
        const { stdout } = await execAsync('df -BG / | tail -1');
        const parts = stdout.trim().split(/\s+/);
        storageInfo.total = parseInt(parts[1].replace('G', ''));
        storageInfo.available = parseInt(parts[3].replace('G', ''));
      }
    } catch (error) {
      console.log('Storage detection using defaults');
    }

    return storageInfo;
  }

  /**
   * Make HTTP request with retry logic
   */
  async makeRequest(method, path, data = null, retries = CONFIG.RETRY_ATTEMPTS) {
    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        return await this._makeRequestOnce(method, path, data);
      } catch (error) {
        if (attempt === retries) throw error;
        
        const delay = CONFIG.RETRY_DELAY * attempt;
        console.log(`Retry ${attempt}/${retries} after ${delay}ms...`);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  /**
   * Single HTTP request attempt
   */
  async _makeRequestOnce(method, path, data = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      const options = {
        method,
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
          'User-Agent': 'DistributeX-Worker-Docker/2.0'
        },
        timeout: 30000
      };

      const req = https.request(url, options, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          try {
            const json = body ? JSON.parse(body) : {};
            
            if (res.statusCode >= 200 && res.statusCode < 300) {
              resolve(json);
            } else {
              reject(new Error(`HTTP ${res.statusCode}: ${json.message || body}`));
            }
          } catch (e) {
            reject(new Error(`Failed to parse response: ${body}`));
          }
        });
      });

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Request timeout'));
      });
      
      if (data) req.write(JSON.stringify(data));
      req.end();
    });
  }

  /**
   * Register worker with network
   */
  async register() {
    console.log('🔍 Detecting system capabilities...');
    const capabilities = await this.detectSystemCapabilities();
    
    console.log('\n📊 System Information:');
    console.log(`  Environment: ${CONFIG.IS_DOCKER ? 'Docker Container' : 'Native'}`);
    console.log(`  CPU: ${capabilities.cpuCores} cores (${capabilities.cpuModel})`);
    console.log(`  RAM: ${Math.floor(capabilities.ramTotal / 1024)} GB total`);
    console.log(`  GPU: ${capabilities.gpuAvailable ? capabilities.gpuModel : 'Not available'}`);
    console.log(`  Storage: ${capabilities.storageTotal} GB total`);
    
    console.log('\n📤 Sharing Configuration:');
    console.log(`  CPU: ${capabilities.cpuSharePercent}% (${Math.floor(capabilities.cpuCores * capabilities.cpuSharePercent / 100)} cores)`);
    console.log(`  RAM: ${capabilities.ramSharePercent}% (~${Math.floor(capabilities.ramAvailable * capabilities.ramSharePercent / 100 / 1024)} GB)`);
    console.log(`  GPU: ${capabilities.gpuSharePercent}%`);
    console.log(`  Storage: ${capabilities.storageSharePercent}% (~${Math.floor(capabilities.storageTotal * capabilities.storageSharePercent / 100)} GB)`);

    console.log('\n🚀 Registering worker...');
    const worker = await this.makeRequest('POST', '/api/workers/register', capabilities);
    this.workerId = worker.id;
    
    // Save worker ID to file
    try {
      const configDir = CONFIG.IS_DOCKER ? '/config' : path.join(os.homedir(), '.distributex');
      await fs.mkdir(configDir, { recursive: true });
      await fs.writeFile(
        path.join(configDir, 'worker-id'),
        this.workerId
      );
    } catch (e) {
      console.warn('Could not save worker ID:', e.message);
    }
    
    console.log(`✅ Worker registered! ID: ${this.workerId}`);
    return worker;
  }

  /**
   * Send heartbeat
   */
  async sendHeartbeat() {
    try {
      const freeRam = Math.floor(os.freemem() / (1024 * 1024));
      const storageInfo = await this.detectStorage();

      await this.makeRequest('POST', `/api/workers/${this.workerId}/heartbeat`, {
        ramAvailable: freeRam,
        storageAvailable: storageInfo.available,
        status: 'online',
      });

      this.metrics.lastHeartbeat = new Date();
      this.metrics.successfulHeartbeats++;
      this.metrics.failedHeartbeats = 0;
      
      console.log(`💓 Heartbeat sent at ${this.metrics.lastHeartbeat.toLocaleTimeString()}`);
    } catch (error) {
      this.metrics.failedHeartbeats++;
      console.error(`❌ Heartbeat failed (${this.metrics.failedHeartbeats}): ${error.message}`);
      
      if (this.metrics.failedHeartbeats >= 3) {
        console.warn('⚠️  Multiple heartbeat failures, attempting re-registration...');
        try {
          await this.register();
          this.metrics.failedHeartbeats = 0;
        } catch (e) {
          console.error('Re-registration failed:', e.message);
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
        throw new Error('API key required');
      }

      // Register worker
      await this.register();
      
      this.isRunning = true;
      
      // Send initial heartbeat
      await this.sendHeartbeat();
      
      // Schedule heartbeats
      this.heartbeatInterval = setInterval(
        () => this.sendHeartbeat(),
        CONFIG.HEARTBEAT_INTERVAL
      );

      console.log('\n✨ Worker is online and contributing!');
      console.log(`📡 Heartbeat interval: ${CONFIG.HEARTBEAT_INTERVAL / 60000} minutes`);
      console.log('Container will run until stopped\n');

      // Graceful shutdown
      process.on('SIGINT', () => this.stop());
      process.on('SIGTERM', () => this.stop());

      // Log stats every hour
      setInterval(() => {
        console.log('\n📊 Worker Stats:');
        console.log(`  Successful heartbeats: ${this.metrics.successfulHeartbeats}`);
        console.log(`  Last heartbeat: ${this.metrics.lastHeartbeat?.toLocaleString() || 'Never'}`);
        console.log(`  Worker ID: ${this.workerId}\n`);
      }, 3600000);

    } catch (error) {
      console.error('❌ Failed to start worker:', error.message);
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
        await this.makeRequest('POST', `/api/workers/${this.workerId}/heartbeat`, {
          ramAvailable: 0,
          storageAvailable: 0,
          status: 'offline',
        }, 1);
        
        console.log('✅ Worker stopped gracefully');
        console.log(`📊 Total heartbeats sent: ${this.metrics.successfulHeartbeats}`);
      } catch (error) {
        console.warn('Warning: Failed to send offline status');
      }
    }
    
    process.exit(0);
  }
}

// CLI Entry Point
if (require.main === module) {
  const args = process.argv.slice(2);
  
  // Parse arguments
  const apiKeyIndex = args.indexOf('--api-key');
  const urlIndex = args.indexOf('--url');
  
  if (apiKeyIndex === -1 || !args[apiKeyIndex + 1]) {
    console.error('❌ Usage: node worker-agent.js --api-key YOUR_API_KEY [--url API_URL]');
    process.exit(1);
  }

  const config = {
    apiKey: args[apiKeyIndex + 1],
    baseUrl: urlIndex !== -1 && args[urlIndex + 1] ? args[urlIndex + 1] : undefined
  };

  // Banner
  console.log('\n╔═════════════════════════════════════════════════════════════════════════════════╗');
  console.log('  ║                           DistributeX Worker Agent v2.0                         ║');
  console.log(`  ║      ${CONFIG.IS_DOCKER ? 'Docker Container Mode 🐳' : 'Native Mode 💻'}        ║`);
  console.log('  ╚═════════════════════════════════════════════════════════════════════════════════╝\n');

  const worker = new DistributeXWorker(config);
  worker.start();
}

module.exports = DistributeXWorker;
