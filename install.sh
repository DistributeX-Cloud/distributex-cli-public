#!/bin/bash
# DistributeX CLI Installer - FIXED VERSION
# Prevents infinite shell loops and handles permission issues

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     DistributeX CLI Installer        ║${NC}"
echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo ""

# Detect OS
OS="$(uname -s)"
ARCH="$(uname -m)"

echo -e "${BLUE}→${NC} Detected: $OS $ARCH"

# Set installation directories
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.distributex"
WORKER_DIR="$CONFIG_DIR/worker"

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then 
    echo -e "${YELLOW}⚠️  Warning: Running as root. Installation will be system-wide.${NC}"
fi

# Create directories
echo -e "${BLUE}→${NC} Creating directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$WORKER_DIR"
mkdir -p "$CONFIG_DIR/logs"

# Handle permission for INSTALL_DIR
if [ ! -w "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}🔑 Root access required to write to $INSTALL_DIR. Using sudo...${NC}"
    SUDO="sudo"
else
    SUDO=""
fi

# Download CLI binary
echo -e "${BLUE}→${NC} Installing CLI..."

# Create the CLI executable directly (no recursive bash calls)
$SUDO sh -c "cat > $INSTALL_DIR/dxcloud" << 'DXCLOUD_EOF'
#!/usr/bin/env node

/**
 * DistributeX CLI Entry Point
 * This file should NEVER call bash or source itself
 */

const path = require('path');
const fs = require('fs');

// Get the actual CLI directory
const CLI_DIR = path.join(process.env.HOME, '.distributex', 'cli');
const CLI_MAIN = path.join(CLI_DIR, 'index.js');

// Check if CLI is installed
if (!fs.existsSync(CLI_MAIN)) {
  console.error('\x1b[31m❌ DistributeX CLI not found. Please reinstall:\x1b[0m');
  console.error('   curl -fsSL https://get.distributex.cloud | bash');
  process.exit(1);
}

// Execute the main CLI (DO NOT USE bash or shell)
try {
  require(CLI_MAIN);
} catch (error) {
  console.error('\x1b[31m❌ CLI Error:\x1b[0m', error.message);
  process.exit(1);
}
DXCLOUD_EOF

$SUDO chmod +x "$INSTALL_DIR/dxcloud"

# Install Node.js CLI implementation
CLI_DIR="$CONFIG_DIR/cli"
mkdir -p "$CLI_DIR"

echo -e "${BLUE}→${NC} Installing CLI components..."

# Create actual CLI implementation
cat > "$CLI_DIR/index.js" << 'CLI_EOF'
#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');
const https = require('https');

const CONFIG_PATH = path.join(os.homedir(), '.distributex', 'config.json');
const API_URL = 'https://distributex-api.distributex.workers.dev';

// Parse command line arguments
const args = process.argv.slice(2);
const command = args[0];
const subcommand = args[1];

// Main CLI router
async function main() {
  if (!command || command === '--help' || command === '-h') {
    showHelp();
    return;
  }

  switch (command) {
    case 'signup':
      await signup();
      break;
    case 'login':
      await login();
      break;
    case 'worker':
      await handleWorker(subcommand);
      break;
    case 'submit':
      await submitJob();
      break;
    case 'jobs':
      await listJobs();
      break;
    case 'status':
      await showStatus();
      break;
    case 'version':
      console.log('DistributeX CLI v1.0.0');
      break;
    default:
      console.error(`❌ Unknown command: ${command}`);
      console.log('Run "dxcloud --help" for usage');
      process.exit(1);
  }
}

function showHelp() {
  console.log(`
╔═══════════════════════════════════════╗
║     DistributeX CLI v1.0.0            ║
╚═══════════════════════════════════════╝

USAGE:
  dxcloud <command> [options]

COMMANDS:
  signup              Create a new account
  login               Login to your account
  worker start        Start contributing compute
  worker stop         Stop the worker
  submit              Submit a job
  jobs                List your jobs
  status              Show network status
  version             Show CLI version

EXAMPLES:
  dxcloud signup
  dxcloud worker start
  dxcloud submit --image python:3.11 --command "python script.py"

For more help: https://docs.distributex.cloud
`);
}

async function signup() {
  const readline = require('readline').createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const question = (query) => new Promise((resolve) => readline.question(query, resolve));

  console.log('\n🔐 DistributeX Account Creation\n');
  
  const name = await question('Name: ');
  const email = await question('Email: ');
  const password = await question('Password (8+ characters): ');
  const role = await question('Role (developer/contributor/both): ');

  readline.close();

  console.log('\n⏳ Creating account...');

  const data = JSON.stringify({ name, email, password, role });
  
  const options = {
    hostname: 'distributex-api.distributex.workers.dev',
    path: '/api/auth/signup',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': data.length
    }
  };

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        try {
          const response = JSON.parse(body);
          
          if (res.statusCode === 201 || res.statusCode === 200) {
            const config = {
              authToken: response.token,
              workerId: response.worker?.workerId || `worker-${Date.now()}`,
              apiUrl: API_URL,
              user: response.user
            };
            
            fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
            fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
            
            console.log('\n✅ Account created successfully!');
            console.log(`   Email: ${email}`);
            console.log(`   Role: ${role}`);
            
            if (response.worker) {
              console.log('\n📦 Worker credentials generated:');
              console.log(`   Worker ID: ${response.worker.workerId}`);
              console.log('\n   Run "dxcloud worker start" to begin contributing');
            }
            
            resolve();
          } else {
            console.error(`\n❌ Signup failed: ${response.error || 'Unknown error'}`);
            process.exit(1);
          }
        } catch (error) {
          console.error('\n❌ Error:', error.message);
          process.exit(1);
        }
      });
    });

    req.on('error', (error) => {
      console.error('\n❌ Connection error:', error.message);
      process.exit(1);
    });

    req.write(data);
    req.end();
  });
}

async function login() {
  console.log('Login functionality - use signup for now');
}

async function handleWorker(subcmd) {
  if (subcmd === 'start') {
    console.log('\n🚀 Starting DistributeX Worker...\n');
    
    // Check config
    if (!fs.existsSync(CONFIG_PATH)) {
      console.error('❌ Not authenticated. Run: dxcloud signup');
      process.exit(1);
    }

    // Execute the worker (DO NOT use bash here)
    const { spawn } = require('child_process');
    const workerScript = path.join(os.homedir(), '.distributex', 'worker', 'distributex-worker.js');
    
    if (!fs.existsSync(workerScript)) {
      console.error('❌ Worker script not found. Please reinstall.');
      process.exit(1);
    }

    const worker = spawn('node', [workerScript], {
      stdio: 'inherit',
      detached: false
    });

    worker.on('error', (error) => {
      console.error('❌ Failed to start worker:', error.message);
      process.exit(1);
    });

  } else if (subcmd === 'stop') {
    console.log('⏹️  Stopping worker...');
    // Implementation for stopping worker
  } else {
    console.log('Usage: dxcloud worker [start|stop]');
  }
}

async function submitJob() {
  console.log('Job submission - Coming soon');
}

async function listJobs() {
  console.log('Jobs list - Coming soon');
}

async function showStatus() {
  console.log('\n📊 DistributeX Network Status\n');
  console.log('Fetching...\n');
  
  const options = {
    hostname: 'distributex-api.distributex.workers.dev',
    path: '/api/pool/status',
    method: 'GET'
  };

  return new Promise((resolve) => {
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        try {
          const data = JSON.parse(body);
          console.log(`Workers Online: ${data.workers.online}/${data.workers.total}`);
          console.log(`CPU Cores: ${data.resources.cpu.total}`);
          console.log(`Memory: ${data.resources.memory.totalGb.toFixed(1)} GB`);
          console.log(`Jobs Completed: ${data.queue.completed}`);
          console.log(`Jobs Running: ${data.queue.running}`);
          resolve();
        } catch (error) {
          console.error('❌ Failed to parse status');
          resolve();
        }
      });
    });

    req.on('error', (error) => {
      console.error('❌ Connection error:', error.message);
      resolve();
    });

    req.end();
  });
}

// Run the CLI
main().catch((error) => {
  console.error('❌ CLI Error:', error.message);
  process.exit(1);
});
CLI_EOF

chmod +x "$CLI_DIR/index.js"

# Install worker script (if needed)
echo -e "${BLUE}→${NC} Installing worker components..."

# Create minimal worker script placeholder
cat > "$WORKER_DIR/distributex-worker.js" << 'WORKER_EOF'
#!/usr/bin/env node
console.log('Worker starting...');
console.log('Full worker implementation coming soon');
console.log('Press Ctrl+C to exit');

process.on('SIGINT', () => {
  console.log('\n👋 Worker stopped');
  process.exit(0);
});

// Keep process alive
setInterval(() => {}, 1000);
WORKER_EOF

chmod +x "$WORKER_DIR/distributex-worker.js"

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo -e "${BLUE}Quick Start:${NC}"
echo -e "  1. Create account:  ${GREEN}dxcloud signup${NC}"
echo -e "  2. Start worker:    ${GREEN}dxcloud worker start${NC}"
echo -e "  3. Check status:    ${GREEN}dxcloud status${NC}"
echo ""
echo -e "${YELLOW}Note: You may need to restart your terminal or run:${NC}"
echo -e "      ${GREEN}source ~/.bashrc${NC}  (or ~/.zshrc for Zsh)"
echo ""
