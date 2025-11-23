#!/usr/bin/env node
// packages/worker-node/distributex-worker.js
// FIXED: Proper authentication and connection handling

const WebSocket = require('ws');
const Docker = require('dockerode');
const os = require('os');
const fs = require('fs').promises;
const path = require('path');

const CONFIG_PATH = path.join(os.homedir(), '.distributex', 'config.json');
const LOGS_PATH = path.join(os.homedir(), '.distributex', 'logs');

class WorkerNode {
  constructor(config) {
    this.config = config;
    this.docker = new Docker();
    this.ws = null;
    this.activeJobs = new Map();
    this.isShuttingDown = false;
    this.heartbeatInterval = null;
    this.reconnectTimeout = null;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 10;
  }

  async start() {
    console.log('🚀 Starting DistributeX Worker...\n');
    
    try {
      await fs.mkdir(LOGS_PATH, { recursive: true });
      await this.testDocker();
      await this.connect();
      await this.sendCapabilities();
      this.startHeartbeat();
      this.setupSignalHandlers();
      
      console.log('✅ Worker started successfully\n');
      console.log(`Worker ID: ${this.config.workerId}`);
      console.log(`API URL: ${this.config.apiUrl}`);
      console.log(`Auth Token: ${this.config.authToken?.substring(0, 20)}...`);
      console.log(`Status: Online and ready to accept jobs\n`);
      
      this.log('Worker started successfully');
    } catch (error) {
      console.error('❌ Failed to start worker:', error.message);
      this.log('ERROR', error.message);
      process.exit(1);
    }
  }

  async testDocker() {
    console.log('🐳 Testing Docker connection...');
    try {
      await this.docker.ping();
      const info = await this.docker.info();
      console.log(`✓ Docker connected (${info.Containers} containers)\n`);
    } catch (error) {
      throw new Error('Docker not available. Please ensure Docker is installed and running.');
    }
  }

  async connect() {
    return new Promise((resolve, reject) => {
      console.log('🔌 Connecting to coordinator...');
      
      // FIX: Build proper WebSocket URL
      let wsUrl = this.config.coordinatorUrl;
      
      // If coordinatorUrl not set, derive from apiUrl
      if (!wsUrl) {
        wsUrl = this.config.apiUrl
          .replace('https://distributex-api', 'wss://distributex-coordinator')
          .replace('http://localhost:8787', 'ws://localhost:8788');
        wsUrl += '/ws';
      }
      
      console.log(`   URL: ${wsUrl}`);
      console.log(`   Worker ID: ${this.config.workerId}`);
      console.log(`   Auth Token: ${this.config.authToken?.substring(0, 20)}...`);
      
      // FIX: Proper authentication headers
      this.ws = new WebSocket(wsUrl, {
        headers: {
          'Authorization': `Bearer ${this.config.authToken}`,
          'X-Worker-ID': this.config.workerId,
          'Upgrade': 'websocket',
          'Connection': 'Upgrade'
        }
      });

      this.ws.on('open', () => {
        console.log('✓ Connected to coordinator\n');
        this.reconnectAttempts = 0;
        this.log('Connected to coordinator');
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
        console.log(`⚠️  Disconnected from coordinator (${code}: ${reason})`);
        this.log(`Disconnected: ${code} ${reason}`);
        if (!this.isShuttingDown) {
          this.scheduleReconnect();
        }
      });

      this.ws.on('error', (error) => {
        console.error('WebSocket error:', error.message);
        this.log('ERROR', error.message);
        
        // Don't reject immediately - let close handler trigger reconnect
        if (error.message.includes('401') || error.message.includes('Unauthorized')) {
          console.error('\n❌ Authentication failed!');
          console.error('Your auth token or worker ID may be invalid.');
          console.error('Please re-register your worker:\n');
          console.error('  curl -fsSL https://get.distributex.cloud | bash\n');
          reject(new Error('Authentication failed'));
        }
      });

      // Timeout after 30 seconds
      setTimeout(() => {
        if (this.ws && this.ws.readyState !== WebSocket.OPEN) {
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
    
    if (this.reconnectAttempts > this.maxReconnectAttempts) {
      console.error('❌ Max reconnection attempts reached. Exiting...');
      console.error('Please check your configuration and try again.\n');
      process.exit(1);
    }
    
    // Exponential backoff: 2s, 4s, 8s, 16s, 30s (max)
    const delay = Math.min(2000 * Math.pow(2, this.reconnectAttempts - 1), 30000);
    
    console.log(`⏳ Reconnecting in ${delay/1000}s... (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})\n`);
    
    this.reconnectTimeout = setTimeout(async () => {
      try {
        await this.connect();
        this.startHeartbeat();
      } catch (error) {
        console.error('Reconnection failed:', error.message);
        this.scheduleReconnect();
      }
    }, delay);
  }

  async sendCapabilities() {
    const cpus = os.cpus();
    const totalMem = os.totalmem() / (1024 ** 3);
    
    const capabilities = {
      cpuCores: this.config.maxCpuCores || cpus.length,
      memoryGb: this.config.maxMemoryGb || Math.round(totalMem * 0.7),
      storageGb: this.config.maxStorageGb || 50,
      gpuAvailable: this.config.enableGpu || false,
      nodeName: this.config.nodeName || os.hostname(),
      platform: os.platform(),
      arch: os.arch()
    };

    this.send({
      type: 'capabilities',
      capabilities
    });
    
    this.log('Sent capabilities', JSON.stringify(capabilities));
  }

  startHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }
    
    this.heartbeatInterval = setInterval(() => {
      // Pong responses handled in handleMessage
    }, 30000);
  }

  handleMessage(message) {
    switch (message.type) {
      case 'connected':
        console.log(`✓ Connection confirmed: ${message.workerId}\n`);
        break;
      
      case 'ping':
        this.send({ 
          type: 'pong', 
          timestamp: Date.now(), 
          healthScore: this.calculateHealthScore(),
          activeJobs: Array.from(this.activeJobs.keys())
        });
        break;
      
      case 'job_assigned':
        this.executeJob(message.job);
        break;
      
      case 'disconnect':
        console.log('⚠️  Coordinator requested disconnect:', message.reason);
        this.stop();
        break;
      
      default:
        console.log('Unknown message type:', message.type);
    }
  }

  calculateHealthScore() {
    const cpuLoad = os.loadavg()[0] / os.cpus().length;
    const memUsed = (os.totalmem() - os.freemem()) / os.totalmem();
    
    let score = 100;
    if (cpuLoad > 0.8) score -= 20;
    else if (cpuLoad > 0.6) score -= 10;
    if (memUsed > 0.9) score -= 20;
    else if (memUsed > 0.75) score -= 10;
    
    return Math.max(0, score);
  }

  async executeJob(job) {
    console.log('\n' + '='.repeat(60));
    console.log(`📦 New Job Assigned: ${job.jobId}`);
    console.log('='.repeat(60));
    console.log(`Type: ${job.jobType}`);
    console.log(`Image: ${job.containerImage}`);
    console.log('='.repeat(60) + '\n');
    
    this.activeJobs.set(job.jobId, job);
    this.log(`Starting job ${job.jobId}`);
    
    this.send({
      type: 'job_update',
      jobId: job.jobId,
      status: 'running',
      data: { startedAt: new Date().toISOString() }
    });

    const startTime = Date.now();
    let container = null;

    try {
      console.log(`📥 Pulling image: ${job.containerImage}...`);
      await this.pullImage(job.containerImage);
      console.log('✓ Image ready\n');
      
      console.log('🏗️  Creating container...');
      container = await this.docker.createContainer({
        Image: job.containerImage,
        Cmd: job.command || [],
        Env: Object.entries(job.environmentVars || {}).map(([k, v]) => `${k}=${v}`),
        HostConfig: {
          CpuQuota: (job.resources?.cpu || 1) * 100000,
          Memory: (job.resources?.memory || 2) * 1024 * 1024 * 1024,
          NetworkMode: this.config.allowNetwork ? 'bridge' : 'none',
          AutoRemove: false
        }
      });
      console.log('✓ Container created\n');

      console.log('▶️  Starting container...');
      await container.start();
      console.log('✓ Container started\n');
      
      console.log('📄 Container output:');
      console.log('-'.repeat(60));

      const logStream = await container.logs({
        follow: true,
        stdout: true,
        stderr: true
      });

      logStream.on('data', (chunk) => {
        const message = chunk.toString().replace(/[\x00-\x08]/g, '');
        process.stdout.write(message);
        
        this.send({
          type: 'log',
          jobId: job.jobId,
          log: {
            level: 'info',
            message,
            timestamp: new Date().toISOString()
          }
        });
      });

      await Promise.race([
        container.wait(),
        new Promise((_, reject) => 
          setTimeout(() => reject(new Error('Job timeout')), (job.timeoutSeconds || 3600) * 1000)
        )
      ]);

      console.log('-'.repeat(60) + '\n');

      const inspection = await container.inspect();
      const exitCode = inspection.State.ExitCode;
      await container.remove();

      const runtime = (Date.now() - startTime) / 1000;

      console.log(`✅ Job completed successfully`);
      console.log(`   Exit code: ${exitCode}`);
      console.log(`   Runtime: ${runtime.toFixed(2)}s\n`);

      this.send({
        type: 'job_update',
        jobId: job.jobId,
        status: 'completed',
        data: {
          exitCode,
          runtime,
          completedAt: new Date().toISOString()
        }
      });
      
      this.log(`Job ${job.jobId} completed (exit ${exitCode})`);
    } catch (error) {
      console.error(`\n❌ Job failed: ${error.message}\n`);
      
      if (container) {
        try {
          await container.remove({ force: true });
        } catch (e) {}
      }
      
      this.send({
        type: 'job_update',
        jobId: job.jobId,
        status: 'failed',
        data: {
          errorMessage: error.message,
          failedAt: new Date().toISOString()
        }
      });
      
      this.log('ERROR', `Job ${job.jobId} failed: ${error.message}`);
    } finally {
      this.activeJobs.delete(job.jobId);
    }
  }

  async pullImage(image) {
    try {
      await this.docker.getImage(image).inspect();
    } catch {
      await new Promise((resolve, reject) => {
        this.docker.pull(image, (err, stream) => {
          if (err) return reject(err);
          
          this.docker.modem.followProgress(stream, (err) => {
            if (err) return reject(err);
            resolve();
          }, (event) => {
            if (event.status) {
              process.stdout.write(`\r   ${event.status}...`);
            }
          });
        });
      });
      process.stdout.write('\n');
    }
  }

  send(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  async log(level, message) {
    const timestamp = new Date().toISOString();
    const logMessage = `[${timestamp}] ${typeof level === 'string' && level === 'ERROR' ? 'ERROR' : 'INFO'}: ${message || level}\n`;
    
    try {
      await fs.appendFile(path.join(LOGS_PATH, 'worker.log'), logMessage);
    } catch (e) {
      // Ignore log errors
    }
  }

  setupSignalHandlers() {
    const shutdown = async () => {
      if (this.isShuttingDown) return;
      this.isShuttingDown = true;
      
      console.log('\n⚠️  Shutting down gracefully...');
      
      if (this.heartbeatInterval) {
        clearInterval(this.heartbeatInterval);
      }
      
      if (this.reconnectTimeout) {
        clearTimeout(this.reconnectTimeout);
      }
      
      if (this.activeJobs.size > 0) {
        console.log(`⏳ Waiting for ${this.activeJobs.size} job(s) to complete...`);
        
        const timeout = setTimeout(() => {
          console.log('⚠️  Shutdown timeout, forcing exit');
          process.exit(0);
        }, 60000);
        
        while (this.activeJobs.size > 0) {
          await new Promise(resolve => setTimeout(resolve, 1000));
        }
        
        clearTimeout(timeout);
      }
      
      this.send({
        type: 'status',
        status: 'offline'
      });
      
      if (this.ws) {
        this.ws.close();
      }
      
      console.log('✅ Shutdown complete\n');
      process.exit(0);
    };
    
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  }

  async stop() {
    await this.setupSignalHandlers();
  }
}

// Main execution
(async () => {
  try {
    const configData = await fs.readFile(CONFIG_PATH, 'utf-8');
    const config = JSON.parse(configData);
    
    if (!config.authToken || !config.workerId) {
      console.error('❌ Invalid configuration. Please run the setup again.');
      process.exit(1);
    }
    
    const worker = new WorkerNode(config);
    await worker.start();
  } catch (error) {
    if (error.code === 'ENOENT') {
      console.error('❌ Configuration not found. Please run the setup:');
      console.error('   curl -fsSL https://get.distributex.cloud | bash');
    } else {
      console.error('❌ Failed to start worker:', error.message);
    }
    process.exit(1);
  }
})();
