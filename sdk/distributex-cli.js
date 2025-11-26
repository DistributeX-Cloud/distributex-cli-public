#!/usr/bin/env node
/**
 * DistributeX Developer SDK - FIXED VERSION
 * 
 * Allows developers to run ANY script/code on the distributed network
 * Supports: Python, Node.js, Ruby, Go, Rust, C++, Java, and more
 */

const fs = require('fs').promises;
const path = require('path');
const { exec, spawn } = require('child_process');
const { promisify } = require('util');
const https = require('https');
const crypto = require('crypto');
const tar = require('tar');

const execAsync = promisify(exec);

class DistributeXClient {
  constructor(apiKey, baseUrl = 'https://distributex-cloud-network.pages.dev') {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
    this.pollInterval = 5000; // 5 seconds
  }

  /**
   * Make API request with proper auth
   */
  async request(method, endpoint, data = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(endpoint, this.baseUrl);
      const options = {
        method,
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
          'User-Agent': 'DistributeX-SDK/1.0'
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
   * Upload file/directory to storage
   */
  async uploadCode(filePath) {
    console.log('📦 Packaging code...');
    
    const stats = await fs.stat(filePath);
    const isDirectory = stats.isDirectory();
    
    // Create tarball
    const tarballPath = `/tmp/distributex-${Date.now()}.tar.gz`;
    
    if (isDirectory) {
      await tar.create(
        {
          gzip: true,
          file: tarballPath,
          cwd: path.dirname(filePath)
        },
        [path.basename(filePath)]
      );
    } else {
      await tar.create(
        {
          gzip: true,
          file: tarballPath,
          cwd: path.dirname(filePath)
        },
        [path.basename(filePath)]
      );
    }
    
    // Read as base64
    const tarballData = await fs.readFile(tarballPath);
    const base64Data = tarballData.toString('base64');
    
    // Calculate hash
    const hash = crypto.createHash('sha256').update(tarballData).digest('hex');
    
    console.log(`✓ Packaged ${(tarballData.length / 1024 / 1024).toFixed(2)} MB`);
    
    // Upload to API
    const uploadResult = await this.request('POST', '/api/storage/upload', {
      filename: path.basename(filePath),
      data: base64Data,
      hash: hash,
      size: tarballData.length
    });
    
    // Clean up
    await fs.unlink(tarballPath);
    
    return uploadResult;
  }

  /**
   * Submit script execution task
   */
  async runScript(options) {
    const {
      script,
      command,
      runtime = 'auto',
      workers = 1,
      cpuPerWorker = 2,
      ramPerWorker = 2048,
      gpu = false,
      cuda = false,
      inputFiles = [],
      outputFiles = [],
      env = {},
      timeout = 3600
    } = options;

    console.log('🚀 Submitting task...');

    // Detect runtime
    let detectedRuntime = runtime;
    if (runtime === 'auto' && script) {
      const ext = path.extname(script).toLowerCase();
      const runtimeMap = {
        '.py': 'python',
        '.js': 'node',
        '.ts': 'node',
        '.rb': 'ruby',
        '.go': 'go',
        '.rs': 'rust',
        '.java': 'java',
        '.cpp': 'cpp',
        '.c': 'c',
        '.sh': 'bash'
      };
      detectedRuntime = runtimeMap[ext] || 'bash';
    }

    console.log(`✓ Runtime: ${detectedRuntime}`);

    // Upload script
    let codeUrl = null;
    if (script) {
      const uploadResult = await this.uploadCode(script);
      codeUrl = uploadResult.url;
      console.log(`✓ Code uploaded: ${uploadResult.id}`);
    }

    // Upload input files
    const inputUrls = [];
    for (const inputFile of inputFiles) {
      console.log(`📤 Uploading input: ${inputFile}`);
      const uploadResult = await this.uploadCode(inputFile);
      inputUrls.push({
        path: inputFile,
        url: uploadResult.url,
        id: uploadResult.id
      });
    }

    // Submit task using /api/tasks/execute endpoint
    const taskResult = await this.request('POST', '/api/tasks/execute', {
      name: `Execute ${path.basename(script || command)}`,
      taskType: 'script_execution',
      runtime: detectedRuntime,
      codeUrl,
      command: command || null,
      workers,
      cpuPerWorker,
      ramPerWorker,
      gpuRequired: gpu,
      requiresCuda: cuda,
      inputFiles: inputUrls,
      outputPaths: outputFiles,
      environment: env,
      timeout
    });

    console.log(`✅ Task submitted: ${taskResult.id}`);
    console.log(`   Workers available: ${taskResult.availableWorkers}`);
    console.log(`   Est. wait time: ${taskResult.estimatedWaitTime}s`);

    return taskResult;
  }

  /**
   * Run Docker container
   */
  async runDocker(options) {
    const {
      image,
      command,
      workers = 1,
      cpuPerWorker = 2,
      ramPerWorker = 2048,
      gpu = false,
      volumes = {},
      env = {},
      ports = {},
      timeout = 3600
    } = options;

    console.log('🐳 Submitting Docker task...');
    console.log(`   Image: ${image}`);

    const taskResult = await this.request('POST', '/api/tasks/execute', {
      name: `Docker: ${image}`,
      taskType: 'docker_execution',
      dockerImage: image,
      dockerCommand: command,
      workers,
      cpuPerWorker,
      ramPerWorker,
      gpuRequired: gpu,
      volumes,
      environment: env,
      ports,
      timeout
    });

    console.log(`✅ Docker task submitted: ${taskResult.id}`);
    return taskResult;
  }

  /**
   * Monitor task progress
   */
  async waitForTask(taskId, onProgress = null) {
    console.log(`⏳ Waiting for task ${taskId}...`);
    
    while (true) {
      const status = await this.request('GET', `/api/tasks/${taskId}`);
      
      if (onProgress) {
        onProgress(status);
      }

      // Show progress
      if (status.status === 'active' && status.progressPercent !== undefined) {
        process.stdout.write(`\r   Progress: ${status.progressPercent.toFixed(1)}% `);
      }

      // Check if complete
      if (status.status === 'completed') {
        console.log('\n✅ Task completed!');
        return status;
      }

      if (status.status === 'failed') {
        console.log('\n❌ Task failed:', status.errorMessage);
        throw new Error(status.errorMessage);
      }

      // Wait before polling
      await new Promise(resolve => setTimeout(resolve, this.pollInterval));
    }
  }

  /**
   * Download results
   */
  async downloadResults(taskId, outputDir = './results') {
    console.log('📥 Downloading results...');
    
    const status = await this.request('GET', `/api/tasks/${taskId}`);
    
    if (!status.resultUrl) {
      throw new Error('No results available');
    }

    await fs.mkdir(outputDir, { recursive: true });

    return new Promise((resolve, reject) => {
      const url = new URL(status.resultUrl);
      const filePath = path.join(outputDir, `results-${taskId}.tar.gz`);
      const file = require('fs').createWriteStream(filePath);

      https.get(url, (response) => {
        response.pipe(file);
        file.on('finish', async () => {
          file.close();
          
          console.log('📂 Extracting results...');
          await tar.extract({
            file: filePath,
            cwd: outputDir
          });
          
          await fs.unlink(filePath);
          
          console.log(`✓ Results saved to ${outputDir}`);
          resolve(outputDir);
        });
      }).on('error', (err) => {
        fs.unlink(filePath);
        reject(err);
      });
    });
  }

  /**
   * Get network statistics
   */
  async getNetworkStats() {
    return await this.request('GET', '/api/stats/network');
  }
}

// CLI Implementation
async function main() {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args[0] === '--help') {
    showHelp();
    process.exit(0);
  }

  const apiKey = process.env.DISTRIBUTEX_API_KEY || 
    await getConfigValue('apiKey');
  
  if (!apiKey) {
    console.error('❌ API key required. Set DISTRIBUTEX_API_KEY or run: distributex login');
    process.exit(1);
  }

  const client = new DistributeXClient(apiKey);
  const command = args[0];

  try {
    switch (command) {
      case 'run':
        await handleRun(client, args.slice(1));
        break;
      
      case 'docker':
        await handleDocker(client, args.slice(1));
        break;
      
      case 'status':
        await handleStatus(client, args[1]);
        break;
      
      case 'results':
        await handleResults(client, args[1], args[2]);
        break;
      
      case 'network':
        await handleNetwork(client);
        break;
      
      case 'login':
        await handleLogin();
        break;
      
      default:
        console.error(`Unknown command: ${command}`);
        showHelp();
        process.exit(1);
    }
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

async function handleRun(client, args) {
  const scriptOrCommand = args[0];
  if (!scriptOrCommand) {
    console.error('Usage: distributex run <script|command> [options]');
    process.exit(1);
  }

  const options = {
    script: null,
    command: null,
    workers: 1,
    cpuPerWorker: 2,
    ramPerWorker: 2048,
    gpu: false,
    cuda: false,
    inputFiles: [],
    outputFiles: [],
    env: {},
    timeout: 3600
  };

  // Check if file or command
  try {
    await fs.access(scriptOrCommand);
    options.script = scriptOrCommand;
  } catch {
    options.command = scriptOrCommand;
  }

  // Parse flags
  for (let i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--workers':
        options.workers = parseInt(args[++i]);
        break;
      case '--cpu':
        options.cpuPerWorker = parseInt(args[++i]);
        break;
      case '--ram':
        options.ramPerWorker = parseInt(args[++i]);
        break;
      case '--gpu':
        options.gpu = true;
        break;
      case '--cuda':
        options.cuda = true;
        options.gpu = true;
        break;
      case '--input':
        options.inputFiles.push(args[++i]);
        break;
      case '--output':
        options.outputFiles.push(args[++i]);
        break;
      case '--env':
        const [key, val] = args[++i].split('=');
        options.env[key] = val;
        break;
      case '--timeout':
        options.timeout = parseInt(args[++i]);
        break;
    }
  }

  const task = await client.runScript(options);
  const result = await client.waitForTask(task.id);

  if (options.outputFiles.length > 0) {
    await client.downloadResults(task.id);
  }

  console.log('\n🎉 Execution complete!');
  console.log(`   Duration: ${result.executionTime}s`);
}

async function handleDocker(client, args) {
  if (args[0] !== 'run') {
    console.error('Usage: distributex docker run <image> [options]');
    process.exit(1);
  }

  const image = args[1];
  if (!image) {
    console.error('Docker image required');
    process.exit(1);
  }

  const options = {
    image,
    command: null,
    workers: 1,
    cpuPerWorker: 2,
    ramPerWorker: 2048,
    gpu: false,
    volumes: {},
    env: {},
    ports: {},
    timeout: 3600
  };

  for (let i = 2; i < args.length; i++) {
    switch (args[i]) {
      case '--command':
      case '-c':
        options.command = args[++i];
        break;
      case '--workers':
        options.workers = parseInt(args[++i]);
        break;
      case '--gpu':
        options.gpu = true;
        break;
      case '--volume':
      case '-v':
        const [host, container] = args[++i].split(':');
        options.volumes[host] = container;
        break;
      case '--env':
      case '-e':
        const [key, val] = args[++i].split('=');
        options.env[key] = val;
        break;
    }
  }

  const task = await client.runDocker(options);
  const result = await client.waitForTask(task.id);

  console.log('\n🎉 Docker execution complete!');
  console.log(`   Duration: ${result.executionTime}s`);
}

async function handleStatus(client, taskId) {
  if (!taskId) {
    console.error('Usage: distributex status <task-id>');
    process.exit(1);
  }

  const status = await client.request('GET', `/api/tasks/${taskId}`);
  
  console.log(`\n📊 Task Status: ${status.id}`);
  console.log(`   Status: ${status.status}`);
  console.log(`   Progress: ${status.progressPercent || 0}%`);
  console.log(`   Worker: ${status.workerId || 'Not assigned'}`);
  if (status.startedAt) {
    console.log(`   Started: ${new Date(status.startedAt).toLocaleString()}`);
  }
}

async function handleResults(client, taskId, outputDir) {
  if (!taskId) {
    console.error('Usage: distributex results <task-id> [output-dir]');
    process.exit(1);
  }

  await client.downloadResults(taskId, outputDir);
}

async function handleNetwork(client) {
  const stats = await client.getNetworkStats();
  
  console.log('\n🌍 Network Statistics');
  console.log(`   Total Workers: ${stats.totalWorkers || 0}`);
  console.log(`   Active Workers: ${stats.activeWorkers || 0}`);
  console.log(`   Total CPU Cores: ${stats.totalCpuCores || 0}`);
  console.log(`   Total RAM: ${Math.floor((stats.totalRam || 0) / 1024)} GB`);
  console.log(`   GPU Devices: ${stats.totalGpus || 0}`);
  console.log(`   Active Tasks: ${stats.activeTasks || 0}`);
}

async function handleLogin() {
  const readline = require('readline');
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const question = (query) => new Promise(resolve => rl.question(query, resolve));

  console.log('\n🔐 DistributeX Login');
  const email = await question('Email: ');
  const password = await question('Password: ');
  rl.close();

  const response = await new Promise((resolve, reject) => {
    const data = JSON.stringify({ email, password });
    const options = {
      hostname: 'distributex-cloud-network.pages.dev',
      path: '/api/auth/login',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length
      }
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => resolve(JSON.parse(body)));
    });

    req.on('error', reject);
    req.write(data);
    req.end();
  });

  if (response.token) {
    await saveConfig('apiKey', response.token);
    console.log('✅ Login successful!');
    console.log('   API key saved to ~/.distributex/config.json');
  } else {
    console.error('❌ Login failed:', response.message);
  }
}

function showHelp() {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║            DistributeX Developer CLI v1.0                 ║
║        Run ANY script on the distributed network          ║
╚═══════════════════════════════════════════════════════════╝

COMMANDS:

  distributex run <script>           Run a script
  distributex docker run <image>     Run Docker container
  distributex status <task-id>       Check task status
  distributex results <task-id>      Download results
  distributex network                Show network stats
  distributex login                  Login to account

EXAMPLES:

  # Run Python script with GPU
  distributex run train.py --gpu --workers 2

  # Run with custom resources
  distributex run process.js --cpu 8 --ram 16384

  # Docker execution
  distributex docker run python:3.9 --command "python train.py" --gpu

For more: https://distributex.io/docs
  `);
}

// Config helpers
async function getConfigValue(key) {
  try {
    const configPath = path.join(require('os').homedir(), '.distributex', 'config.json');
    const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
    return config[key];
  } catch {
    return null;
  }
}

async function saveConfig(key, value) {
  const configDir = path.join(require('os').homedir(), '.distributex');
  const configPath = path.join(configDir, 'config.json');
  
  await fs.mkdir(configDir, { recursive: true });
  
  let config = {};
  try {
    config = JSON.parse(await fs.readFile(configPath, 'utf8'));
  } catch {}
  
  config[key] = value;
  await fs.writeFile(configPath, JSON.stringify(config, null, 2));
}

module.exports = DistributeXClient;

if (require.main === module) {
  main().catch(console.error);
}
