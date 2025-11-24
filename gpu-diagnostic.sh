#!/bin/bash
# GPU Diagnostic Script for DistributeX
# Tests GPU availability and Docker GPU access

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔══════════════════════════════════════════════════╗
║                                                  ║
║          GPU Diagnostic Tool                     ║
║                                                  ║
╚══════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

echo -e "${BOLD}System Information${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OS: $(uname -s)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo ""

# ==================== NVIDIA DETECTION ====================
echo -e "${BOLD}NVIDIA GPU Detection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Step 1: Check nvidia-smi
echo -e "${BLUE}[1/5] Checking nvidia-smi command...${NC}"
if command -v nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓ nvidia-smi found at: $(which nvidia-smi)${NC}"
else
    echo -e "${RED}✗ nvidia-smi not found${NC}"
    echo "  Install NVIDIA drivers: https://www.nvidia.com/download/index.aspx"
    NVIDIA_AVAILABLE=false
fi

# Step 2: Test nvidia-smi execution
if [ "$NVIDIA_AVAILABLE" != false ]; then
    echo -e "\n${BLUE}[2/5] Testing nvidia-smi execution...${NC}"
    if nvidia-smi &> /dev/null; then
        echo -e "${GREEN}✓ nvidia-smi executed successfully${NC}"
        
        # Show GPU info
        echo ""
        nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv
        echo ""
        
        GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        
        echo -e "  GPU Count:      ${CYAN}$GPU_COUNT${NC}"
        echo -e "  GPU Model:      ${CYAN}$GPU_NAME${NC}"
        echo -e "  Driver Version: ${CYAN}$DRIVER_VERSION${NC}"
    else
        echo -e "${RED}✗ nvidia-smi failed to execute${NC}"
        echo "  This usually means:"
        echo "    - NVIDIA drivers are not properly installed"
        echo "    - GPU is not recognized by the system"
        NVIDIA_AVAILABLE=false
    fi
fi

# Step 3: Check Docker
if [ "$NVIDIA_AVAILABLE" != false ]; then
    echo -e "\n${BLUE}[3/5] Checking Docker installation...${NC}"
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓ Docker found at: $(which docker)${NC}"
        
        if docker ps &> /dev/null; then
            echo -e "${GREEN}✓ Docker daemon is running${NC}"
            DOCKER_VERSION=$(docker --version)
            echo -e "  Version: ${CYAN}$DOCKER_VERSION${NC}"
        else
            echo -e "${RED}✗ Docker daemon not running${NC}"
            echo "  Start Docker: sudo systemctl start docker"
            NVIDIA_AVAILABLE=false
        fi
    else
        echo -e "${RED}✗ Docker not found${NC}"
        NVIDIA_AVAILABLE=false
    fi
fi

# Step 4: Check NVIDIA Container Toolkit
if [ "$NVIDIA_AVAILABLE" != false ]; then
    echo -e "\n${BLUE}[4/5] Checking NVIDIA Container Toolkit...${NC}"
    
    # Check nvidia-container-cli
    if command -v nvidia-container-cli &> /dev/null; then
        echo -e "${GREEN}✓ nvidia-container-cli found${NC}"
        TOOLKIT_VERSION=$(nvidia-container-cli --version 2>/dev/null | head -1 || echo "unknown")
        echo -e "  Version: ${CYAN}$TOOLKIT_VERSION${NC}"
    else
        echo -e "${YELLOW}⚠ nvidia-container-cli not found${NC}"
        echo "  NVIDIA Container Toolkit may not be installed"
    fi
    
    # Check Docker daemon config
    if [ -f /etc/docker/daemon.json ]; then
        if grep -q "nvidia" /etc/docker/daemon.json; then
            echo -e "${GREEN}✓ NVIDIA runtime configured in Docker daemon${NC}"
        else
            echo -e "${YELLOW}⚠ NVIDIA runtime not found in /etc/docker/daemon.json${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ /etc/docker/daemon.json not found${NC}"
    fi
fi

# Step 5: Test Docker GPU access
if [ "$NVIDIA_AVAILABLE" != false ]; then
    echo -e "\n${BLUE}[5/5] Testing Docker GPU access...${NC}"
    echo "  Pulling nvidia/cuda:11.0-base image..."
    
    if docker pull nvidia/cuda:11.0-base &> /dev/null; then
        echo -e "${GREEN}✓ Image pulled successfully${NC}"
        
        # Test with --gpus flag (modern)
        echo ""
        echo -e "${BLUE}Testing: docker run --gpus all${NC}"
        if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi &> /tmp/gpu-test.log 2>&1; then
            echo -e "${GREEN}✓ SUCCESS: Docker can access GPU with --gpus flag${NC}"
            echo ""
            cat /tmp/gpu-test.log
            DOCKER_GPU_WORKS=true
        else
            echo -e "${RED}✗ FAILED: --gpus flag doesn't work${NC}"
            echo ""
            cat /tmp/gpu-test.log
            
            # Try legacy --runtime=nvidia
            echo ""
            echo -e "${BLUE}Testing: docker run --runtime=nvidia${NC}"
            if docker run --rm --runtime=nvidia nvidia/cuda:11.0-base nvidia-smi &> /tmp/gpu-test2.log 2>&1; then
                echo -e "${GREEN}✓ SUCCESS: Docker can access GPU with --runtime=nvidia${NC}"
                echo ""
                cat /tmp/gpu-test2.log
                DOCKER_GPU_WORKS=true
            else
                echo -e "${RED}✗ FAILED: --runtime=nvidia doesn't work${NC}"
                echo ""
                cat /tmp/gpu-test2.log
                DOCKER_GPU_WORKS=false
            fi
        fi
        
        rm -f /tmp/gpu-test.log /tmp/gpu-test2.log
    else
        echo -e "${RED}✗ Failed to pull nvidia/cuda image${NC}"
        DOCKER_GPU_WORKS=false
    fi
fi

# ==================== AMD GPU DETECTION ====================
echo -e "\n${BOLD}AMD GPU Detection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v rocm-smi &> /dev/null; then
    echo -e "${GREEN}✓ rocm-smi found${NC}"
    if rocm-smi &> /dev/null; then
        echo -e "${GREEN}✓ AMD GPU detected via ROCm${NC}"
        rocm-smi
        AMD_AVAILABLE=true
    else
        echo -e "${YELLOW}⚠ rocm-smi found but not working${NC}"
        AMD_AVAILABLE=false
    fi
elif lspci 2>/dev/null | grep -iE "vga|3d|display" | grep -qi "amd\|radeon"; then
    echo -e "${YELLOW}⚠ AMD GPU detected via lspci but ROCm not installed${NC}"
    AMD_GPU=$(lspci | grep -iE "vga|3d" | grep -i "amd" | head -1)
    echo "  $AMD_GPU"
    echo ""
    echo "  Install ROCm: https://rocmdocs.amd.com/en/latest/Installation_Guide/Installation-Guide.html"
    AMD_AVAILABLE=false
else
    echo -e "  No AMD GPU detected"
    AMD_AVAILABLE=false
fi

# ==================== SUMMARY ====================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                   SUMMARY                        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$DOCKER_GPU_WORKS" = true ]; then
    echo -e "${GREEN}${BOLD}✓ GPU is ready for DistributeX!${NC}"
    echo ""
    echo "You can now run the installation:"
    echo -e "${CYAN}  curl -fsSL https://get.distributex.cloud | bash${NC}"
    echo ""
    exit 0
elif [ "$NVIDIA_AVAILABLE" != false ] && [ "$DOCKER_GPU_WORKS" != true ]; then
    echo -e "${YELLOW}${BOLD}⚠ GPU detected but Docker cannot access it${NC}"
    echo ""
    echo -e "${BOLD}To fix this:${NC}"
    echo ""
    echo "1. Install NVIDIA Container Toolkit:"
    echo -e "${CYAN}   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg${NC}"
    echo -e "${CYAN}   curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list${NC}"
    echo ""
    echo "2. Install the toolkit:"
    echo -e "${CYAN}   sudo apt-get update${NC}"
    echo -e "${CYAN}   sudo apt-get install -y nvidia-container-toolkit${NC}"
    echo ""
    echo "3. Configure Docker:"
    echo -e "${CYAN}   sudo nvidia-ctk runtime configure --runtime=docker${NC}"
    echo -e "${CYAN}   sudo systemctl restart docker${NC}"
    echo ""
    echo "4. Test again:"
    echo -e "${CYAN}   docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi${NC}"
    echo ""
    echo "5. Once working, install DistributeX:"
    echo -e "${CYAN}   curl -fsSL https://get.distributex.cloud | bash${NC}"
    echo ""
    exit 1
else
    echo -e "${YELLOW}${BOLD}⚠ No GPU detected${NC}"
    echo ""
    echo "Your system will run in CPU-only mode."
    echo ""
    echo "You can still install DistributeX:"
    echo -e "${CYAN}  curl -fsSL https://get.distributex.cloud | bash${NC}"
    echo ""
    exit 0
fi
