#!/bin/bash
#
# DistributeX Python SDK Installer (Corrected)
# This file must be a Bash script, NOT Python.
#

set -e
set -o pipefail

echo ""
echo "██████╗ ██╗███████╗████████╗██████╗ ██╗   ██╗████████╗███████╗██╗  ██╗"
echo "██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║   ██║╚══██╔══╝██╔════╝██║ ██╔╝"
echo "██████╔╝██║█████╗     ██║   ██████╔╝██║   ██║   ██║   █████╗  █████╔╝ "
echo "██╔══██╗██║██╔══╝     ██║   ██╔══██╗██║   ██║   ██║   ██╔══╝  ██╔═██╗ "
echo "██║  ██║██║███████╗   ██║   ██║  ██║╚██████╔╝   ██║   ███████╗██║  ██╗"
echo "╚═╝  ╚═╝╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝╚═╝  ╚═╝"
echo ""

echo "📦 Installing DistributeX Python SDK…"
echo ""

# Ensure Python exists
if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ Python3 not found. Install Python 3.8+ first."
    exit 1
fi

if ! command -v pip3 >/dev/null 2>&1; then
    echo "❌ pip3 not found. Install pip first."
    exit 1
fi

PACKAGE="distributex-cloud"

echo "Installing package: $PACKAGE"
pip3 install --upgrade "$PACKAGE"

echo ""
echo "✅ DistributeX Python SDK installed successfully!"
echo ""
echo "Usage example:"
echo "-------------------------------------------"
echo "from distributex import DistributeX"
echo "dx = DistributeX(api_key='your_api_key')"
echo "result = dx.run(lambda x: x*2, args=(5,))"
echo "-------------------------------------------"
echo ""
echo "Get your API key at:"
echo "👉 https://distributex-cloud-network.pages.dev"
echo ""
