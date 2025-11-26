#!/bin/bash
#
# DistributeX Uninstaller
# Removes the Docker worker and optionally all configuration
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/uninstall.sh | bash
#

set -e

# Configuration
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

echo ""
echo -e "${CYAN}DistributeX Uninstaller${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    warn "Docker not found. Worker may not be installed."
else
    # Stop and remove container
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        info "Stopping container..."
        docker stop $CONTAINER_NAME &> /dev/null || true
        
        info "Removing container..."
        docker rm $CONTAINER_NAME &> /dev/null || true
        
        log "Docker container removed"
    else
        info "No container found (may already be removed)"
    fi
    
    # Remove Docker image (optional)
    echo ""
    read -p "Remove Docker image? This will save disk space but require re-download if you reinstall. [y/N]: " remove_image < /dev/tty
    if [[ "$remove_image" =~ ^[Yy]$ ]]; then
        docker rmi distributex/worker:latest &> /dev/null || true
        log "Docker image removed"
    fi
fi

# Remove systemd service (Linux only)
if [ -f "/etc/systemd/system/distributex-worker.service" ]; then
    info "Removing systemd service..."
    sudo systemctl stop distributex-worker.service &> /dev/null || true
    sudo systemctl disable distributex-worker.service &> /dev/null || true
    sudo rm /etc/systemd/system/distributex-worker.service &> /dev/null || true
    sudo systemctl daemon-reload &> /dev/null || true
    log "Systemd service removed"
fi

# Handle configuration
echo ""
if [ -d "$CONFIG_DIR" ]; then
    read -p "Remove all configuration and data? This will delete your API token and settings. [y/N]: " remove_config < /dev/tty
    if [[ "$remove_config" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        log "Configuration removed"
    else
        info "Configuration kept at: $CONFIG_DIR"
        info "You can reinstall later without re-authenticating"
    fi
else
    info "No configuration found"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     DistributeX Uninstalled Successfully!             ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
log "Worker has been removed from your system"

if [ -d "$CONFIG_DIR" ]; then
    info "To reinstall: curl -sSL https://distributex.io/install.sh | bash"
    info "Your authentication will be preserved"
else
    info "To reinstall: curl -sSL https://distributex.io/install.sh | bash"
    info "You will need to authenticate again"
fi

echo ""
