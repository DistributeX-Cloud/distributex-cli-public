#!/usr/bin/env node
/**
 * DistributeX Worker - Runs inside Docker container
 */

const fs = require('fs');
const os = require('os');
const http = require('http');
const https = require('https');

let config = {};
let workerId = null;
let heartbeatInterval = null;

// Load configuration from mounted volume
function loadConfig() {
  try {
    const configPath = '/config/config.json';
    const configData = fs.readFileSync(configPath, 'utf8');
    config = JSON.parse(configData);
    console.log('[Worker] Configuration loaded');
    return true;
  } catch (error) {
    console.error('[Worker] Failed to load config:', error.message);
    return false;
  }
}

// Make API request
async function apiRequest(method, path, data = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, config.apiUrl);
    const isHttps = url.protocol === 'https:';
    const lib = isHttps ? https : http;
    
    const options = {
      method,
      headers: {
        'Authorization': `Bearer ${config.apiKey}`,
        'Content-Type': 'application/json',
      },
    };

    const req = lib.request(url, options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(body));
          } catch {
            resolve(body);
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${body}`));
        }
      });
    });

    req.on('error', reject);
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}

// Get current resources
function getCurrentResources() {
  return {
    ramAvailable: Math.floor(os.freemem() / (1024 * 1024)),
    storageAvailable: config.worker.storageAvailable, // Static from config
    status: 'online',
  };
}

// Register worker
async function register() {
  try {
    console.log('[Worker] Registering with DistributeX...');
    const worker = await apiRequest('POST', '/api/workers/register', config.worker);
    workerId = worker.id;
    console.log(`[Worker] Registered: ${workerId}`);
    return worker;
  } catch (error) {
    console.error('[Worker] Registration failed:', error.message);
    throw error;
  }
}

// Send heartbeat
async function sendHeartbeat() {
  if (!workerId) return;
  
  try {
    const resources = getCurrentResources();
    await apiRequest('POST', `/api/workers/${workerId}/heartbeat`, resources);
    console.log(`[Worker] Heartbeat sent at ${new Date().toISOString()}`);
  } catch (error) {
    console.error('[Worker] Heartbeat failed:', error.message);
  }
}

// Health check server
function startHealthServer() {
  const server = http.createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'healthy',
        workerId,
        uptime: process.uptime(),
      }));
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  server.listen(3001, () => {
    console.log('[Worker] Health server listening on :3001');
  });
}

// Graceful shutdown
function setupShutdown() {
  const shutdown = async () => {
    console.log('[Worker] Shutting down...');
    
    if (heartbeatInterval) {
      clearInterval(heartbeatInterval);
    }
    
    if (workerId) {
      try {
        await apiRequest('POST', `/api/workers/${workerId}/heartbeat`, {
          ramAvailable: 0,
          storageAvailable: 0,
          status: 'offline',
        });
      } catch (error) {
        console.error('[Worker] Failed to send offline status');
      }
    }
    
    process.exit(0);
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

// Main startup
async function main() {
  console.log('╔═══════════════════════════════════════╗');
  console.log('║   DistributeX Worker v1.0.0          ║');
  console.log('╚═══════════════════════════════════════╝');
  console.log('');

  // Load config
  if (!loadConfig()) {
    console.error('[Worker] Cannot start without configuration');
    process.exit(1);
  }

  // Setup shutdown
  setupShutdown();

  // Start health server
  startHealthServer();

  try {
    // Register
    await register();

    // Start heartbeat (every 60 seconds)
    heartbeatInterval = setInterval(sendHeartbeat, 60000);

    // Send initial heartbeat
    await sendHeartbeat();

    console.log('[Worker] Running successfully');
    console.log(`[Worker] Worker ID: ${workerId}`);
    console.log('[Worker] Contributing to the network...');
  } catch (error) {
    console.error('[Worker] Startup failed:', error.message);
    process.exit(1);
  }
}

// Start
main().catch(error => {
  console.error('[Worker] Fatal error:', error);
  process.exit(1);
});
