#!/usr/bin/env node
/**
 * DistributeX Worker Agent - DEBUG VERSION
 * Enhanced logging to diagnose task polling issues
 */

const os = require('os');
const https = require('https');
const { exec, spawn } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');
const path = require('path');

const execAsync = promisify(exec);

// Configuration
const CONFIG = {
  API_BASE_URL: process.env.DISTRIBUTEX_API_URL || 'https://distributex-cloud-network.pages.dev',
  HEARTBEAT_INTERVAL: 60 * 1000,
  TASK_POLL_INTERVAL: 10 * 1000,
  IS_DOCKER: process.env.DOCKER_CONTAINER === 'true' || fs.existsSync('/.dockerenv'),
  DISABLE_SELF_REGISTER: process.env.DISABLE_SELF_REGISTER === 'true',
  HOST_MAC_ADDRESS: process.env.HOST_MAC_ADDRESS,
  WORK_DIR: '/tmp/distributex-tasks',
  DEBUG: true // ENABLE DEBUG LOGGING
};

function debugLog(message, data = null) {
  if (CONFIG.DEBUG) {
    const timestamp = new Date().toISOString();
    console.log(`[DEBUG ${timestamp}] ${message}`);
    if (data) {
      console.log(JSON.stringify(data, null, 2));
    }
  }
}

class WorkerAgent {
  constructor(config) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || CONFIG.API_BASE_URL;
    this.workerId = null;
    this.macAddress = null;
    this.hostname = os.hostname();
    this.isRunning = true;
    this.isShuttingDown = false;
    this.heartbeatTimer = null;
    this.taskPollTimer = null;
    this.isExecutingTask = false;
    this.currentTaskId = null;
    this.pollAttempts = 0;
    
    this.metrics = {
      startTime: Date.now(),
      successfulHeartbeats: 0,
      failedHeartbeats: 0,
      pollAttempts: 0,
      tasksReceived: 0,
      tasksExecuted: 0,
      tasksFailed: 0
    };
    
    if (!fs.existsSync(CONFIG.WORK_DIR)) {
      fs.mkdirSync(CONFIG.WORK_DIR, { recursive: true });
    }
    
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
      
      if (this.heartbeatTimer) clearTimeout(this.heartbeatTimer);
      if (this.taskPollTimer) clearTimeout(this.taskPollTimer);
      
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
  }

  async getMacAddress() {
    if (CONFIG.HOST_MAC_ADDRESS) {
      const mac = CONFIG.HOST_MAC_ADDRESS.toLowerCase().replace(/[:-]/g, '');
      if (/^[0-9a-f]{12}$/.test(mac)) {
        debugLog('MAC from ENV', { mac });
        return mac;
      }
    }

    if (CONFIG.IS_DOCKER) {
      try {
        const configPath = '/config/mac_address';
        if (fs.existsSync(configPath)) {
          const mac = fs.readFileSync(configPath, 'utf8').trim().toLowerCase().replace(/[:-]/g, '');
          if (/^[0-9a-f]{12}$/.test(mac)) {
            debugLog('MAC from config file', { mac });
            return mac;
          }
        }
      } catch (e) {
        debugLog('Could not read MAC from config', { error: e.message });
      }
    }

    const interfaces = os.networkInterfaces();
    for (const [name, ifaces] of Object.entries(interfaces)) {
      if (!ifaces) continue;
      for (const iface of ifaces) {
        if (iface.internal || !iface.mac || iface.mac === '00:00:00:00:00:00') {
          continue;
        }
        const mac = iface.mac.toLowerCase().replace(/[:-]/g, '');
        if (/^[0-9a-f]{12}$/.test(mac)) {
          debugLog('MAC detected from interface', { interface: name, mac });
          return mac;
        }
      }
    }
    
    throw new Error('No valid MAC address found');
  }

  async makeRequest(method, path, data = null) {
    debugLog(`Making ${method} request to ${path}`, { hasData: !!data });
    
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      
      const headers = {
        'Content-Type': 'application/json',
        'User-Agent': 'DistributeX-Worker/5.0-debug'
      };
      
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
          debugLog(`Response ${res.statusCode} from ${path}`, { 
            statusCode: res.statusCode,
            bodyLength: body.length 
          });
          
          try {
            const json = body ? JSON.parse(body) : {};
            
            if (res.statusCode >= 200 && res.statusCode < 300) {
              resolve(json);
            } else {
              debugLog('Request failed', { statusCode: res.statusCode, response: json });
              reject(new Error(`HTTP ${res.statusCode}: ${json.message || json.error || body}`));
            }
          } catch (e) {
            debugLog('Parse error', { body, error: e.message });
            reject(new Error(`Parse error: ${body}`));
          }
        });
      });

      req.on('error', (err) => {
        debugLog('Request error', { error: err.message });
        reject(err);
      });
      
      req.on('timeout', () => {
        req.destroy();
        debugLog('Request timeout', { path });
        reject(new Error('Request timeout'));
      });
      
      if (data) req.write(JSON.stringify(data));
      req.end();
    });
  }

  async detectGPU() {
    try {
      const { stdout } = await execAsync(
        'nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader',
        { timeout: 5000 }
      );
      
      const lines = stdout.trim().split('\n');
      if (lines.length > 0 && lines[0]) {
        const [name, memory, driver] = lines[0].split(',').map(s => s.trim());
        debugLog('GPU detected', { name, memory, driver, count: lines.length });
        return {
          available: true,
          model: name,
          memory: parseInt(memory) || 0,
          count: lines.length,
          driverVersion: driver,
          cudaVersion: null
        };
      }
    } catch (e) {
      debugLog('No GPU detected', { error: e.message });
    }

    return {
      available: false,
      model: null,
      memory: 0,
      count: 0,
      driverVersion: null,
      cudaVersion: null
    };
  }

  async detectSystem() {
    const cpus = os.cpus();
    const totalRam = Math.floor(os.totalmem() / (1024 * 1024));
    const freeRam = Math.floor(os.freemem() / (1024 * 1024));
    const gpu = await this.detectGPU();
    this.macAddress = await this.getMacAddress();

    const capabilities = {
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
      storageTotal: 100 * 1024,
      storageAvailable: 50 * 1024,
      cpuSharePercent: 90,
      ramSharePercent: 80,
      gpuSharePercent: 70,
      storageSharePercent: 50,
      isDocker: CONFIG.IS_DOCKER,
      macAddress: this.macAddress
    };

    debugLog('System capabilities detected', capabilities);
    return capabilities;
  }

  async loadWorkerIdFromConfig() {
    try {
      const configPath = '/config/worker_id';
      if (fs.existsSync(configPath)) {
        const workerId = fs.readFileSync(configPath, 'utf8').trim();
        if (workerId) {
          debugLog('Loaded worker ID from config', { workerId });
          return workerId;
        }
      }
    } catch (e) {
      debugLog('Could not load worker ID', { error: e.message });
    }
    return null;
  }

  async register() {
    this.macAddress = await this.getMacAddress();
    
    if (CONFIG.DISABLE_SELF_REGISTER) {
      console.log('ℹ️  Self-registration disabled, loading from config...');
      this.workerId = await this.loadWorkerIdFromConfig();
      
      if (this.workerId) {
        console.log(`✅ Using worker: ${this.workerId}`);
        debugLog('Worker loaded', { workerId: this.workerId, macAddress: this.macAddress });
        return { workerId: this.workerId, isNew: false };
      }
      
      console.error('\n❌ Worker ID not found in config');
      await new Promise(resolve => setTimeout(resolve, 30000));
      return await this.register();
    }
    
    console.log('\n🔍 Detecting system...');
    const capabilities = await this.detectSystem();
    
    console.log('\n🚀 Registering...');
    const worker = await this.makeRequest('POST', '/api/workers/register', capabilities);
    this.workerId = worker.workerId;
    
    console.log(`\n✅ ${worker.isNew ? 'Registered' : 'Reconnected'}!`);
    console.log(`  Worker ID: ${this.workerId}`);
    
    return worker;
  }

  async sendHeartbeat(status = 'online') {
    if (!this.isRunning && status !== 'offline') return;
    
    const actualStatus = this.isExecutingTask ? 'busy' : status;
    
    debugLog('Sending heartbeat', { 
      workerId: this.workerId,
      status: actualStatus,
      isExecutingTask: this.isExecutingTask 
    });
    
    try {
      const freeRam = Math.floor(os.freemem() / (1024 * 1024));
      
      await this.makeRequest('POST', '/api/workers/heartbeat', {
        macAddress: this.macAddress,
        ramAvailable: freeRam,
        storageAvailable: 50 * 1024,
        status: actualStatus
      });

      this.metrics.successfulHeartbeats++;
      
      if (this.metrics.successfulHeartbeats % 5 === 0) {
        console.log(`💓 Heartbeat #${this.metrics.successfulHeartbeats} | Status: ${actualStatus}`);
      }
      
    } catch (error) {
      this.metrics.failedHeartbeats++;
      console.error(`❌ Heartbeat failed:`, error.message);
    }
  }

  async pollForTasks() {
    if (!this.isRunning || this.isExecutingTask) {
      debugLog('Skipping poll', { 
        isRunning: this.isRunning, 
        isExecutingTask: this.isExecutingTask 
      });
      return;
    }

    this.metrics.pollAttempts++;
    this.pollAttempts++;

    console.log(`\n🔍 [Poll #${this.pollAttempts}] Checking for tasks...`);
    debugLog('Polling for tasks', { 
      workerId: this.workerId,
      pollAttempt: this.pollAttempts,
      endpoint: `/api/workers/${this.workerId}/tasks/next`
    });

    try {
      const response = await this.makeRequest('GET', `/api/workers/${this.workerId}/tasks/next`);
      
      debugLog('Poll response received', { 
        hasTask: !!response.task,
        response 
      });
      
      if (response && response.task) {
        this.metrics.tasksReceived++;
        console.log(`\n📥 ✅ TASK RECEIVED! (Total: ${this.metrics.tasksReceived})`);
        console.log(`   Task ID: ${response.task.id}`);
        console.log(`   Name: ${response.task.name}`);
        console.log(`   Type: ${response.task.taskType}`);
        
        debugLog('Task details', response.task);
        
        await this.executeTask(response.task);
      } else {
        console.log(`   ℹ️  No tasks available (this is normal)`);
      }
      
    } catch (error) {
      if (!error.message.includes('No tasks') && 
          !error.message.includes('Worker not found') &&
          !error.message.includes('404')) {
        console.error(`⚠️  Task poll error:`, error.message);
        debugLog('Poll error', { error: error.message, stack: error.stack });
      } else {
        debugLog('No tasks available (expected)', { error: error.message });
      }
    }
  }

  async executeTask(task) {
    this.isExecutingTask = true;
    this.currentTaskId = task.id;
    const startTime = Date.now();
    
    console.log(`\n⚙️  🚀 EXECUTING TASK ${task.id}...`);
    debugLog('Task execution started', { taskId: task.id, task });
    
    try {
      // Simulate execution for debugging
      console.log('   ⏱️  Simulating 5-second execution...');
      await new Promise(resolve => setTimeout(resolve, 5000));
      
      const executionTime = Math.floor((Date.now() - startTime) / 1000);
      
      console.log('   📤 Reporting success to API...');
      debugLog('Reporting completion', { taskId: task.id, executionTime });
      
      await this.makeRequest('PUT', `/api/tasks/${task.id}/complete`, {
        workerId: this.workerId,
        result: { output: 'Test execution successful', executionTime },
        executionTime: executionTime
      });
      
      this.metrics.tasksExecuted++;
      console.log(`✅ ✨ TASK COMPLETED! (${executionTime}s)`);
      console.log(`   Total executed: ${this.metrics.tasksExecuted} | Failed: ${this.metrics.tasksFailed}`);
      
    } catch (error) {
      console.error(`❌ Task ${task.id} failed:`, error.message);
      debugLog('Task execution error', { error: error.message, stack: error.stack });
      
      try {
        await this.makeRequest('PUT', `/api/tasks/${task.id}/fail`, {
          workerId: this.workerId,
          errorMessage: error.message
        });
      } catch (reportError) {
        console.error(`⚠️  Could not report failure:`, reportError.message);
      }
      
      this.metrics.tasksFailed++;
      
    } finally {
      this.isExecutingTask = false;
      this.currentTaskId = null;
      debugLog('Task execution finished', { taskId: task.id });
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

  scheduleTaskPolling() {
    if (this.isRunning && !this.isShuttingDown) {
      this.taskPollTimer = setTimeout(async () => {
        await this.pollForTasks();
        this.scheduleTaskPolling();
      }, CONFIG.TASK_POLL_INTERVAL);
    }
  }

  async runForever() {
    console.log('\n╔═══════════════════════════════════════════════════════════╗');
    console.log('║      DistributeX Worker v5.0 - DEBUG MODE                ║');
    console.log('║      Enhanced logging for task polling diagnostics       ║');
    console.log('╚═══════════════════════════════════════════════════════════╝\n');
    
    if (!this.apiKey) {
      console.error('❌ API key required');
      process.exit(1);
    }

    await this.register();
    
    console.log('\n✨ Worker ONLINE and actively polling');
    console.log('💓 Heartbeat: Every 60 seconds');
    console.log('🔍 Task polling: Every 10 seconds');
    console.log('🐛 Debug logging: ENABLED');
    console.log('🔒 Press Ctrl+C to stop gracefully\n');
    
    debugLog('Worker started', {
      workerId: this.workerId,
      macAddress: this.macAddress,
      hostname: this.hostname,
      apiUrl: this.baseUrl
    });

    this.scheduleHeartbeat();
    this.scheduleTaskPolling();
    
    // Print statistics every minute
    setInterval(() => {
      console.log('\n📊 Statistics:');
      console.log(`   Uptime: ${Math.floor((Date.now() - this.metrics.startTime) / 60000)} minutes`);
      console.log(`   Poll attempts: ${this.metrics.pollAttempts}`);
      console.log(`   Tasks received: ${this.metrics.tasksReceived}`);
      console.log(`   Tasks executed: ${this.metrics.tasksExecuted}`);
      console.log(`   Tasks failed: ${this.metrics.tasksFailed}`);
      console.log(`   Heartbeats: ${this.metrics.successfulHeartbeats} OK / ${this.metrics.failedHeartbeats} failed`);
    }, 60000);
    
    await new Promise(() => {});
  }

  async start() {
    try {
      await this.runForever();
    } catch (error) {
      console.error('\n❌ Fatal error:', error.message);
      debugLog('Fatal error', { error: error.message, stack: error.stack });
      process.exit(1);
    }
  }
}

// CLI
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args.includes('--help')) {
    console.log(`
╔═══════════════════════════════════════════════════════════╗
║      DistributeX Worker v5.0 - DEBUG MODE                ║
╚═══════════════════════════════════════════════════════════╝

USAGE:
  node worker-agent.js --api-key YOUR_KEY [--url API_URL]

DEBUG FEATURES:
  ✅ Detailed logging of all API calls
  ✅ Poll attempt tracking
  ✅ Task receipt confirmation
  ✅ Per-minute statistics
  ✅ Full error stack traces

OPTIONS:
  --api-key KEY    Your DistributeX API key (required)
  --url URL        API base URL (default: production)
  --help           Show this help
`);
    process.exit(0);
  }
  
  const apiKeyIndex = args.indexOf('--api-key');
  const urlIndex = args.indexOf('--url');
  
  if (apiKeyIndex === -1 || !args[apiKeyIndex + 1]) {
    console.error('❌ --api-key required\n');
    process.exit(1);
  }

  const config = {
    apiKey: args[apiKeyIndex + 1],
    baseUrl: urlIndex !== -1 && args[urlIndex + 1] ? args[urlIndex + 1] : undefined
  };

  const worker = new WorkerAgent(config);
  worker.start();
}

module.exports = WorkerAgent;
