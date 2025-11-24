#!/bin/bash
# dxcloud - DistributeX CLI Wrapper (Updated for Docker)
# Manages Docker-based worker nodes

set -e

INSTALL_DIR="$HOME/.distributex"
CONFIG_FILE="$INSTALL_DIR/config.json"
DOCKER_COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Detect Docker Compose command
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    echo -e "${RED}Error: Docker Compose not found${NC}"
    echo "Install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

# ==================== WORKER COMMANDS ====================

cmd_worker_start() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Not configured. Run installation first:${NC}"
        echo "  curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/install.sh | bash"
        exit 1
    fi
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        echo -e "${RED}Docker configuration not found.${NC}"
        echo "Run setup: bash setup-docker-worker.sh"
        exit 1
    fi
    
    # Detect GPU type
    GPU_PROFILE="cpu"
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        GPU_PROFILE="nvidia"
    elif lspci 2>/dev/null | grep -iE "vga|3d" | grep -qi "amd\|radeon"; then
        GPU_PROFILE="amd"
    fi
    
    # Check if already running
    if $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps | grep -q "Up"; then
        echo -e "${YELLOW}Worker already running${NC}"
        cmd_worker_status
        exit 0
    fi
    
    echo -e "${CYAN}Starting DistributeX Worker (${GPU_PROFILE})...${NC}"
    
    cd "$INSTALL_DIR"
    $COMPOSE_CMD --profile $GPU_PROFILE up -d
    
    sleep 3
    
    if $COMPOSE_CMD ps | grep -q "Up"; then
        echo -e "${GREEN}✓ Worker started successfully${NC}"
        echo ""
        echo "Commands:"
        echo -e "  View logs: ${CYAN}dxcloud worker logs${NC}"
        echo -e "  Status:    ${CYAN}dxcloud worker status${NC}"
        echo -e "  Stop:      ${CYAN}dxcloud worker stop${NC}"
    else
        echo -e "${RED}✗ Worker failed to start${NC}"
        echo "Check logs: $COMPOSE_CMD logs"
        exit 1
    fi
}

cmd_worker_stop() {
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        echo -e "${YELLOW}Worker not configured${NC}"
        exit 0
    fi
    
    cd "$INSTALL_DIR"
    
    if ! $COMPOSE_CMD ps | grep -q "Up"; then
        echo -e "${YELLOW}Worker not running${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}Stopping worker...${NC}"
    $COMPOSE_CMD down
    
    echo -e "${GREEN}✓ Worker stopped${NC}"
}

cmd_worker_restart() {
    echo -e "${CYAN}Restarting worker...${NC}"
    cmd_worker_stop
    sleep 2
    cmd_worker_start
}

cmd_worker_status() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Not configured.${NC}"
        exit 1
    fi
    
    API_URL=$(grep -o '"apiUrl":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    WORKER_ID=$(grep -o '"workerId":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    TOKEN=$(grep -o '"authToken":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    
    # Check local Docker status
    echo -e "${CYAN}Local Status:${NC}"
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        cd "$INSTALL_DIR"
        if $COMPOSE_CMD ps | grep -q "Up"; then
            CONTAINER_NAME=$($COMPOSE_CMD ps --services | head -1)
            echo -e "  ${GREEN}✓ Container running${NC}"
            echo "  Container: $CONTAINER_NAME"
        else
            echo -e "  ${RED}✗ Container not running${NC}"
        fi
    else
        echo -e "  ${RED}✗ Not configured${NC}"
    fi
    
    echo ""
    
    # Check server status
    echo -e "${CYAN}Server Status:${NC}"
    response=$(curl -s "$API_URL/api/workers/my-worker" \
        -H "Authorization: Bearer $TOKEN" 2>/dev/null)
    
    if echo "$response" | grep -q '"success":true'; then
        status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        node_name=$(echo "$response" | grep -o '"node_name":"[^"]*"' | cut -d'"' -f4)
        cpu=$(echo "$response" | grep -o '"cpu_cores":[0-9]*' | cut -d':' -f2)
        memory=$(echo "$response" | grep -o '"memory_gb":[0-9.]*' | cut -d':' -f2)
        gpu=$(echo "$response" | grep -o '"gpu_available":[01]' | cut -d':' -f2)
        
        if [ "$status" = "online" ]; then
            echo -e "  ${GREEN}✓ Online${NC}"
        elif [ "$status" = "busy" ]; then
            echo -e "  ${YELLOW}◉ Busy${NC}"
        else
            echo -e "  ${RED}✗ Offline${NC}"
        fi
        
        if [ -n "$node_name" ]; then
            echo "  Node: $node_name"
        fi
        
        if [ -n "$cpu" ] && [ "$cpu" != "0" ]; then
            echo ""
            echo "Resources:"
            echo "  CPU: $cpu cores"
            echo "  Memory: $memory GB"
            [ "$gpu" = "1" ] && echo "  GPU: Available"
        fi
    else
        echo -e "  ${RED}✗ Could not reach server${NC}"
    fi
    
    echo ""
}

cmd_worker_logs() {
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        echo -e "${RED}Worker not configured${NC}"
        exit 1
    fi
    
    cd "$INSTALL_DIR"
    
    if [ "$1" = "-f" ] || [ "$1" = "--follow" ]; then
        echo -e "${CYAN}Streaming logs (Ctrl+C to stop)...${NC}"
        $COMPOSE_CMD logs -f
    else
        LINES="${1:-100}"
        $COMPOSE_CMD logs --tail="$LINES"
    fi
}

cmd_worker_update() {
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        echo -e "${RED}Worker not configured${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Updating worker...${NC}"
    
    cd "$INSTALL_DIR"
    
    # Pull latest image
    echo "Pulling latest image..."
    docker pull distributex-worker:latest 2>/dev/null || {
        echo "Building latest image..."
        docker build -t distributex-worker:latest .
    }
    
    # Restart with new image
    echo "Restarting with updated image..."
    cmd_worker_restart
    
    echo -e "${GREEN}✓ Worker updated${NC}"
}

# ==================== POOL COMMANDS ====================

cmd_pool_status() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Not configured.${NC}"
        exit 1
    fi
    
    API_URL=$(grep -o '"apiUrl":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    
    response=$(curl -s "$API_URL/api/pool/status")
    
    if echo "$response" | grep -q "workers"; then
        echo -e "${CYAN}Pool Status:${NC}"
        echo ""
        
        # Workers
        total=$(echo "$response" | grep -o '"total":[0-9]*' | head -1 | cut -d':' -f2)
        online=$(echo "$response" | grep -o '"online":[0-9]*' | head -1 | cut -d':' -f2)
        busy=$(echo "$response" | grep -o '"busy":[0-9]*' | cut -d':' -f2)
        
        echo "Workers:"
        echo "  Total:   $total"
        echo "  Online:  $online"
        echo "  Busy:    $busy"
        
        echo ""
        
        # Resources
        cpu_total=$(echo "$response" | grep -o '"total":[0-9]*' | sed -n '2p' | cut -d':' -f2)
        cpu_avail=$(echo "$response" | grep -o '"available":[0-9.]*' | head -1 | cut -d':' -f2)
        
        echo "Resources:"
        echo "  CPU:     $cpu_avail / $cpu_total cores available"
        
        mem_total=$(echo "$response" | grep -o '"totalGb":[0-9.]*' | head -1 | cut -d':' -f2)
        mem_avail=$(echo "$response" | grep -o '"availableGb":[0-9.]*' | head -1 | cut -d':' -f2)
        echo "  Memory:  $mem_avail / $mem_total GB available"
        
        gpu_total=$(echo "$response" | grep -o '"total":[0-9]*' | tail -1 | cut -d':' -f2)
        echo "  GPUs:    $gpu_total"
    else
        echo -e "${RED}Failed to fetch pool status${NC}"
        exit 1
    fi
    
    echo ""
}

# ==================== DIAGNOSTIC COMMANDS ====================

cmd_diagnose() {
    echo -e "${CYAN}${BOLD}DistributeX System Diagnostics${NC}"
    echo "=================================="
    echo ""
    
    # Check Docker
    echo -e "${CYAN}1. Docker Status${NC}"
    if command -v docker &> /dev/null; then
        echo -e "  ${GREEN}✓ Docker installed${NC}"
        if docker ps &> /dev/null; then
            echo -e "  ${GREEN}✓ Docker daemon running${NC}"
            docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
            echo "    Version: $docker_version"
        else
            echo -e "  ${RED}✗ Docker daemon not running${NC}"
        fi
    else
        echo -e "  ${RED}✗ Docker not installed${NC}"
    fi
    
    echo ""
    
    # Check Docker Compose
    echo -e "${CYAN}2. Docker Compose${NC}"
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Docker Compose available${NC}"
        compose_version=$($COMPOSE_CMD version --short 2>/dev/null || echo "unknown")
        echo "    Version: $compose_version"
    else
        echo -e "  ${RED}✗ Docker Compose not available${NC}"
    fi
    
    echo ""
    
    # Check GPU
    echo -e "${CYAN}3. GPU Detection${NC}"
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        echo -e "  ${GREEN}✓ NVIDIA GPU detected${NC}"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | while read line; do
            echo "    $line"
        done
    elif lspci 2>/dev/null | grep -iE "vga|3d" | grep -qi "amd\|radeon"; then
        echo -e "  ${GREEN}✓ AMD GPU detected${NC}"
        lspci | grep -iE "vga|3d" | grep -i "amd\|radeon" | head -1
    else
        echo -e "  ${YELLOW}⚠ No GPU detected (CPU-only mode)${NC}"
    fi
    
    echo ""
    
    # Check Configuration
    echo -e "${CYAN}4. Configuration${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "  ${GREEN}✓ Configuration found${NC}"
        API_URL=$(grep -o '"apiUrl":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        WORKER_ID=$(grep -o '"workerId":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        echo "    API: $API_URL"
        echo "    Worker ID: $WORKER_ID"
    else
        echo -e "  ${RED}✗ Configuration not found${NC}"
    fi
    
    echo ""
    
    # Check API Connection
    echo -e "${CYAN}5. API Connectivity${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        API_URL=$(grep -o '"apiUrl":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        if curl -sf "$API_URL/health" > /dev/null; then
            echo -e "  ${GREEN}✓ API reachable${NC}"
        else
            echo -e "  ${RED}✗ API not reachable${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠ Cannot test (no config)${NC}"
    fi
    
    echo ""
    echo "=================================="
}

# ==================== INFO COMMANDS ====================

cmd_info() {
    echo -e "${CYAN}${BOLD}DistributeX Worker Information${NC}"
    echo ""
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Not configured. Run installation first.${NC}"
        exit 1
    fi
    
    # Read config
    API_URL=$(grep -o '"apiUrl":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    WORKER_ID=$(grep -o '"workerId":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    NODE_NAME=$(grep -o '"nodeName":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    
    echo "Configuration:"
    echo "  API URL:     $API_URL"
    echo "  Worker ID:   $WORKER_ID"
    echo "  Node Name:   $NODE_NAME"
    echo ""
    
    # Docker info
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        cd "$INSTALL_DIR"
        if $COMPOSE_CMD ps | grep -q "Up"; then
            echo "Docker Status:"
            $COMPOSE_CMD ps
        fi
    fi
    
    echo ""
}

# ==================== MAIN DISPATCHER ====================

show_help() {
    echo "DistributeX CLI - Docker Worker Management"
    echo ""
    echo "Usage: dxcloud <command> [options]"
    echo ""
    echo "Worker Commands:"
    echo "  worker start              Start the worker container"
    echo "  worker stop               Stop the worker container"
    echo "  worker restart            Restart the worker"
    echo "  worker status             Check worker status"
    echo "  worker logs [-f] [lines]  View worker logs"
    echo "  worker update             Update worker to latest version"
    echo ""
    echo "Pool Commands:"
    echo "  pool status               View global pool status"
    echo ""
    echo "Diagnostic Commands:"
    echo "  diagnose                  Run system diagnostics"
    echo "  info                      Show worker information"
    echo ""
    echo "Options:"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  dxcloud worker start"
    echo "  dxcloud worker logs -f"
    echo "  dxcloud pool status"
    echo ""
}

case "${1:-help}" in
    worker)
        case "${2:-help}" in
            start) cmd_worker_start ;;
            stop) cmd_worker_stop ;;
            restart) cmd_worker_restart ;;
            status) cmd_worker_status ;;
            logs) shift 2; cmd_worker_logs "$@" ;;
            update) cmd_worker_update ;;
            *) 
                echo "Usage: dxcloud worker {start|stop|restart|status|logs|update}"
                exit 1
                ;;
        esac
        ;;
    pool)
        case "${2:-help}" in
            status) cmd_pool_status ;;
            *) 
                echo "Usage: dxcloud pool {status}"
                exit 1
                ;;
        esac
        ;;
    diagnose)
        cmd_diagnose
        ;;
    info)
        cmd_info
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'dxcloud help' for usage"
        exit 1
        ;;
esac
