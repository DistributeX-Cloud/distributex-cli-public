#!/usr/bin/env node
/**
 * DistributeX Worker Agent
 * Runs inside Docker container to contribute resources
 */

const fs = require('fs');
const os = require('os');
const http = require('http');
const https = require('https');
const { spawn } = require('child_process');
const WebSocket = require('ws');

// Configuration
let config = {};
let workerId = null;
let ws = null;
let heartbeatInterval = null;

// Load configuration
function loadConfig() {
    try {
        const configPath = process.env.CONFIG_PATH || '/config/config.json';
        const configData = fs.readFileSync(configPath, 'utf8');
        config = JSON.parse(configData);
        console.log('[Worker] Configuration loaded');
        return true;
    } catch (error) {
        console.error('[Worker] Failed to load configuration:', error.message);
        return false;
    }
}

// Get current resource availability
function getResourceAvailability() {
    const freemem = os.freemem();
    const totalmem = os.totalmem();
    const ramAvailable = Math.floor(freemem / 1024 / 1024); // MB
    
    // Estimate available storage (simplified)
    const storageAvailable = Math.floor(config.worker.storageTotal * (config.worker.storageSharePercent / 100));
    
    return {
        ramAvailable,
        storageAvailable,
        cpuLoad: os.loadavg()[0],
    };
}

// Register worker with API
async function registerWorker() {
    return new Promise((resolve, reject) => {
        const data = JSON.stringify({
            name: config.worker.name,
            hostname: os.hostname(),
            platform: os.platform(),
            architecture: os.arch(),
            cpuCores: config.worker.cpuCores,
            cpuModel: config.worker.cpuModel,
            ramTotal: config.worker.ramTotal,
            ramAvailable: Math.floor(os.freemem() / 1024 / 1024),
            gpuAvailable: config.worker.gpuAvailable,
            gpuModel: config.worker.gpuModel,
            storageTotal: config.worker.storageTotal,
            storageAvailable: Math.floor(config.worker.storageTotal * 0.8),
            cpuSharePercent: config.worker.cpuSharePercent,
            ramSharePercent: config.worker.ramSharePercent,
            gpuSharePercent: config.worker.gpuSharePercent,
            storageSharePercent: config.worker.storageSharePercent,
        });

        const url = new URL('/api/workers/register', config.apiUrl);
        const options = {
            hostname: url.hostname,
            port: url.port || (url.protocol === 'https:' ? 443 : 80),
            path: url.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': data.length,
                'Authorization': `Bearer ${config.apiKey}`,
            },
        };

        const protocol = url.protocol === 'https:' ? https : http;
        const req = protocol.request(options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                if (res.statusCode === 201) {
                    const worker = JSON.parse(body);
                    workerId = worker.id;
                    console.log(`[Worker] Registered successfully: ${workerId}`);
                    resolve(worker);
                } else {
                    reject(new Error(`Registration failed: ${res.statusCode} ${body}`));
                }
            });
        });

        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

// Send heartbeat to API
async function sendHeartbeat() {
    if (!workerId) return;

    return new Promise((resolve, reject) => {
        const resources = getResourceAvailability();
        const data = JSON.stringify({
            ...resources,
            status: 'online',
        });

        const url = new URL(`/api/workers/${workerId}/heartbeat`, config.apiUrl);
        const options = {
            hostname: url.hostname,
            port: url.port || (url.protocol === 'https:' ? 443 : 80),
            path: url.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': data.length,
                'Authorization': `Bearer ${config.apiKey}`,
            },
        };

        const protocol = url.protocol === 'https:' ? https : http;
        const req = protocol.request(options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                if (res.statusCode === 200) {
                    console.log('[Worker] Heartbeat sent');
                    resolve();
                } else {
                    console.error(`[Worker] Heartbeat failed: ${res.statusCode}`);
                    reject(new Error(`Heartbeat failed: ${res.statusCode}`));
                }
            });
        });

        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

// Connect to WebSocket for real-time task assignments
function connectWebSocket() {
    const wsUrl = config.apiUrl.replace('http', 'ws') + '/ws';
    
    console.log(`[Worker] Connecting to WebSocket: ${wsUrl}`);
    
    ws = new WebSocket(wsUrl, {
        headers: {
            'Authorization': `Bearer ${config.apiKey}`,
        },
    });

    ws.on('open', () => {
        console.log('[Worker] WebSocket connected');
        ws.send(JSON.stringify({
            type: 'worker_connect',
            workerId,
        }));
    });

    ws.on('message', (data) => {
        try {
            const message = JSON.parse(data.toString());
            handleWebSocketMessage(message);
        } catch (error) {
            console.error('[Worker] Error parsing WebSocket message:', error);
        }
    });

    ws.on('close', () => {
        console.log('[Worker] WebSocket disconnected. Reconnecting in 5s...');
        setTimeout(connectWebSocket, 5000);
    });

    ws.on('error', (error) => {
        console.error('[Worker] WebSocket error:', error.message);
    });
}

// Handle WebSocket messages
function handleWebSocketMessage(message) {
    console.log('[Worker] Received message:', message.type);
    
    switch (message.type) {
        case 'task_assigned':
            handleTaskAssignment(message);
            break;
        case 'task_cancel':
            handleTaskCancellation(message);
            break;
        default:
            console.log('[Worker] Unknown message type:', message.type);
    }
}

// Handle task assignment
async function handleTaskAssignment(message) {
    const { taskId, task } = message;
    console.log(`[Worker] Task assigned: ${taskId}`);
    
    try {
        // Execute task in isolated Docker container
        await executeTask(taskId, task);
        
        // Report completion
        await reportTaskCompletion(taskId, 'completed');
    } catch (error) {
        console.error(`[Worker] Task execution failed: ${error.message}`);
        await reportTaskCompletion(taskId, 'failed', error.message);
    }
}

// Execute task in Docker container
function executeTask(taskId, task) {
    return new Promise((resolve, reject) => {
        console.log(`[Worker] Executing task ${taskId}...`);
        
        // Resource limits for task container
        const cpuLimit = Math.floor(config.worker.cpuCores * config.worker.cpuSharePercent / 100);
        const memLimit = Math.floor(config.worker.ramTotal * config.worker.ramSharePercent / 100);
        
        // Run task in isolated container
        const dockerArgs = [
            'run',
            '--rm',
            '--name', `distributex-task-${taskId}`,
            '--cpus', String(cpuLimit),
            '--memory', `${memLimit}m`,
            '--network', 'none', // Isolated network
            'alpine:latest',
            'sh', '-c', 'echo "Task execution placeholder"'
        ];
        
        const process = spawn('docker', dockerArgs);
        
        let output = '';
        process.stdout.on('data', (data) => {
            output += data.toString();
        });
        
        process.stderr.on('data', (data) => {
            console.error(`[Task ${taskId}] ${data}`);
        });
        
        process.on('close', (code) => {
            if (code === 0) {
                console.log(`[Worker] Task ${taskId} completed successfully`);
                resolve(output);
            } else {
                reject(new Error(`Task exited with code ${code}`));
            }
        });
        
        process.on('error', reject);
    });
}

// Report task completion to API
async function reportTaskCompletion(taskId, status, error = null) {
    return new Promise((resolve, reject) => {
        const data = JSON.stringify({
            status,
            workerId,
            error,
            completedAt: new Date().toISOString(),
        });

        const url = new URL(`/api/tasks/${taskId}`, config.apiUrl);
        const options = {
            hostname: url.hostname,
            port: url.port || (url.protocol === 'https:' ? 443 : 80),
            path: url.pathname,
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': data.length,
                'Authorization': `Bearer ${config.apiKey}`,
            },
        };

        const protocol = url.protocol === 'https:' ? https : http;
        const req = protocol.request(options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                if (res.statusCode === 200) {
                    console.log(`[Worker] Task ${taskId} status updated: ${status}`);
                    resolve();
                } else {
                    reject(new Error(`Failed to update task status: ${res.statusCode}`));
                }
            });
        });

        req.on('error', reject);
        req.write(data);
        req.end();
    });
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
                memoryUsage: process.memoryUsage(),
            }));
        } else {
            res.writeHead(404);
            res.end();
        }
    });

    server.listen(3001, () => {
        console.log('[Worker] Health check server listening on port 3001');
    });
}

// Handle graceful shutdown
function setupGracefulShutdown() {
    const shutdown = async (signal) => {
        console.log(`[Worker] Received ${signal}, shutting down gracefully...`);
        
        // Stop heartbeat
        if (heartbeatInterval) {
            clearInterval(heartbeatInterval);
        }
        
        // Close WebSocket
        if (ws) {
            ws.close();
        }
        
        // Update worker status to offline
        if (workerId) {
            try {
                await sendHeartbeat(); // One last heartbeat with offline status
            } catch (error) {
                console.error('[Worker] Failed to send final heartbeat:', error);
            }
        }
        
        console.log('[Worker] Shutdown complete');
        process.exit(0);
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
}

// Main startup
async function main() {
    console.log('╔═══════════════════════════════════════╗');
    console.log('║   DistributeX Worker Agent v1.0.0    ║');
    console.log('╚═══════════════════════════════════════╝');
    console.log('');

    // Load configuration
    if (!loadConfig()) {
        console.error('[Worker] Failed to load configuration');
        process.exit(1);
    }

    // Setup graceful shutdown
    setupGracefulShutdown();

    // Start health server
    startHealthServer();

    try {
        // Register with API
        await registerWorker();

        // Start heartbeat (every 60 seconds)
        heartbeatInterval = setInterval(async () => {
            try {
                await sendHeartbeat();
            } catch (error) {
                console.error('[Worker] Heartbeat error:', error.message);
            }
        }, 60000);

        // Send initial heartbeat
        await sendHeartbeat();

        // Connect WebSocket
        connectWebSocket();

        console.log('[Worker] Worker agent running successfully');
        console.log(`[Worker] Worker ID: ${workerId}`);
        console.log('[Worker] Waiting for task assignments...');
    } catch (error) {
        console.error('[Worker] Startup failed:', error.message);
        process.exit(1);
    }
}

// Start the worker
main().catch((error) => {
    console.error('[Worker] Fatal error:', error);
    process.exit(1);
});
