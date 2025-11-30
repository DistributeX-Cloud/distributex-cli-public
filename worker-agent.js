#!/usr/bin/env node
/**
 * DistributeX Worker Agent - REAL EXECUTION VERSION
 * 
 * FIXED: Actually executes tasks instead of mocking
 * - Downloads code from storage
 * - Runs Python/Node.js/Docker tasks
 * - Returns real results
 */

const os = require('os');
const https = require('https');
const http = require('http');
const { exec, spawn } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const zlib = require('zlib');
const { pipeline } = require('stream');
const { promisify: pipelineAsync } = require('util');

const execAsync = promisify(exec);
const pipelinePromise = promisify(pipeline);

// Configuration
const CONFIG = {
  API_BASE_URL: process.env.DISTRIBUTEX_API_URL || 'https://distributex-cloud-network.pages.dev',
  HEARTBEAT_INTERVAL: 60 * 1000, // 1 minute
  TASK_POLL_INTERVAL: 10 * 1000, // 10 seconds
  MAX_CONSECUTIVE_FAILURES: 5,
  IS_DOCKER: process.env.DOCKER_CONTAINER === 'true' || fs.existsSync('/.dockerenv'),
  DISABLE_SELF_REGISTER: process.env.DISABLE_SELF_REGISTER === 'true',
  HOST_MAC_ADDRESS: process.env.HOST_MAC_ADDRESS,
  WORK_DIR: '/tmp/distributex-tasks'
};

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
    
    this.metrics = {
      startTime: Date.now(),
      successfulHeartbeats: 0,
      failedHeartbeats: 0,
      consecutiveFailures: 0,
      tasksExecuted: 0,
      tasksFailed: 0
    };
    
    // Create work directory
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
    
    process.on('uncaughtException', (error) => {
      console.error('❌ Uncaught exception:', error.message);
    });
    
    process.on('unhandledRejection', (reason) => {
      console.error('❌ Unhandled rejection:', reason);
    });
  }

  async getMacAddress() {
    try {
      if (CONFIG.HOST_MAC_ADDRESS) {
        const mac = CONFIG.HOST_MAC_ADDRESS.toLowerCase().replace(/[:-]/g, '');
        if (/^[0-9a-f]{12}$/.test(mac)) {
          console.log(`📌 MAC from ENV: ${mac}`);
          return mac;
        }
      }

      if (CONFIG.IS_DOCKER) {
        try {
          const configPath = '/config/mac_address';
          if (fs.existsSync(configPath)) {
            const mac = fs.readFileSync(configPath, 'utf8').trim().toLowerCase().replace(/[:-]/g, '');
            if (/^[0-9a-f]{12}$/.test(mac)) {
              console.log(`📌 MAC from config: ${mac}`);
              return mac;
            }
          }
        } catch (e) {
          console.warn('⚠️  Could not read MAC from config file');
        }
      }

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
        'User-Agent': 'DistributeX-Worker/5.0'
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

  async downloadFile(url, destPath) {
    return new Promise((resolve, reject) => {
      const urlObj = new URL(url);
      const protocol = urlObj.protocol === 'https:' ? https : http;
      
      const file = fs.createWriteStream(destPath);
      
      protocol.get(url, (response) => {
        if (response.statusCode !== 200) {
          reject(new Error(`Download failed: ${response.statusCode}`));
          return;
        }
        
        response.pipe(file);
        
        file.on('finish', () => {
          file.close();
          resolve();
        });
      }).on('error', (err) => {
        fs.unlink(destPath, () => {});
        reject(err);
      });
    });
  }

  async extractTarGz(tarPath, destDir) {
    return new Promise((resolve, reject) => {
      const gunzip = zlib.createGunzip();
      const extract = require('tar').extract({ cwd: destDir });
      
      const source = fs.createReadStream(tarPath);
      
      source
        .pipe(gunzip)
        .pipe(extract)
        .on('finish', resolve)
        .on('error', reject);
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
      this.workerId = await this.loadWorkerIdFromConfig();
      
      if (this.workerId) {
        console.log(`✅ Using worker: ${this.workerId}`);
        return { workerId: this.workerId, isNew: false };
      }
      
      console.error('\n❌ Worker ID not found');
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
      const freeRam = Math.floor(os.freemem() / (1024 * 1024));
      const storage = await this.detectStorage();

      const heartbeatData = {
        macAddress: this.macAddress,
        ramAvailable: freeRam,
        storageAvailable: storage.available * 1024,
        status: this.isExecutingTask ? 'busy' : status
      };

      await this.makeRequest('POST', '/api/workers/heartbeat', heartbeatData);

      this.metrics.successfulHeartbeats++;
      this.metrics.consecutiveFailures = 0;
      
      if (this.metrics.successfulHeartbeats % 5 === 0) {
        console.log(`💓 Heartbeat #${this.metrics.successfulHeartbeats} | Status: ${heartbeatData.status}`);
      }
      
    } catch (error) {
      this.metrics.failedHeartbeats++;
      this.metrics.consecutiveFailures++;
      console.error(`❌ Heartbeat failed:`, error.message);
    }
  }

  // ==================== REAL TASK EXECUTION ====================

  async pollForTasks() {
    if (!this.isRunning || this.isExecutingTask) return;

    try {
      const response = await this.makeRequest('GET', `/api/workers/${this.workerId}/tasks/next`);
      
      if (response && response.task) {
        console.log(`\n📥 Received task: ${response.task.id}`);
        console.log(`   Name: ${response.task.name}`);
        console.log(`   Type: ${response.task.taskType}`);
        await this.executeTask(response.task);
      }
      
    } catch (error) {
      if (!error.message.includes('No tasks') && 
          !error.message.includes('Worker not found') &&
          !error.message.includes('404')) {
        console.error(`⚠️  Task poll error:`, error.message);
      }
    }
  }

  async executeTask(task) {
    this.isExecutingTask = true;
    this.currentTaskId = task.id;
    const startTime = Date.now();
    
    console.log(`\n⚙️  Executing task ${task.id}...`);
    
    try {
      let result;
      
      if (task.executionConfig?.codeUrl) {
        // Has code to download and execute
        result = await this.executeCodeTask(task);
      } else if (task.taskType === 'docker_execution') {
        result = await this.executeDockerTask(task);
      } else if (task.taskType === 'script_execution') {
        result = await this.executeScriptTask(task);
      } else {
        throw new Error(`Unsupported task type: ${task.taskType}`);
      }
      
      const executionTime = Math.floor((Date.now() - startTime) / 1000);
      
      // Report success
      await this.makeRequest('PUT', `/api/tasks/${task.id}/complete`, {
        workerId: this.workerId,
        result: result,
        executionTime: executionTime
      });
      
      this.metrics.tasksExecuted++;
      console.log(`✅ Task ${task.id} completed in ${executionTime}s`);
      console.log(`   Total executed: ${this.metrics.tasksExecuted} | Failed: ${this.metrics.tasksFailed}`);
      
    } catch (error) {
      console.error(`❌ Task ${task.id} failed:`, error.message);
      
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
    }
  }

  async executeCodeTask(task) {
    const taskDir = path.join(CONFIG.WORK_DIR, task.id);
    fs.mkdirSync(taskDir, { recursive: true });
    
    try {
      console.log('📥 Downloading code...');
      
      // Parse execution config
      let config = task.executionConfig;
      if (typeof config === 'string') {
        config = JSON.parse(config);
      }
      
      // Download code tarball
      const tarPath = path.join(taskDir, 'code.tar.gz');
      await this.downloadFile(config.codeUrl, tarPath);
      
      console.log('📦 Extracting code...');
      await this.extractTarGz(tarPath, taskDir);
      
      // Determine runtime
      const runtime = config.runtime || task.runtime || 'python';
      
      console.log(`🚀 Executing with ${runtime}...`);
      
      let output;
      if (runtime === 'python') {
        output = await this.runPython(taskDir);
      } else if (runtime === 'node' || runtime === 'javascript') {
        output = await this.runNode(taskDir);
      } else {
        throw new Error(`Unsupported runtime: ${runtime}`);
      }
      
      return {
        status: 'completed',
        output: output,
        result: output
      };
      
    } finally {
      // Cleanup
      try {
        fs.rmSync(taskDir, { recursive: true, force: true });
      } catch (e) {
        console.warn('⚠️  Could not cleanup task directory');
      }
    }
  }

  async runPython(taskDir) {
    return new Promise((resolve, reject) => {
      // Try to find Python script
      const files = fs.readdirSync(taskDir);
      let scriptFile = files.find(f => f.endsWith('.py'));
      
      if (!scriptFile) {
        // Check for runner.py (from SDK)
        scriptFile = 'runner.py';
        if (!fs.existsSync(path.join(taskDir, scriptFile))) {
          reject(new Error('No Python script found'));
          return;
        }
      }
      
      const child = spawn('python3', [scriptFile], {
        cwd: taskDir,
        stdio: ['ignore', 'pipe', 'pipe']
      });
      
      let stdout = '';
      let stderr = '';
      
      child.stdout.on('data', (data) => {
        stdout += data.toString();
        process.stdout.write(data);
      });
      
      child.stderr.on('data', (data) => {
        stderr += data.toString();
        process.stderr.write(data);
      });
      
      child.on('close', (code) => {
        if (code === 0) {
          // Check for result.pkl
          const resultPath = path.join(taskDir, 'result.pkl');
          if (fs.existsSync(resultPath)) {
            resolve(`Result saved to result.pkl\n${stdout}`);
          } else {
            resolve(stdout);
          }
        } else {
          reject(new Error(`Python script failed with code ${code}: ${stderr}`));
        }
      });
      
      child.on('error', reject);
    });
  }

  async runNode(taskDir) {
    return new Promise((resolve, reject) => {
      const files = fs.readdirSync(taskDir);
      let scriptFile = files.find(f => f.endsWith('.js'));
      
      if (!scriptFile) {
        scriptFile = 'run.js';
        if (!fs.existsSync(path.join(taskDir, scriptFile))) {
          reject(new Error('No Node.js script found'));
          return;
        }
      }
      
      const child = spawn('node', [scriptFile], {
        cwd: taskDir,
        stdio: ['ignore', 'pipe', 'pipe']
      });
      
      let stdout = '';
      let stderr = '';
      
      child.stdout.on('data', (data) => {
        stdout += data.toString();
        process.stdout.write(data);
      });
      
      child.stderr.on('data', (data) => {
        stderr += data.toString();
        process.stderr.write(data);
      });
      
      child.on('close', (code) => {
        if (code === 0) {
          resolve(stdout);
        } else {
          reject(new Error(`Node.js script failed with code ${code}: ${stderr}`));
        }
      });
      
      child.on('error', reject);
    });
  }

  async executeDockerTask(task) {
    console.log('🐳 Executing Docker task...');
    
    let config = task.executionConfig;
    if (typeof config === 'string') {
      config = JSON.parse(config);
    }
    
    const image = config.dockerImage;
    const command = config.dockerCommand || 'echo "Hello from Docker"';
    
    return new Promise((resolve, reject) => {
      const child = spawn('docker', [
        'run',
        '--rm',
        image,
        'sh', '-c', command
      ], {
        stdio: ['ignore', 'pipe', 'pipe']
      });
      
      let stdout = '';
      let stderr = '';
      
      child.stdout.on('data', (data) => {
        stdout += data.toString();
        process.stdout.write(data);
      });
      
      child.stderr.on('data', (data) => {
        stderr += data.toString();
        process.stderr.write(data);
      });
      
      child.on('close', (code) => {
        if (code === 0) {
          resolve({
            status: 'completed',
            output: stdout,
            exitCode: 0
          });
        } else {
          reject(new Error(`Docker failed with code ${code}: ${stderr}`));
        }
      });
      
      child.on('error', reject);
    });
  }

  async executeScriptTask(task) {
    console.log('📜 Executing script task...');
    
    let config = task.executionConfig;
    if (typeof config === 'string') {
      config = JSON.parse(config);
    }
    
    const script = config.executionScript || config.command || 'echo "No script provided"';
    
    return new Promise((resolve, reject) => {
      exec(script, (error, stdout, stderr) => {
        if (error) {
          reject(new Error(`Script failed: ${stderr}`));
        } else {
          resolve({
            status: 'completed',
            output: stdout,
            exitCode: 0
          });
        }
      });
    });
  }

  // ==================== SCHEDULING ====================

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
    console.log('║      DistributeX Worker v5.0 - REAL EXECUTION            ║');
    console.log('╚═══════════════════════════════════════════════════════════╝\n');
    
    if (!this.apiKey) {
      console.error('❌ API key required');
      process.exit(1);
    }

    await this.register();
    
    console.log('\n✨ Worker ONLINE and ready for REAL task execution');
    console.log('💓 Heartbeat: Every 60 seconds');
    console.log('🔍 Task polling: Every 10 seconds');
    console.log('🚀 Will execute: Python, Node.js, Docker tasks');
    console.log('🔒 Press Ctrl+C to stop gracefully\n');

    this.scheduleHeartbeat();
    this.scheduleTaskPolling();
    
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

// ==================== CLI ====================

if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args.includes('--help')) {
    console.log(`
╔═══════════════════════════════════════════════════════════╗
║      DistributeX Worker v5.0 - REAL EXECUTION            ║
╚═══════════════════════════════════════════════════════════╝

USAGE:
  node worker-agent.js --api-key YOUR_KEY [--url API_URL]

CHANGES IN v5.0:
  ✅ REAL code execution (no more mocks!)
  ✅ Downloads and runs actual Python/Node.js code
  ✅ Supports Docker container execution
  ✅ Returns real results to API

OPTIONS:
  --api-key KEY    Your DistributeX API key (required)
  --url URL        API base URL (default: production)
  --help           Show this help

Get your API key at: https://distributex-cloud-network.pages.dev/auth
`);
    process.exit(0);
  }
  
  const apiKeyIndex = args.indexOf('--api-key');
  const urlIndex = args.indexOf('--url');
  
  if (apiKeyIndex === -1 || !args[apiKeyIndex + 1]) {
    console.error('❌ --api-key required\n');
    console.error('Usage: node worker-agent.js --api-key YOUR_KEY');
    console.error('Run with --help for more information');
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
