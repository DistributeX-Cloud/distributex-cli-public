#!/bin/bash
set -e

echo "📦 Installing DistributeX Python SDK..."

if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ Python3 required. Install from: https://python.org/"
    exit 1
fi

pip3 install --upgrade distributex-cloud

echo ""
echo "✅ Installation complete!"
echo ""
echo "Quick start:"
echo "  from distributex import DistributeX"
echo "  dx = DistributeX(api_key='your_key')"
echo ""
echo "Get API key: https://distributex-cloud-network.pages.dev/auth"
