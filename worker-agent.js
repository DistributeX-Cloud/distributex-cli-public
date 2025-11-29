#!/usr/bin/env node
/**
 * DistributeX Worker Agent - FIXED: Use host MAC address in Docker
 * 
 * CRITICAL FIX:
 * - Docker containers have virtual MAC addresses
 * - Must use host's real MAC address (passed via config or env var)
 * - Falls back to detecting MAC if not in Docker
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
  MAX_CONSECUTIVE_FAILURES: 5,
  IS_DOCKER: process.env.DOCKER_CONTAINER === 'true' || fs.existsSync('/.dockerenv'),
  DISABLE_SELF_REGISTER: process.env.DISABLE_SELF_REGISTER === 'true',
  HOST_MAC_ADDRESS: process.env.HOST_MAC_ADDRESS // Pass host MAC to container
};

class PersistentWorker {
  constructor(config) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || CONFIG.API_BASE_URL;
    this.workerId = null;
    this.macAddress = null;
    this.hostname = os.hostname();
    this.isRunning = true;
    this.isShuttingDown = false;
    this.heartbeatTimer = null;
    
    this.metrics = {
      startTime: Date.now(),
      successfulHeartbeats: 0,
      failedHeartbeats: 0,
      consecutiveFailures: 0
    };
    
    this.setupProcessHandlers();
  }

  setupProcessHandlers() {
    const shutdown = async (signal) => {
      if (this.isShuttingDown) {
        console.log('⚠️  Forced shutdown');
        process.exit(1);
      }
      
      console.log(`\n🛑 Received ${signal}, shutting down gracefully...`);
      this.isShuttingDown = true;
      this.isRunning = false;
      
      if (this.heartbeatTimer) {
        clearTimeout(this.heartbeatTimer);
      }
      
      if (this.macAddress) {
        try {
          await this.sendHeartbeat('offline');
          console.log('✅ Graceful shutdown complete');
        } catch (e) {
          console.log('⚠️  Could not send offline status');
        }
      }
      
      setTimeout(() => process.exit(0), 5000);
    };

    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
    
    process.on('uncaughtException', (error) => {
      console.error('❌ Uncaught exception:', error.message);
    });
    
    process.on('unhandledRejection', (reason) => {
      console.error('❌ Unhandled rejection:', reason);
    });
  }

  /**
   * Get MAC address - FIXED for Docker
   * Priority:
   * 1. Environment variable (HOST_MAC_ADDRESS) - set by install script
   * 2. Config file (/config/mac_address) - saved during installation
   * 3. Auto-detect from network interfaces (for non-Docker)
   */
  async getMacAddress() {
    try {
      // 1. Check environment variable (highest priority)
      if (CONFIG.HOST_MAC_ADDRESS) {
        const mac = CONFIG.HOST_MAC_ADDRESS.toLowerCase().replace(/[:-]/g, '');
        if (/^[0-9a-f]{12}$/.test(mac)) {
          console.log(`📌 MAC from ENV: ${mac}`);
          console.log(`📌 Source: HOST_MAC_ADDRESS environment variable`);
          return mac;
        }
      }

      // 2. Check config file (for Docker containers)
      if (CONFIG.IS_DOCKER) {
        try {
          const configPath = '/config/mac_address';
          if (fs.existsSync(configPath)) {
            const mac = fs.readFileSync(configPath, 'utf8').trim().toLowerCase().replace(/[:-]/g, '');
            if (/^[0-9a-f]{12}$/.test(mac)) {
              console.log(`📌 MAC from config: ${mac}`);
              console.log(`📌 Source: /config/mac_address file`);
              return mac;
            }
          }
        } catch (e) {
          console.warn('⚠️  Could not read MAC from config file');
        }
      }

      // 3. Auto-detect from network interfaces (fallback)
      console.log('📌 Detecting MAC from network interfaces...');
      const interfaces = os.networkInterfaces();
      
      for (const [name, ifaces] of Object.entries(interfaces)) {
        if (!ifaces) continue;
        
        for (const iface of ifaces) {
          if (iface.internal || !iface.mac || iface.mac === '00:00:00:00:00:00') {
            continue;
          }
          
          const mac = iface.mac.toLowerCase().replace(/[:-]/g, '');
          
          if (/^[0-9a-f]{12}$/.test(mac)) {
            console.log(`📌 MAC detected: ${mac} (interface: ${name})`);
            
            // Warn if in Docker (should use config/env instead)
            if (CONFIG.IS_DOCKER) {
              console.warn('⚠️  WARNING: Using Docker container MAC instead of host MAC');
              console.warn('⚠️  This may cause heartbeat failures');
              console.warn('⚠️  Set HOST_MAC_ADDRESS env var or mount /config/mac_address');
            }
            
            return mac;
          }
        }
      }
      
      throw new Error('No valid MAC address found');
    } catch (error) {
      console.error('❌ MAC detection failed:', error.message);
      throw error;
    }
  }

  async makeRequest(method, path, data = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      
      const headers = {
        'Content-Type': 'application/json',
        'User-Agent': 'DistributeX-Worker/3.5'
      };
      
      // Only add JWT for non-heartbeat endpoints
      if (!path.includes('/heartbeat')) {
        headers['Authorization'] = `Bearer ${this.apiKey}`;
      }
      
      const options = {
        method,
        headers,
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

  async detectStorage() {
    let storage = { total: 100, available: 50 };
    
    try {
      const platform = os.platform();
      
      if (platform === 'linux' || platform === 'darwin') {
        const { stdout } = await execAsync('df -BG / | tail -1');
        const parts = stdout.trim().split(/\s+/);
        
        storage.total = parseInt(parts[1].replace('G', '')) || 100;
        storage.available = parseInt(parts[3].replace('G', '')) || 50;
      }
    } catch {}

    return storage;
  }

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
      name: `Worker-${this.macAddress}`,
      hostname: this.hostname,
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
      storageTotal: storage.total * 1024,
      storageAvailable: storage.available * 1024,
      cpuSharePercent: cpuShare,
      ramSharePercent: ramShare,
      gpuSharePercent: gpuShare,
      storageSharePercent: storageShare,
      isDocker: CONFIG.IS_DOCKER,
      macAddress: this.macAddress
    };
  }

  async loadWorkerIdFromConfig() {
    try {
      const configPath = '/config/worker_id';
      if (fs.existsSync(configPath)) {
        const workerId = fs.readFileSync(configPath, 'utf8').trim();
        if (workerId) {
          console.log(`✅ Loaded worker ID: ${workerId}`);
          return workerId;
        }
      }
    } catch {}
    return null;
  }

  async register() {
    this.macAddress = await this.getMacAddress();
    
    if (CONFIG.DISABLE_SELF_REGISTER) {
      console.log('ℹ️  Self-registration disabled');
      console.log('ℹ️  Using pre-registered worker (heartbeat-only mode)');
      
      this.workerId = await this.loadWorkerIdFromConfig();
      
      if (this.workerId) {
        console.log(`✅ Using worker: ${this.workerId}`);
        console.log(`   Name: Worker-${this.macAddress}`);
        console.log(`   MAC: ${this.macAddress}`);
        console.log(`   Hostname: ${this.hostname}`);
        return { workerId: this.workerId, isNew: false };
      }
      
      console.error('\n❌ Worker ID not found');
      console.error('   Run installation script first');
      
      await new Promise(resolve => setTimeout(resolve, 30000));
      return await this.register();
    }
    
    console.log('\n🔍 Detecting system...');
    const capabilities = await this.detectSystem();
    
    console.log('\n📊 System:');
    console.log(`  Name: ${capabilities.name}`);
    console.log(`  MAC: ${capabilities.macAddress}`);
    console.log(`  CPU: ${capabilities.cpuCores} cores`);
    console.log(`  RAM: ${Math.floor(capabilities.ramTotal / 1024)}GB`);
    console.log(`  GPU: ${capabilities.gpuAvailable ? capabilities.gpuModel : 'None'}`);
    
    console.log('\n🚀 Registering...');
    const worker = await this.makeRequest('POST', '/api/workers/register', capabilities);
    this.workerId = worker.workerId;
    
    console.log(`\n✅ ${worker.isNew ? 'Registered' : 'Reconnected'}!`);
    console.log(`  Worker ID: ${this.workerId}`);
    
    return worker;
  }

  async sendHeartbeat(status = 'online') {
    if (!this.isRunning && status !== 'offline') return;
    
    try {
      if (!this.macAddress || !/^[0-9a-f]{12}$/.test(this.macAddress)) {
        throw new Error(`Invalid MAC format: ${this.macAddress}`);
      }
      
      const freeRam = Math.floor(os.freemem() / (1024 * 1024));
      const storage = await this.detectStorage();

      const heartbeatData = {
        macAddress: this.macAddress,
        ramAvailable: freeRam,
        storageAvailable: storage.available * 1024,
        status: status
      };

      const response = await this.makeRequest(
        'POST',
        '/api/workers/heartbeat',
        heartbeatData
      );

      this.metrics.successfulHeartbeats++;
      this.metrics.consecutiveFailures = 0;
      
      if (this.metrics.successfulHeartbeats % 5 === 0) {
        console.log(`💓 Heartbeat #${this.metrics.successfulHeartbeats} - ${response.workerName || 'OK'}`);
      }
      
    } catch (error) {
      this.metrics.failedHeartbeats++;
      this.metrics.consecutiveFailures++;
      
      console.error(`❌ Heartbeat failed (${this.metrics.consecutiveFailures}/${CONFIG.MAX_CONSECUTIVE_FAILURES}):`, error.message);
      
      if (this.metrics.consecutiveFailures === 1) {
        console.error('🔍 Debug info:', {
          macAddress: this.macAddress,
          macLength: this.macAddress?.length,
          workerId: this.workerId,
          hostname: this.hostname,
          isDocker: CONFIG.IS_DOCKER,
          macSource: CONFIG.HOST_MAC_ADDRESS ? 'ENV' : (CONFIG.IS_DOCKER ? 'Config file' : 'Auto-detected')
        });
      }
      
      if (this.metrics.consecutiveFailures >= CONFIG.MAX_CONSECUTIVE_FAILURES) {
        console.error('\n⚠️  Too many failures!');
        console.error('   MAC in database:', this.macAddress);
        console.error('   Check: SELECT * FROM workers WHERE mac_address =', this.macAddress);
      }
    }
  }

  scheduleHeartbeat() {
    if (this.isRunning && !this.isShuttingDown) {
      this.heartbeatTimer = setTimeout(async () => {
        await this.sendHeartbeat();
        this.scheduleHeartbeat();
      }, CONFIG.HEARTBEAT_INTERVAL);
    }
  }

  async runForever() {
    console.log('\n╔═══════════════════════════════════════════════════════════╗');
    console.log('║         DistributeX Worker v3.5 - Docker MAC Fix         ║');
    console.log('╚═══════════════════════════════════════════════════════════╝\n');
    
    if (!this.apiKey) {
      console.error('❌ API key required');
      process.exit(1);
    }

    await this.register();
    
    console.log('\n✨ Worker ONLINE');
    console.log('💓 Heartbeat every 60 seconds');
    console.log('🔒 Press Ctrl+C to stop\n');

    this.scheduleHeartbeat();
    
    await new Promise(() => {});
  }

  async start() {
    try {
      await this.runForever();
    } catch (error) {
      console.error('\n❌ Fatal error:', error.message);
      process.exit(1);
    }
  }
}

if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args.includes('--help')) {
    console.log(`
DistributeX Worker v3.5 - Docker MAC Fix

USAGE:
  node worker-agent.js --api-key YOUR_KEY

ENVIRONMENT:
  HOST_MAC_ADDRESS        Host's real MAC address (for Docker)
  DISABLE_SELF_REGISTER   Set to 'true' for heartbeat-only mode

DOCKER:
  docker run -e HOST_MAC_ADDRESS=aabbccddeeff ...
  Or mount config: -v ~/.distributex:/config:ro
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
