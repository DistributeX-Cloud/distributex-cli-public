#!/bin/bash
set -e

echo "📦 Installing DistributeX JavaScript SDK..."

if ! command -v npm >/dev/null 2>&1; then
    echo "❌ npm required. Install from: https://nodejs.org/"
    exit 1
fi

npm install -g distributex-cloud

echo ""
echo "✅ Installation complete!"
echo ""
echo "Quick start:"
echo "  const DistributeX = require('distributex-cloud');"
echo "  const dx = new DistributeX('your_api_key');"
echo ""
echo "Get API key: https://distributex-cloud-network.pages.dev/auth"
