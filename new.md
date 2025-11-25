# DistributeX Self-Hosted on Raspberry Pi 4B

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│           Cloudflare DNS + Tunnel (Free Tier)           │
│                 distributex.yourdomain.com               │
└────────────────────┬────────────────────────────────────┘
                     │ (encrypted tunnel, no port forward)
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Raspberry Pi 4B (4GB RAM)                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  Cloudflared Tunnel Client                     │    │
│  │  - Zero Trust Access (no firewall changes)     │    │
│  │  - Automatic HTTPS                              │    │
│  │  - No exposed ports                             │    │
│  └────────────────┬───────────────────────────────┘    │
│                   ▼                                      │
│  ┌────────────────────────────────────────────────┐    │
│  │  Caddy Server (Reverse Proxy)                  │    │
│  │  - Load balancing                               │    │
│  │  - Auto caching                                 │    │
│  │  - Compression                                  │    │
│  └────────────┬───────────────────┬─────────────┬─┘    │
│               │                   │             │       │
│  ┌────────────▼──────┐  ┌────────▼────────┐  ┌▼────┐  │
│  │ API Server        │  │ Coordinator     │  │ Web │  │
│  │ (Fastify/Express) │  │ (WebSocket)     │  │ UI  │  │
│  │ Port 3001         │  │ Port 3002       │  │3000 │  │
│  │                   │  │                 │  │     │  │
│  │ • Auth            │  │ • Worker mgmt   │  │Next │  │
│  │ • Job queue       │  │ • Job routing   │  │ .js │  │
│  │ • Pool stats      │  │ • Heartbeats    │  │     │  │
│  └────────┬──────────┘  └─────────────────┘  └─────┘  │
│           │                                             │
│  ┌────────▼──────────────────────────────────────┐    │
│  │  SQLite Database (local file)                 │    │
│  │  /var/lib/distributex/database.db             │    │
│  │  - Users, workers, jobs, stats                │    │
│  └───────────────────────────────────────────────┘    │
│                                                         │
└─────────────────────────────────────────────────────────┘

Benefits:
✅ Unlimited requests (no Cloudflare limits)
✅ No port forwarding needed
✅ Automatic HTTPS
✅ Zero-trust security
✅ Full control over data
✅ No vendor lock-in
```

## Installation Steps

### 1. Raspberry Pi Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y \
  git \
  nodejs \
  npm \
  sqlite3 \
  docker.io \
  docker-compose

# Enable Docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Install Node.js 20 (LTS)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Verify versions
node --version   # Should be v20.x
npm --version    # Should be 10.x
docker --version # Should be 24.x
```

### 2. Install Cloudflared (Tunnel Client)

```bash
# Download and install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared-linux-arm64.deb

# Verify installation
cloudflared --version
```

### 3. Setup Cloudflare Tunnel

```bash
# Authenticate with Cloudflare
cloudflared tunnel login

# This opens a browser to authenticate
# Follow the prompts to authorize

# Create a tunnel
cloudflared tunnel create distributex

# Note the tunnel ID from output
# Save credentials to ~/.cloudflared/
```

### 4. Clone DistributeX

```bash
# Create directory
sudo mkdir -p /opt/distributex
sudo chown $USER:$USER /opt/distributex

# Clone repository
cd /opt/distributex
git clone https://github.com/YOUR_USERNAME/distributex.git .

# Install dependencies
npm install
```

### 5. Setup Database

```bash
# Create database directory
sudo mkdir -p /var/lib/distributex
sudo chown $USER:$USER /var/lib/distributex

# Initialize SQLite database
sqlite3 /var/lib/distributex/database.db < packages/api/schema.sql
```

### 6. Configure Environment

```bash
# Create .env file
cat > /opt/distributex/.env << EOF
# Server Configuration
NODE_ENV=production
PORT_API=3001
PORT_COORDINATOR=3002
PORT_FRONTEND=3000

# Database
DATABASE_PATH=/var/lib/distributex/database.db

# JWT Secret (generate: openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)

# Cloudflare Tunnel
TUNNEL_ID=your-tunnel-id-here
TUNNEL_TOKEN=your-tunnel-token-here

# Domain
DOMAIN=distributex.yourdomain.com
EOF
```

### 7. Setup Caddy (Reverse Proxy)

```bash
# Install Caddy
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy

# Create Caddyfile
sudo tee /etc/caddy/Caddyfile << 'EOF'
{
    # Global options
    admin off
    auto_https off
}

:80 {
    # API routes
    handle /api/* {
        reverse_proxy localhost:3001
    }
    
    # WebSocket coordinator
    handle /ws {
        reverse_proxy localhost:3002
    }
    
    # Health checks
    handle /health {
        reverse_proxy localhost:3001
    }
    
    # Frontend (Next.js)
    handle /* {
        reverse_proxy localhost:3000
    }
}
EOF

# Reload Caddy
sudo systemctl reload caddy
```

### 8. Configure Cloudflare Tunnel

```bash
# Create tunnel config
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << EOF
tunnel: distributex
credentials-file: /home/$USER/.cloudflared/<TUNNEL-ID>.json

ingress:
  # Send all traffic to Caddy
  - hostname: distributex.yourdomain.com
    service: http://localhost:80
  
  # Catch-all rule (required)
  - service: http_status:404
EOF
```

### 9. Create Systemd Services

#### API Service
```bash
sudo tee /etc/systemd/system/distributex-api.service << EOF
[Unit]
Description=DistributeX API Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/distributex
EnvironmentFile=/opt/distributex/.env
ExecStart=/usr/bin/node packages/api/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

#### Coordinator Service
```bash
sudo tee /etc/systemd/system/distributex-coordinator.service << EOF
[Unit]
Description=DistributeX Coordinator
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/distributex
EnvironmentFile=/opt/distributex/.env
ExecStart=/usr/bin/node packages/coordinator/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

#### Frontend Service
```bash
sudo tee /etc/systemd/system/distributex-frontend.service << EOF
[Unit]
Description=DistributeX Frontend
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/distributex/frontend
EnvironmentFile=/opt/distributex/.env
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

#### Cloudflare Tunnel Service
```bash
sudo tee /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

### 10. Start All Services

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable services (start on boot)
sudo systemctl enable distributex-api
sudo systemctl enable distributex-coordinator
sudo systemctl enable distributex-frontend
sudo systemctl enable cloudflared
sudo systemctl enable caddy

# Start services
sudo systemctl start distributex-api
sudo systemctl start distributex-coordinator
sudo systemctl start distributex-frontend
sudo systemctl start cloudflared
sudo systemctl start caddy

# Check status
sudo systemctl status distributex-api
sudo systemctl status distributex-coordinator
sudo systemctl status distributex-frontend
sudo systemctl status cloudflared
sudo systemctl status caddy
```

## Monitoring

### Check Logs
```bash
# API logs
sudo journalctl -u distributex-api -f

# Coordinator logs
sudo journalctl -u distributex-coordinator -f

# Frontend logs
sudo journalctl -u distributex-frontend -f

# Tunnel logs
sudo journalctl -u cloudflared -f

# Caddy logs
sudo journalctl -u caddy -f
```

### Check Service Health
```bash
# API health
curl http://localhost:3001/health

# Coordinator health
curl http://localhost:3002/health

# Frontend health
curl http://localhost:3000

# External access (via tunnel)
curl https://distributex.yourdomain.com/health
```

## Performance Tuning for Raspberry Pi 4B

### 1. Optimize Node.js
```bash
# Create Node.js config
cat > /opt/distributex/.node-options << EOF
--max-old-space-size=1024
--max-semi-space-size=16
EOF

# Update service files to use config
# Add to [Service] section:
# Environment="NODE_OPTIONS=--max-old-space-size=1024"
```

### 2. Enable Swap (if needed)
```bash
# Create 2GB swap file
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 3. SQLite Optimizations
```bash
# Add to your database initialization
sqlite3 /var/lib/distributex/database.db << EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;
PRAGMA temp_store = MEMORY;
EOF
```

### 4. Monitor Resources
```bash
# Install monitoring tools
sudo apt install -y htop iotop

# Watch resources
htop

# Monitor disk I/O
sudo iotop
```

## Backup Strategy

### Automated Daily Backups
```bash
# Create backup script
sudo tee /opt/distributex/backup.sh << 'EOF'
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
EOF

sudo chmod +x /opt/distributex/backup.sh

# Add to crontab (daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/distributex/backup.sh") | crontab -
```

## Capacity Estimates

### Raspberry Pi 4B (4GB RAM) Can Handle:

| Metric | Estimate |
|--------|----------|
| **Concurrent Workers** | 50-100 active |
| **Requests/Second** | ~50-100 RPS |
| **Database Size** | Up to 10GB before slowdown |
| **WebSocket Connections** | 500-1000 concurrent |
| **Daily Requests** | **Unlimited** (hardware limited) |

### Scaling Tips:

1. **Database**: Move to PostgreSQL on external drive if SQLite slows down
2. **Workers**: Add more Pi devices as coordinator nodes
3. **Frontend**: Use Cloudflare CDN for static assets
4. **API**: Add Redis cache for hot data

## Security Considerations

### 1. Firewall (UFW)
```bash
# No need to open ports (Cloudflare Tunnel handles it)
# But you can restrict local access:
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 127.0.0.1
sudo ufw enable
```

### 2. Fail2Ban
```bash
# Install
sudo apt install fail2ban

# Configure for API protection
sudo tee /etc/fail2ban/jail.local << EOF
[distributex-api]
enabled = true
port = 3001
filter = distributex-api
logpath = /var/log/syslog
maxretry = 5
findtime = 600
bantime = 3600
EOF
```

### 3. Regular Updates
```bash
# Create update script
sudo tee /opt/distributex/update.sh << 'EOF'
#!/bin/bash
cd /opt/distributex
git pull
npm install
sudo systemctl restart distributex-api
sudo systemctl restart distributex-coordinator
sudo systemctl restart distributex-frontend
EOF

sudo chmod +x /opt/distributex/update.sh
```

## Troubleshooting

### Issue: Tunnel not connecting
```bash
# Check tunnel status
cloudflared tunnel info distributex

# Test connection
cloudflared tunnel run distributex

# Check DNS
nslookup distributex.yourdomain.com
```

### Issue: High memory usage
```bash
# Check what's using memory
sudo ps aux --sort=-%mem | head -10

# Restart services
sudo systemctl restart distributex-*
```

### Issue: Slow responses
```bash
# Check database locks
sqlite3 /var/lib/distributex/database.db "PRAGMA wal_checkpoint;"

# Monitor API performance
curl -w "@curl-format.txt" -o /dev/null -s https://distributex.yourdomain.com/api/pool/status
```

## Cost Analysis

### One-Time Costs:
- Raspberry Pi 4B (4GB): $55
- MicroSD Card (64GB): $15
- Power Supply: $10
- Case: $10
- **Total: ~$90**

### Monthly Costs:
- Electricity: ~$2-3/month
- Cloudflare: $0 (free tier)
- Domain: ~$12/year = $1/month
- **Total: ~$3-4/month**

### Savings vs Cloudflare Paid:
- No 100k request limit
- No Workers usage fees
- No D1 database charges
- No Pages bandwidth charges

## Conclusion

You now have:
✅ Self-hosted DistributeX on Raspberry Pi
✅ Cloudflare Tunnel for secure access
✅ No request limits
✅ Full control over infrastructure
✅ ~$4/month operating cost
✅ Automatic HTTPS via Cloudflare
✅ Zero-trust security model

Your Pi 4B can easily handle 50-100 concurrent workers and unlimited requests (hardware limited)!
