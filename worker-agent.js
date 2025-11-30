#!/usr/bin/env node
/**
 * DistributeX Worker Agent - COMPLETE MULTI-LANGUAGE VERSION
 * 
 * Supports: Python, Node.js, Java, Go, Rust, Ruby, PHP, C/C++, Docker
 * Features: Auto-detection, package installation, runtime verification
 */

const os = require('os');
const https = require('https');
const { exec, spawn } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const execAsync = promisify(exec);

// Configuration
const CONFIG = {
  API_BASE_URL: process.env.DISTRIBUTEX_API_URL || 'https://distributex-cloud-network.pages.dev',
  HEARTBEAT_INTERVAL: 60 * 1000,
  TASK_POLL_INTERVAL: 10 * 1000,
  IS_DOCKER: process.env.DOCKER_CONTAINER === 'true' || fs.existsSync('/.dockerenv'),
  DISABLE_SELF_REGISTER: process.env.DISABLE_SELF_REGISTER === 'true',
  HOST_MAC_ADDRESS: process.env.HOST_MAC_ADDRESS,
  WORK_DIR: '/tmp/distributex-tasks'
};

// ============================================================================
// RUNTIME DETECTION & VERIFICATION
// ============================================================================

class RuntimeManager {
  constructor() {
    this.runtimes = {};
  }

  async detectAllRuntimes() {
    console.log('🔍 Detecting available runtimes...');
    
    const detectors = [
      this.detectPython(),
      this.detectNode(),
      this.detectJava(),
      this.detectGo(),
      this.detectRust(),
      this.detectRuby(),
      this.detectPHP(),
      this.detectDocker()
    ];

    await Promise.all(detectors);
    
    console.log('✅ Runtime detection complete:');
    Object.entries(this.runtimes).forEach(([runtime, info]) => {
      console.log(`   ${runtime}: ${info.available ? '✓' : '✗'} ${info.version || ''}`);
    });

    return this.runtimes;
  }

  async detectPython() {
    try {
      const { stdout } = await execAsync('python3 --version', { timeout: 3000 });
      const version = stdout.trim().split(' ')[1];
      this.runtimes.python = { available: true, version, command: 'python3' };
    } catch {
      try {
        const { stdout } = await execAsync('python --version', { timeout: 3000 });
        const version = stdout.trim().split(' ')[1];
        this.runtimes.python = { available: true, version, command: 'python' };
      } catch {
        this.runtimes.python = { available: false };
      }
    }
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
      const match = stdout.match(/version "(.+?)"/);
      const version = match ? match[1] : 'unknown';
      this.runtimes.java = { available: true, version, command: 'java' };
    } catch {
      this.runtimes.java = { available: false };
    }
  }

  async detectGo() {
    try {
      const { stdout } = await execAsync('go version', { timeout: 3000 });
      const match = stdout.match(/go(\d+\.\d+\.\d+)/);
      const version = match ? match[1] : 'unknown';
      this.runtimes.go = { available: true, version, command: 'go' };
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
      const match = stdout.match(/ruby (\d+\.\d+\.\d+)/);
      const version = match ? match[1] : 'unknown';
      this.runtimes.ruby = { available: true, version, command: 'ruby' };
    } catch {
      this.runtimes.ruby = { available: false };
    }
  }

  async detectPHP() {
    try {
      const { stdout } = await execAsync('php --version', { timeout: 3000 });
      const match = stdout.match(/PHP (\d+\.\d+\.\d+)/);
      const version = match ? match[1] : 'unknown';
      this.runtimes.php = { available: true, version, command: 'php' };
    } catch {
      this.runtimes.php = { available: false };
    }
  }

  async detectDocker() {
    try {
      const { stdout } = await execAsync('docker --version', { timeout: 3000 });
      const match = stdout.match(/Docker version (\d+\.\d+\.\d+)/);
      const version = match ? match[1] : 'unknown';
      this.runtimes.docker = { available: true, version, command: 'docker' };
    } catch {
      this.runtimes.docker = { available: false };
    }
  }

  async installPackages(runtime, packages) {
    console.log(`📦 Installing ${runtime} packages: ${packages.join(', ')}`);
    
    const installers = {
      python: async (pkgs) => {
        await execAsync(`pip3 install ${pkgs.join(' ')}`, { timeout: 300000 });
      },
      node: async (pkgs) => {
        await execAsync(`npm install -g ${pkgs.join(' ')}`, { timeout: 300000 });
      },
      ruby: async (pkgs) => {
        await execAsync(`gem install ${pkgs.join(' ')}`, { timeout: 300000 });
      },
      java: async (pkgs) => {
        // Maven dependencies would be in pom.xml
        console.log('⚠️  Java packages should be in project dependencies');
      },
      go: async (pkgs) => {
        for (const pkg of pkgs) {
          await execAsync(`go get ${pkg}`, { timeout: 300000 });
        }
      }
    };

    if (installers[runtime]) {
      await installers[runtime](packages);
      console.log('✅ Packages installed');
    }
  }
}

// ============================================================================
// TASK EXECUTORS
// ============================================================================

class TaskExecutor {
  constructor(runtimeManager) {
    this.runtimeManager = runtimeManager;
  }

  async execute(task, taskDir) {
    const config = typeof task.execution_config === 'string' 
      ? JSON.parse(task.execution_config) 
      : task.execution_config;

    const runtime = config.runtime || task.runtime || 'python';

    console.log(`🚀 Executing ${runtime} task: ${task.name}`);

    // Check runtime availability
    if (!this.runtimeManager.runtimes[runtime]?.available) {
      throw new Error(`Runtime ${runtime} not available on this worker`);
    }

    // Install dependencies if specified
    if (config.dependencies && config.dependencies.length > 0) {
      await this.runtimeManager.installPackages(runtime, config.dependencies);
    }

    // Execute based on runtime
    const executors = {
      python: () => this.executePython(taskDir, config),
      node: () => this.executeNode(taskDir, config),
      java: () => this.executeJava(taskDir, config),
      go: () => this.executeGo(taskDir, config),
      rust: () => this.executeRust(taskDir, config),
      ruby: () => this.executeRuby(taskDir, config),
      php: () => this.executePHP(taskDir, config),
      docker: () => this.executeDocker(config),
      bash: () => this.executeBash(taskDir, config)
    };

    if (!executors[runtime]) {
      throw new Error(`Unsupported runtime: ${runtime}`);
    }

    return await executors[runtime]();
  }

  async executePython(taskDir, config) {
    return new Promise((resolve, reject) => {
      const files = fs.readdirSync(taskDir);
      let scriptFile = files.find(f => f.endsWith('.py'));
      
      if (!scriptFile && config.command) {
        // Create script from command
        scriptFile = 'task.py';
        fs.writeFileSync(
          path.join(taskDir, scriptFile), 
          config.command.replace(/^python3?\s+/, '')
        );
      }

      if (!scriptFile) {
        reject(new Error('No Python script found'));
        return;
      }

      const pythonCmd = this.runtimeManager.runtimes.python.command;
      const child = spawn(pythonCmd, [scriptFile], {
        cwd: taskDir,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, ...config.environment }
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
          reject(new Error(`Python failed with code ${code}: ${stderr}`));
        }
      });

      child.on('error', reject);
    });
  }

  async executeNode(taskDir, config) {
    return new Promise((resolve, reject) => {
      const files = fs.readdirSync(taskDir);
      let scriptFile = files.find(f => f.endsWith('.js'));

      if (!scriptFile && config.command) {
        scriptFile = 'task.js';
        fs.writeFileSync(
          path.join(taskDir, scriptFile),
          config.command.replace(/^node\s+/, '')
        );
      }

      if (!scriptFile) {
        reject(new Error('No Node.js script found'));
        return;
      }

      const child = spawn('node', [scriptFile], {
        cwd: taskDir,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, ...config.environment }
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
          reject(new Error(`Node.js failed with code ${code}: ${stderr}`));
        }
      });

      child.on('error', reject);
    });
  }

  async executeJava(taskDir, config) {
    return new Promise(async (resolve, reject) => {
      try {
        const files = fs.readdirSync(taskDir);
        const javaFile = files.find(f => f.endsWith('.java'));

        if (!javaFile) {
          reject(new Error('No Java file found'));
          return;
        }

        // Compile
        console.log('📦 Compiling Java...');
        await execAsync(`javac ${javaFile}`, { cwd: taskDir });

        // Run
        const className = javaFile.replace('.java', '');
        const child = spawn('java', [className], {
          cwd: taskDir,
          stdio: ['ignore', 'pipe', 'pipe'],
          env: { ...process.env, ...config.environment }
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
            reject(new Error(`Java failed with code ${code}: ${stderr}`));
          }
        });

        child.on('error', reject);
      } catch (error) {
        reject(error);
      }
    });
  }

  async executeGo(taskDir, config) {
    return new Promise((resolve, reject) => {
      const child = spawn('go', ['run', '.'], {
        cwd: taskDir,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, ...config.environment }
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
          reject(new Error(`Go failed with code ${code}: ${stderr}`));
        }
      });

      child.on('error', reject);
    });
  }

  async executeRust(taskDir, config) {
    return new Promise(async (resolve, reject) => {
      try {
        console.log('📦 Compiling Rust...');
        await execAsync('cargo build --release', { cwd: taskDir, timeout: 300000 });

        const child = spawn('./target/release/main', [], {
          cwd: taskDir,
          stdio: ['ignore', 'pipe', 'pipe'],
          env: { ...process.env, ...config.environment }
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
            reject(new Error(`Rust failed with code ${code}: ${stderr}`));
          }
        });

        child.on('error', reject);
      } catch (error) {
        reject(error);
      }
    });
  }

  async executeRuby(taskDir, config) {
    return new Promise((resolve, reject) => {
      const files = fs.readdirSync(taskDir);
      const rubyFile = files.find(f => f.endsWith('.rb'));

      if (!rubyFile) {
        reject(new Error('No Ruby file found'));
        return;
      }

      const child = spawn('ruby', [rubyFile], {
        cwd: taskDir,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, ...config.environment }
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
          reject(new Error(`Ruby failed with code ${code}: ${stderr}`));
        }
      });

      child.on('error', reject);
    });
  }

  async executePHP(taskDir, config) {
    return new Promise((resolve, reject) => {
      const files = fs.readdirSync(taskDir);
      const phpFile = files.find(f => f.endsWith('.php'));

      if (!phpFile) {
        reject(new Error('No PHP file found'));
        return;
      }

      const child = spawn('php', [phpFile], {
        cwd: taskDir,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, ...config.environment }
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
          reject(new Error(`PHP failed with code ${code}: ${stderr}`));
        }
      });

      child.on('error', reject);
    });
  }

  async executeDocker(config) {
    return new Promise((resolve, reject) => {
      const image = config.dockerImage;
      const command = config.dockerCommand || 'sh';

      const dockerArgs = ['run', '--rm'];

      // Add GPU support if needed
      if (config.gpuRequired) {
        dockerArgs.push('--gpus', 'all');
      }

      // Add resource limits
      if (config.cpuPerWorker) {
        dockerArgs.push('--cpus', config.cpuPerWorker.toString());
      }
      if (config.ramPerWorker) {
        dockerArgs.push('--memory', `${config.ramPerWorker}m`);
      }

      // Add volumes
      if (config.volumes) {
        Object.entries(config.volumes).forEach(([host, container]) => {
          dockerArgs.push('-v', `${host}:${container}`);
        });
      }

      // Add environment
      if (config.environment) {
        Object.entries(config.environment).forEach(([key, val]) => {
          dockerArgs.push('-e', `${key}=${val}`);
        });
      }

      dockerArgs.push(image, 'sh', '-c', command);

      const child = spawn('docker', dockerArgs, {
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
          reject(new Error(`Docker failed with code ${code}: ${stderr}`));
        }
      });

      child.on('error', reject);
    });
  }

  async executeBash(taskDir, config) {
    return new Promise((resolve, reject) => {
      exec(config.command || config.executionScript, {
        cwd: taskDir,
        env: { ...process.env, ...config.environment },
        timeout: config.timeout * 1000
      }, (error, stdout, stderr) => {
        if (error) {
          reject(new Error(`Bash failed: ${stderr}`));
        } else {
          resolve(stdout);
        }
      });
    });
  }
}

// Export
module.exports = { RuntimeManager, TaskExecutor };

// Note: This would be integrated into the existing worker-agent.js
// The full integration is in the next artifact
