#!/bin/bash
#
# DistributeX Docker Worker Installer + Local Image Build Fallback
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
LOCAL_DOCKERFILE_URL="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-worker/main/Dockerfile"

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
    command -v docker &> /dev/null || error "Docker not installed: https://docs.docker.com/get-docker/"
    docker ps &> /dev/null || error "Docker daemon not running"
    local missing=()
    for cmd in curl jq bc uname; do
        command -v $cmd &> /dev/null || missing+=($cmd)
    done
    [ ${#missing[@]} -eq 0 ] || error "Missing required commands: ${missing[*]}"
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
        [ "$HTTP_CODE" = "200" ] && log "Using existing authentication" && return 0
        warn "Existing token expired"; rm -f "$CONFIG_DIR/token"
    fi

    echo "Choose an option:"
    echo "  1) Sign up"
    echo "  2) Login"
    while true; do
        read -p "Enter choice [1-2]: " choice < /dev/tty
        case "$choice" in 1) signup_user; break ;; 2) login_user; break ;; *) echo "Invalid choice" ;; esac
    done
}

signup_user() {
    read -p "First Name: " first_name < /dev/tty
    read -p "Last Name: " last_name < /dev/tty
    read -p "Email: " email < /dev/tty
    while true; do
        read -s -p "Password (min 8 chars): " password < /dev/tty; echo
        [ ${#password} -lt 8 ] && warn "Password too short" && continue
        read -s -p "Confirm Password: " password_confirm < /dev/tty; echo
        [ "$password" != "$password_confirm" ] && warn "Passwords do not match" && continue
        break
    done

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\"}")
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ] && error "Signup failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message')"

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ] && error "No token returned"
    echo "$API_TOKEN" > "$CONFIG_DIR/token"; chmod 600 "$CONFIG_DIR/token"
    log "Account created successfully"
}

login_user() {
    read -p "Email: " email < /dev/tty
    read -s -p "Password: " password < /dev/tty; echo
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    [ "$HTTP_CODE" != "200" ] && error "Login failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message')"

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ] && error "No token returned"
    echo "$API_TOKEN" > "$CONFIG_DIR/token"; chmod 600 "$CONFIG_DIR/token"
    log "Logged in successfully"
}

# --------------------------
# System Detection
# --------------------------
detect_system() {
    section "System Detection"
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    CPU_CORES=$(nproc 2>/dev/null || echo 4)
    RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}' 2>/dev/null || echo 8192)
    STORAGE_TOTAL=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//' 2>/dev/null || echo 100)
    DOCKER_CPU_LIMIT=$(echo "scale=1; $CPU_CORES * 0.5" | bc)
    DOCKER_RAM_LIMIT=$(echo "scale=0; $RAM_TOTAL * 0.3 / 1024" | bc)
    log "System: $OS ($ARCH)"
    log "CPU: $CPU_CORES cores (Docker limit: ${DOCKER_CPU_LIMIT} cores)"
    log "RAM: ${RAM_TOTAL}MB (Docker limit: ${DOCKER_RAM_LIMIT}GB)"
    log "Storage: ${STORAGE_TOTAL}GB"
}

# --------------------------
# Docker Setup with Fallback
# --------------------------
pull_docker_image() {
    section "Pulling Docker Image"
    info "Pulling $DOCKER_IMAGE..."
    if docker pull $DOCKER_IMAGE; then
        log "Docker image pulled successfully"
    else
        warn "Failed to pull $DOCKER_IMAGE. Building image locally..."
        mkdir -p "$CONFIG_DIR/docker-build"
        curl -sSL "$LOCAL_DOCKERFILE_URL" -o "$CONFIG_DIR/docker-build/Dockerfile"
        docker build -t $DOCKER_IMAGE "$CONFIG_DIR/docker-build"
        log "Docker image built locally as $DOCKER_IMAGE"
    fi
}

# --------------------------
# Stop Existing Container
# --------------------------
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

# --------------------------
# Start Container
# --------------------------
start_container() {
    section "Starting Docker Container"
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

    sleep 3
    docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && \
        log "Container started successfully" || \
        error "Container failed to start. Check logs: docker logs $CONTAINER_NAME"
}

# --------------------------
# Save Config
# --------------------------
save_config() {
    section "Saving Configuration"
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "version": "2.0.0-docker",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "containerName": "$CONTAINER_NAME",
  "dockerImage": "$DOCKER_IMAGE",
  "system": {"os":"$OS","arch":"$ARCH","cpuCores":$CPU_CORES,"ramTotal":$RAM_TOTAL,"storageTotal":$STORAGE_TOTAL},
  "resourceLimits":{"cpuLimit":"$DOCKER_CPU_LIMIT","memoryLimit":"${DOCKER_RAM_LIMIT}G"},
  "installedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    chmod 600 "$CONFIG_DIR/config.json"
    log "Configuration saved"
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
    section "Installation Complete! 🎉"
    echo "✅ DistributeX worker is running"
    echo "Management scripts in $CONFIG_DIR"
    echo "Dashboard: $DISTRIBUTEX_API_URL/dashboard"
}

main
