# DistributeX Complete Fix & Raspberry Pi Setup

## 🔧 CRITICAL FIXES NEEDED

### 1. Frontend Issues

**Problem**: Frontend imports from `@/lib/api` but file has wrong exports

**Fix `frontend/src/lib/api.ts`**:
```typescript
// Change line 16-17 from:
const headers: Record<string, string> = {

// To:
const headers: { [key: string]: string } = {
```

**Fix `frontend/src/app/page.tsx`**:
- Remove all direct API imports
- Use only `fetch()` for pool status
- File is mostly correct, just needs cleanup

### 2. Worker Optimization

**Problem**: Workers send 2,880 heartbeats/day = 288,000 for 100 workers (exceeds limit)

**Already Fixed in `distributex-worker.js`**:
- ✅ Reduced to 720 heartbeats/day per worker
- ✅ Only sends updates on significant changes
- ✅ Batched device registration

### 3. API Missing Endpoints

**Problem**: Worker calls `/api/workers/:id/heartbeat` but it doesn't exist in `packages/api/src/index.ts`

**You need to add these endpoints** (see backend setup below)

---

## 🥧 RASPBERRY PI 4B BACKEND SETUP

Your Raspberry Pi 4B can handle:
- **Unlimited worker heartbeats** (no Cloudflare limits)
- **200+ concurrent workers** (with 8GB RAM)
- **API + Coordinator + Database** all on one device

### Architecture

```
┌─────────────────────────────────────────────────────┐
│         Raspberry Pi 4B (Your Home)                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  SQLite Database (distributex.db)            │  │
│  │  - All worker states                         │  │
│  │  - User accounts                             │  │
│  │  - Job queue                                 │  │
│  └──────────────────────────────────────────────┘  │
│           ↕                    ↕                    │
│  ┌─────────────────┐  ┌─────────────────────────┐  │
│  │  API Server     │  │  WebSocket Coordinator  │  │
│  │  Port 3001      │  │  Port 3002              │  │
│  │  (Fastify)      │  │  (Fastify + WS)         │  │
│  └─────────────────┘  └─────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
           ↕                            ↕
    HTTP/REST API              WebSocket (persistent)
           ↕                            ↕
┌─────────────────┐          ┌─────────────────┐
│  Next.js        │          │  Worker Nodes   │
│  Frontend       │          │  (Docker)       │
│  Port 3000      │          │  Everywhere     │
└─────────────────┘          └─────────────────┘
```

---

## 📋 INSTALLATION STEPS

### Step 1: Prepare Raspberry Pi

```bash
# SSH into your Raspberry Pi
ssh pi@raspberrypi.local

# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Verify
node --version  # Should be v20.x
npm --version

# Install required packages
sudo npm install -g better-sqlite3 fastify @fastify/websocket @fastify/cors
```

### Step 2: Create Project Structure

```bash
# Create directory
mkdir -p ~/distributex-backend
cd ~/distributex-backend

# Create subdirectories
mkdir -p logs data
```

### Step 3: Install Backend Files

**You need to create these files on your Pi:**

1. **`~/distributex-backend/api-server.js`** (see artifact below)
2. **`~/distributex-backend/coordinator-server.js`** (see artifact below)
3. **`~/distributex-backend/package.json`** (see artifact below)
4. **`~/distributex-backend/schema.sql`** (copy from `packages/api/schema.sql`)

### Step 4: Initialize Database

```bash
cd ~/distributex-backend

# Install dependencies
npm install

# Create database
sqlite3 data/distributex.db < schema.sql

# Verify
sqlite3 data/distributex.db "SELECT name FROM sqlite_master WHERE type='table';"
```

### Step 5: Configure Systemd Services

**Create API service:**
```bash
sudo nano /etc/systemd/system/distributex-api.service
```

```ini
[Unit]
Description=DistributeX API Server
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/distributex-backend
Environment=PORT_API=3001
Environment=DATABASE_PATH=/home/pi/distributex-backend/data/distributex.db
Environment=JWT_SECRET=your-secret-key-change-this
ExecStart=/usr/bin/node api-server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Create Coordinator service:**
```bash
sudo nano /etc/systemd/system/distributex-coordinator.service
```

```ini
[Unit]
Description=DistributeX WebSocket Coordinator
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/distributex-backend
Environment=PORT_COORDINATOR=3002
Environment=DATABASE_PATH=/home/pi/distributex-backend/data/distributex.db
ExecStart=/usr/bin/node coordinator-server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Enable and start services:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable distributex-api distributex-coordinator
sudo systemctl start distributex-api distributex-coordinator

# Check status
sudo systemctl status distributex-api
sudo systemctl status distributex-coordinator
```

### Step 6: Configure Port Forwarding

**On your router**, forward these ports to your Raspberry Pi:

- **3001** → API Server (HTTP)
- **3002** → Coordinator (WebSocket)

Or use **ngrok** for testing:
```bash
# Install ngrok
curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | \
  sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null && \
  echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | \
  sudo tee /etc/apt/sources.list.d/ngrok.list && \
  sudo apt update && sudo apt install ngrok

# Configure with your token (from ngrok.com)
ngrok config add-authtoken YOUR_TOKEN

# Create tunnels (run in separate terminals)
ngrok http 3001 --region us  # API
ngrok http 3002 --region us  # Coordinator
```

### Step 7: Update Worker Install Script

**Edit `install.sh` line 48:**
```bash
# Change from:
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"

# To (use your Pi's IP or ngrok URL):
API_URL="${DISTRIBUTEX_API_URL:-http://YOUR_PI_IP:3001}"
# Or with ngrok:
# API_URL="${DISTRIBUTEX_API_URL:-https://abc123.ngrok-free.app}"
```

### Step 8: Update Frontend

**Edit `frontend/.env.local`** (create if missing):
```bash
NEXT_PUBLIC_API_URL=http://YOUR_PI_IP:3001
# Or with ngrok:
# NEXT_PUBLIC_API_URL=https://abc123.ngrok-free.app
```

---

## 🔄 MIGRATION FROM CLOUDFLARE

If you want to migrate existing workers:

1. **Export Cloudflare D1 data**:
```bash
wrangler d1 export distributex-db --remote > backup.sql
```

2. **Import to Raspberry Pi**:
```bash
scp backup.sql pi@raspberrypi.local:~/distributex-backend/
ssh pi@raspberrypi.local
cd ~/distributex-backend
sqlite3 data/distributex.db < backup.sql
```

3. **Update all workers**:
```bash
# On each worker machine:
docker stop distributex-worker
cd ~/.distributex
nano .env
# Change DISTRIBUTEX_API_URL to your Pi's IP
docker start distributex-worker
```

---

## 📊 CAPACITY ESTIMATES

**Raspberry Pi 4B (8GB) can handle:**

| Metric | Capacity |
|--------|----------|
| Concurrent workers | 200+ |
| Heartbeats/second | 50+ |
| Database size | 100GB+ (with USB SSD) |
| API requests/second | 100+ |
| WebSocket connections | 500+ |

**Optimization tips:**
- Use USB 3.0 SSD for database
- Enable swap if needed: `sudo dphys-swapfile swapfile`
- Monitor with: `htop`, `iotop`

---

## 🐛 DEBUGGING

**Check logs:**
```bash
# API logs
sudo journalctl -u distributex-api -f

# Coordinator logs
sudo journalctl -u distributex-coordinator -f

# Database queries
sqlite3 ~/distributex-backend/data/distributex.db "SELECT COUNT(*) FROM worker_nodes;"
```

**Test endpoints:**
```bash
# Health check
curl http://localhost:3001/health

# Pool status
curl http://localhost:3001/api/pool/status

# WebSocket test (requires websocat)
websocat ws://localhost:3002/ws
```

---

## 🎯 FINAL CHECKLIST

- [ ] Raspberry Pi has static IP
- [ ] Port forwarding configured (or ngrok running)
- [ ] Services running: `systemctl status distributex-*`
- [ ] Database initialized: `ls -lh data/distributex.db`
- [ ] Frontend updated: `NEXT_PUBLIC_API_URL` in `.env.local`
- [ ] Worker install script updated: `API_URL` in `install.sh`
- [ ] Test worker registration: `curl http://YOUR_PI_IP:3001/api/pool/status`

---

## 🚀 BENEFITS

✅ **No Cloudflare limits** - unlimited requests  
✅ **Full control** - no vendor lock-in  
✅ **Low cost** - just electricity  
✅ **Expandable** - add more Pis as cluster nodes  
✅ **Private** - all data stays on your network  

---

## 📁 FILES TO CREATE/UPDATE

### Delete These (Not Needed):
- `packages/api/src/index.ts` (replace with Node.js version)
- `packages/coordinator/src/index.ts` (replace with Node.js version)

### Create These (See Artifacts):
1. `~/distributex-backend/api-server.js`
2. `~/distributex-backend/coordinator-server.js`
3. `~/distributex-backend/package.json`

### Update These:
1. `install.sh` - Change API_URL
2. `frontend/.env.local` - Add NEXT_PUBLIC_API_URL
3. `packages/worker-node/distributex-worker.js` - Already optimized ✅

### Keep As-Is:
- `packages/api/schema.sql` - Database schema
- `frontend/` - All frontend files
- `Dockerfile`, `docker-compose.yml` - Worker files
- All documentation files
