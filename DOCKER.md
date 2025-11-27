# DistributeX Worker - Docker Image

Official Docker image for the DistributeX distributed computing worker agent.

## Quick Start

### 1. Get Your API Key
Sign up at [https://distributex-cloud-network.pages.dev](https://distributex-cloud-network.pages.dev) to get your API key.

### 2. Run the Worker
```bash
docker run -d \
  --name distributex-worker \
  --restart unless-stopped \
  distributexcloud/worker:latest \
  --api-key YOUR_API_KEY
```

### 3. With GPU Support (NVIDIA)
```bash
docker run -d \
  --name distributex-worker \
  --restart unless-stopped \
  --gpus all \
  distributexcloud/worker:latest \
  --api-key YOUR_API_KEY
```

## Using Docker Compose

Create a `.env` file:
```env
DISTRIBUTEX_API_KEY=your_api_key_here
```

Create `docker-compose.yml`:
```yaml
version: '3.8'
services:
  distributex-worker:
    image: distributexcloud/worker:latest
    container_name: distributex-worker
    restart: unless-stopped
    command:
      - --api-key
      - ${DISTRIBUTEX_API_KEY}
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
```

Then run:
```bash
docker-compose up -d
```

## Features

✅ Auto-detects system capabilities (CPU, RAM, GPU, Storage)  
✅ Multi-architecture support (amd64, arm64, armv7)  
✅ GPU support (NVIDIA CUDA)  
✅ Automatic resource throttling  
✅ Secure Docker isolation  
✅ Auto-restart on failure  

## Environment Variables

- `DISTRIBUTEX_API_URL` - API endpoint (default: https://distributex-cloud-network.pages.dev)
- `DOCKER_CONTAINER` - Set to `true` (automatically detected)

## Health Check

The container includes a health check that runs every 5 minutes.

## Resource Limits

Default resource allocation:
- **CPU**: 30-50% of available cores
- **RAM**: 20-30% of total memory
- **GPU**: 50% when idle (if available)
- **Storage**: 10-20% of free space

## License

MIT License - See repository for details
