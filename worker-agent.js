#!/usr/bin/env node
/**
 * DistributeX Worker Agent v6.0 - FULL MULTI-LANGUAGE + DEBUG
 *
 * Features:
 *   • Debug logging & polling diagnostics
 *   • Auto-detect + install packages for 9 runtimes
 *   • Full task download → extract → execute → report
 *   • Graceful shutdown, metrics, GPU detection
 */

const os = require('os');
const https = require('https');
const { exec, spawn } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { pipeline } = require('stream');
const streamPipeline = promisify(pipeline);

const execAsync = promisify(exec);

// ============================================================================
// CONFIGURATION
// ============================================================================
const CONFIG = {
  API_BASE_URL: process.env.DISTRIBUTEX_API_URL || 'https://distributex-cloud-network.pages.dev',
  HEARTBEAT_INTERVAL: 60 * 1000,
  TASK_POLL_INTERVAL: 10 * 1000,
  IS_DOCKER: process.env.DOCKER_CONTAINER === 'true' || fs.existsSync('/.dockerenv'),
  DISABLE_SELF_REGISTER: process.env.DISABLE_SELF_REGISTER === 'true',
  HOST_MAC_ADDRESS: process.env.HOST_MAC_ADDRESS,
  WORK_DIR: '/tmp/distributex-tasks',
  DEBUG: true  // Set to false in production if desired
};

function debugLog(message, data = null) {
  if (CONFIG.DEBUG) {
    const timestamp = new Date().toISOString();
    console.log(`[DEBUG ${timestamp}] ${message}`);
    if (data) console.log(JSON.stringify(data, null, 2));
  }
}

// ============================================================================
// RUNTIME MANAGER (detect + install packages)
// ============================================================================
class RuntimeManager {
  constructor() { this.runtimes = {}; }

  async detectAllRuntimes() {
    console.log('Detecting available runtimes...');
    await Promise.all([
      this.detectPython(),
      this.detectNode(),
      this.detectJava(),
      this.detectGo(),
      this.detectRust(),
      this.detectRuby(),
      this.detectPHP(),
      this.detectDocker()
    ]);

    console.log('Runtime detection complete:');
    Object.entries(this.runtimes).forEach(([name, info]) => {
      console.log(` ${name.padEnd(8)} ${info.available ? 'Available' : 'Not Available'} ${info.version || ''}`);
    });
    return this.runtimes;
  }

  async detectPython() {
    for (const cmd of ['python3', 'python']) {
      try {
        const { stdout } = await execAsync(`${cmd} --version`, { timeout: 3000 });
        const version = stdout.trim().split(' ')[1];
        this.runtimes.python = { available: true, version, command: cmd };
        return;
      } catch { /* continue */ }
    }
    this.runtimes.python = { available: false };
  }

  async detectNode() {
    try {
      const { stdout } = await execAsync('node --version', { timeout: 3000 });
      const version = stdout.trim().replace('v', '');
      this.runtimes.node = { available: true, version, command: 'node' };
    } catch {
      this.runtimes.node = { available: false };
    }
  }

  async detectJava() {
    try {
      const { stdout } = await execAsync('java -version 2>&1', { timeout: 3000 });
      const m = stdout.match(/version "(.+?)"/);
      this.runtimes.java = { available: true, version: m ? m[1] : 'unknown', command: 'java' };
    } catch {
      this.runtimes.java = { available: false };
    }
  }

  async detectGo() {
    try {
      const { stdout } = await execAsync('go version', { timeout: 3000 });
      const m = stdout.match(/go(\d+\.\d+(\.\d+)?)/);
      this.runtimes.go = { available: true, version: m ? m[1] : 'unknown', command: 'go' };
    } catch {
      this.runtimes.go = { available: false };
    }
  }

  async detectRust() {
    try {
      const { stdout } = await execAsync('rustc --version', { timeout: 3000 });
      const version = stdout.split(' ')[1];
      this.runtimes.rust = { available: true, version, command: 'rustc' };
    } catch {
      this.runtimes.rust = { available: false };
    }
  }

  async detectRuby() {
    try {
      const { stdout } = await execAsync('ruby --version', { timeout: 3000 });
      const m = stdout.match(/ruby (\d+\.\d+\.\d+)/);
      this.runtimes.ruby = { available: true, version: m ? m[1] : 'unknown', command: 'ruby' };
    } catch {
      this.runtimes.ruby = { available: false };
    }
  }

  async detectPHP() {
    try {
      const { stdout } = await execAsync('php --version', { timeout: 3000 });
      const m = stdout.match(/PHP (\d+\.\d+\.\d+)/);
      this.runtimes.php = { available: true, version: m ? m[1] : 'unknown', command: 'php' };
    } catch {
      this.runtimes.php = { available: false };
    }
  }

  async detectDocker() {
    try {
      const { stdout } = await execAsync('docker --version', { timeout: 3000 });
      const m = stdout.match(/Docker version (\d+\.\d+\.\d+)/);
      this.runtimes.docker = { available:true, version: m ? m[1] : 'unknown', command: 'docker' };
    } catch {
      this.runtimes.docker = { available: false };
    }
  }

  async installPackages(runtime, packages) {
    if (!packages || packages.length === 0) return;
    console.log(`Installing ${runtime} packages: ${packages.join(', ')}`);

    const installers = {
      python: () => execAsync(`pip3 install --no-cache-dir ${packages.join(' ')}`, { timeout: 300000 }),
      node: () => execAsync(`npm install -g ${packages.join(' ')}`, { timeout: 300000 }),
      ruby: () => execAsync(`gem install ${packages.join(' ')}`, { timeout: 300000 }),
      go: async () => {
        for (const pkg of packages) await execAsync(`go get ${pkg}`, { timeout: 300000 });
      }
    };

    if (installers[runtime]) {
      await installers[runtime]();
      console.log(`${runtime} packages installed`);
    } else {
      console.log(`No installer for ${runtime} – skipping`);
    }
  }
}

// ============================================================================
// TASK EXECUTOR (multi-language support)
// ============================================================================
class TaskExecutor {
  constructor(runtimeManager) {
    this.rm = runtimeManager;
  }

  async execute(task, taskDir) {
    const cfg = typeof task.execution_config === 'string'
      ? JSON.parse(task.execution_config)
      : task.execution_config || {};

    const runtime = cfg.runtime || task.runtime || 'python';
    console.log(`Executing task with runtime: ${runtime}`);

    if (!this.rm.runtimes[runtime]?.available && runtime !== 'bash') {
      throw new Error(`Runtime "${runtime}" not available on this worker`);
    }

    // Install dependencies if requested
    if (cfg.dependencies?.length > 0) {
      await this.rm.installPackages(runtime, cfg.dependencies);
    }

    const executors = {
      python: () => this.execPython(taskDir, cfg),
      node: () => this.execNode(taskDir, cfg),
      java: () => this.execJava(taskDir, cfg),
      go: () => this.execGo(taskDir, cfg),
      rust: () => this.execRust(taskDir, cfg),
      ruby: () => this.execRuby(taskDir, cfg),
      php: () => this.execPHP(taskDir, cfg),
      docker: () => this.execDocker(cfg),
      bash: () => this.execBash(taskDir, cfg)
    };

    if (!executors[runtime]) throw new Error(`Unsupported runtime: ${runtime}`);

    return await executors[runtime]();
  }

  // ───── Individual executors ─────
  async execPython(taskDir, cfg) { return this.runScript(taskDir, cfg, '.py', this.rm.runtimes.python.command); }
  async execNode(taskDir, cfg)   { return this.runScript(taskDir, cfg, '.js', 'node'); }
  async execRuby(taskDir, cfg)   { return this.runScript(taskDir, cfg, '.rb', 'ruby'); }
  async execPHP(taskDir, cfg)    { return this.runScript(taskDir, cfg, '.php', 'php'); }

  async runScript(taskDir, cfg, ext, command) {
    return new Promise((resolve, reject) => {
      let script = fs.readdirSync(taskDir).find(f => f.endsWith(ext));
      if (!script && cfg.command) {
        script = `task${ext}`;
        fs.writeFileSync(path.join(taskDir, script), cfg.command.replace(new RegExp(`^${command}\\s+`), ''));
      }
      if (!script) return reject(new Error(`No ${ext} script found`));

      const child = spawn(command, [script], {
        cwd: taskDir,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, ...cfg.environment }
      });

      let out = '', err = '';
      child.stdout.on('data', d => { out += d; process.stdout.write(d); });
      child.stderr.on('data', d => { err += d; process.stderr.write(d); });
      child.on('close', code => code === 0 ? resolve(out) : reject(new Error(`${command} exited ${code}: ${err}`)));
      child.on('error', reject);
    });
  }

  async execJava(taskDir, cfg) {
    const javaFile = fs.readdirSync(taskDir).find(f => f.endsWith('.java'));
    if (!javaFile) throw new Error('No .java file');

    await execAsync(`javac ${javaFile}`, { cwd: taskDir });
    const className = javaFile.replace('.java', '');
    return new Promise((resolve, reject) => {
      const child = spawn('java', [className], { cwd: taskDir, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...cfg.environment } });
      let out = '', err = '';
      child.stdout.on('data', d => { out += d; process.stdout.write(d); });
      child.stderr.on('data', d => { err += d; process.stderr.write(d); });
      child.on('close', code => code === 0 ? resolve(out) : reject(new Error(`Java exited ${code}: ${err}`)));
    });
  }

  async execGo(taskDir, cfg) {
    return new Promise((resolve, reject) => {
      const child = spawn('go', ['run', '.'], { cwd: taskDir, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...cfg.environment } });
      let out = '', err = '';
      child.stdout.on('data', d => { out += d; process.stdout.write(d); });
      child.stderr.on('data', d => { err += d; process.stderr.write(d); });
      child.on('close', code => code === 0 ? resolve(out) : reject(new Error(`Go exited ${code}: ${err}`)));
    });
  }

  async execRust(taskDir, cfg) {
    await execAsync('cargo build --release', { cwd: taskDir, timeout: 600000 });
    return new Promise((resolve, reject) => {
      const child = spawn('./target/release/main', [], { cwd: taskDir, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...cfg.environment } });
      let out = '', err = '';
      child.stdout.on('data', d => { out += d; process.stdout.write(d); });
      child.stderr.on('data', d => { err += d; process.stderr.write(d); });
      child.on('close', code => code === 0 ? resolve(out) : reject(new Error(`Rust exited ${code}: ${err}`)));
    });
  }

  async execDocker(cfg) {
    const args = ['run', '--rm'];
    if (cfg.gpuRequired) args.push('--gpus', 'all');
    if (cfg.cpuPerWorker) args.push('--cpus', cfg.cpuPerWorker.toString());
    if (cfg.ramPerWorker) args.push('--memory', `${cfg.ramPerWorker}m`);
    
    // ✅ FIXED: Removed extra closing parenthesis
    if (cfg.volumes) {
      Object.entries(cfg.volumes).forEach(([h, c]) => args.push('-v', `${h}:${c}`));
    }
    
    if (cfg.environment) {
      Object.entries(cfg.environment).forEach(([k, v]) => args.push('-e', `${k}=${v}`));
    }

    args.push(cfg.dockerImage, 'sh', '-c', cfg.dockerCommand || 'echo "No command"');

    return new Promise((resolve, reject) => {
      const child = spawn('docker', args, { stdio: ['ignore', 'pipe', 'pipe'] });
      let out = '', err = '';
      child.stdout.on('data', d => { out += d; process.stdout.write(d); });
      child.stderr.on('data', d => { err += d; process.stderr.write(d); });
      child.on('close', code => code === 0 ? resolve(out) : reject(new Error(`Docker exited ${code}: ${err}`)));
    });
  }

  async execBash(taskDir, cfg) {
    return new Promise((resolve, reject) => {
      exec(cfg.command || cfg.executionScript || 'echo "No command"', {
        cwd: taskDir,
        env: { ...process.env, ...cfg.environment },
        timeout: (cfg.timeout || 300) * 1000
      }, (err, stdout, stderr) => err ? reject(new Error(stderr || err.message)) : resolve(stdout));
    });
  }
}

// ============================================================================
// MAIN WORKER AGENT
// ============================================================================
class WorkerAgent {
  constructor(config) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || CONFIG.API_BASE_URL;
    this.workerId = null;
    this.macAddress = null;
    this.hostname = os.hostname();
    this.isRunning = true;
    this.isShuttingDown = false;
    this.isExecutingTask = false;
    this.currentTaskId = null;
    this.runtimeManager = new RuntimeManager();
    this.taskExecutor = new TaskExecutor(this.runtimeManager);

    this.metrics = {
      startTime: Date.now(),
      successfulHeartbeats: 0,
      failedHeartbeats: 0,
      pollAttempts: 0,
      tasksReceived: 0,
      tasksExecuted: 0,
      tasksFailed: 0
    };

    if (!fs.existsSync(CONFIG.WORK_DIR)) fs.mkdirSync(CONFIG.WORK_DIR, { recursive: true });
    this.setupProcessHandlers();
  }

  // ───── System & Network ─────
  async getMacAddress() {
    if (CONFIG.HOST_MAC_ADDRESS) {
      const mac = CONFIG.HOST_MAC_ADDRESS.toLowerCase().replace(/[:-]/g, '');
      if (/^[0-9a-f]{12}$/.test(mac)) return mac;
    }
    if (CONFIG.IS_DOCKER) {
      const p = '/config/mac_address';
      if (fs.existsSync(p)) {
        const mac = fs.readFileSync(p, 'utf8').trim().toLowerCase().replace(/[:-]/g, '');
        if (/^[0-9a-f]{12}$/.test(mac)) return mac;
      }
    }
    const nets = os.networkInterfaces();
    for (const ifaces of Object.values(nets)) {
      if (!ifaces) continue;
      for (const i of ifaces) {
        if (i.internal || !i.mac || i.mac === '00:00:00:00:00:00') continue;
        const mac = i.mac.toLowerCase().replace(/[:-]/g, '');
        if (/^[0-9a-f]{12}$/.test(mac)) return mac;
      }
    }
    throw new Error('No valid MAC address found');
  }

  // ============================================================================
  // RESULT UPLOAD - NEW METHOD
  // ============================================================================
  async uploadResult(taskId, resultData) {
    console.log(`📤 Uploading result for task ${taskId}...`);
  
    try {
      // Package result into tarball
      const tmpDir = '/tmp/distributex-results';
      if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });
    
      const resultDir = path.join(tmpDir, `result-${taskId}`);
      if (!fs.existsSync(resultDir)) fs.mkdirSync(resultDir, { recursive: true });
    
      // Write output.txt
      const outputPath = path.join(resultDir, 'output.txt');
      fs.writeFileSync(outputPath, resultData.output || '');
    
      // Write result.json if available
      if (resultData.structuredResult) {
        const jsonPath = path.join(resultDir, 'result.json');
        fs.writeFileSync(jsonPath, JSON.stringify(resultData.structuredResult, null, 2));
      }
    
      // Create tarball
      const tarPath = path.join(tmpDir, `result-${taskId}.tar.gz`);
      await execAsync(`tar -czf "${tarPath}" -C "${resultDir}" .`);
    
      // Read tarball as base64
      const tarData = fs.readFileSync(tarPath);
      const base64Data = tarData.toString('base64');
      const hash = require('crypto').createHash('sha256').update(tarData).digest('hex');
    
      // Upload to storage
      const uploadResult = await this.makeRequest('POST', '/api/storage/upload', {
        filename: `result-${taskId}.tar.gz`,
        data: base64Data,
        hash: hash,
        size: tarData.length
      });
    
      console.log(`✅ Result uploaded: ${uploadResult.id}`);
    
      // Clean up
      fs.rmSync(resultDir, { recursive: true, force: true });
      fs.unlinkSync(tarPath);
    
      return uploadResult.id; // Return storage file ID
    
    } catch (error) {
      console.error('❌ Result upload failed:', error.message);
      return null;
    }
  }
  
  async detectGPU() {
    try {
      const { stdout } = await execAsync('nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader', { timeout: 5000 });
      const lines = stdout.trim().split('\n').filter(Boolean);
      if (lines.length > 0) {
        const [name, mem, driver] = lines[0].split(',').map(s => s.trim());
        return { available: true, model: name, memory: parseInt(mem) || 0, count: lines.length, driverVersion: driver };
      }
    } catch { /* ignore */ }
    return { available: false };
  }

  async detectSystem() {
    const cpus = os.cpus();
    const gpu = await this.detectGPU();
    this.macAddress = await this.getMacAddress();

    return {
      name: `Worker-${this.macAddress}`,
      hostname: this.hostname,
      platform: os.platform(),
      architecture: os.arch(),
      cpuCores: cpus.length,
      cpuModel: cpus[0]?.model || 'unknown',
      ramTotal: Math.floor(os.totalmem() / (1024*1024)),
      ramAvailable: Math.floor(os.freemem() / (1024*1024)),
      gpuAvailable: gpu.available,
      gpuModel: gpu.model,
      gpuMemory: gpu.memory,
      gpuCount: gpu.count,
      isDocker: CONFIG.IS_DOCKER,
      macAddress: this.macAddress,
      runtimes: await this.runtimeManager.detectAllRuntimes()
    };
  }

  // ───── HTTP Helper ─────
  async makeRequest(method, path, data = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      const headers = {
        'Content-Type': 'application/json',
        'User-Agent': 'DistributeX-Worker/6.0'
      };
      if (!path.includes('/heartbeat')) headers['Authorization'] = `Bearer ${this.apiKey}`;

      const req = https.request(url, { method, headers, timeout: 30000 }, res => {
        let body = '';
        res.on('data', c => body += c);
        res.on('end', () => {
          try {
            const json = body ? JSON.parse(body) : {};
            if (res.statusCode >= 200 && res.statusCode < 300) resolve(json);
            else reject(new Error(`HTTP ${res.statusCode}: ${json.message || json.error || body}`));
          } catch (e) {
            reject(new Error(`JSON parse error: ${body}`));
          }
        });
      });

      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
      if (data) req.write(JSON.stringify(data));
      req.end();
    });
  }

  // ───── Registration & Heartbeat ─────
  async register() {
    this.macAddress = await this.getMacAddress();
    if (CONFIG.DISABLE_SELF_REGISTER) {
      // try load from file (Docker volume)
      const p = '/config/worker_id';
      if (fs.existsSync(p)) this.workerId = fs.readFileSync(p, 'utf8').trim();
    }

    if (!this.workerId) {
      console.log('Registering worker...');
      const caps = await this.detectSystem();
      const res = await this.makeRequest('POST', '/api/workers/register', caps);
      this.workerId = res.workerId;
      console.log(`Registered! Worker ID: ${this.workerId}`);
    } else {
      console.log(`Re-using existing worker ID: ${this.workerId}`);
    }
  }

  async sendHeartbeat(status = 'online') {
    if (!this.isRunning && status !== 'offline') return;
    const actual = this.isExecutingTask ? 'busy' : status;
    try {
      await this.makeRequest('POST', '/api/workers/heartbeat', {
        macAddress: this.macAddress,
        ramAvailable: Math.floor(os.freemem() / (1024*1024)),
        status: actual
      });
      this.metrics.successfulHeartbeats++;
    } catch (e) {
      this.metrics.failedHeartbeats++;
      console.error('Heartbeat failed:', e.message);
    }
  }

  // ───── Task Handling ─────
  async downloadAndExtract(task) {
    const taskDir = path.join(CONFIG.WORK_DIR, `task-${task.id}`);
    if (fs.existsSync(taskDir)) fs.rmSync(taskDir, { recursive: true, force: true });
    fs.mkdirSync(taskDir, { recursive: true });

    const zipPath = path.join(taskDir, 'task.zip');
    const file = fs.createWriteStream(zipPath);
    await new Promise((resolve, reject) => {
      https.get(task.downloadUrl, { headers: { Authorization: `Bearer ${this.apiKey}` } }, res => {
        if (res.statusCode !== 200) return reject(new Error(`Download failed: ${res.statusCode}`));
        pipeline(res, file, err => err ? reject(err) : resolve());
      }).on('error', reject);
    });

    await execAsync(`unzip -o "${zipPath}" -d "${taskDir}"`);
    fs.unlinkSync(zipPath);
    console.log(`Task files extracted to ${taskDir}`);
    return taskDir;
  }

  async executeTask(task) {
    this.isExecutingTask = true;
    this.currentTaskId = task.id;
    const start = Date.now();

    let taskDir;
    try {
      taskDir = await this.downloadAndExtract(task);
      const output = await this.taskExecutor.execute(task, taskDir);

      const duration = Math.round((Date.now() - start) / 1000);
      await this.makeRequest('PUT', `/api/tasks/${task.id}/complete`, {
        workerId: this.workerId,
        result: { output, executionTime: duration },
        executionTime: duration
      });

      this.metrics.tasksExecuted++;
      console.log(`Task ${task.id} COMPLETED in ${duration}s`);
    } catch (err) {
      console.error(`Task ${task.id} FAILED:`, err.message);
      try {
        await this.makeRequest('PUT', `/api/tasks/${task.id}/fail`, {
          workerId: this.workerId,
          errorMessage: err.message
        });
      } catch { /* ignore */ }
      this.metrics.tasksFailed++;
    } finally {
      if (taskDir) fs.rmSync(taskDir, { recursive: true, force: true });
      this.isExecutingTask = false;
      this.currentTaskId = null;
    }
  }

  async pollForTasks() {
    if (!this.isRunning || this.isExecutingTask) return;
    this.metrics.pollAttempts++;
    try {
      const res = await this.makeRequest('GET', `/api/workers/${this.workerId}/tasks/next`);
      if (res?.task) {
        this.metrics.tasksReceived++;
        console.log(`\nTASK RECEIVED: ${res.task.name} (ID: ${res.task.id})`);
        await this.executeTask(res.task);
      }
    } catch (e) {
      if (!e.message.includes('No tasks') && !e.message.includes('404')) {
        console.error('Poll error:', e.message);
      }
    }
  }

  // ───── Lifecycle ─────
  setupProcessHandlers() {
    const shutdown = async signal => {
      if (this.isShuttingDown) process.exit(1);
      console.log(`\nReceived ${signal} – shutting down...`);
      this.isShuttingDown = true;
      this.isRunning = false;
      clearTimeout(this.hbTimer);
      clearTimeout(this.pollTimer);
      if (this.macAddress) await this.sendHeartbeat('offline').catch(() => {});
      setTimeout(() => process.exit(0), 5000);
    };
    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
  }

  scheduleHeartbeat() {
    if (!this.isRunning) return;
    this.hbTimer = setTimeout(async () => {
      await this.sendHeartbeat();
      this.scheduleHeartbeat();
    }, CONFIG.HEARTBEAT_INTERVAL);
  }

  scheduleTaskPolling() {
    if (!this.isRunning) return;
    this.pollTimer = setTimeout(async () => {
      await this.pollForTasks();
      this.scheduleTaskPolling();
    }, CONFIG.TASK_POLL_INTERVAL);
  }

  async start() {
    console.log(`
╔═══════════════════════════════════════════════════════════╗
║   DistributeX Worker v6.0 – MULTI-LANGUAGE + DEBUG MODE   ║
╚═══════════════════════════════════════════════════════════╝
`);
    if (!this.apiKey) {
      console.error('API key required');
      process.exit(1);
    }

    await this.register();
    await this.runtimeManager.detectAllRuntimes();

    this.scheduleHeartbeat();
    this.scheduleTaskPolling();

    setInterval(() => {
      const up = Math.floor((Date.now() - this.metrics.startTime) / 60000);
      console.log(`\nStats – Uptime: ${up}m | Polls: ${this.metrics.pollAttempts} | Tasks: ${this.metrics.tasksExecuted}+${this.metrics.tasksFailed} | HB: ${this.metrics.successfulHeartbeats}/${this.metrics.failedHeartbeats}`);
    }, 60000);

    await new Promise(() => {}); // run forever
  }
}

// ============================================================================
// CLI ENTRYPOINT
// ============================================================================
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.includes('--help') || args.length === 0) {
    console.log(`
Usage: node worker.js --api-key YOUR_KEY [--url BASE_URL]

Options:
  --api-key   Required API key
  --url       Custom API base URL
  --help      Show this message
`);
    process.exit(0);
  }

  const keyIdx = args.indexOf('--api-key');
  const urlIdx = args.indexOf('--url');
  if (keyIdx === -1) {
    console.error('Missing --api-key');
    process.exit(1);
  }

  const worker = new WorkerAgent({
    apiKey: args[keyIdx + 1],
    baseUrl: urlIdx !== -1 ? args[urlIdx + 1] : undefined
  });
  worker.start().catch(err => {
    console.error('Fatal:', err);
    process.exit(1);
  });
}

module.exports = WorkerAgent;
