#!/usr/bin/env node
/**
 * DistributeX Immortal Worker Agent
 * 
 * PRODUCTION-READY: Never stops, auto-recovers, persistent tracking
 * - Self-healing heartbeat system
 * - Automatic reconnection
 * - Crash recovery
 * - Resource monitoring
 * - Session persistence
 */

const os = require('os');
const https = require('https');
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');
const path = require('path');

const execAsync = promisify(exec);

// Configuration
const CONFIG = {
  API_BASE_URL: process.env.DISTRIBUTEX_API_URL || 'https://distributex-cloud-network.pages.dev',
  HEARTBEAT_INTERVAL: 60 * 1000, // 1 minute (production: more frequent)
  REGISTRATION_RETRY_DELAY: 10 * 1000, // 10 seconds
  MAX_REGISTRATION_RETRIES: 999999, // Infinite retries
  HEARTBEAT_RETRY_DELAY: 5 * 1000, // 5 seconds
  MAX_CONSECUTIVE_FAILURES: 3,
  METRICS_UPDATE_INTERVAL: 5 * 60 * 1000, // 5 minutes
  CACHE_DIR: '/config',
  IS_DOCKER: process.env.DOCKER_CONTAINER === 'true' || fs.existsSync('/.dockerenv'),
  DOCKER_PERSISTENCE_CHECK_INTERVAL: 60 * 1000 // Check every minute
};

class ImmortalWorker {
  constructor(config) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || CONFIG.API_BASE_URL;
    this.workerId = null;
    this.deviceFingerprint = null;
    this.isRunning = false;
    this.isShuttingDown = false;
    
    // Timers
    this.heartbeatTimer = null;
    this.metricsTimer = null;
    this.persistenceCheckTimer = null;
    
    // Metrics
    this.metrics = {
      startTime: Date.now(),
      lastHeartbeat: null,
      successfulHeartbeats: 0,
      failedHeartbeats: 0,
      consecutiveFailures: 0,
      totalUptime: 0,
      registrationAttempts: 0,
      lastError: null
    };
    
    // Self-healing
    this.setupProcessHandlers();
    this.setupSelfHealing();
  }

  /**
   * Setup process handlers for graceful shutdown
   */
  setupProcessHandlers() {
    const shutdown = async (signal) => {
      if (this.isShuttingDown) return;
      
      console.log(`\n🛑 Received ${signal}, shutting down gracefully...`);
      this.isShuttingDown = true;
      
      await this.stop();
      process.exit(0);
    };

    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
    
    // Handle uncaught errors - DO NOT EXIT
    process.on('uncaughtException', (error) => {
      console.error('❌ Uncaught exception:', error);
      this.metrics.lastError = error.message;
      
      // Try to recover
      setTimeout(() => {
        console.log('🔄 Attempting recovery after uncaught exception...');
        this.attemptRecovery();
      }, 5000);
    });
    
    process.on('unhandledRejection', (reason, promise) => {
      console.error('❌ Unhandled rejection:', reason);
      this.metrics.lastError = String(reason);
      
      // Try to recover
      setTimeout(() => {
        console.log('🔄 Attempting recovery after unhandled rejection...');
        this.attemptRecovery();
      }, 5000);
    });
  }

  /**
   * Setup self-healing mechanisms
   */
  setupSelfHealing() {
    // Check if worker is still responding every minute
    setInterval(() => {
      if (!this.isRunning) {
        console.warn('⚠️  Worker not running, attempting restart...');
        this.attemptRecovery();
      }
    }, CONFIG.DOCKER_PERSISTENCE_CHECK_INTERVAL);
    
    // Memory leak prevention - log memory usage
    setInterval(() => {
      const used = process.memoryUsage();
      const heapPercent = (used.heapUsed / used.heapTotal * 100).toFixed(2);
      
      if (heapPercent > 90) {
        console.warn(`⚠️  High memory usage: ${heapPercent}%`);
      }
      
      console.log(`💾 Memory: Heap ${heapPercent}% (${Math.round(used.heapUsed / 1024 / 1024)}MB / ${Math.round(used.heapTotal / 1024 / 1024)}MB)`);
    }, 5 * 60 * 1000); // Every 5 minutes
  }

  /**
   * Attempt to recover from errors
   */
  async attemptRecovery() {
    if (this.isShuttingDown) return;
    
    try {
      // Stop existing timers
      this.clearAllTimers();
      
      // Wait a bit
      await new Promise(resolve => setTimeout(resolve, 5000));
      
      // Re-register
      console.log('🔄 Re-registering worker...');
      await this.register();
      
      // Restart heartbeat
      this.startHeartbeat();
      
      console.log('✅ Recovery successful');
    } catch (error) {
      console.error('❌ Recovery failed:', error.message);
      
      // Try again later
      setTimeout(() => this.attemptRecovery(), CONFIG.REGISTRATION_RETRY_DELAY);
    }
  }

  /**
   * Clear all timers
   */
  clearAllTimers() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    
    if (this.metricsTimer) {
      clearInterval(this.metricsTimer);
      this.metricsTimer = null;
    }
    
    if (this.persistenceCheckTimer) {
      clearInterval(this.persistenceCheckTimer);
      this.persistenceCheckTimer = null;
    }
  }

  /**
   * Generate device fingerprint (MAC address)
   */
  async generateDeviceFingerprint() {
    try {
      const networkInterfaces = os.networkInterfaces();
      
      for (const [name, interfaces] of Object.entries(networkInterfaces)) {
        for (const iface of interfaces) {
          if (!iface.internal && iface.mac && iface.mac !== '00:00:00:00:00:00') {
            // Normalize: lowercase, remove colons
            const mac = iface.mac.toLowerCase().replace(/[:-]/g, '');
            
            if (/^[0-9a-f]{12}$/.test(mac)) {
              console.log(`📌 MAC Address: ${mac} (${name})`);
              return mac;
            }
          }
        }
      }
      
      throw new Error('No valid MAC address found');
    } catch (error) {
      console.error('❌ MAC address detection failed:', error.message);
      throw error;
    }
  }

  /**
   * Detect GPU information
   */
  async detectGPU() {
    const gpuInfo = {
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
        gpuInfo.available = true;
        gpuInfo.count = lines.length;
        
        const [name, memory, driver] = lines[0].split(',').map(s => s.trim());
        gpuInfo.model = name;
        gpuInfo.memory = parseInt(memory) || 0;
        gpuInfo.driverVersion = driver;
      }

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
      // No GPU
    }

    return gpuInfo;
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
      // Use defaults
    }

    return storageInfo;
  }

  /**
   * Detect system capabilities
   */
  async detectSystemCapabilities() {
    const cpus = os.cpus();
    const totalRam = Math.floor(os.totalmem() / (1024 * 1024));
    const freeRam = Math.floor(os.freemem() / (1024 * 1024));
    
    const gpuInfo = await this.detectGPU();
    const storageInfo = await this.detectStorage();
    
    // Generate MAC address
    this.deviceFingerprint = await this.generateDeviceFingerprint();

    const cpuSharePercent = CONFIG.IS_DOCKER ? 90 : (cpus.length >= 8 ? 50 : cpus.length >= 4 ? 40 : 30);
    const ramSharePercent = CONFIG.IS_DOCKER ? 85 : (totalRam >= 16384 ? 30 : totalRam >= 8192 ? 25 : 20);
    const gpuSharePercent = gpuInfo.available ? (CONFIG.IS_DOCKER ? 95 : 50) : 0;
    const storageSharePercent = CONFIG.IS_DOCKER ? 85 : (storageInfo.total >= 200 ? 20 : storageInfo.total >= 100 ? 15 : 10);

    return {
      name: os.hostname() + ' Worker',
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
      gpuCount: gpuInfo.count,
      gpuDriverVersion: gpuInfo.driverVersion,
      gpuCudaVersion: gpuInfo.cudaVersion,
      storageTotal: storageInfo.total * 1024, // Convert to MB for database
      storageAvailable: storageInfo.available * 1024,
      cpuSharePercent,
      ramSharePercent,
      gpuSharePercent,
      storageSharePercent,
      isDocker: CONFIG.IS_DOCKER,
      macAddress: this.deviceFingerprint
    };
  }

  /**
   * Make HTTP request with retries
   */
  async makeRequest(method, path, data = null, retries = 3) {
    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        return await this._makeRequestOnce(method, path, data);
      } catch (error) {
        if (attempt === retries) {
          throw error;
        }
        
        const delay = CONFIG.HEARTBEAT_RETRY_DELAY * attempt;
        console.log(`⏳ Retrying in ${delay}ms... (${attempt}/${retries})`);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  /**
   * Single HTTP request
   */
  async _makeRequestOnce(method, path, data = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      
      const options = {
        method,
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
          'User-Agent': 'DistributeX-Immortal-Worker/3.0'
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
      
      if (data) {
        req.write(JSON.stringify(data));
      }
      
      req.end();
    });
  }

  /**
   * Register worker with UNLIMITED retries
   */
  async register() {
    let attempt = 0;
    
    while (true) {
      if (this.isShuttingDown) {
        throw new Error('Worker is shutting down');
      }
      
      attempt++;
      this.metrics.registrationAttempts = attempt;
      
      try {
        console.log(`\n🔍 Detecting system capabilities... (Attempt ${attempt})`);
        const capabilities = await this.detectSystemCapabilities();
        
        console.log('\n📊 System Information:');
        console.log(`  Environment: ${CONFIG.IS_DOCKER ? 'Docker Container 🐳' : 'Native 💻'}`);
        console.log(`  MAC Address: ${capabilities.macAddress}`);
        console.log(`  CPU: ${capabilities.cpuCores} cores (${capabilities.cpuModel})`);
        console.log(`  RAM: ${Math.floor(capabilities.ramTotal / 1024)} GB`);
        console.log(`  GPU: ${capabilities.gpuAvailable ? `${capabilities.gpuCount}x ${capabilities.gpuModel}` : 'None'}`);
        console.log(`  Storage: ${Math.floor(capabilities.storageTotal / 1024)} GB`);
        
        console.log('\n🚀 Registering worker...');
        
        const worker = await this.makeRequest('POST', '/api/workers/register', capabilities);
        this.workerId = worker.workerId;
        
        console.log(`\n✅ Worker ${worker.isNew ? 'registered' : 'reconnected'}!`);
        console.log(`  Worker ID: ${this.workerId}`);
        console.log(`  Status: ${worker.status}`);
        
        return worker;
        
      } catch (error) {
        console.error(`\n❌ Registration failed (Attempt ${attempt}):`, error.message);
        
        this.metrics.lastError = error.message;
        
        // Wait before retry
        const delay = Math.min(CONFIG.REGISTRATION_RETRY_DELAY * Math.min(attempt, 5), 60000);
        console.log(`⏳ Retrying in ${delay / 1000} seconds...`);
        
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  /**
   * Send heartbeat
   */
  async sendHeartbeat() {
    if (this.isShuttingDown) return;
    
    try {
      const freeRam = Math.floor(os.freemem() / (1024 * 1024));
      const storageInfo = await this.detectStorage();

      await this.makeRequest(
        'POST', 
        `/api/workers/${this.workerId}/heartbeat`,
        {
          macAddress: this.deviceFingerprint,
          ramAvailable: freeRam,
          storageAvailable: storageInfo.available * 1024,
          status: 'online',
        },
        1 // Only 1 retry for heartbeat
      );

      this.metrics.lastHeartbeat = new Date();
      this.metrics.successfulHeartbeats++;
      this.metrics.consecutiveFailures = 0;
      this.metrics.totalUptime = Date.now() - this.metrics.startTime;
      
      // Only log every 5th heartbeat to reduce noise
      if (this.metrics.successfulHeartbeats % 5 === 0) {
        console.log(`💓 Heartbeat #${this.metrics.successfulHeartbeats} at ${this.metrics.lastHeartbeat.toLocaleTimeString()}`);
      }
      
    } catch (error) {
      this.metrics.failedHeartbeats++;
      this.metrics.consecutiveFailures++;
      this.metrics.lastError = error.message;
      
      console.error(`❌ Heartbeat failed (${this.metrics.consecutiveFailures}/${CONFIG.MAX_CONSECUTIVE_FAILURES}):`, error.message);
      
      // If too many consecutive failures, try re-registering
      if (this.metrics.consecutiveFailures >= CONFIG.MAX_CONSECUTIVE_FAILURES) {
        console.warn('⚠️  Too many heartbeat failures, attempting re-registration...');
        this.attemptRecovery();
      }
    }
  }

  /**
   * Start heartbeat loop
   */
  startHeartbeat() {
    // Clear existing timer
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
    }
    
    // Send first heartbeat immediately
    this.sendHeartbeat();
    
    // Then send periodically
    this.heartbeatTimer = setInterval(
      () => this.sendHeartbeat(),
      CONFIG.HEARTBEAT_INTERVAL
    );
    
    console.log(`\n💓 Heartbeat started (every ${CONFIG.HEARTBEAT_INTERVAL / 1000}s)`);
  }

  /**
   * Start metrics reporting
   */
  startMetricsReporting() {
    this.metricsTimer = setInterval(() => {
      const uptime = Date.now() - this.metrics.startTime;
      const uptimeHours = (uptime / 1000 / 60 / 60).toFixed(2);
      const successRate = this.metrics.successfulHeartbeats + this.metrics.failedHeartbeats > 0
        ? (this.metrics.successfulHeartbeats / (this.metrics.successfulHeartbeats + this.metrics.failedHeartbeats) * 100).toFixed(2)
        : 0;
      
      console.log('\n📊 Worker Metrics:');
      console.log(`  Uptime: ${uptimeHours} hours`);
      console.log(`  Successful heartbeats: ${this.metrics.successfulHeartbeats}`);
      console.log(`  Failed heartbeats: ${this.metrics.failedHeartbeats}`);
      console.log(`  Success rate: ${successRate}%`);
      console.log(`  Last heartbeat: ${this.metrics.lastHeartbeat?.toLocaleString() || 'Never'}`);
      console.log(`  Worker ID: ${this.workerId}`);
      console.log(`  MAC Address: ${this.deviceFingerprint}`);
      if (this.metrics.lastError) {
        console.log(`  Last error: ${this.metrics.lastError}`);
      }
      console.log('');
    }, CONFIG.METRICS_UPDATE_INTERVAL);
  }

  /**
   * Start worker (NEVER STOPS)
   */
  async start() {
    try {
      console.log('\n╔═══════════════════════════════════════════════════════════╗');
      console.log('  ║         DistributeX Immortal Worker v3.0                ║');
      console.log('  ║         PRODUCTION MODE: Never Stops Running            ║');
      console.log('  ╚═══════════════════════════════════════════════════════════╝\n');
      
      if (!this.apiKey) {
        throw new Error('API key required. Use --api-key YOUR_KEY');
      }

      // Register (with unlimited retries)
      await this.register();
      
      this.isRunning = true;
      
      // Start heartbeat
      this.startHeartbeat();
      
      // Start metrics reporting
      this.startMetricsReporting();
      
      console.log('\n✨ Worker is ONLINE and will run FOREVER');
      console.log('📡 Contributing resources to the network');
      console.log('🔒 Press Ctrl+C to stop gracefully\n');

    } catch (error) {
      console.error('\n❌ Failed to start worker:', error.message);
      
      // Try recovery instead of exiting
      console.log('🔄 Attempting recovery...');
      setTimeout(() => this.attemptRecovery(), 5000);
    }
  }

  /**
   * Stop worker gracefully
   */
  async stop() {
    console.log('\n🛑 Stopping worker gracefully...');
    this.isRunning = false;
    
    // Clear all timers
    this.clearAllTimers();

    // Send final heartbeat with offline status
    if (this.workerId) {
      try {
        await this.makeRequest(
          'POST',
          `/api/workers/${this.workerId}/heartbeat`,
          {
            macAddress: this.deviceFingerprint,
            status: 'offline'
          },
          1
        );
        
        console.log('✅ Worker disconnected gracefully');
        console.log(`📊 Total heartbeats: ${this.metrics.successfulHeartbeats}`);
        console.log(`⏱️  Total uptime: ${((Date.now() - this.metrics.startTime) / 1000 / 60 / 60).toFixed(2)} hours`);
      } catch (error) {
        console.warn('⚠️  Failed to send final heartbeat:', error.message);
      }
    }
  }
}

// ==========================================
// CLI ENTRY POINT
// ==========================================

if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    console.log(`
╔═══════════════════════════════════════════════════════════╗
║         DistributeX Immortal Worker v3.0                 ║
║         Production-Grade: Never Stops Running            ║
╚═══════════════════════════════════════════════════════════╝

FEATURES:
  ✅ Self-healing: Auto-recovers from crashes
  ✅ Persistent: Runs forever until manually stopped
  ✅ Intelligent: Tracks resources accurately
  ✅ Monitored: Real-time metrics and health checks
  ✅ Docker-optimized: Perfect for containerized environments

USAGE:
  node worker-agent.js --api-key YOUR_API_KEY [--url API_URL]

OPTIONS:
  --api-key    Your DistributeX API key (REQUIRED)
  --url        API base URL (default: production URL)
  --help       Show this help message

EXAMPLE:
  node worker-agent.js --api-key abc123xyz456

DOCKER:
  docker run -d \\
    --name distributex-worker \\
    --restart always \\
    -e DISTRIBUTEX_API_KEY=YOUR_KEY \\
    distributexcloud/worker:latest

GET YOUR API KEY:
  https://distributex-cloud-network.pages.dev/auth
`);
    process.exit(0);
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

  const worker = new ImmortalWorker(config);
  worker.start();
}

module.exports = ImmortalWorker;
