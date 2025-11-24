#!/bin/bash
# dxcloud - DistributeX CLI Management Tool
# Install: sudo curl -fsSL https://get.distributex.cloud/cli -o /usr/local/bin/dxcloud && sudo chmod +x /usr/local/bin/dxcloud

set -e

VERSION="1.0.0"
CONFIG_DIR="$HOME/.distributex"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==================== HELPER FUNCTIONS ====================

show_help() {
    cat << EOF
${BOLD}dxcloud${NC} - DistributeX CLI v${VERSION}

${BOLD}USAGE:${NC}
    dxcloud <command> [options]

${BOLD}COMMANDS:${NC}
    ${CYAN}install${NC}         Install DistributeX worker on this device
    ${CYAN}worker status${NC}   Show worker status
    ${CYAN}worker logs${NC}     View worker logs
    ${CYAN}worker start${NC}    Start worker
    ${CYAN}worker stop${NC}     Stop worker
    ${CYAN}worker restart${NC}  Restart worker
    ${CYAN}worker remove${NC}   Remove worker from this device
    ${CYAN}pool status${NC}     View global pool status
    ${CYAN}devices list${NC}    List all your devices
    ${CYAN}version${NC}         Show version
    ${CYAN}help${NC}            Show this help

${BOLD}EXAMPLES:${NC}
    # Install on a new device
    dxcloud install

    # Check worker status
    dxcloud worker status

    # View live logs
    dxcloud worker logs -f

    # See all your devices
    dxcloud devices list

${BOLD}DOCUMENTATION:${NC}
    https://docs.distributex.cloud

EOF
}

get_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}❌ Not configured. Run: dxcloud install${NC}"
        exit 1
    fi
    
    # Load config values
    AUTH_TOKEN=$(jq -r '.authToken' "$CONFIG_FILE")
    USER_ID=$(jq -r '.userId' "$CONFIG_FILE")
    WORKER_ID=$(jq -r '.workerId' "$CONFIG_FILE")
    API_URL=$(jq -r '.apiUrl' "$CONFIG_FILE")
}

# ==================== WORKER COMMANDS ====================

worker_status() {
    get_config
    
    echo -e "${BOLD}Worker Status${NC}\n"
    
    # Check if container is running
    if docker ps --format '{{.Names}}' | grep -q "^distributex-worker$"; then
        echo -e "Container: ${GREEN}Running${NC}"
        
        # Get container info
        UPTIME=$(docker inspect -f '{{.State.StartedAt}}' distributex-worker 2>/dev/null)
        if [ -n "$UPTIME" ]; then
            echo -e "Started:   $(date -d "$UPTIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$UPTIME")"
        fi
    elif docker ps -a --format '{{.Names}}' | grep -q "^distributex-worker$"; then
        echo -e "Container: ${YELLOW}Stopped${NC}"
    else
        echo -e "Container: ${RED}Not installed${NC}"
        echo ""
        echo "Run: dxcloud install"
        exit 1
    fi
    
    echo ""
    echo -e "${BOLD}Worker Details:${NC}"
    echo -e "  Worker ID: $WORKER_ID"
    
    # Get status from API
    response=$(curl -s "$API_URL/api/workers/$WORKER_ID" \
        -H "Authorization: Bearer $AUTH_TOKEN" 2>/dev/null)
    
    if echo "$response" | jq -e '.success' &> /dev/null; then
        status=$(echo "$response" | jq -r '.worker.status')
        cpu=$(echo "$response" | jq -r '.worker.cpu_cores')
        memory=$(echo "$response" | jq -r '.worker.memory_gb')
        gpu=$(echo "$response" | jq -r '.worker.gpu_available')
        last_heartbeat=$(echo "$response" | jq -r '.worker.last_heartbeat')
        
        case $status in
            "online") status_color="${GREEN}" ;;
            "offline") status_color="${RED}" ;;
            "busy") status_color="${YELLOW}" ;;
            *) status_color="${NC}" ;;
        esac
        
        echo -e "  Status:    ${status_color}${status}${NC}"
        echo -e "  CPU:       ${cpu} cores"
        echo -e "  Memory:    ${memory} GB"
        echo -e "  GPU:       $([ "$gpu" == "1" ] && echo "Yes" || echo "No")"
        
        if [ "$last_heartbeat" != "null" ]; then
            echo -e "  Last seen: $(date -d "$last_heartbeat" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$last_heartbeat")"
        fi
    else
        echo -e "  ${YELLOW}Could not fetch API status${NC}"
    fi
    
    echo ""
}

worker_logs() {
    get_config
    
    if [ "$1" == "-f" ] || [ "$1" == "--follow" ]; then
        docker logs -f distributex-worker
    else
        docker logs --tail 100 distributex-worker
    fi
}

worker_start() {
    get_config
    
    echo -e "${BLUE}Starting worker...${NC}"
    
    if docker ps --format '{{.Names}}' | grep -q "^distributex-worker$"; then
        echo -e "${YELLOW}Worker is already running${NC}"
        exit 0
    fi
    
    docker start distributex-worker
    
    sleep 2
    
    if docker ps --format '{{.Names}}' | grep -q "^distributex-worker$"; then
        echo -e "${GREEN}✓ Worker started${NC}"
    else
        echo -e "${RED}❌ Failed to start worker${NC}"
        exit 1
    fi
}

worker_stop() {
    get_config
    
    echo -e "${BLUE}Stopping worker...${NC}"
    
    docker stop distributex-worker
    
    echo -e "${GREEN}✓ Worker stopped${NC}"
}

worker_restart() {
    get_config
    
    echo -e "${BLUE}Restarting worker...${NC}"
    
    docker restart distributex-worker
    
    sleep 2
    
    if docker ps --format '{{.Names}}' | grep -q "^distributex-worker$"; then
        echo -e "${GREEN}✓ Worker restarted${NC}"
    else
        echo -e "${RED}❌ Failed to restart worker${NC}"
        exit 1
    fi
}

worker_remove() {
    get_config
    
    echo -e "${YELLOW}⚠️  This will remove the worker from this device${NC}"
    read -p "Are you sure? (yes/no) " -r
    
    if [ "$REPLY" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    echo -e "${BLUE}Removing worker...${NC}"
    
    # Stop and remove container
    docker stop distributex-worker 2>/dev/null || true
    docker rm distributex-worker 2>/dev/null || true
    
    # Remove image
    docker rmi distributex-worker:latest 2>/dev/null || true
    
    # Keep config but mark as removed
    if [ -f "$CONFIG_FILE" ]; then
        jq '. + {removed: true, removedAt: "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}✓ Worker removed from this device${NC}"
    echo ""
    echo "Your account is still active. To reinstall:"
    echo "  dxcloud install"
}

# ==================== POOL COMMANDS ====================

pool_status() {
    get_config
    
    echo -e "${BOLD}Global Pool Status${NC}\n"
    
    response=$(curl -s "$API_URL/api/pool/status")
    
    if ! echo "$response" | jq -e '.' &> /dev/null; then
        echo -e "${RED}❌ Failed to fetch pool status${NC}"
        exit 1
    fi
    
    total=$(echo "$response" | jq -r '.workers.total')
    online=$(echo "$response" | jq -r '.workers.online')
    busy=$(echo "$response" | jq -r '.workers.busy')
    
    cpu_total=$(echo "$response" | jq -r '.resources.cpu.total')
    cpu_avail=$(echo "$response" | jq -r '.resources.cpu.available')
    
    mem_total=$(echo "$response" | jq -r '.resources.memory.totalGb')
    mem_avail=$(echo "$response" | jq -r '.resources.memory.availableGb')
    
    gpu_total=$(echo "$response" | jq -r '.resources.gpu.total')
    
    echo -e "${BOLD}Workers:${NC}"
    echo -e "  Total:   $total"
    echo -e "  Online:  ${GREEN}$online${NC}"
    echo -e "  Busy:    ${YELLOW}$busy${NC}"
    
    echo ""
    echo -e "${BOLD}Resources:${NC}"
    echo -e "  CPU:     $cpu_avail / $cpu_total cores available"
    echo -e "  Memory:  $mem_avail / $mem_total GB available"
    echo -e "  GPUs:    $gpu_total"
    
    echo ""
}

# ==================== DEVICE COMMANDS ====================

devices_list() {
    get_config
    
    echo -e "${BOLD}Your Devices${NC}\n"
    
    response=$(curl -s "$API_URL/api/workers" \
        -H "Authorization: Bearer $AUTH_TOKEN")
    
    if ! echo "$response" | jq -e '.success' &> /dev/null; then
        echo -e "${RED}❌ Failed to fetch devices${NC}"
        exit 1
    fi
    
    workers=$(echo "$response" | jq -r '.workers')
    count=$(echo "$workers" | jq 'length')
    
    if [ "$count" == "0" ]; then
        echo "No devices registered"
        echo ""
        echo "Add this device: dxcloud install"
        exit 0
    fi
    
    echo "$workers" | jq -r '.[] | "[\(.status | ascii_upcase)] \(.node_name)\n  ID: \(.id)\n  CPU: \(.cpu_cores) cores, RAM: \(.memory_gb) GB\n  Last seen: \(.last_heartbeat // "Never")\n"'
}

# ==================== MAIN ====================

case "$1" in
    install)
        # Run the installation script
        curl -fsSL https://get.distributex.cloud | bash
        ;;
    
    worker)
        case "$2" in
            status) worker_status ;;
            logs) worker_logs "$3" ;;
            start) worker_start ;;
            stop) worker_stop ;;
            restart) worker_restart ;;
            remove) worker_remove ;;
            *) echo "Unknown worker command: $2"; show_help; exit 1 ;;
        esac
        ;;
    
    pool)
        case "$2" in
            status) pool_status ;;
            *) echo "Unknown pool command: $2"; show_help; exit 1 ;;
        esac
        ;;
    
    devices)
        case "$2" in
            list) devices_list ;;
            *) echo "Unknown devices command: $2"; show_help; exit 1 ;;
        esac
        ;;
    
    version)
        echo "dxcloud v${VERSION}"
        ;;
    
    help|--help|-h)
        show_help
        ;;
    
    *)
        if [ -z "$1" ]; then
            show_help
        else
            echo "Unknown command: $1"
            show_help
            exit 1
        fi
        ;;
esac
