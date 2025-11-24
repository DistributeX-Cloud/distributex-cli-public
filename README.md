# DistributeX Docker Worker

Run a DistributeX worker node in Docker with automatic GPU detection and support for NVIDIA, AMD, and Intel GPUs.

## Features

- ✅ **Always Active**: Runs as a Docker container with auto-restart
- 🎮 **GPU Support**: Detects and uses NVIDIA, AMD, and Intel GPUs
- 📊 **Accurate Detection**: Real system resource detection from inside container
- 🔄 **Auto-Recovery**: Automatically reconnects on disconnect
- 📦 **Docker-in-Docker**: Executes jobs in isolated containers
- 🛡️ **Secure**: Isolated from host system

## GPU Support Matrix

| Vendor | Minimum Generation | Detection Method | Requirements |
|--------|-------------------|------------------|--------------|
| **NVIDIA** | Kepler (2012+) | `nvidia-smi` | NVIDIA Container Toolkit |
| **AMD** | GCN 3rd Gen (2016+) | `rocm-smi` / `lspci` | ROCm (optional) |
| **Intel** | Arc / Recent Integrated | `lspci` | Intel GPU drivers |
| **None** | N/A | N/A | CPU-only mode |

### Supported NVIDIA GPUs
- ✅ GeForce 600 series and newer (Kepler+)
- ✅ Quadro K-series and newer
- ✅ Tesla K-series and newer
- ✅ RTX 20/30/40 series
- ✅ Compute Capability 3.0+

### Supported AMD GPUs
- ✅ Radeon RX 400 series and newer (Polaris+)
- ✅ Radeon VII
- ✅ RX 5000/6000/7000 series
- ✅ Radeon Pro WX/Vega series

### Intel GPUs
- ✅ Intel Arc A-series
- ⚠️ Integrated GPUs (limited support)

## Quick Start

### Prerequisites

1. **Docker** (20.10+)
   ```bash
   # Linux
   curl -fsSL https://get.docker.com | sh
   
   # Mac
   brew install --cask docker
   ```

2. **Docker Compose**
   ```bash
   # Usually included with Docker Desktop
   docker compose version
   ```

3. **For NVIDIA GPUs**: [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
   ```bash
   # Ubuntu/Debian
   distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
   curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
   curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
   
   sudo apt-get update
   sudo apt-get install -y nvidia-docker2
   sudo systemctl restart docker
   
   # Test
   docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
   ```

4. **For AMD GPUs**: [ROCm](https://docs.amd.com/bundle/ROCm-Installation-Guide-v5.4.3/page/How_to_Install_ROCm.html) (optional)

### Installation

1. **Clone or create project directory**
   ```bash
   mkdir distributex-worker && cd distributex-worker
   ```

2. **Download files**
   ```bash
   # Download all required files
   curl -O https://raw.githubusercontent.com/yourusername/distributex/main/docker/Dockerfile
   curl -O https://raw.githubusercontent.com/yourusername/distributex/main/docker/docker-compose.yml
   curl -O https://raw.githubusercontent.com/yourusername/distributex/main/docker/setup-docker-worker.sh
   curl -O https://raw.githubusercontent.com/yourusername/distributex/main/docker/gpu-detect.sh
   curl -O https://raw.githubusercontent.com/yourusername/distributex/main/docker/distributex-worker.js
   curl -O https://raw.githubusercontent.com/yourusername/distributex/main/docker/package.json
   
   chmod +x setup-docker-worker.sh gpu-detect.sh
   ```

3. **Run setup**
   ```bash
   ./setup-docker-worker.sh
   ```

   The script will:
   - Detect your GPU automatically
   - Guide you through authentication
   - Build the Docker image
   - Start the worker container

## Manual Setup

### 1. Create `.env` file

```bash
cp .env.template .env
# Edit .env with your credentials
```

### 2. Build image

```bash
docker build -t distributex-worker:latest .
```

### 3. Start worker

**For NVIDIA GPU:**
```bash
docker compose --profile nvidia up -d
```

**For AMD GPU:**
```bash
docker compose --profile amd up -d
```

**For CPU only:**
```bash
docker compose --profile cpu up -d
```

## Usage

### View logs
```bash
docker compose logs -f
```

### Check status
```bash
docker ps | grep distributex
docker compose ps
```

### Stop worker
```bash
# Stop specific profile
docker compose --profile nvidia down

# Or stop all
docker compose down
```

### Restart worker
```bash
docker compose --profile nvidia restart
```

### Update worker
```bash
# Pull latest code
git pull

# Rebuild and restart
docker compose --profile nvidia up -d --build
```

## Resource Limits

Set resource limits in `.env`:

```bash
MAX_CPU_CORES=8          # Limit CPU cores
MAX_MEMORY_GB=16         # Limit RAM (GB)
MAX_STORAGE_GB=100       # Limit storage (GB)
```

## Troubleshooting

### GPU not detected

**NVIDIA:**
```bash
# Check NVIDIA driver
nvidia-smi

# Check Docker GPU access
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi

# If fails, reinstall NVIDIA Container Toolkit
sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker
```

**AMD:**
```bash
# Check ROCm
rocm-smi

# Check GPU via lspci
lspci | grep -i "vga\|3d\|display"
```

### Worker not connecting

1. **Check logs:**
   ```bash
   docker compose logs
   ```

2. **Verify credentials:**
   ```bash
   cat .env
   # Ensure AUTH_TOKEN and WORKER_ID are set
   ```

3. **Test API connectivity:**
   ```bash
   curl https://distributex-api.distributex.workers.dev/health
   ```

4. **Check coordinator:**
   ```bash
   curl https://distributex-coordinator.distributex.workers.dev/health
   ```

### Docker-in-Docker issues

If job execution fails:

1. **Verify Docker socket mount:**
   ```bash
   docker exec distributex-worker-nvidia ls -la /var/run/docker.sock
   ```

2. **Check permissions:**
   ```bash
   # On host
   sudo chmod 666 /var/run/docker.sock
   ```

3. **Test Docker access from inside:**
   ```bash
   docker exec distributex-worker-nvidia docker ps
   ```

### High resource usage

1. **Limit resources in docker-compose.yml:**
   ```yaml
   services:
     worker-nvidia:
       deploy:
         resources:
           limits:
             cpus: '4'
             memory: 8G
   ```

2. **Monitor usage:**
   ```bash
   docker stats distributex-worker-nvidia
   ```

## Advanced Configuration

### Custom API URL (for development)
```bash
# In .env
DISTRIBUTEX_API_URL=http://localhost:8787
DISTRIBUTEX_COORDINATOR_URL=ws://localhost:8788/ws
```

### Multiple GPUs
```yaml
# In docker-compose.yml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          device_ids: ['0', '1']  # Specific GPUs
          capabilities: [gpu]
```

### Persistent logs
```yaml
# Add to docker-compose.yml volumes
volumes:
  - ./logs:/root/.distributex/logs
```

## Architecture

```
Host Machine
├── Docker Engine
│   └── DistributeX Worker Container
│       ├── Node.js Worker Process
│       ├── GPU Detection Scripts
│       ├── Docker Client (for jobs)
│       └── WebSocket Connection
│
├── GPU Devices (/dev/nvidia*, /dev/dri)
│   └── Passed through to container
│
└── Docker Socket (/var/run/docker.sock)
    └── Mounted for job execution
```

## Security Considerations

- Worker runs in `--privileged` mode for Docker-in-Docker
- Jobs execute in isolated containers
- GPU access controlled by device permissions
- Host filesystem not accessible by default
- Network isolated unless explicitly enabled

## Performance Tips

1. **SSD for storage**: Faster job I/O
2. **Latest drivers**: Better GPU performance
3. **Adequate RAM**: At least 2x GPU VRAM for ML tasks
4. **Network**: Stable connection for coordinator
5. **Cooling**: Ensure adequate cooling for sustained workloads

## Support

- **Documentation**: https://docs.distributex.cloud
- **Issues**: https://github.com/yourusername/distributex/issues
- **Discord**: https://discord.gg/distributex

## License

MIT License - See LICENSE file for details
