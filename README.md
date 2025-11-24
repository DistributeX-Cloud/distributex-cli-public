# DistributeX - Docker-First Setup Guide

## Overview

DistributeX uses **Docker containers** for workers to ensure:
- ✅ Always-active workers (auto-restart on failures)
- ✅ Consistent environment across all platforms
- ✅ Automatic resource detection and reporting
- ✅ Real-time updates to the frontend dashboard

## Quick Start

### One-Line Installation (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/install.sh | bash
```

**This single command:**
1. ✅ Checks Docker is installed and running
2. ✅ Detects your system resources (GPU, CPU, RAM, Storage)
3. ✅ Creates your DistributeX account (or logs in)
4. ✅ Builds the worker Docker image
5. ✅ Starts the container (runs forever with auto-restart)
6. ✅ Installs `dxcloud` CLI for management
7. ✅ Registers your worker with the coordinator
8. ✅ Begins sending real-time updates to the dashboard

**Time to complete:** 2-3 minutes

**After installation:** Your worker is live and visible on [distributex.cloud](https://distributex.cloud)

### What Gets Installed

- **Docker Worker Container**: Runs 24/7, automatically restarts
- **CLI Tool** (`dxcloud`): Manage your worker
- **Configuration**: Stored in `~/.distributex/`

## System Architecture (Docker-First Design)

```
┌─────────────────────────────────────────────────────┐
│              User's Computer (24/7)                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Docker Container (restart: unless-stopped)  │  │
│  ├──────────────────────────────────────────────┤  │
│  │  ✓ Auto-starts on system boot               │  │
│  │  ✓ Detects: 8 CPU, 16GB RAM, RTX 3080       │  │
│  │  ✓ Sends heartbeat every 30 seconds         │  │
│  │  ✓ Executes jobs in isolated containers     │  │
│  └──────────────────────────────────────────────┘  │
│           ↕ WebSocket (persistent)                 │
├─────────────────────────────────────────────────────┤
│         Cloudflare Edge (Global CDN)                │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Coordinator (Durable Object + WebSocket)    │  │
│  │  ✓ Maintains connections to all workers     │  │
│  │  ✓ Routes jobs to available workers         │  │
│  └──────────────────────────────────────────────┘  │
│           ↕                                         │
│  ┌──────────────────────────────────────────────┐  │
│  │  API (Cloudflare Worker + D1 Database)       │  │
│  │  ✓ Stores worker states                      │  │
│  │  ✓ Updates every 30s from heartbeats         │  │
│  │  ✓ Serves /api/pool/status                   │  │
│  └──────────────────────────────────────────────┘  │
│           ↕                                         │
│  ┌──────────────────────────────────────────────┐  │
│  │  Frontend (Next.js on Cloudflare Pages)      │  │
│  │  ✓ Polls /api/pool/status every 10s          │  │
│  │  ✓ Shows real-time worker count              │  │
│  │  ✓ Displays actual resources (CPU/RAM/GPU)   │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│         https://distributex.cloud                   │
└─────────────────────────────────────────────────────┘

Timeline:
─────────────────────────────────────────────────────►
T+0s:   User runs install script
T+2m:   Docker container built & started
T+3m:   Worker appears on homepage (Online Workers: 1)
T+5m:   Resource data populates (8 CPU, 16 GB RAM)
Forever: Automatic updates every 30s → Frontend sees changes every 10s
```

## How It Works

### 1. Worker Registration (Once)

When you run the installer:
```bash
curl -fsSL https://get.distributex.cloud | bash
```

The system:
1. **Authenticates you** → Creates account in database
2. **Detects resources** → CPU, RAM, GPU, Storage
3. **Registers worker** → Creates worker record in DB
4. **Starts container** → Docker container with auto-restart

### 2. Continuous Operation

The Docker container:
```yaml
restart: unless-stopped  # Automatically restarts if it crashes
```

- Starts on system boot
- Reconnects if network drops
- Sends heartbeat every 30 seconds
- Updates resource usage in real-time

### 3. Real-Time Updates to Frontend

**Every 30 seconds**, the worker sends:
```javascript
{
  workerId: "worker-abc123",
  status: "online",
  capabilities: {
    cpuCores: 8,
    memoryGb: 16,
    storageGb: 100,
    gpuAvailable: true,
    gpuModel: "NVIDIA RTX 3080",
    cpuUsagePercent: 45,      // Real-time
    memoryUsedGb: 8.2,        // Real-time
    dockerContainers: 3       // Real-time
  }
}
```

**Database Update**:
```sql
UPDATE worker_nodes 
SET 
  status = 'online',
  cpu_cores = 8,
  memory_gb = 16,
  storage_gb = 100,
  gpu_available = 1,
  gpu_model = 'NVIDIA RTX 3080',
  last_heartbeat = NOW()
WHERE id = 'worker-abc123'
```

**Frontend Refresh** (every 10 seconds):
```javascript
// Frontend polls /api/pool/status
const poolStatus = await fetch('/api/pool/status');
// Returns REAL data from database
{
  workers: { online: 5, total: 8 },  // From DB
  resources: {
    cpu: { total: 40, available: 28 },
    memory: { totalGb: 128, availableGb: 92 }
  }
}
```

## User Experience

### For Contributors (Share Resources)

#### Initial Setup
```bash
# 1. Run installer
curl -fsSL https://get.distributex.cloud | bash

# Interactive prompts:
Choose an option:
  1) Create new account
  2) Login to existing account

Full Name: John Doe
Email: john@example.com
Password: ********

Select Role:
  1) Contributor (share resources)  ← Select this
  2) Developer (submit jobs)
  3) Both

✓ NVIDIA GPU detected: RTX 3080 (10 GB)
✓ Docker image built
✓ Worker started successfully

Worker Status: Running in Docker
Profile: nvidia
```

#### What Happens Next

**Immediately**:
- Docker container starts
- Connects to coordinator via WebSocket
- Sends initial capabilities
- Shows as "online" in dashboard

**Ongoing** (automatic):
- Container runs 24/7
- Sends heartbeat every 30s
- Updates resource usage in real-time
- Auto-restarts if crashed
- Starts on system boot

**Dashboard Updates**:
```
Homepage: https://distributex.cloud
├─ "5 Online Workers" ← Updates every 10s
├─ "128 GB Total RAM"  ← Real data from DB
└─ Resource graphs    ← Shows your contribution
```

### For Developers (Submit Jobs)

#### Setup
```bash
# Same installer, choose "Developer" or "Both"
curl -fsSL https://get.distributex.cloud | bash

# If "Both", you contribute AND submit jobs
```

#### Submit Jobs
```bash
# Via CLI
dxcloud run python:3.11 python -c "print('Hello')"

# Via API
curl -X POST https://distributex-api.distributex.workers.dev/api/jobs/submit \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "jobName": "test",
    "containerImage": "python:3.11",
    "command": ["python", "-c", "print(\"Hello\")"],
    "requiredCpuCores": 1,
    "requiredMemoryGb": 2
  }'
```

## Management Commands

```bash
# Check worker status
dxcloud worker status
# Output:
#   Worker: worker-abc123
#   Status: Running (online)
#   Uptime: 2 days, 5 hours
#   Resources: 8 CPU, 16 GB RAM, RTX 3080

# View live logs
dxcloud worker logs -f

# Stop worker
dxcloud worker stop

# Restart worker
dxcloud worker restart

# Update to latest version
dxcloud worker update

# View global pool
dxcloud pool status
```

## Troubleshooting

### Worker Not Showing Online

```bash
# 1. Check Docker container
docker ps | grep distributex
# Should show: distributex-worker-nvidia (or cpu/amd)

# 2. Check logs
dxcloud worker logs

# 3. Verify heartbeat
# Logs should show:
# ✓ Capabilities registered with API (every 30s)

# 4. Check database
# Worker should appear in worker_nodes table with:
# - status = 'online'
# - last_heartbeat = recent timestamp
```

### Frontend Not Updating

```bash
# Frontend polls /api/pool/status every 10 seconds

# Test API manually:
curl https://distributex-api.distributex.workers.dev/api/pool/status

# Should return:
{
  "workers": {
    "online": 5,  ← Should match active workers
    "total": 8
  },
  "resources": {
    "cpu": { "total": 40 },  ← Sum of all worker CPUs
    "memory": { "totalGb": 128 }
  }
}

# If returns 0s, workers aren't sending heartbeats
```

## Key Files

```
~/.distributex/
├── config.json          # Worker credentials
├── .env                 # Docker environment
├── docker-compose.yml   # Docker configuration
├── Dockerfile          # Container image
├── logs/
│   └── worker.log      # Worker logs
└── distributex-worker.js # Worker code
```

## Auto-Start on Boot

The installer configures Docker's restart policy:

```yaml
# docker-compose.yml
services:
  worker-nvidia:
    restart: unless-stopped  # Auto-start on boot
```

This means:
- ✅ Starts when system boots
- ✅ Restarts if crashes
- ✅ Stops only when manually stopped
- ✅ Survives Docker daemon restarts

## Database Schema

### worker_nodes table
```sql
CREATE TABLE worker_nodes (
    id TEXT PRIMARY KEY,           -- Worker ID
    status TEXT,                   -- 'online', 'offline', 'busy'
    cpu_cores INTEGER,             -- Detected CPU cores
    memory_gb REAL,                -- Detected RAM
    storage_gb REAL,               -- Available storage
    gpu_available INTEGER,         -- 1 or 0
    gpu_model TEXT,                -- GPU name
    last_heartbeat TEXT,           -- Last update time
    registered_at TEXT             -- First seen
);
```

### Real-time Updates
```sql
-- Every 30 seconds from worker:
UPDATE worker_nodes 
SET 
  status = 'online',
  cpu_cores = 8,
  memory_gb = 16,
  storage_gb = 100,
  gpu_available = 1,
  gpu_model = 'RTX 3080',
  last_heartbeat = datetime('now')
WHERE id = ?
```

## Frontend Integration

### Homepage (/)
```javascript
// Polls every 10 seconds
const { data } = useQuery({
  queryKey: ['pool-status'],
  queryFn: () => fetch('/api/pool/status'),
  refetchInterval: 10000  // 10 seconds
});

// Shows REAL data:
<div>Online Workers: {data.workers.online}</div>
<div>Total CPU: {data.resources.cpu.total}</div>
```

### Dashboard (/dashboard)
```javascript
// Real-time worker list
const { data: workers } = useQuery({
  queryKey: ['workers'],
  queryFn: () => fetch('/api/workers'),
  refetchInterval: 5000  // 5 seconds
});

// Shows each worker:
workers.map(w => (
  <div>
    {w.node_name}
    <Status online={w.status === 'online'} />
    <Resources cpu={w.cpu_cores} ram={w.memory_gb} />
  </div>
))
```

## Summary

1. **User installs once** → Docker container auto-starts
2. **Container runs 24/7** → Sends heartbeat every 30s
3. **Database stays updated** → Real resource data
4. **Frontend polls API** → Shows live status every 10s

**No manual intervention needed after setup!**
