#!/usr/bin/env node
/**
 * DistributeX Worker Agent
 * Install: npm install -g distributex-worker
 * Usage: distributex-worker --api-key YOUR_API_KEY
 */

const os = require('os');
const https = require('https');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

class DistributeXWorker {
  constructor(config) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || 'https://YOUR-SITE.pages.dev';
    this.workerId = null;
    this.heartbeatInterval = null;
    this.isRunning = false;
  }

  async detectSystemCapabilities() {
    const cpus = os.cpus();
    const totalRam = Math.floor(os.totalmem() / (1024 * 1024)); // MB
    const freeRam = Math.floor(os.freemem() / (1024 * 1024)); // MB
    
    // Detect GPU (basic detection)
    let gpuInfo = { available: false, model: null, memory: null };
    try {
      if (os.platform() === 'linux') {
        const { stdout } = await execAsync('lspci | grep -i vga || nvidia-smi --query-gpu=name,memory.total --format=csv,noheader');
        if (stdout.includes('NVIDIA') || stdout.includes('AMD')) {
          gpuInfo.available = true;
          gpuInfo.model = stdout.split('\n')[0];
          // Parse VRAM if available
          const vramMatch = stdout.match(/(\d+)MiB/);
          if (vramMatch) gpuInfo.memory = parseInt(vramMatch[1]);
        }
      } else if (os.platform() === 'darwin') {
        const { stdout } = await execAsync('system_profiler SPDisplaysDataType');
        gpuInfo.available = stdout.includes('Metal');
        gpuInfo.model = 'Apple GPU';
      } else if (os.platform() === 'win32') {
        const { stdout } = await execAsync('wmic path win32_VideoController get name');
        gpuInfo.available = true;
        gpuInfo.model = stdout.split('\n')[1].trim();
      }
    } catch (error) {
      console.log('GPU detection failed, assuming no GPU available');
    }

    // Detect storage
    let storageInfo = { total: 100, available: 50 }; // GB, defaults
    try {
      if (os.platform() === 'linux' || os.platform() === 'darwin') {
        const { stdout } = await execAsync('df -BG / | tail -1');
        const parts = stdout.trim().split(/\s+/);
        storageInfo.total = parseInt(parts[1]);
        storageInfo.available = parseInt(parts[3]);
      } else if (os.platform() === 'win32') {
        const { stdout } = await execAsync('wmic logicaldisk get size,freespace,caption');
        const lines = stdout.trim().split('\n').slice(1);
        if (lines.length > 0) {
          const parts = lines[0].trim().split(/\s+/);
          storageInfo.total = Math.floor(parseInt(parts[2]) / (1024 * 1024 * 1024));
          storageInfo.available = Math.floor(parseInt(parts[1]) / (1024 * 1024 * 1024));
        }
      }
    } catch (error) {
      console.log('Storage detection failed, using defaults');
    }

    // Calculate safe sharing percentages (don't impact system)
    const cpuSharePercent = cpus.length >= 4 ? 40 : 30;
    const ramSharePercent = totalRam >= 8192 ? 30 : 20;
    const gpuSharePercent = gpuInfo.available ? 50 : 0;
    const storageSharePercent = storageInfo.total >= 100 ? 20 : 10;

    return {
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
  }

  async makeRequest(method, path, data = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      const options = {
        method,
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
      };

      const req = https.request(url, options, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          try {
            const json = JSON.parse(body);
            if (res.statusCode >= 200 && res.statusCode < 300) {
              resolve(json);
            } else {
              reject(new Error(`HTTP ${res.statusCode}: ${json.message}`));
            }
          } catch (e) {
            reject(new Error(`Failed to parse response: ${body}`));
          }
        });
      });

      req.on('error', reject);
      if (data) req.write(JSON.stringify(data));
      req.end();
    });
  }

  async register() {
    console.log('🔍 Detecting system capabilities...');
    const capabilities = await this.detectSystemCapabilities();
    
    console.log('\n📊 System Information:');
    console.log(`  CPU: ${capabilities.cpuCores} cores (${capabilities.cpuModel})`);
    console.log(`  RAM: ${Math.floor(capabilities.ramTotal / 1024)} GB total, ${Math.floor(capabilities.ramAvailable / 1024)} GB available`);
    console.log(`  GPU: ${capabilities.gpuAvailable ? capabilities.gpuModel : 'Not available'}`);
    console.log(`  Storage: ${capabilities.storageTotal} GB total, ${capabilities.storageAvailable} GB available`);
    console.log('\n📤 Sharing Configuration:');
    console.log(`  CPU: ${capabilities.cpuSharePercent}% (${Math.floor(capabilities.cpuCores * capabilities.cpuSharePercent / 100)} cores)`);
    console.log(`  RAM: ${capabilities.ramSharePercent}% (${Math.floor(capabilities.ramAvailable * capabilities.ramSharePercent / 100 / 1024)} GB)`);
    console.log(`  GPU: ${capabilities.gpuSharePercent}%`);
    console.log(`  Storage: ${capabilities.storageSharePercent}% (${Math.floor(capabilities.storageTotal * capabilities.storageSharePercent / 100)} GB)`);

    console.log('\n🚀 Registering worker with DistributeX...');
    const worker = await this.makeRequest('POST', '/api/workers/register', capabilities);
    this.workerId = worker.id;
    
    console.log(`✅ Worker registered successfully! ID: ${this.workerId}`);
    return worker;
  }

  async sendHeartbeat() {
    const freeRam = Math.floor(os.freemem() / (1024 * 1024));
    
    // Update storage availability
    let storageAvailable = 50;
    try {
      if (os.platform() === 'linux' || os.platform() === 'darwin') {
        const { stdout } = await execAsync('df -BG / | tail -1');
        storageAvailable = parseInt(stdout.trim().split(/\s+/)[3]);
      }
    } catch (error) {
      // Use default
    }

    await this.makeRequest('POST', `/api/workers/${this.workerId}/heartbeat`, {
      ramAvailable: freeRam,
      storageAvailable,
      status: 'online',
    });
  }

  async start() {
    try {
      if (!this.apiKey) {
        throw new Error('API key is required. Get one from https://distributex.io');
      }

      await this.register();
      
      this.isRunning = true;
      
      // Send heartbeat every 60 seconds
      this.heartbeatInterval = setInterval(async () => {
        try {
          await this.sendHeartbeat();
          console.log(`💓 Heartbeat sent at ${new Date().toLocaleTimeString()}`);
        } catch (error) {
          console.error('❌ Heartbeat failed:', error.message);
        }
      }, 60000);

      console.log('\n✨ Worker is now online and contributing to the network!');
      console.log('Press Ctrl+C to stop\n');

      // Handle graceful shutdown
      process.on('SIGINT', () => this.stop());
      process.on('SIGTERM', () => this.stop());

    } catch (error) {
      console.error('❌ Failed to start worker:', error.message);
      process.exit(1);
    }
  }

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
        });
        console.log('✅ Worker stopped gracefully');
      } catch (error) {
        console.error('Warning: Failed to send offline status');
      }
    }
    
    process.exit(0);
  }
}

// CLI entry point
if (require.main === module) {
  const args = process.argv.slice(2);
  const apiKeyIndex = args.indexOf('--api-key');
  
  if (apiKeyIndex === -1 || !args[apiKeyIndex + 1]) {
    console.error('Usage: distributex-worker --api-key YOUR_API_KEY');
    console.error('\nGet your API key from: https://distributex.io/dashboard');
    process.exit(1);
  }

  const apiKey = args[apiKeyIndex + 1];
  const worker = new DistributeXWorker({ apiKey });
  worker.start();
}

module.exports = DistributeXWorker;
