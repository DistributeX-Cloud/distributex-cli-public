# DistributeX Worker Node - Docker Image
# Supports NVIDIA, AMD, and Intel GPUs with accurate detection

FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    python3 \
    python3-pip \
    pciutils \
    lshw \
    dmidecode \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (to run containers from within)
RUN curl -fsSL https://get.docker.com | sh

# Install NVIDIA detection tools (optional, for GPU detection)
RUN apt-get update && apt-get install -y --no-install-recommends \
    nvidia-smi || true \
    && rm -rf /var/lib/apt/lists/*

# Install ROCm tools for AMD GPU detection (optional)
RUN apt-get update && apt-get install -y --no-install-recommends \
    rocm-smi || true \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install Node.js dependencies
RUN npm install --omit=dev --no-package-lock

# Copy worker source
COPY distributex-worker.js ./
COPY gpu-detect.sh ./

# Make scripts executable
RUN chmod +x distributex-worker.js gpu-detect.sh

# Create directories
RUN mkdir -p /root/.distributex/logs

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => { process.exit(r.statusCode === 200 ? 0 : 1); })"

# Expose health check port
EXPOSE 3000

# Run worker
CMD ["node", "distributex-worker.js"]
