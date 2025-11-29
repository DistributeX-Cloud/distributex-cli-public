#!/bin/bash
#
# DistributeX JavaScript/Node.js SDK Installer
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/javascript/install.sh | bash
#

set -e

REPO_URL="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main"
INSTALL_DIR="/tmp/distributex-js-sdk"

echo "📦 Installing DistributeX JavaScript SDK..."
echo ""

# Check Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is required but not found"
    echo "   Install from: https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node --version)
echo "✓ Found Node.js $NODE_VERSION"

# Check npm
if ! command -v npm &> /dev/null; then
    echo "❌ npm is required but not found"
    exit 1
fi

NPM_VERSION=$(npm --version)
echo "✓ Found npm $NPM_VERSION"
echo ""

# Create temporary directory
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/src"

# Download files
echo "📥 Downloading SDK files..."

curl -sSL "$REPO_URL/javascript/distributex/src/index.js" -o "$INSTALL_DIR/src/index.js"
curl -sSL "$REPO_URL/javascript/distributex/package.json" -o "$INSTALL_DIR/package.json"

# Create README
cat > "$INSTALL_DIR/README.md" << 'EOF'
# DistributeX JavaScript SDK

Distributed computing platform for Node.js.

## Installation

```bash
npm install -g distributex
```

## Quick Start

```javascript
const DistributeX = require('distributex');

const dx = new DistributeX('your_api_key');

// Run any function
const result = await dx.run((n) => {
  return Array.from({length: n}, (_, i) => i).reduce((a, b) => a + b, 0);
}, { args: [1000000] });

console.log('Result:', result);
```

## Documentation

https://distributex.io/docs
EOF

# Install globally
echo "🌍 Installing globally..."
cd "$INSTALL_DIR"

# Install dependencies first
npm install

# Link globally
npm link

echo ""
echo "✅ Installation Complete!"
echo ""
echo "Quick Start:"
echo "  node -e 'const DX = require(\"distributex\"); console.log(\"SDK Ready!\")'"
echo ""
echo "Get your API key at:"
echo "  https://distributex-cloud-network.pages.dev/auth"
echo ""
echo "Documentation:"
echo "  https://distributex.io/docs"
echo ""

# Keep installation files (don't cleanup for npm link)
echo "ℹ️  SDK installed from: $INSTALL_DIR"
echo ""
