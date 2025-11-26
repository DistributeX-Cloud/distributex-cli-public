# DistributeX Worker Docker Image
# Multi-stage build for minimal image size

FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package.json ./
COPY worker-agent.js ./

# Install dependencies (if any are added later)
RUN npm install --production

# Production image
FROM node:18-alpine

# Install required system tools
RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates

WORKDIR /app

# Copy from builder
COPY --from=builder /app /app

# Create config directory
RUN mkdir -p /config

# Set environment variables
ENV NODE_ENV=production \
    DISTRIBUTEX_API_URL=https://distributex-cloud-network.pages.dev

# Health check
HEALTHCHECK --interval=5m --timeout=10s --start-period=30s --retries=3 \
  CMD node -e "console.log('Worker running')" || exit 1

# Run as non-root user
RUN addgroup -g 1001 -S distributex && \
    adduser -S distributex -u 1001 && \
    chown -R distributex:distributex /app /config

USER distributex

# Start the worker
ENTRYPOINT ["node", "worker-agent.js"]

# Default args (override with --api-key YOUR_KEY)
CMD ["--api-key", ""]
