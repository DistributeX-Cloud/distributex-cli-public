/**
 * DistributeX JavaScript/Node.js SDK
 */

const https = require('https');
const fs = require('fs').promises;
const path = require('path');
const tar = require('tar');
const crypto = require('crypto');

class DistributeX {
  constructor(apiKey, baseUrl = 'https://distributex-cloud-network.pages.dev') {
    this.apiKey = apiKey || process.env.DISTRIBUTEX_API_KEY;
    
    if (!this.apiKey) {
      throw new Error('API key required. Set DISTRIBUTEX_API_KEY or pass to constructor');
    }
    
    this.baseUrl = baseUrl;
    this.pollInterval = 5000;
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
    
    // Package function and arguments
    const codeUrl = await this.packageFunction(func, args);
    
    console.log(`🚀 Submitting to ${workers} worker(s)...`);
    
    const task = await this.submitTask({
      codeUrl,
      runtime: 'node',
      workers,
      cpuPerWorker,
      ramPerWorker,
      gpuRequired: gpu,
      timeout
    });
    
    if (!wait) return task;
    
    console.log('⏳ Waiting for execution...');
    return await this.waitForCompletion(task.id);
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
        '.cpp': 'cpp',
        '.c': 'c',
        '.sh': 'bash'
      };
      detectedRuntime = runtimeMap[ext] || 'bash';
    }

    console.log(`📦 Uploading ${scriptPath}...`);
    const codeUrl = await this.uploadFile(scriptPath);

    // Upload input files
    const inputUrls = [];
    for (const inputFile of inputFiles) {
      console.log(`📤 Uploading input: ${inputFile}`);
      const url = await this.uploadFile(inputFile);
      inputUrls.push({ path: inputFile, url });
    }

    console.log(`🚀 Submitting ${detectedRuntime} script...`);
    
    const task = await this.submitTask({
      codeUrl,
      runtime: detectedRuntime,
      command,
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

    console.log(`✅ Task submitted: ${task.id}`);

    if (!wait) return task;

    console.log('⏳ Executing...');
    return await this.waitForCompletion(task.id);
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

    const response = await this.request('POST', '/api/tasks/execute', {
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

    console.log(`✅ Task submitted: ${response.id}`);

    if (!wait) return response;

    console.log('⏳ Executing Docker container...');
    return await this.waitForCompletion(response.id);
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
   * Package function for execution
   */
  async packageFunction(func, args) {
    const tmpDir = await fs.mkdtemp('/tmp/distributex-');
    
    try {
      // Create function file
      const funcCode = `
const func = ${func.toString()};
const args = ${JSON.stringify(args)};

// Execute function
const result = func(...args);

// Save result
const fs = require('fs');
fs.writeFileSync('result.json', JSON.stringify(result));
`;
      
      await fs.writeFile(path.join(tmpDir, 'run.js'), funcCode);
      
      // Create tarball
      const tarballPath = path.join(tmpDir, 'code.tar.gz');
      await tar.create(
        {
          gzip: true,
          file: tarballPath,
          cwd: tmpDir
        },
        ['run.js']
      );
      
      // Upload
      const url = await this.uploadFile(tarballPath);
      
      // Cleanup
      await fs.rm(tmpDir, { recursive: true });
      
      return url;
    } catch (error) {
      await fs.rm(tmpDir, { recursive: true }).catch(() => {});
      throw error;
    }
  }

  /**
   * Upload file to storage
   */
  async uploadFile(filePath) {
    const data = await fs.readFile(filePath);
    const crypto = require('crypto');
    const base64Data = data.toString('base64');
    const hash = crypto.createHash('sha256').update(data).digest('hex');

    const response = await this.request('POST', '/api/storage/upload', {
      filename: path.basename(filePath),
      data: base64Data,
      hash,
      size: data.length
    });

    return response.url;
  }

  /**
   * Submit task to API
   */
  async submitTask(params) {
    return await this.request('POST', '/api/tasks/execute', params);
  }

  /**
   * Wait for task completion
   */
  async waitForCompletion(taskId) {
    while (true) {
      const task = await this.getTask(taskId);

      if (task.progressPercent !== undefined && task.progressPercent > 0) {
        process.stdout.write(`\r   Progress: ${task.progressPercent.toFixed(1)}%`);
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
// REPLACE downloadResult method (around line 176):
async downloadResult(taskId) {
  // Use NEW endpoint
  const response = await this.request('GET', `/api/tasks/${taskId}/result`);
  
  // Check if JSON result
  if (response && typeof response === 'object' && response.result) {
    return response.result;
  }
  
  // Otherwise it's a file - the API will redirect to storage
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
          'User-Agent': 'DistributeX-JS-SDK/1.0'
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

// Convenience functions
let defaultClient = null;

function init(apiKey, baseUrl) {
  defaultClient = new DistributeX(apiKey, baseUrl);
}

async function run(func, options) {
  if (!defaultClient) init();
  return await defaultClient.run(func, options);
}

async function runScript(scriptPath, options) {
  if (!defaultClient) init();
  return await defaultClient.runScript(scriptPath, options);
}

async function runDocker(image, options) {
  if (!defaultClient) init();
  return await defaultClient.runDocker(image, options);
}

module.exports = DistributeX;
module.exports.init = init;
module.exports.run = run;
module.exports.runScript = runScript;
module.exports.runDocker = runDocker;

// Example usage
if (require.main === module) {
  (async () => {
    const dx = new DistributeX(process.env.DISTRIBUTEX_API_KEY);

    // Example 1: Run JavaScript function
    const result1 = await dx.run(
      (n) => {
        let sum = 0;
        for (let i = 0; i < n; i++) {
          sum += i;
        }
        return sum;
      },
      { args: [1000000], cpuPerWorker: 4 }
    );
    console.log('Result:', result1);

    // Example 2: Run Node.js script
    const result2 = await dx.runScript('process.js', {
      workers: 2,
      ramPerWorker: 4096
    });
    console.log('Script result:', result2);

    // Example 3: Run Docker container
    const result3 = await dx.runDocker('python:3.9', {
      command: 'python -c "print(sum(range(1000000)))"',
      cpuPerWorker: 2
    });
    console.log('Docker result:', result3);

    // Example 4: Get network stats
    const stats = await dx.networkStats();
    console.log('Network stats:', stats);
  })();
}
