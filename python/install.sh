#!/bin/bash
#
# DistributeX Python SDK Installer
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/python/install.sh | bash
#

set -e

REPO_URL="https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main"
INSTALL_DIR="/tmp/distributex-python-sdk"

echo "🐍 Installing DistributeX Python SDK..."
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not found"
    echo "   Install from: https://www.python.org/downloads/"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo "✓ Found Python $PYTHON_VERSION"

# Check pip
if ! command -v pip3 &> /dev/null; then
    echo "❌ pip3 is required but not found"
    echo "   Install: python3 -m ensurepip --upgrade"
    exit 1
fi

echo "✓ Found pip3"
echo ""

# Create temporary directory
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/distributex"

# Download files
echo "📥 Downloading SDK files..."

curl -sSL "$REPO_URL/python/distributex/__init__.py" -o "$INSTALL_DIR/distributex/__init__.py"
curl -sSL "$REPO_URL/python/distributex/client.py" -o "$INSTALL_DIR/distributex/client.py"
curl -sSL "$REPO_URL/python/distributex/setup.py" -o "$INSTALL_DIR/setup.py"

# Create README
cat > "$INSTALL_DIR/README.md" << 'EOF'
# DistributeX Python SDK

Distributed computing platform for Python.

## Installation

```bash
pip install distributex
```

## Quick Start

```python
from distributex import DistributeX

dx = DistributeX(api_key="your_api_key")

# Run any Python function
def my_function(data):
    return processed_data

result = dx.run(my_function, args=(data,), workers=4)
```

## Documentation

https://distributex.io/docs
EOF

# Install
echo "📦 Installing package..."
cd "$INSTALL_DIR"

# Install in user space (no sudo required)
pip3 install --user -e .

echo ""
echo "✅ Installation Complete!"
echo ""
echo "Quick Start:"
echo "  python3 -c 'from distributex import DistributeX; print(\"SDK Ready!\")'"
echo ""
echo "Get your API key at:"
echo "  https://distributex-cloud-network.pages.dev/auth"
echo ""
echo "Documentation:"
echo "  https://distributex.io/docs"
echo ""

# Cleanup
cd /tmp
rm -rf "$INSTALL_DIR"
