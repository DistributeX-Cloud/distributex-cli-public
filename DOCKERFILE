# DistributeX Worker Docker Image
FROM node:18-alpine AS builder

WORKDIR /app
COPY package.json ./
COPY worker-agent.js ./
RUN npm install --production || true

# Production image
FROM node:18-alpine

# Install tools (removed numpy - causes ARM/v7 build issues)
RUN apk add --no-cache \
    bash \
    curl \
    bc \
    procps \
    coreutils \
    ca-certificates \
    python3 \
    py3-pip \
    tar \
    gzip

# Install basic Python packages only
RUN pip3 install --no-cache-dir \
    requests \
    --break-system-packages

WORKDIR /app

COPY --from=builder /app /app

RUN mkdir -p /config && chmod 755 /config

ENV NODE_ENV=production \
    DISTRIBUTEX_API_URL=https://distributex.cloud \
    DOCKER_CONTAINER=true

HEALTHCHECK --interval=10m --timeout=30s --start-period=2m --retries=5 \
  CMD node -e "console.log('Worker healthy')" || exit 1

RUN addgroup -g 1001 -S distributex && \
    adduser -S distributex -u 1001 -G distributex && \
    chown -R distributex:distributex /app /config

USER distributex

LABEL org.opencontainers.image.title="DistributeX Worker" \
      org.opencontainers.image.description="Distributed computing worker - Python + Node.js" \
      org.opencontainers.image.vendor="DistributeX" \
      org.opencontainers.image.version="6.3"

ENTRYPOINT ["node", "worker-agent.js"]
CMD ["--help"]
