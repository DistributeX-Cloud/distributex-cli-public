/**
 * DistributeX JavaScript/Node.js SDK - FIXED VERSION
 * Properly connects to distributed network
 */

const https = require('https');
const fs = require('fs').promises;
const path = require('path');

class DistributeX {
  constructor(apiKey, baseUrl = 'https://distributex-cloud-network.pages.dev') {
    this.apiKey = apiKey || process.env.DISTRIBUTEX_API_KEY;
    
    if (!this.apiKey) {
      throw new Error('API key required. Set DISTRIBUTEX_API_KEY or pass to constructor');
    }
    
    this.baseUrl = baseUrl;
    this.pollInterval = 5000;
    
    // Verify connection
    this._verifyConnection();
  }

  async _verifyConnection() {
    try {
      const user = await this.request('GET', '/api/auth/user');
      console.log(`✅ Connected as: ${user.email || 'Unknown'}`);
      
      if (user.role !== 'developer') {
        console.warn(`⚠️  Warning: Your role is '${user.role}', should be 'developer'`);
      }
    } catch (error) {
      if (error.message.includes('401')) {
        throw new Error('Invalid API key. Generate a new one at: https://distributex-cloud-network.pages.dev/api-dashboard');
      }
      throw new Error(`Connection failed: ${error.message}`);
    }
  }

  /**
   * Run JavaScript function on distributed network
   */
  async run(func, options = {}) {
    const {
      args = [],
      workers = 1,
      cpuPerWorker = 2,
      ramPerWorker = 2048,
      gpu = false,
      timeout = 3600,
      wait = true
    } = options;

    console.log('📦 Packaging function...');
    
    // Create execution script
    const script = this._createFunctionScript(func, args);
    
    // Write to temp file
    const tmpFile = `/tmp/distributex_${Date.now()}.js`;
    await fs.writeFile(tmpFile, script);
    
    try {
      const result = await this.runScript(tmpFile, {
        runtime: 'node',
        workers,
        cpuPerWorker,
        ramPerWorker,
        gpu,
        timeout,
        wait
      });
      
      return result;
    } finally {
      await fs.unlink(tmpFile).catch(() => {});
    }
  }

  _createFunctionScript(func, args) {
    return `
const fs = require('fs');

// User function
const userFunc = ${func.toString()};

// Arguments
const args = ${JSON.stringify(args)};

// Execute
try {
  const result = userFunc(...args);
  
  fs.writeFileSync('result.json', JSON.stringify({
    success: true,
    result: result
  }));
  
  console.log(JSON.stringify(result));
  process.exit(0);
  
} catch (error) {
  fs.writeFileSync('result.json', JSON.stringify({
    success: false,
    error: error.message
  }));
  
  console.error('ERROR:', error.message);
  process.exit(1);
}
`;
  }

  /**
   * Run any script file
   */
  async runScript(scriptPath, options = {}) {
    const {
      command = null,
      runtime = 'auto',
      workers = 1,
      cpuPerWorker = 2,
      ramPerWorker = 2048,
      gpu = false,
      cuda = false,
      inputFiles = [],
      outputFiles = [],
      env = {},
      timeout = 3600,
      wait = true
    } = options;

    // Auto-detect runtime
    let detectedRuntime = runtime;
    if (runtime === 'auto') {
      const ext = path.extname(scriptPath).toLowerCase();
      const runtimeMap = {
        '.py': 'python',
        '.js': 'node',
        '.ts': 'node',
        '.rb': 'ruby',
        '.go': 'go',
        '.rs': 'rust',
        '.java': 'java',
        '.sh': 'bash'
      };
      detectedRuntime = runtimeMap[ext] || 'node';
    }

    console.log(`📤 Uploading script: ${scriptPath}`);
    
    // Read and encode script
    const scriptData = await fs.readFile(scriptPath);
    const scriptBase64 = scriptData.toString('base64');
    const crypto = require('crypto');
    const scriptHash = crypto.createHash('sha256').update(scriptData).digest('hex');

    console.log(`🚀 Submitting task to network...`);
    
    // Submit task with embedded script
    const taskData = {
      name: `Execute ${path.basename(scriptPath)}`,
      taskType: 'script_execution',
      runtime: detectedRuntime,
      command,
      workers,
      cpuPerWorker,
      ramPerWorker,
      gpuRequired: gpu,
      requiresCuda: cuda,
      timeout,
      priority: 5,
      executionScript: scriptBase64,
      scriptHash,
      inputFiles: [],
      outputPaths: outputFiles,
      environment: env
    };
    
    const response = await this.request('POST', '/api/tasks/execute', taskData);
    
    if (!response.success) {
      throw new Error(`Task submission failed: ${response.message || 'Unknown error'}`);
    }
    
    const taskId = response.id;
    console.log(`✅ Task submitted: ${taskId}`);
    console.log(`   Status: ${response.status || 'pending'}`);
    
    if (response.queuePosition) {
      console.log(`   Queue position: ${response.queuePosition}`);
    }
    if (response.assignedWorker) {
      console.log(`   Assigned to: ${response.assignedWorker.name}`);
    }
    
    const task = { id: taskId, status: response.status };
    
    if (!wait) return task;
    
    console.log('⏳ Waiting for execution...');
    return await this.waitForCompletion(taskId);
  }

  /**
   * Run Docker container
   */
  async runDocker(image, options = {}) {
    const {
      command = null,
      workers = 1,
      cpuPerWorker = 2,
      ramPerWorker = 2048,
      gpu = false,
      volumes = {},
      env = {},
      ports = {},
      timeout = 3600,
      wait = true
    } = options;

    console.log(`🐳 Submitting Docker task: ${image}`);
    
    const taskData = {
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
    };

    const response = await this.request('POST', '/api/tasks/execute', taskData);
    
    const taskId = response.id;
    console.log(`✅ Task submitted: ${taskId}`);
    
    const task = { id: taskId, status: response.status };
    
    if (!wait) return task;
    
    console.log('⏳ Executing Docker container...');
    return await this.waitForCompletion(taskId);
  }

  /**
   * Get task status
   */
  async getTask(taskId) {
    return await this.request('GET', `/api/tasks/${taskId}`);
  }

  /**
   * Get network statistics
   */
  async networkStats() {
    return await this.request('GET', '/api/stats/network');
  }

  /**
   * Wait for task completion
   */
  async waitForCompletion(taskId) {
    let lastProgress = -1;
    
    while (true) {
      const task = await this.getTask(taskId);

      if (task.progressPercent !== undefined && task.progressPercent > lastProgress) {
        process.stdout.write(`\r   Progress: ${task.progressPercent.toFixed(1)}%`);
        lastProgress = task.progressPercent;
      }

      if (task.status === 'completed') {
        console.log('\n✅ Execution complete!');
        return await this.downloadResult(taskId);
      }

      if (task.status === 'failed') {
        console.log(`\n❌ Task failed: ${task.errorMessage}`);
        throw new Error(task.errorMessage);
      }

      await new Promise(resolve => setTimeout(resolve, this.pollInterval));
    }
  }

  /**
   * Download task result
   */
  async downloadResult(taskId) {
    console.log('📥 Downloading result...');
    
    const response = await this.request('GET', `/api/tasks/${taskId}/result`);
    
    if (response && typeof response === 'object' && response.result !== undefined) {
      return response.result;
    }
    
    return response;
  }

  /**
   * Make HTTP request
   */
  async request(method, endpoint, data = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(endpoint, this.baseUrl);
      
      const options = {
        method,
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
          'User-Agent': 'DistributeX-JS-SDK/1.0.1'
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
}

module.exports = DistributeX;
