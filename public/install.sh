#!/bin/bash
#
# DistributeX Docker Worker Installer
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
#

set -e

# --------------------------
# Configuration
# --------------------------
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributex/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n━━━ $1 ━━━\n"; }

# --------------------------
# Requirements
# --------------------------
check_requirements() {
    section "Checking Requirements"
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first: https://docs.docker.com/get-docker/"
    fi
    
    # Check Docker daemon is running
    if ! docker ps &> /dev/null; then
        error "Docker daemon is not running. Please start Docker and try again."
    fi
    
    # Check for required commands
    local missing=()
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required commands: ${missing[*]}. Install with: sudo apt install ${missing[*]}"
    fi
    
    log "All requirements satisfied"
    log "Docker version: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
}

# --------------------------
# User Authentication
# --------------------------
authenticate_user() {
    section "User Authentication"

    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_DIR/token" ]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $API_TOKEN" \
            "$DISTRIBUTEX_API_URL/api/auth/user")
        if [ "$HTTP_CODE" = "200" ]; then
            log "Using existing authentication"
            return 0
        else
            warn "Existing token expired"
            rm -f "$CONFIG_DIR/token"
        fi
    fi

    echo "Choose an option:"
    echo "  1) Sign up"
    echo "  2) Login"
    local choice
    while true; do
        read -p "Enter choice [1-2]: " choice < /dev/tty
        case "$choice" in
            1) signup_user; break ;;
            2) login_user; break ;;
            *) echo "Invalid choice" ;;
        esac
    done
}

signup_user() {
    read -p "First Name: " first_name < /dev/tty
    read -p "Last Name: " last_name < /dev/tty
    read -p "Email: " email < /dev/tty
    while true; do
        read -s -p "Password (min 8 chars): " password < /dev/tty
        echo
        [ ${#password} -lt 8 ] && warn "Password too short" && continue
        read -s -p "Confirm Password: " password_confirm < /dev/tty
        echo
        [ "$password" != "$password_confirm" ] && warn "Passwords do not match" && continue
        break
    done

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ] && \
        error "Signup failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message')"

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ] && error "No token returned"

    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Account created successfully"
}

login_user() {
    read -p "Email: " email < /dev/tty
    read -s -p "Password: " password < /dev/tty
    echo

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")

    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    [ "$HTTP_CODE" != "200" ] && error "Login failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message')"

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ] && error "No token returned"

    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in successfully"
}

# --------------------------
# System Detection
# --------------------------
detect_system() {
    section "System Detection"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    # Detect CPU
    if command -v nproc &> /dev/null; then
        CPU_CORES=$(nproc)
    else
        CPU_CORES=4
    fi
    
    # Detect RAM
    if command -v free &> /dev/null; then
        RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    else
        RAM_TOTAL=8192
    fi
    
    # Detect Storage
    if command -v df &> /dev/null; then
        STORAGE_TOTAL=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//')
    else
        STORAGE_TOTAL=100
    fi
    
    # Calculate resource limits for Docker
    DOCKER_CPU_LIMIT=$(echo "scale=1; $CPU_CORES * 0.5" | bc)
    DOCKER_RAM_LIMIT=$(echo "scale=0; $RAM_TOTAL * 0.3 / 1024" | bc)
    
    log "System: $OS ($ARCH)"
    log "CPU: $CPU_CORES cores (Docker limit: ${DOCKER_CPU_LIMIT} cores)"
    log "RAM: ${RAM_TOTAL}MB (Docker limit: ${DOCKER_RAM_LIMIT}GB)"
    log "Storage: ${STORAGE_TOTAL}GB"
}

# --------------------------
# Docker Setup
# --------------------------
pull_docker_image() {
    section "Pulling Docker Image"
    
    info "Pulling $DOCKER_IMAGE..."
    if docker pull $DOCKER_IMAGE; then
        log "Docker image pulled successfully"
    else
        error "Failed to pull Docker image"
    fi
}

stop_existing_container() {
    section "Checking Existing Container"
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        warn "Existing container found, stopping and removing..."
        docker stop $CONTAINER_NAME &> /dev/null || true
        docker rm $CONTAINER_NAME &> /dev/null || true
        log "Existing container removed"
    else
        log "No existing container found"
    fi
}

create_docker_compose() {
    section "Creating Docker Compose Configuration"
    
    cat > "$CONFIG_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  distributex-worker:
    image: $DOCKER_IMAGE
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    
    environment:
      - DISTRIBUTEX_API_URL=$DISTRIBUTEX_API_URL
    
    command:
      - --api-key
      - $API_TOKEN
      - --url
      - $DISTRIBUTEX_API_URL
    
    deploy:
      resources:
        limits:
          cpus: '$DOCKER_CPU_LIMIT'
          memory: ${DOCKER_RAM_LIMIT}G
        reservations:
          cpus: '0.5'
          memory: 512M
    
    volumes:
      - $CONFIG_DIR:/config:ro
    
    healthcheck:
      test: ["CMD", "node", "-e", "console.log('ok')"]
      interval: 5m
      timeout: 10s
      retries: 3
      start_period: 30s
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    log "Docker Compose configuration created"
}

start_container() {
    section "Starting Docker Container"
    
    info "Starting DistributeX worker container..."
    
    # Run container with resource limits
    docker run -d \
        --name $CONTAINER_NAME \
        --restart unless-stopped \
        --cpus="$DOCKER_CPU_LIMIT" \
        --memory="${DOCKER_RAM_LIMIT}g" \
        -e DISTRIBUTEX_API_URL="$DISTRIBUTEX_API_URL" \
        -v "$CONFIG_DIR:/config:ro" \
        $DOCKER_IMAGE \
        --api-key "$API_TOKEN" \
        --url "$DISTRIBUTEX_API_URL"
    
    # Wait for container to start
    sleep 3
    
    if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "Container started successfully"
        
        # Show container info
        info "Container ID: $(docker ps --filter "name=$CONTAINER_NAME" --format '{{.ID}}')"
        info "Status: $(docker ps --filter "name=$CONTAINER_NAME" --format '{{.Status}}')"
    else
        error "Container failed to start. Check logs with: docker logs $CONTAINER_NAME"
    fi
}

# --------------------------
# Save Configuration
# --------------------------
save_config() {
    section "Saving Configuration"
    
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "version": "2.0.0-docker",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "containerName": "$CONTAINER_NAME",
  "dockerImage": "$DOCKER_IMAGE",
  "system": {
    "os": "$OS",
    "arch": "$ARCH",
    "cpuCores": $CPU_CORES,
    "ramTotal": $RAM_TOTAL,
    "storageTotal": $STORAGE_TOTAL
  },
  "resourceLimits": {
    "cpuLimit": "$DOCKER_CPU_LIMIT",
    "memoryLimit": "${DOCKER_RAM_LIMIT}G"
  },
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    chmod 600 "$CONFIG_DIR/config.json"
    log "Configuration saved to $CONFIG_DIR/config.json"
}

# --------------------------
# Create Management Scripts
# --------------------------
create_management_scripts() {
    section "Creating Management Scripts"
    
    # Create start script
    cat > "$CONFIG_DIR/start.sh" <<'EOF'
#!/bin/bash
docker start distributex-worker
echo "✅ DistributeX worker started"
docker ps --filter "name=distributex-worker"
EOF
    
    # Create stop script
    cat > "$CONFIG_DIR/stop.sh" <<'EOF'
#!/bin/bash
docker stop distributex-worker
echo "✅ DistributeX worker stopped"
EOF
    
    # Create restart script
    cat > "$CONFIG_DIR/restart.sh" <<'EOF'
#!/bin/bash
docker restart distributex-worker
echo "✅ DistributeX worker restarted"
docker ps --filter "name=distributex-worker"
EOF
    
    # Create logs script
    cat > "$CONFIG_DIR/logs.sh" <<'EOF'
#!/bin/bash
docker logs -f distributex-worker
EOF
    
    # Create status script
    cat > "$CONFIG_DIR/status.sh" <<'EOF'
#!/bin/bash
echo "=== Container Status ==="
docker ps --filter "name=distributex-worker" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "=== Resource Usage ==="
docker stats distributex-worker --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
EOF
    
    # Create uninstall script
    cat > "$CONFIG_DIR/uninstall.sh" <<EOF
#!/bin/bash
echo "Stopping and removing DistributeX worker..."
docker stop distributex-worker 2>/dev/null || true
docker rm distributex-worker 2>/dev/null || true
echo "✅ Container removed"
echo ""
read -p "Remove configuration files from $CONFIG_DIR? [y/N] " -n 1 -r
echo
if [[ \$REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$CONFIG_DIR"
    echo "✅ Configuration removed"
fi
EOF
    
    # Make scripts executable
    chmod +x "$CONFIG_DIR"/*.sh
    
    log "Management scripts created in $CONFIG_DIR"
}

# --------------------------
# Main Execution
# --------------------------
main() {
    clear
    echo "╔════════════════════════════════════╗"
    echo "║  DistributeX Docker Installer      ║"
    echo "╚════════════════════════════════════╝"
    echo ""

    check_requirements
    authenticate_user
    detect_system
    pull_docker_image
    stop_existing_container
    start_container
    save_config
    create_management_scripts

    section "Installation Complete! 🎉"
    echo ""
    echo "✅ DistributeX worker is running in Docker"
    echo ""
    echo "📋 Management Commands:"
    echo "   View logs:    $CONFIG_DIR/logs.sh"
    echo "   Check status: $CONFIG_DIR/status.sh"
    echo "   Restart:      $CONFIG_DIR/restart.sh"
    echo "   Stop:         $CONFIG_DIR/stop.sh"
    echo "   Start:        $CONFIG_DIR/start.sh"
    echo "   Uninstall:    $CONFIG_DIR/uninstall.sh"
    echo ""
    echo "🐳 Docker Commands:"
    echo "   docker logs $CONTAINER_NAME"
    echo "   docker stats $CONTAINER_NAME"
    echo "   docker restart $CONTAINER_NAME"
    echo ""
    echo "🌐 Dashboard: $DISTRIBUTEX_API_URL/dashboard"
    echo ""
}

main
