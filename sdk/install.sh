#!/bin/bash
#
# DistributeX CLI SDK Installer (Universal)
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/sdk/install.sh | bash
#

set -e

REPO_URL="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main"
INSTALL_DIR="$HOME/.distributex-cli"
BIN_DIR="$HOME/.local/bin"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     DistributeX CLI SDK Installer                    ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

# Check Node.js
if ! command -v node &> /dev/null; then
    error "Node.js is required. Install from: https://nodejs.org/"
fi

NODE_VERSION=$(node --version)
log "Found Node.js $NODE_VERSION"
echo ""

# Create directories
info "Setting up installation directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# Download CLI script
info "Downloading CLI tool..."
curl -sSL "$REPO_URL/sdk/distributex-cli.js" -o "$INSTALL_DIR/distributex-cli.js"
chmod +x "$INSTALL_DIR/distributex-cli.js"

# Create wrapper script
cat > "$BIN_DIR/distributex" << 'EOF'
#!/bin/bash
node "$HOME/.distributex-cli/distributex-cli.js" "$@"
EOF

chmod +x "$BIN_DIR/distributex"

log "CLI installed to: $INSTALL_DIR"
log "Binary linked to: $BIN_DIR/distributex"

# Add to PATH if needed
SHELL_RC=""
case "$SHELL" in
  */bash) SHELL_RC="$HOME/.bashrc" ;;
  */zsh) SHELL_RC="$HOME/.zshrc" ;;
  */fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
esac

if [ -n "$SHELL_RC" ]; then
  if ! grep -q "$BIN_DIR" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# DistributeX CLI" >> "$SHELL_RC"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    info "Added to PATH in $SHELL_RC"
  fi
fi

echo ""
log "Installation Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Quick Start:"
echo ""
echo "  1. Reload your shell or run:"
echo "     source $SHELL_RC"
echo ""
echo "  2. Login to get your API key:"
echo "     distributex login"
echo ""
echo "  3. Run your first task:"
echo "     distributex run script.py --workers 2 --gpu"
echo ""
echo "  4. Check network status:"
echo "     distributex network"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Documentation: https://distributex.io/docs"
echo "Get API Key: https://distributex-cloud-network.pages.dev/auth"
echo ""

# Test installation
if command -v distributex &> /dev/null; then
  log "CLI is ready! Test with: distributex --help"
else
  info "Restart your terminal or run: source $SHELL_RC"
fi

echo ""
