#!/bin/bash
# Script to remove old DistributeX CLI and prepare for Docker version

set -e

echo "🧹 Removing old DistributeX CLI..."

# Remove old CLI symlink
if [ -f "/usr/local/bin/dxcloud" ]; then
    echo "Removing old CLI from /usr/local/bin/dxcloud..."
    sudo rm -f /usr/local/bin/dxcloud
fi

# Remove old installation directory
if [ -d "$HOME/.distributex/bin" ]; then
    echo "Removing old worker files..."
    rm -rf "$HOME/.distributex/bin"
fi

# Keep config and logs
echo "Keeping configuration and logs..."

# Download and install new CLI
echo "Installing new Docker-based CLI..."
sudo curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/dxcloud.sh \
    -o /usr/local/bin/dxcloud

sudo chmod +x /usr/local/bin/dxcloud

echo "✅ Old CLI removed"
echo "✅ New Docker-based CLI installed"
echo ""
echo "Next steps:"
echo "  1. Run: bash setup-docker-worker.sh"
echo "  2. Start: dxcloud worker start"
