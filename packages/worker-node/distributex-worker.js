#!/usr/bin/env node
/**
 * DistributeX Worker Node - FIXED AUTH VERSION
 * Connects to coordinator and executes distributed computing jobs
 */

const WebSocket = require('ws');
const Docker = require('dockerode');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Configuration
const INSTALL_DIR = path.join(os.homedir(), '.distributex');
const CONFIG_FILE = path.join(INSTALL_DIR, 'config', 'auth.json');
const LOG_FILE = path.join(INSTALL_DIR, 'logs', 'worker.log');
const COORDINATOR_URL = process.env.DISTRIBUTEX_COORDINATOR_URL || 'wss://distributex-coordinator.distributex.workers.dev/ws';

// State
let config = {};
let ws = null;
let docker = new Docker();
let reconnectAttempts = 0;
let currentJob = null;
const MAX_RECONNECT_ATTEMPTS = 10;
const HEARTBEAT_INTERVAL = 30000; // 30 seconds
let heartbeatTimer = null;

// Logging
function log(message, level = 'INFO') {
    const timestamp = new Date().toISOString();
    const logMessage = `[${timestamp}] [${level}] ${message}`;
    
    console.log(logMessage);
    
    try {
        fs.appendFileSync(LOG_FILE, logMessage + '\n');
    } catch (err) {
        // Silent fail for logging errors
    }
}

// Load configuration
function loadConfig() {
    try {
        if (!fs.existsSync(CONFIG_FILE)) {
            log('Config file not found. Please run: dxcloud login', 'ERROR');
            return false;
        }
        
        const data = fs.readFileSync(CONFIG_FILE, 'utf8');
        config = JSON.parse(data);
        
        if (!config.token || !config.user_id) {
            log('Invalid config: missing token or user_id', 'ERROR');
            return false;
        }
        
        return true;
    } catch (err) {
        log(`Failed to load config: ${err.message}`, 'ERROR');
        return false;
    }
}

// Get system capabilities
function getCapabilities() {
    const cpus = os.cpus();
    const totalMemGB = Math.floor(os.totalmem() / (1024 * 1024 * 1024));
    const freeMemGB = Math.floor(os.freemem() / (1024 * 1024 * 1024));
    
    return {
        cpu_cores: cpus.length,
        cpu_model: cpus[0]?.model || 'Unknown',
        memory_total_gb: totalMemGB,
        memory_free_gb: freeMemGB,
        platform: os.platform(),
        arch: os.arch(),
        docker: true,
        worker_version: '1.0.0'
    };
}

// Send heartbeat
function sendHeartbeat() {
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
            type: 'heartbeat',
            workerId: config.user_id,
            timestamp: Date.now(),
            capabilities: getCapabilities(),
            currentJob: currentJob ? currentJob.jobId : null
        }));
    }
}

// Start heartbeat
function startHeartbeat() {
    if (heartbeatTimer) {
        clearInterval(heartbeatTimer);
    }
    heartbeatTimer = setInterval(sendHeartbeat, HEARTBEAT_INTERVAL);
}

// Stop heartbeat
function stopHeartbeat() {
    if (heartbeatTimer) {
        clearInterval(heartbeatTimer);
        heartbeatTimer = null;
    }
}

// Connect to coordinator
function connect() {
    if (!loadConfig()) {
        log('Cannot connect: Configuration error', 'ERROR');
        process.exit(1);
    }

    log(`Connecting to coordinator: ${COORDINATOR_URL}`);
    log(`Using token: ${config.token.substring(0, 20)}...`);
    
    try {
        // Build WebSocket URL with auth params
        const wsUrl = new URL(COORDINATOR_URL);
        wsUrl.searchParams.set('token', config.token);
        wsUrl.searchParams.set('workerId', config.user_id);
        
        log(`Full WS URL: ${wsUrl.toString().replace(config.token, 'TOKEN_HIDDEN')}`);
        
        ws = new WebSocket(wsUrl.toString(), {
            headers: {
                'Authorization': `Bearer ${config.token}`,
                'User-Agent': 'DistributeX-Worker/1.0.0',
                'X-Worker-Id': config.user_id,
                'X-Worker-Email': config.email || 'unknown'
            },
            handshakeTimeout: 15000,
            perMessageDeflate: false
        });

        ws.on('open', () => {
            log('✓ Connected to coordinator', 'SUCCESS');
            reconnectAttempts = 0;
            
            // Register worker
            const capabilities = getCapabilities();
            log(`Registering worker with ${capabilities.cpu_cores} CPU cores, ${capabilities.memory_total_gb}GB RAM`);
            
            ws.send(JSON.stringify({
                type: 'register',
                workerId: config.user_id,
                email: config.email || 'unknown',
                capabilities: capabilities,
                timestamp: Date.now()
            }));
            
            // Start heartbeat
            startHeartbeat();
        });

        ws.on('message', async (data) => {
            try {
                const message = JSON.parse(data.toString());
                log(`Received: ${message.type}`, 'DEBUG');
                
                switch (message.type) {
                    case 'registered':
                        log(`Worker registered successfully`, 'SUCCESS');
                        break;
                    
                    case 'job_assigned':
                        await handleJobAssignment(message.job);
                        break;
                    
                    case 'job_cancelled':
                        await handleJobCancellation(message.jobId);
                        break;
                    
                    case 'ping':
                        ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
                        break;
                    
                    case 'error':
                        log(`Coordinator error: ${message.message}`, 'ERROR');
                        if (message.message && message.message.includes('auth')) {
                            log('Authentication error - please re-login: dxcloud login', 'ERROR');
                            process.exit(1);
                        }
                        break;
                    
                    default:
                        log(`Unknown message type: ${message.type}`, 'WARN');
                }
            } catch (err) {
                log(`Error handling message: ${err.message}`, 'ERROR');
            }
        });

        ws.on('error', (err) => {
            log(`WebSocket error: ${err.message}`, 'ERROR');
            
            // Check for auth errors
            if (err.message.includes('401') || err.message.includes('Unauthorized')) {
                log('', 'ERROR');
                log('═══════════════════════════════════════════', 'ERROR');
                log('AUTHENTICATION FAILED', 'ERROR');
                log('═══════════════════════════════════════════', 'ERROR');
                log('', 'ERROR');
                log('Your authentication token may be expired or invalid.', 'ERROR');
                log('', 'ERROR');
                log('Please try the following:', 'ERROR');
                log('  1. Login again: dxcloud login', 'ERROR');
                log('  2. Or create new account: dxcloud signup', 'ERROR');
                log('', 'ERROR');
                log('Config location: ' + CONFIG_FILE, 'ERROR');
                log('', 'ERROR');
                
                // Stop trying to reconnect on auth errors
                reconnectAttempts = MAX_RECONNECT_ATTEMPTS;
            }
        });

        ws.on('close', (code, reason) => {
            const reasonStr = reason ? reason.toString() : 'none';
            log(`Disconnected (code: ${code}, reason: ${reasonStr})`, 'WARN');
            stopHeartbeat();
            
            // Don't retry on auth failures (401)
            if (code === 401 || code === 403) {
                log('Authentication error - stopping reconnection attempts', 'ERROR');
                log('Please run: dxcloud login', 'ERROR');
                process.exit(1);
            }
            
            if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
                reconnectAttempts++;
                const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), 30000);
                log(`Reconnecting in ${delay/1000}s... (attempt ${reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS})`);
                setTimeout(connect, delay);
            } else {
                log('Max reconnection attempts reached. Exiting.', 'ERROR');
                process.exit(1);
            }
        });
    } catch (err) {
        log(`Failed to create WebSocket: ${err.message}`, 'ERROR');
        process.exit(1);
    }
}

// Handle job assignment
async function handleJobAssignment(job) {
    if (currentJob) {
        log(`Rejected job ${job.jobId}: Already executing ${currentJob.jobId}`, 'WARN');
        reportJobStatus(job.jobId, 'rejected', 'Worker busy with another job');
        return;
    }
    
    currentJob = job;
    log(`\n${'='.repeat(60)}`);
    log(`Executing Job: ${job.jobId}`);
    log(`Image: ${job.containerImage}`);
    log(`Command: ${job.command?.join(' ') || 'default'}`);
    log(`CPU: ${job.requiredCpuCores || 1} cores, Memory: ${job.requiredMemoryGb || 2}GB`);
    log(`${'='.repeat(60)}`);
    
    try {
        reportJobStatus(job.jobId, 'running', 'Job started');
        
        // Execute the job
        const result = await executeJob(job);
        
        // Report success
        reportJobStatus(job.jobId, 'completed', 'Job completed successfully', result);
        log(`✓ Job ${job.jobId} completed successfully`, 'SUCCESS');
        
    } catch (err) {
        log(`✗ Job ${job.jobId} failed: ${err.message}`, 'ERROR');
        reportJobStatus(job.jobId, 'failed', err.message);
    } finally {
        currentJob = null;
    }
}

// Handle job cancellation
async function handleJobCancellation(jobId) {
    if (currentJob && currentJob.jobId === jobId) {
        log(`Cancelling job ${jobId}`, 'WARN');
        // TODO: Implement container stopping logic
        currentJob = null;
    }
}

// Execute job in Docker container
async function executeJob(job) {
    const startTime = Date.now();
    
    try {
        // Pull image
        log('Pulling Docker image...');
        await pullImage(job.containerImage);
        log('✓ Image pulled');
        
        // Create container
        log('Creating container...');
        const container = await docker.createContainer({
            Image: job.containerImage,
            Cmd: job.command || null,
            HostConfig: {
                Memory: (job.requiredMemoryGb || 2) * 1024 * 1024 * 1024,
                NanoCpus: (job.requiredCpuCores || 1) * 1000000000,
                AutoRemove: false, // Keep container for log retrieval
                NetworkMode: 'bridge'
            },
            Env: job.env || [],
            WorkingDir: job.workingDir || '/app'
        });
        
        log(`✓ Container created: ${container.id.substring(0, 12)}`);
        
        // Start container
        log('Starting container...');
        await container.start();
        log('✓ Container started');
        
        // Wait for completion
        const waitResult = await container.wait();
        const exitCode = waitResult.StatusCode;
        
        // Get logs
        const stdout = await container.logs({
            stdout: true,
            stderr: false
        });
        
        const stderr = await container.logs({
            stdout: false,
            stderr: true
        });
        
        // Remove container
        try {
            await container.remove();
        } catch (err) {
            log(`Warning: Failed to remove container: ${err.message}`, 'WARN');
        }
        
        const duration = Date.now() - startTime;
        log(`Container exited with code ${exitCode} (duration: ${(duration/1000).toFixed(2)}s)`);
        
        return {
            exitCode: exitCode,
            stdout: stdout.toString('utf8'),
            stderr: stderr.toString('utf8'),
            duration: duration,
            success: exitCode === 0
        };
        
    } catch (err) {
        throw new Error(`Job execution failed: ${err.message}`);
    }
}

// Pull Docker image
function pullImage(imageName) {
    return new Promise((resolve, reject) => {
        docker.pull(imageName, (err, stream) => {
            if (err) return reject(err);
            
            let lastProgress = {};
            
            docker.modem.followProgress(
                stream,
                (err, output) => {
                    if (err) return reject(err);
                    resolve(output);
                },
                (event) => {
                    // Log progress for large downloads
                    if (event.id && event.progress) {
                        lastProgress[event.id] = event.progress;
                        
                        // Log every 10 layers
                        const completed = Object.keys(lastProgress).length;
                        if (completed % 10 === 0) {
                            log(`Pulling: ${completed} layers downloaded...`, 'DEBUG');
                        }
                    }
                }
            );
        });
    });
}

// Report job status to coordinator
function reportJobStatus(jobId, status, message, result = null) {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
        log(`Cannot report status: WebSocket not connected`, 'WARN');
        return;
    }
    
    const payload = {
        type: 'job_status',
        jobId: jobId,
        workerId: config.user_id,
        status: status,
        message: message,
        timestamp: Date.now()
    };
    
    if (result) {
        payload.result = {
            exitCode: result.exitCode,
            stdout: result.stdout?.substring(0, 10000), // Limit output size
            stderr: result.stderr?.substring(0, 10000),
            duration: result.duration
        };
    }
    
    ws.send(JSON.stringify(payload));
}

// Graceful shutdown
function shutdown(signal) {
    log(`\nReceived ${signal}, shutting down gracefully...`);
    
    stopHeartbeat();
    
    if (currentJob) {
        log(`Warning: Shutting down while job ${currentJob.jobId} is running`, 'WARN');
    }
    
    if (ws) {
        ws.send(JSON.stringify({
            type: 'unregister',
            workerId: config.user_id
        }));
        ws.close();
    }
    
    log('Worker stopped');
    process.exit(0);
}

// Signal handlers
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

// Unhandled errors
process.on('uncaughtException', (err) => {
    log(`Uncaught exception: ${err.message}`, 'ERROR');
    log(err.stack, 'ERROR');
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    log(`Unhandled rejection: ${reason}`, 'ERROR');
});

// Startup banner
console.log('\n' + '='.repeat(60));
console.log('  DistributeX Worker v1.0.0');
console.log('  Distributed Computing Network');
console.log('='.repeat(60) + '\n');

log('Worker starting...');
log(`User: ${config.email || 'unknown'}`);
log(`Install directory: ${INSTALL_DIR}`);
log(`Log file: ${LOG_FILE}`);

// Verify Docker is accessible
docker.ping()
    .then(() => {
        log('✓ Docker daemon accessible');
        
        // Get Docker info
        return docker.info();
    })
    .then((info) => {
        log(`✓ Docker version: ${info.ServerVersion}`);
        log(`✓ Containers: ${info.Containers} (${info.ContainersRunning} running)`);
        
        // Start worker
        connect();
    })
    .catch((err) => {
        log(`✗ Docker daemon not accessible: ${err.message}`, 'ERROR');
        log('Please ensure Docker is running and you have permission to access it', 'ERROR');
        process.exit(1);
    });
