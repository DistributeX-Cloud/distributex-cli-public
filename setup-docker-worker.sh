#!/bin/bash
# setup-docker-worker.sh - Automated Docker Worker Setup

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔══════════════════════════════════════════════════╗
║                                                  ║
║     DistributeX Docker Worker Setup              ║
║                                                  ║
╚══════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

# Check Docker
echo -e "${BOLD}Checking requirements...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    echo "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "${GREEN}✓ Docker installed${NC}"

if ! docker ps &> /dev/null; then
    echo -e "${RED}✗ Docker daemon not running${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker running${NC}"

# Check Docker Compose
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}✗ Docker Compose not found${NC}"
    echo "Install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi
echo -e "${GREEN}✓ Docker Compose installed${NC}"

# Detect GPU
echo ""
echo -e "${BOLD}Detecting GPU...${NC}"
GPU_TYPE="cpu"
GPU_DETECTED=false

# Check NVIDIA
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    GPU_TYPE="nvidia"
    GPU_DETECTED=true
    GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    echo -e "${GREEN}✓ NVIDIA GPU detected: $GPU_INFO${NC}"
    
    # Check NVIDIA Container Toolkit
    if ! docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi &> /dev/null; then
        echo -e "${YELLOW}⚠ NVIDIA Container Toolkit not configured${NC}"
        echo ""
        echo "Install NVIDIA Container Toolkit:"
        echo "  https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
        echo ""
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
elif lspci 2>/dev/null | grep -iE "vga|3d|display" | grep -qi "amd\|radeon"; then
    GPU_TYPE="amd"
    GPU_DETECTED=true
    GPU_INFO=$(lspci | grep -iE "vga|3d" | grep -i "amd" | head -1 | grep -oP ':\s*\K.*')
    echo -e "${GREEN}✓ AMD GPU detected: $GPU_INFO${NC}"
    echo -e "${YELLOW}  Note: AMD GPU support requires ROCm${NC}"
else
    echo -e "${YELLOW}⚠ No GPU detected, will run CPU-only${NC}"
fi

# Get credentials
echo ""
echo -e "${BOLD}Authentication${NC}\n"

# Check if .env exists
if [ -f .env ]; then
    echo -e "${YELLOW}Found existing .env file${NC}"
    read -p "Use existing configuration? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        source .env
        if [ -n "$AUTH_TOKEN" ] && [ -n "$WORKER_ID" ]; then
            echo -e "${GREEN}✓ Using existing credentials${NC}"
        else
            echo -e "${RED}✗ Invalid .env file${NC}"
            exit 1
        fi
    else
        rm .env
    fi
fi

# Get new credentials if needed
if [ ! -f .env ]; then
    echo "Choose an option:"
    echo "  1) Create new account"
    echo "  2) Login to existing account"
    echo ""
    read -p "Choice [1-2]: " auth_choice
    
    API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"
    
    if [ "$auth_choice" == "1" ]; then
        # Signup
        read -p "Full Name: " name
        read -p "Email: " email
        read -sp "Password: " password
        echo ""
        echo ""
        echo "Select Role:"
        echo "  1) Contributor (share resources)"
        echo "  2) Developer (submit jobs)"
        echo "  3) Both"
        read -p "Choice [1-3]: " role_choice
        
        case $role_choice in
            1) role="contributor" ;;
            2) role="developer" ;;
            3) role="both" ;;
            *) echo "Invalid choice"; exit 1 ;;
        esac
        
        response=$(curl -s -X POST "$API_URL/api/auth/signup" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$name\",\"email\":\"$email\",\"password\":\"$password\",\"role\":\"$role\"}")
    else
        # Login
        read -p "Email: " email
        read -sp "Password: " password
        echo ""
        
        response=$(curl -s -X POST "$API_URL/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    fi
    
    # Parse response
    if echo "$response" | grep -q '"success":true'; then
        AUTH_TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        WORKER_ID=$(echo "$response" | grep -o '"workerId":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$WORKER_ID" ]; then
            # Create worker if needed
            echo "Registering worker..."
            worker_response=$(curl -s -X POST "$API_URL/api/workers/register" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $AUTH_TOKEN" \
                -d "{\"nodeName\":\"$(hostname)-docker\",\"cpuCores\":1,\"memoryGb\":1}")
            
            WORKER_ID=$(echo "$worker_response" | grep -o '"workerId":"[^"]*"' | cut -d'"' -f4)
        fi
        
        # Save to .env
        cat > .env << EOF
AUTH_TOKEN=$AUTH_TOKEN
WORKER_ID=$WORKER_ID
NODE_NAME=$(hostname)-docker-$GPU_TYPE
DISTRIBUTEX_API_URL=$API_URL
DISTRIBUTEX_COORDINATOR_URL=\${DISTRIBUTEX_COORDINATOR_URL:-wss://distributex-coordinator.distributex.workers.dev/ws}
ENABLE_GPU=$GPU_DETECTED
GPU_TYPE=$GPU_TYPE
EOF
        
        echo -e "${GREEN}✓ Credentials saved to .env${NC}"
    else
        error=$(echo "$response" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        echo -e "${RED}✗ Authentication failed: ${error:-Unknown error}${NC}"
        exit 1
    fi
fi

# Build and start worker
echo ""
echo -e "${BOLD}Building Docker image...${NC}"
docker build -t distributex-worker:latest .

echo ""
echo -e "${BOLD}Starting worker...${NC}"

if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

$COMPOSE_CMD --profile $GPU_TYPE up -d

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║                                                  ║${NC}"
echo -e "${GREEN}${BOLD}║          ✅  Worker Started Successfully!        ║${NC}"
echo -e "${GREEN}${BOLD}║                                                  ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Worker Type: $GPU_TYPE"
echo "Container: distributex-worker-$GPU_TYPE"
echo ""
echo "Commands:"
echo -e "  ${CYAN}View logs:${NC}     $COMPOSE_CMD logs -f"
echo -e "  ${CYAN}Stop worker:${NC}   $COMPOSE_CMD --profile $GPU_TYPE down"
echo -e "  ${CYAN}Restart:${NC}       $COMPOSE_CMD --profile $GPU_TYPE restart"
echo -e "  ${CYAN}Status:${NC}        docker ps | grep distributex"
echo ""
