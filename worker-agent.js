#!/usr/bin/env node
/**
 * DistributeX Persistent Worker Agent - FIXED VERSION
 * 
 * KEY FIXES:
 * 1. Never exits - runs indefinitely like Honeygain/EarnApp
 * 2. Fixed storage calculation (GB not TB)
 * 3. Proper error recovery
 * 4. Continuous heartbeat loop
 */

const os = require('os');
const https = require('https');
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');

const execAsync = promisify(exec);

// Configuration
const CONFIG = {
  API_BASE_URL: process.env.DISTRIBUTEX_API_URL || 'https://distributex-cloud-network.pages.dev',
  HEARTBEAT_INTERVAL: 60 * 1000, // 1 minute
  REGISTRATION_RETRY_DELAY: 30 * 1000, // 30 seconds
  MAX_CONSECUTIVE_FAILURES: 5,
  IS_DOCKER: process.env.DOCKER_CONTAINER === 'true' || fs.existsSync('/.dockerenv')
};

class PersistentWorker {
  constructor(config) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || CONFIG.API_BASE_URL;
    this.workerId = null;
    this.macAddress = null;
    this.isRunning = true;
    
    // Metrics
    this.metrics = {
      startTime: Date.now(),
      successfulHeartbeats: 0,
      failedHeartbeats: 0,
      consecutiveFailures: 0
    };
    
    this.setupProcessHandlers();
  }

  /**
   * Setup graceful shutdown only
   */
  setupProcessHandlers() {
    const shutdown = async (signal) => {
      console.log(`\n🛑 Received ${signal}, shutting down gracefully...`);
      this.isRunning = false;
      
      if (this.macAddress && this.workerId) {
        try {
          await this.makeRequest('POST', `/api/workers/${this.workerId}/heartbeat`, {
            macAddress: this.macAddress,
            status: 'offline'
          });
          console.log('✅ Graceful shutdown complete');
        } catch (e) {
          console.log('⚠️  Offline status not sent');
        }
      }
      
      process.exit(0);
    };

    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
    
    // Log errors but DON'T EXIT
    process.on('uncaughtException', (error) => {
      console.error('❌ Uncaught exception (continuing):', error.message);
    });
    
    process.on('unhandledRejection', (reason) => {
      console.error('❌ Unhandled rejection (continuing):', reason);
    });
  }

  /**
   * Get MAC address (normalized to 12 hex chars)
   */
  async getMacAddress() {
    try {
      const interfaces = os.networkInterfaces();
      
      for (const [name, ifaces] of Object.entries(interfaces)) {
        for (const iface of ifaces) {
          if (!iface.internal && iface.mac && iface.mac !== '00:00:00:00:00:00') {
            const mac = iface.mac.toLowerCase().replace(/[:-]/g, '');
            
            if (/^[0-9a-f]{12}$/.test(mac)) {
              console.log(`📌 MAC: ${mac} (${name})`);
              return mac;
            }
          }
        }
      }
      
      throw new Error('No valid MAC address found');
    } catch (error) {
      console.error('❌ MAC detection failed:', error.message);
      throw error;
    }
  }

  /**
   * Detect GPU
   */
  async detectGPU() {
    const gpu = {
      available: false,
      model: null,
      memory: 0,
      count: 0,
      driverVersion: null,
      cudaVersion: null
    };

    try {
      const { stdout } = await execAsync(
        'nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader',
        { timeout: 5000 }
      );
      
      const lines = stdout.trim().split('\n');
      if (lines.length > 0 && lines[0]) {
        gpu.available = true;
        gpu.count = lines.length;
        
        const [name, memory, driver] = lines[0].split(',').map(s => s.trim());
        gpu.model = name;
        gpu.memory = parseInt(memory) || 0;
        gpu.driverVersion = driver;
      }

      try {
        const { stdout: cudaOut } = await execAsync('nvcc --version', { timeout: 3000 });
        const match = cudaOut.match(/release\s+(\d+\.\d+)/i);
        if (match) gpu.cudaVersion = match[1];
      } catch {}
    } catch {}

    return gpu;
  }

  /**
   * Detect storage - FIXED: Returns GB not TB
   */
  async detectStorage() {
    let storage = { total: 100, available: 50 };
    
    try {
      const platform = os.platform();
      
      if (platform === 'linux' || platform === 'darwin') {
        const { stdout } = await execAsync('df -BG / | tail -1');
        const parts = stdout.trim().split(/\s+/);
        
        // FIXED: Parse GB values correctly
        storage.total = parseInt(parts[1].replace('G', '')) || 100;
        storage.available = parseInt(parts[3].replace('G', '')) || 50;
        
        console.log(`💾 Storage: ${storage.total}GB total, ${storage.available}GB available`);
      }
    } catch (error) {
      console.warn('⚠️  Storage detection failed, using defaults');
    }

    return storage;
  }

  /**
   * Detect system capabilities
   */
  async detectSystem() {
    const cpus = os.cpus();
    const totalRam = Math.floor(os.totalmem() / (1024 * 1024));
    const freeRam = Math.floor(os.freemem() / (1024 * 1024));
    
    const gpu = await this.detectGPU();
    const storage = await this.detectStorage();
    
    this.macAddress = await this.getMacAddress();

    const cpuShare = CONFIG.IS_DOCKER ? 90 : (cpus.length >= 8 ? 50 : 40);
    const ramShare = CONFIG.IS_DOCKER ? 85 : 30;
    const gpuShare = gpu.available ? (CONFIG.IS_DOCKER ? 95 : 50) : 0;
    const storageShare = CONFIG.IS_DOCKER ? 85 : 15;

    return {
      name: `${os.hostname()} Worker`,
      hostname: os.hostname(),
      platform: os.platform(),
      architecture: os.arch(),
      cpuCores: cpus.length,
      cpuModel: cpus[0].model,
      ramTotal: totalRam,
      ramAvailable: freeRam,
      gpuAvailable: gpu.available,
      gpuModel: gpu.model,
      gpuMemory: gpu.memory,
      gpuCount: gpu.count,
      gpuDriverVersion: gpu.driverVersion,
      gpuCudaVersion: gpu.cudaVersion,
      storageTotal: storage.total * 1024, // Convert GB to MB for database
      storageAvailable: storage.available * 1024,
      cpuSharePercent: cpuShare,
      ramSharePercent: ramShare,
      gpuSharePercent: gpuShare,
      storageSharePercent: storageShare,
      isDocker: CONFIG.IS_DOCKER,
      macAddress: this.macAddress
    };
  }

  /**
   * Make HTTP request
   */
  async makeRequest(method, path, data = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      
      const options = {
        method,
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
          'User-Agent': 'DistributeX-Worker/3.1'
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
              reject(new Error(`HTTP ${res.statusCode}: ${json.message || json.error || body}`));
            }
          } catch (e) {
            reject(new Error(`Parse error: ${body}`));
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
   * Register worker with retries
   */
  async register() {
    let attempt = 0;
    
    while (this.isRunning) {
      attempt++;
      
      try {
        console.log(`\n🔍 Detecting system (Attempt ${attempt})...`);
        const capabilities = await this.detectSystem();
        
        console.log('\n📊 System:');
        console.log(`  MAC: ${capabilities.macAddress}`);
        console.log(`  CPU: ${capabilities.cpuCores} cores`);
        console.log(`  RAM: ${Math.floor(capabilities.ramTotal / 1024)}GB`);
        console.log(`  Storage: ${Math.floor(capabilities.storageTotal / 1024)}GB`);
        console.log(`  GPU: ${capabilities.gpuAvailable ? capabilities.gpuModel : 'None'}`);
        
        console.log('\n🚀 Registering...');
        const worker = await this.makeRequest('POST', '/api/workers/register', capabilities);
        this.workerId = worker.workerId;
        
        console.log(`\n✅ ${worker.isNew ? 'Registered' : 'Reconnected'}!`);
        console.log(`  Worker ID: ${this.workerId}`);
        
        return worker;
        
      } catch (error) {
        console.error(`\n❌ Registration failed (Attempt ${attempt}):`, error.message);
        
        if (!this.isRunning) break;
        
        console.log(`⏳ Retrying in 30s...`);
        await new Promise(resolve => setTimeout(resolve, CONFIG.REGISTRATION_RETRY_DELAY));
      }
    }
  }

  /**
   * Send heartbeat
   */
  async sendHeartbeat() {
    if (!this.isRunning) return;
    
    try {
      const freeRam = Math.floor(os.freemem() / (1024 * 1024));
      const storage = await this.detectStorage();

      await this.makeRequest(
        'POST',
        `/api/workers/${this.workerId}/heartbeat`,
        {
          macAddress: this.macAddress,
          ramAvailable: freeRam,
          storageAvailable: storage.available * 1024, // Convert GB to MB
          status: 'online'
        }
      );

      this.metrics.successfulHeartbeats++;
      this.metrics.consecutiveFailures = 0;
      
      // Log every 5th heartbeat
      if (this.metrics.successfulHeartbeats % 5 === 0) {
        console.log(`💓 Heartbeat #${this.metrics.successfulHeartbeats}`);
      }
      
    } catch (error) {
      this.metrics.failedHeartbeats++;
      this.metrics.consecutiveFailures++;
      
      console.error(`❌ Heartbeat failed (${this.metrics.consecutiveFailures}/${CONFIG.MAX_CONSECUTIVE_FAILURES}):`, error.message);
      
      // Re-register if too many failures
      if (this.metrics.consecutiveFailures >= CONFIG.MAX_CONSECUTIVE_FAILURES) {
        console.warn('⚠️  Too many failures, re-registering...');
        await this.register();
      }
    }
  }

  /**
   * Run indefinitely - LIKE HONEYGAIN/EARNAPP
   */
  async runForever() {
    console.log('\n╔═══════════════════════════════════════════════════════════╗');
    console.log('║         DistributeX Persistent Worker v3.1              ║');
    console.log('║         Runs Forever Like Honeygain/EarnApp             ║');
    console.log('╚═══════════════════════════════════════════════════════════╝\n');
    
    if (!this.apiKey) {
      console.error('❌ API key required. Use --api-key YOUR_KEY');
      process.exit(1);
    }

    // Register
    await this.register();
    
    console.log('\n✨ Worker is ONLINE and running FOREVER');
    console.log('💓 Heartbeat every 60 seconds');
    console.log('🔒 Press Ctrl+C to stop\n');

    // CRITICAL: Infinite heartbeat loop
    while (this.isRunning) {
      await this.sendHeartbeat();
      
      // Wait for next heartbeat
      await new Promise(resolve => setTimeout(resolve, CONFIG.HEARTBEAT_INTERVAL));
    }
  }

  /**
   * Start worker
   */
  async start() {
    try {
      await this.runForever();
    } catch (error) {
      console.error('\n❌ Critical error:', error.message);
      
      // Try to recover
      if (this.isRunning) {
        console.log('🔄 Attempting recovery in 10s...');
        await new Promise(resolve => setTimeout(resolve, 10000));
        await this.start();
      }
    }
  }
}

// CLI Entry Point
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args.includes('--help')) {
    console.log(`
╔═══════════════════════════════════════════════════════════╗
║         DistributeX Persistent Worker v3.1               ║
╚═══════════════════════════════════════════════════════════╝

USAGE:
  node worker-agent.js --api-key YOUR_API_KEY

OPTIONS:
  --api-key    Your API key (REQUIRED)
  --url        API URL (optional)

EXAMPLE:
  node worker-agent.js --api-key abc123xyz456

GET API KEY:
  https://distributex-cloud-network.pages.dev/auth
`);
    process.exit(0);
  }
  
  const apiKeyIndex = args.indexOf('--api-key');
  const urlIndex = args.indexOf('--url');
  
  if (apiKeyIndex === -1 || !args[apiKeyIndex + 1]) {
    console.error('❌ --api-key required');
    process.exit(1);
  }

  const config = {
    apiKey: args[apiKeyIndex + 1],
    baseUrl: urlIndex !== -1 && args[urlIndex + 1] ? args[urlIndex + 1] : undefined
  };

  const worker = new PersistentWorker(config);
  worker.start();
}

module.exports = PersistentWorker;
