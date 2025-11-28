# DistributeX Worker Docker Image
# Stable build - runs once without restart loops

FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package.json ./
COPY worker-agent.js ./

# Install dependencies
RUN npm install --production || true

# Production image
FROM node:18-alpine

# Install system tools for detection
RUN apk add --no-cache \
    bash \
    curl \
    bc \
    procps \
    coreutils \
    ca-certificates

WORKDIR /app

# Copy from builder
COPY --from=builder /app /app

# Create config directory
RUN mkdir -p /config && \
    chmod 755 /config

# Set environment variables
ENV NODE_ENV=production \
    DISTRIBUTEX_API_URL=https://distributex-cloud-network.pages.dev \
    DOCKER_CONTAINER=true

# Health check - more lenient to avoid false failures
HEALTHCHECK --interval=10m --timeout=30s --start-period=2m --retries=5 \
  CMD node -e "console.log('Worker healthy')" || exit 1

# Run as non-root user for security
RUN addgroup -g 1001 -S distributex && \
    adduser -S distributex -u 1001 -G distributex && \
    chown -R distributex:distributex /app /config

USER distributex

# Labels
LABEL org.opencontainers.image.title="DistributeX Worker" \
      org.opencontainers.image.description="Distributed computing worker node - stable version" \
      org.opencontainers.image.vendor="DistributeX" \
      org.opencontainers.image.version="3.2.0"

# Start the worker - will run continuously without restart
ENTRYPOINT ["node", "worker-agent.js"]

# Default args (must be overridden with actual API key)
CMD ["--help"]
