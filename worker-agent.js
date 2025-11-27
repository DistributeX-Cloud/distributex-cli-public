#!/usr/bin/env node
/**
 * DistributeX Worker Agent - FIXED VERSION
 * 
 * FIXED: Consistent device fingerprinting to prevent duplicate workers
 * - Uses single, deterministic fingerprint generation method
 * - Ensures one device = one worker registration
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
   * FIXED: Generate consistent device fingerprint
   * This ensures the same device always generates the same fingerprint
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
        console.warn('Could not get MAC address');
      }
      
      // CRITICAL FIX: Use consistent, deterministic fingerprint components
      // Remove any timestamp or random elements that would cause duplicates
      const fingerprintComponents = [
        macAddress.toLowerCase().trim(),
        cpuModel.toLowerCase().trim().replace(/\s+/g, '-'),
        platform.toLowerCase().trim(),
        arch.toLowerCase().trim()
      ];
      
      // Create deterministic fingerprint from components
      const fingerprintString = fingerprintComponents.join('|');
      const fingerprint = crypto
        .createHash('sha256')
        .update(fingerprintString)
        .digest('hex')
        .substring(0, 32);
      
      console.log('📌 Device Fingerprint Components:');
      console.log('   Hostname:', hostname);
      console.log('   MAC:', macAddress);
      console.log('   CPU:', cpuModel);
      console.log('   Platform:', platform);
      console.log('   Arch:', arch);
      console.log('📌 Generated Fingerprint:', fingerprint);
      
      return fingerprint;
    } catch (error) {
      console.error('❌ Error generating fingerprint:', error);
      // Fallback to basic fingerprint
      const fallback = crypto
        .createHash('sha256')
        .update(`${os.hostname()}-${os.platform()}-${os.arch()}`)
        .digest('hex')
        .substring(0, 32);
      console.log('⚠️  Using fallback fingerprint:', fallback);
      return fallback;
    }
  }

  /**
   * Detect GPU devices and capabilities
   */
  async detectGPU() {
    let gpuInfo = { 
      available: false, 
      model: null, 
      memory: null,
      count: 0,
      driverVersion: null,
      cudaVersion: null
    };
    
    try {
      const platform = os.platform();
      
      if (platform === 'linux') {
        // Try NVIDIA first
        try {
          const { stdout } = await execAsync('nvidia-smi --query-gpu=name,memory.total,driver_version,count --format=csv,noheader');
          const lines = stdout.trim().split('\n');
          
          if (lines.length > 0 && lines[0]) {
            const [name, memory, driverVersion] = lines[0].split(',').map(s => s.trim());
            gpuInfo.available = true;
            gpuInfo.model = name;
            gpuInfo.memory = parseInt(memory);
            gpuInfo.driverVersion = driverVersion;
            gpuInfo.count = lines.length;
            
            // Try to get CUDA version
            try {
              const { stdout: cudaOut } = await execAsync('nvcc --version 2>/dev/null || nvidia-smi | grep "CUDA Version"');
              const cudaMatch = cudaOut.match(/CUDA Version[:\s]+(\d+\.\d+)/i);
              if (cudaMatch) {
                gpuInfo.cudaVersion = cudaMatch[1];
              }
            } catch (e) {
              console.log('Could not detect CUDA version');
            }
            
            console.log(`✓ Detected ${gpuInfo.count} NVIDIA GPU(s): ${gpuInfo.model}`);
          }
        } catch (e) {
          // Try AMD ROCm
          try {
            const { stdout } = await execAsync('rocm-smi --showproductname 2>/dev/null');
            const gpuMatches = stdout.match(/GPU\[(\d+)\].*:\s*(.+)/g);
            if (gpuMatches && gpuMatches.length > 0) {
              gpuInfo.available = true;
              gpuInfo.model = gpuMatches[0].split(':')[1].trim();
              gpuInfo.count = gpuMatches.length;
              
              const { stdout: memOut } = await execAsync('rocm-smi --showmeminfo vram 2>/dev/null');
              const memMatch = memOut.match(/Total.*?(\d+)/);
              if (memMatch) {
                gpuInfo.memory = parseInt(memMatch[1]);
              }
              
              console.log(`✓ Detected ${gpuInfo.count} AMD GPU(s): ${gpuInfo.model}`);
            }
          } catch (e) {
            // No AMD GPU found
          }
        }
      } else if (platform === 'darwin') {
        // macOS Metal detection
        try {
          const { stdout } = await execAsync('system_profiler SPDisplaysDataType 2>/dev/null');
          const gpuMatch = stdout.match(/Chipset Model:\s*(.+)/);
          if (gpuMatch) {
            gpuInfo.available = true;
            gpuInfo.model = gpuMatch[1].trim();
            gpuInfo.count = 1;
            
            const totalRam = os.totalmem();
            gpuInfo.memory = Math.floor(totalRam / (1024 * 1024) * 0.5);
            
            console.log(`✓ Detected Metal GPU: ${gpuInfo.model}`);
          }
        } catch (e) {
          // No GPU detection on macOS
        }
      } else if (platform === 'win32') {
        // Windows GPU detection
        try {
          const { stdout } = await execAsync('wmic path win32_VideoController get name,AdapterRAM');
          const lines = stdout.trim().split('\n').slice(1).filter(l => l.trim());
          
          if (lines.length > 0) {
            const firstGpu = lines[0].trim().split(/\s{2,}/);
            gpuInfo.available = true;
            gpuInfo.model = firstGpu[1] || 'Unknown GPU';
            gpuInfo.memory = firstGpu[0] ? Math.floor(parseInt(firstGpu[0]) / (1024 * 1024)) : null;
            gpuInfo.count = lines.length;
            
            console.log(`✓ Detected ${gpuInfo.count} GPU(s): ${gpuInfo.model}`);
          }
        } catch (e) {
          // No GPU detection on Windows
        }
      }
    } catch (error) {
      console.log('GPU detection failed:', error.message);
    }
    
    if (!gpuInfo.available) {
      console.log('ℹ No GPU detected or GPU tools not installed');
    }
    
    return gpuInfo;
  }

  /**
   * Detect system capabilities
   */

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
    // 1. Prefer Docker container ID if inside Docker
    const dockerId = await this.getDockerId();
    if (dockerId) {
      return `docker-${dockerId}`;
    }

    // 2. Otherwise use OS hostname
    const h = os.hostname();
    if (h) return h.toLowerCase();

    // 3. Absolute fallback
    return 'unknown';
  }
  
  async detectSystemCapabilities() {
    console.log('🔍 Detecting system capabilities...');
    
    const cpus = os.cpus();
    const totalRam = Math.floor(os.totalmem() / (1024 * 1024));
    const freeRam = Math.floor(os.freemem() / (1024 * 1024));
    
    const gpuInfo = await this.detectGPU();
    const storageInfo = await this.detectStorage();
    
    // CRITICAL: Generate device fingerprint ONCE
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
      deviceFingerprint: this.deviceFingerprint
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
          'User-Agent': 'DistributeX-Worker-Fixed/3.1'
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
   * Register worker with consistent fingerprint
   */
  async register() {
    console.log('🔍 Detecting system capabilities...');
    const capabilities = await this.detectSystemCapabilities();
    
    console.log('\n📊 System Information:');
    console.log(`  Environment: ${CONFIG.IS_DOCKER ? 'Docker Container' : 'Native'}`);
    console.log(`  Device Fingerprint: ${capabilities.deviceFingerprint}`);
    console.log(`  CPU: ${capabilities.cpuCores} cores (${capabilities.cpuModel})`);
    console.log(`  RAM: ${Math.floor(capabilities.ramTotal / 1024)} GB total`);
    
    if (capabilities.gpuAvailable) {
      console.log(`  GPU: ${capabilities.gpuCount}x ${capabilities.gpuModel}`);
      if (capabilities.gpuMemory) {
        console.log(`       ${Math.floor(capabilities.gpuMemory / 1024)} GB VRAM per GPU`);
      }
      if (capabilities.gpuDriverVersion) {
        console.log(`       Driver: ${capabilities.gpuDriverVersion}`);
      }
      if (capabilities.gpuCudaVersion) {
        console.log(`       CUDA: ${capabilities.gpuCudaVersion}`);
      }
    } else {
      console.log(`  GPU: Not available`);
    }
    
    console.log(`  Storage: ${capabilities.storageTotal} GB total`);
    
    console.log('\n📤 Sharing Configuration:');
    console.log(`  CPU: ${capabilities.cpuSharePercent}% (${Math.floor(capabilities.cpuCores * capabilities.cpuSharePercent / 100)} cores)`);
    console.log(`  RAM: ${capabilities.ramSharePercent}% (~${Math.floor(capabilities.ramAvailable * capabilities.ramSharePercent / 100 / 1024)} GB)`);
    console.log(`  GPU: ${capabilities.gpuSharePercent}% (${Math.ceil(capabilities.gpuCount * capabilities.gpuSharePercent / 100)} devices)`);
    console.log(`  Storage: ${capabilities.storageSharePercent}% (~${Math.floor(capabilities.storageTotal * capabilities.storageSharePercent / 100)} GB)`);

    console.log('\n🚀 Registering worker...');
    const worker = await this.makeRequest('POST', '/api/workers/register', capabilities);
    this.workerId = worker.id;
    
    console.log(`✅ Worker ${worker.isNew ? 'registered' : 'reconnected'}! ID: ${this.workerId}`);
    if (!worker.isNew) {
      console.log('   (Recognized existing device - no duplicate created)');
    }
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

      await this.register();
      
      this.isRunning = true;
      
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

      setInterval(() => {
        console.log('\n📊 Worker Stats:');
        console.log(`  Successful heartbeats: ${this.metrics.successfulHeartbeats}`);
        console.log(`  Last heartbeat: ${this.metrics.lastHeartbeat?.toLocaleString() || 'Never'}`);
        console.log(`  Worker ID: ${this.workerId}`);
        console.log(`  Device Fingerprint: ${this.deviceFingerprint}\n`);
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
        await this.makeRequest('DELETE', `/api/workers/${this.workerId}`, null, 1);
        
        console.log('✅ Worker disconnected gracefully');
        console.log(`📊 Total heartbeats sent: ${this.metrics.successfulHeartbeats}`);
      } catch (error) {
        console.warn('Warning: Failed to send disconnect signal');
      }
    }
    
    process.exit(0);
  }
}

// CLI Entry Point
if (require.main === module) {
  const args = process.argv.slice(2);
  
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

  console.log('\n╔═════════════════════════════════════════════════════════════════════════════════╗');
  console.log('  ║                        DistributeX Worker Agent v3.1                            ║');
  console.log(`  ║      ${CONFIG.IS_DOCKER ? 'Docker Container Mode 🐳' : 'Native Mode 💻'}        ║`);
  console.log('  ║              FIXED: Consistent Device Fingerprinting                            ║');
  console.log('  ╚═════════════════════════════════════════════════════════════════════════════════╝\n');

  const worker = new DistributeXWorker(config);
  worker.start();
}

module.exports = DistributeXWorker;
