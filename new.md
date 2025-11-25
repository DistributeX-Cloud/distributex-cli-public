# Complete Self-Hosted DistributeX Setup on Raspberry Pi 4B

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Domain Setup](#domain-setup)
3. [System Preparation](#system-preparation)
4. [File Structure](#file-structure)
5. [Installation Steps](#installation-steps)
6. [Configuration](#configuration)
7. [Worker Client Setup](#worker-client-setup)

---

## Prerequisites

### Hardware
- Raspberry Pi 4B (4GB RAM minimum)
- MicroSD card (64GB+ recommended)
- Stable internet connection
- Power supply

### Domain Requirements
- You own `distributex.cloud`
- Access to domain DNS settings

---

## Domain Setup

### Option 1: Cloudflare Tunnel (Recommended - No Port Forwarding)

**Advantages:**
- No router configuration needed
- Automatic HTTPS
- DDoS protection
- Free tier available

**Steps:**

1. **Add domain to Cloudflare** (if not already):
   - Go to cloudflare.com and add `distributex.cloud`
   - Update nameservers at your domain registrar

2. **Install Cloudflared on Pi**:
```bash
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared-linux-arm64.deb
```

3. **Authenticate**:
```bash
cloudflared tunnel login
```

4. **Create tunnel**:
```bash
cloudflared tunnel create distributex
```

5. **Configure DNS**:
```bash
# Main domain
cloudflared tunnel route dns distributex distributex.cloud

# Subdomains
cloudflared tunnel route dns distributex api.distributex.cloud
cloudflared tunnel route dns distributex coordinator.distributex.cloud
```

### Option 2: Traditional Port Forwarding

If you prefer not to use Cloudflare Tunnel:

1. **Get a static IP** or use Dynamic DNS (DuckDNS, No-IP)
2. **Configure router** to forward ports:
   - Port 80 → Pi:80 (HTTP)
   - Port 443 → Pi:443 (HTTPS)
3. **Set up Let's Encrypt** for SSL certificates
4. **Configure DNS A records**:
   - `distributex.cloud` → Your public IP
   - `api.distributex.cloud` → Your public IP
   - `coordinator.distributex.cloud` → Your public IP

---

## System Preparation

### 1. Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Install Dependencies

```bash
# Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Essential tools
sudo apt install -y \
  git \
  sqlite3 \
  build-essential \
  nginx \
  certbot \
  python3-certbot-nginx

# Verify versions
node --version   # Should be v20.x
npm --version    # Should be 10.x
```

### 3. Create Directory Structure

```bash
# Create main directory
sudo mkdir -p /opt/distributex
sudo chown $USER:$USER /opt/distributex

# Create data directories
sudo mkdir -p /var/lib/distributex
sudo mkdir -p /var/lib/distributex/logs
sudo mkdir -p /var/backups/distributex
sudo chown -R $USER:$USER /var/lib/distributex
sudo chown -R $USER:$USER /var/backups/distributex
```

---

## File Structure

Here's the complete directory structure for your self-hosted setup:

```
/opt/distributex/
├── api/
│   ├── server.js           # API server (Node.js)
│   ├── schema.sql          # Database schema
│   └── package.json        # API dependencies
├── coordinator/
│   ├── server.js           # Coordinator server (WebSocket)
│   └── package.json        # Coordinator dependencies
├── frontend/
│   ├── out/                # Built Next.js static files
│   ├── src/                # Source code
│   ├── package.json        # Frontend dependencies
│   └── next.config.js      # Next.js config
├── worker-client/
│   ├── distributex-worker.js   # Worker node client
│   ├── install.sh              # Installation script for workers
│   └── package.json            # Worker dependencies
├── scripts/
│   ├── backup.sh           # Backup script
│   ├── update.sh           # Update script
│   └── install.sh          # Main installation script
├── .env                    # Environment configuration
└── README.md               # Documentation

/var/lib/distributex/
├── database.db             # SQLite database
└── logs/                   # Application logs

/etc/nginx/
├── nginx.conf              # Main Nginx config
└── sites-available/
    └── distributex         # Site configuration
```

---

## Installation Steps

### Step 1: Clone Your Project

```bash
cd /opt/distributex
# If you have a git repo:
git clone https://github.com/YOUR_USERNAME/distributex.git .

# OR manually create the structure
mkdir -p api coordinator frontend worker-client scripts
```

### Step 2: Set Up Database

```bash
# Initialize database
sqlite3 /var/lib/distributex/database.db < api/schema.sql

# Optimize SQLite for Pi
sqlite3 /var/lib/distributex/database.db << EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;
PRAGMA temp_store = MEMORY;
EOF
```

### Step 3: Configure Environment

```bash
# Generate JWT secret
JWT_SECRET=$(openssl rand -base64 32)

# Create .env file
cat > /opt/distributex/.env << EOF
# Environment
NODE_ENV=production

# Ports
PORT_API=3001
PORT_COORDINATOR=3002
PORT_FRONTEND=3000

# Database
DATABASE_PATH=/var/lib/distributex/database.db

# Security
JWT_SECRET=${JWT_SECRET}

# Domain (update these with your actual domain)
DOMAIN=distributex.cloud
API_URL=https://api.distributex.cloud
COORDINATOR_URL=wss://coordinator.distributex.cloud
FRONTEND_URL=https://distributex.cloud

# Cloudflare Tunnel (if using)
TUNNEL_ID=your-tunnel-id-here
TUNNEL_TOKEN=your-tunnel-token-here
EOF
```

### Step 4: Install Dependencies

```bash
# API
cd /opt/distributex/api
npm install fastify @fastify/cors @fastify/websocket better-sqlite3

# Coordinator
cd /opt/distributex/coordinator
npm install fastify @fastify/cors @fastify/websocket better-sqlite3

# Frontend (build static version)
cd /opt/distributex/frontend
npm install
npm run build
# This creates /opt/distributex/frontend/out/

# Worker client
cd /opt/distributex/worker-client
npm install ws dockerode
```

### Step 5: Configure Nginx

#### If Using Cloudflare Tunnel:

Nginx only needs to route internal traffic since Cloudflare handles external access:

```bash
sudo tee /etc/nginx/sites-available/distributex << 'EOF'
# Frontend
server {
    listen 80;
    server_name localhost;
    root /opt/distributex/frontend/out;
    index index.html;
    
    location / {
        try_files $uri $uri/ $uri.html =404;
    }
}

# API
server {
    listen 3001;
    server_name localhost;
    
    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}

# Coordinator
server {
    listen 3002;
    server_name localhost;
    
    location / {
        proxy_pass http://localhost:3002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Enable site
sudo ln -s /etc/nginx/sites-available/distributex /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

#### If Using Port Forwarding:

```bash
sudo tee /etc/nginx/sites-available/distributex << 'EOF'
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name distributex.cloud api.distributex.cloud coordinator.distributex.cloud;
    return 301 https://$server_name$request_uri;
}

# Frontend
server {
    listen 443 ssl http2;
    server_name distributex.cloud;
    
    ssl_certificate /etc/letsencrypt/live/distributex.cloud/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/distributex.cloud/privkey.pem;
    
    root /opt/distributex/frontend/out;
    index index.html;
    
    location / {
        try_files $uri $uri/ $uri.html =404;
    }
}

# API
server {
    listen 443 ssl http2;
    server_name api.distributex.cloud;
    
    ssl_certificate /etc/letsencrypt/live/distributex.cloud/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/distributex.cloud/privkey.pem;
    
    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Coordinator (WebSocket)
server {
    listen 443 ssl http2;
    server_name coordinator.distributex.cloud;
    
    ssl_certificate /etc/letsencrypt/live/distributex.cloud/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/distributex.cloud/privkey.pem;
    
    location / {
        proxy_pass http://localhost:3002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
}
EOF

# Get SSL certificates
sudo certbot --nginx -d distributex.cloud -d api.distributex.cloud -d coordinator.distributex.cloud

# Enable site
sudo ln -s /etc/nginx/sites-available/distributex /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Step 6: Create Systemd Services

```bash
# API Service
sudo tee /etc/systemd/system/distributex-api.service << EOF
[Unit]
Description=DistributeX API Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/distributex/api
EnvironmentFile=/opt/distributex/.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=append:/var/lib/distributex/logs/api.log
StandardError=append:/var/lib/distributex/logs/api-error.log

[Install]
WantedBy=multi-user.target
EOF

# Coordinator Service
sudo tee /etc/systemd/system/distributex-coordinator.service << EOF
[Unit]
Description=DistributeX Coordinator
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/distributex/coordinator
EnvironmentFile=/opt/distributex/.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=append:/var/lib/distributex/logs/coordinator.log
StandardError=append:/var/lib/distributex/logs/coordinator-error.log

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

# Enable and start services
sudo systemctl enable distributex-api
sudo systemctl enable distributex-coordinator
sudo systemctl start distributex-api
sudo systemctl start distributex-coordinator

# Check status
sudo systemctl status distributex-api
sudo systemctl status distributex-coordinator
```

### Step 7: Configure Cloudflare Tunnel (if using)

```bash
# Create tunnel config
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << EOF
tunnel: distributex
credentials-file: /home/$USER/.cloudflared/<YOUR-TUNNEL-ID>.json

ingress:
  # Frontend
  - hostname: distributex.cloud
    service: http://localhost:80
  
  # API
  - hostname: api.distributex.cloud
    service: http://localhost:3001
  
  # Coordinator (WebSocket)
  - hostname: coordinator.distributex.cloud
    service: http://localhost:3002
  
  # Catch-all
  - service: http_status:404
EOF

# Install as systemd service
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared

# Check status
sudo systemctl status cloudflared
```

### Step 8: Create Backup Script

```bash
cat > /opt/distributex/scripts/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=/var/backups/distributex
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup database
sqlite3 /var/lib/distributex/database.db ".backup '$BACKUP_DIR/database_$DATE.db'"

# Backup config
cp /opt/distributex/.env $BACKUP_DIR/env_$DATE

# Keep only last 7 days
find $BACKUP_DIR -name "database_*.db" -mtime +7 -delete
find $BACKUP_DIR -name "env_*" -mtime +7 -delete

echo "Backup complete: $BACKUP_DIR/database_$DATE.db"
EOF

chmod +x /opt/distributex/scripts/backup.sh

# Add to crontab (daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/distributex/scripts/backup.sh") | crontab -
```

---

## Configuration

### Update Frontend Configuration

Edit `/opt/distributex/frontend/.env.production`:

```bash
# YOUR domain
NEXT_PUBLIC_API_URL=https://api.distributex.cloud
```

Rebuild frontend:

```bash
cd /opt/distributex/frontend
npm run build
```

### Firewall Configuration

```bash
# If using Cloudflare Tunnel (no ports needed)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# If using port forwarding
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow ssh
sudo ufw enable
```

---

## Worker Client Setup

### Create Installation Script for Workers

Create `/opt/distributex/worker-client/install.sh`:

```bash
#!/bin/bash
# This script will be hosted at https://distributex.cloud/worker-install.sh
# Users will run: curl -fsSL https://distributex.cloud/worker-install.sh | bash

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  DistributeX Worker Installation     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
    echo "   Visit: https://docs.docker.com/engine/install/"
    exit 1
fi

# Download worker client
echo -e "${YELLOW}📥 Downloading worker client...${NC}"
mkdir -p ~/.distributex
cd ~/.distributex

curl -fsSL https://api.distributex.cloud/worker/download -o distributex-worker.js
curl -fsSL https://api.distributex.cloud/worker/package.json -o package.json

# Install dependencies
npm install

# Get user credentials
echo ""
echo -e "${YELLOW}🔑 Please provide your credentials:${NC}"
read -p "Email: " email
read -sp "Password: " password
echo ""

# Authenticate
AUTH_RESPONSE=$(curl -s -X POST https://api.distributex.cloud/api/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$email\",\"password\":\"$password\"}")

TOKEN=$(echo $AUTH_RESPONSE | grep -o '"token":"[^"]*' | cut -d'"' -f4)
USER_ID=$(echo $AUTH_RESPONSE | grep -o '"userId":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo -e "${RED}❌ Authentication failed${NC}"
    exit 1
fi

# Generate worker ID
WORKER_ID="worker-$(date +%s)-$(openssl rand -hex 4)"

# Create config
cat > ~/.distributex/config.json << EOF
{
  "workerId": "$WORKER_ID",
  "authToken": "$TOKEN",
  "userId": "$USER_ID",
  "apiUrl": "https://api.distributex.cloud",
  "coordinatorUrl": "wss://coordinator.distributex.cloud",
  "nodeName": "$(hostname)",
  "maxCpuCores": null,
  "maxMemoryGb": null,
  "maxStorageGb": null,
  "enableGpu": true
}
EOF

echo -e "${GREEN}✅ Configuration saved${NC}"

# Start worker
echo ""
echo -e "${YELLOW}🚀 Starting worker...${NC}"
node distributex-worker.js &

echo ""
echo -e "${GREEN}✅ Worker started successfully!${NC}"
echo ""
echo "Your Worker ID: $WORKER_ID"
echo "Dashboard: https://distributex.cloud/dashboard"
echo ""
echo "To check status:"
echo "  curl http://localhost:3000/health"
echo ""
echo "To view logs:"
echo "  tail -f ~/.distributex/logs/*.log"
EOF

chmod +x /opt/distributex/worker-client/install.sh
```

### Host Installation Script

Add to your frontend to serve the install script:

```bash
# Copy install script to frontend public directory
cp /opt/distributex/worker-client/install.sh /opt/distributex/frontend/public/worker-install.sh
cp /opt/distributex/worker-client/distributex-worker.js /opt/distributex/frontend/public/distributex-worker.js
cp /opt/distributex/worker-client/package.json /opt/distributex/frontend/public/worker-package.json

# Rebuild frontend
cd /opt/distributex/frontend
npm run build
```

---

## Verification

### 1. Check All Services

```bash
# Service status
sudo systemctl status distributex-api
sudo systemctl status distributex-coordinator
sudo systemctl status nginx
sudo systemctl status cloudflared  # if using

# Health checks
curl http://localhost:3001/health
curl http://localhost:3002/health

# External access
curl https://distributex.cloud
curl https://api.distributex.cloud/health
```

### 2. Test Worker Installation

On another machine:

```bash
curl -fsSL https://distributex.cloud/worker-install.sh | bash
```

### 3. Check Dashboard

Visit `https://distributex.cloud` and verify:
- Frontend loads
- Can sign up/login
- Pool status shows workers
- Real-time updates work

---

## Maintenance Commands

```bash
# View logs
sudo journalctl -u distributex-api -f
sudo journalctl -u distributex-coordinator -f
tail -f /var/lib/distributex/logs/*.log

# Restart services
sudo systemctl restart distributex-api
sudo systemctl restart distributex-coordinator
sudo systemctl restart nginx

# Run backup manually
/opt/distributex/scripts/backup.sh

# Update system
sudo apt update && sudo apt upgrade -y
cd /opt/distributex/frontend && npm run build
sudo systemctl restart distributex-*
```

---

## Troubleshooting

### Workers Not Appearing

1. Check coordinator logs:
```bash
sudo journalctl -u distributex-coordinator -n 50
```

2. Verify database:
```bash
sqlite3 /var/lib/distributex/database.db "SELECT * FROM worker_nodes;"
```

3. Test WebSocket:
```bash
wscat -c wss://coordinator.distributex.cloud
```

### Frontend Not Loading

1. Check Nginx:
```bash
sudo nginx -t
sudo systemctl status nginx
```

2. Verify build:
```bash
ls -la /opt/distributex/frontend/out/
```

### API Errors

1. Check logs:
```bash
tail -f /var/lib/distributex/logs/api-error.log
```

2. Test database:
```bash
sqlite3 /var/lib/distributex/database.db "SELECT 1;"
```

---

## Security Recommendations

1. **Enable UFW firewall**
2. **Keep system updated**: `sudo apt update && sudo apt upgrade`
3. **Use strong JWT secret** (already generated)
4. **Regular backups**: Automated daily at 2 AM
5. **Monitor logs**: Check `/var/lib/distributex/logs/`
6. **Use Cloudflare Tunnel** for DDoS protection
7. **Enable fail2ban** for SSH protection

---

## Performance Tuning

### For Raspberry Pi 4B:

```bash
# Increase swap
sudo dphys-swapfile swapoff
sudo sed -i 's/CONF_SWAPSIZE=100/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
sudo dphys-swapfile setup
sudo dphys-swapfile swapon

# Optimize Node.js
echo 'NODE_OPTIONS="--max-old-space-size=1024"' | sudo tee -a /opt/distributex/.env

# Restart services
sudo systemctl restart distributex-*
```

---

## Success!

Your self-hosted DistributeX is now running at:
- **Frontend**: https://distributex.cloud
- **API**: https://api.distributex.cloud
- **Coordinator**: wss://coordinator.distributex.cloud

Users can connect workers via:
```bash
curl -fsSL https://distributex.cloud/worker-install.sh | bash
```

**Estimated capacity:**
- 50-100 concurrent workers
- Unlimited requests (hardware limited)
- ~$4/month operating cost
