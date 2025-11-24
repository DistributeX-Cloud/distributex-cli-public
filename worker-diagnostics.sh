#!/bin/bash
# worker-diagnostics.sh - Comprehensive diagnostics and fix for DistributeX worker

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}🔍 DistributeX Worker Diagnostics${NC}\n"

INSTALL_DIR="$HOME/.distributex"

# Check if directory exists
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}✗ Installation directory not found: $INSTALL_DIR${NC}"
    exit 1
fi

cd "$INSTALL_DIR"

echo -e "${YELLOW}1. Checking Docker container status...${NC}"
docker ps -a | grep distributex || echo "No DistributeX containers found"
echo ""

echo -e "${YELLOW}2. Checking container logs...${NC}"
if docker ps -a | grep -q distributex-worker; then
    docker logs --tail 50 distributex-worker-cpu 2>&1 || \
    docker logs --tail 50 distributex-worker-nvidia 2>&1 || \
    docker logs --tail 50 distributex-worker-amd 2>&1
else
    echo "No worker container found"
fi
echo ""

echo -e "${YELLOW}3. Checking configuration files...${NC}"
if [ -f "$INSTALL_DIR/config.json" ]; then
    echo "✓ config.json exists"
    # Check if required fields are present
    if grep -q "authToken" "$INSTALL_DIR/config.json" && \
       grep -q "workerId" "$INSTALL_DIR/config.json"; then
        echo "✓ Required fields present"
    else
        echo -e "${RED}✗ Missing authToken or workerId${NC}"
    fi
else
    echo -e "${RED}✗ config.json not found${NC}"
fi

if [ -f "$INSTALL_DIR/.env" ]; then
    echo "✓ .env exists"
    cat "$INSTALL_DIR/.env" | grep -v "TOKEN" | grep -v "WORKER_ID"
else
    echo -e "${RED}✗ .env not found${NC}"
fi
echo ""

echo -e "${YELLOW}4. Checking required files...${NC}"
for file in docker-compose.yml Dockerfile distributex-worker.js package.json; do
    if [ -f "$INSTALL_DIR/$file" ]; then
        echo "✓ $file exists"
    else
        echo -e "${RED}✗ $file missing${NC}"
    fi
done
echo ""

echo -e "${YELLOW}5. Testing Docker daemon...${NC}"
if docker info > /dev/null 2>&1; then
    echo "✓ Docker daemon accessible"
else
    echo -e "${RED}✗ Docker daemon not accessible${NC}"
fi
echo ""

echo -e "${YELLOW}6. Checking Node.js in container...${NC}"
if docker ps | grep -q distributex-worker; then
    CONTAINER=$(docker ps | grep distributex-worker | awk '{print $1}')
    docker exec $CONTAINER node --version 2>&1 || echo "Node.js check failed"
else
    echo "Container not running, cannot check"
fi
echo ""

echo -e "${YELLOW}7. Testing API connectivity...${NC}"
API_URL=$(grep DISTRIBUTEX_API_URL "$INSTALL_DIR/.env" | cut -d'=' -f2 || echo "https://distributex-api.distributex.workers.dev")
echo "Testing: $API_URL"
curl -s -m 5 "$API_URL/health" | head -20 || echo -e "${RED}✗ API not reachable${NC}"
echo ""

echo -e "${YELLOW}8. Checking network connectivity...${NC}"
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "✓ Internet connectivity OK"
else
    echo -e "${RED}✗ No internet connectivity${NC}"
fi
echo ""

echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}Diagnostics Complete${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}\n"

# Offer fixes
echo -e "${YELLOW}Would you like to try automatic fixes? (y/n)${NC}"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo -e "\n${CYAN}Applying fixes...${NC}\n"
    
    # Fix 1: Stop and remove existing containers
    echo "1. Cleaning up old containers..."
    docker compose down 2>/dev/null || true
    docker rm -f distributex-worker-cpu distributex-worker-nvidia distributex-worker-amd 2>/dev/null || true
    
    # Fix 2: Rebuild image
    echo "2. Rebuilding Docker image..."
    docker build -t distributex-worker:latest . --no-cache
    
    # Fix 3: Fix permissions
    echo "3. Fixing file permissions..."
    chmod +x distributex-worker.js gpu-detect.sh 2>/dev/null || true
    
    # Fix 4: Restart with proper profile
    echo "4. Detecting GPU and starting worker..."
    GPU_PROFILE="cpu"
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        GPU_PROFILE="nvidia"
    elif lspci 2>/dev/null | grep -iE "vga|3d" | grep -qi "amd\|radeon"; then
        GPU_PROFILE="amd"
    fi
    
    echo "Starting with profile: $GPU_PROFILE"
    
    if command -v docker-compose &> /dev/null; then
        docker-compose --profile $GPU_PROFILE up -d
    else
        docker compose --profile $GPU_PROFILE up -d
    fi
    
    echo ""
    echo -e "${GREEN}✓ Fixes applied${NC}\n"
    
    # Wait and check status
    sleep 5
    echo "Checking worker status..."
    if docker ps | grep -q distributex-worker; then
        echo -e "${GREEN}✓ Worker is now running!${NC}"
        docker ps | grep distributex-worker
        echo ""
        echo "View logs: docker logs -f distributex-worker-$GPU_PROFILE"
    else
        echo -e "${RED}✗ Worker still not running${NC}"
        echo "Check logs: docker logs distributex-worker-$GPU_PROFILE"
    fi
fi
