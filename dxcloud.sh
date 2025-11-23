#!/bin/bash
# dxcloud - DistributeX CLI Wrapper
# Save this as dxcloud.sh in your repo

set -e

INSTALL_DIR="$HOME/.distributex"
CONFIG_FILE="$INSTALL_DIR/config.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Command: worker start
cmd_worker_start() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Not configured. Run installation first.${NC}"
        exit 1
    fi
    
    # Check if already running
    if [ -f "$INSTALL_DIR/worker.pid" ]; then
        pid=$(cat "$INSTALL_DIR/worker.pid")
        if ps -p $pid >/dev/null 2>&1; then
            echo -e "${YELLOW}Worker already running (PID: $pid)${NC}"
            exit 0
        fi
    fi
    
    echo -e "${CYAN}Starting DistributeX Worker...${NC}"
    
    # Start worker
    cd "$INSTALL_DIR/bin"
    node worker.js > "$INSTALL_DIR/logs/worker.log" 2>&1 &
    echo $! > "$INSTALL_DIR/worker.pid"
    
    sleep 2
    
    if ps -p $(cat "$INSTALL_DIR/worker.pid") >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Worker started (PID: $(cat "$INSTALL_DIR/worker.pid"))${NC}"
        echo ""
        echo "View logs: tail -f $INSTALL_DIR/logs/worker.log"
    else
        echo -e "${RED}✗ Worker failed to start${NC}"
        echo "Check logs: cat $INSTALL_DIR/logs/worker.log"
        exit 1
    fi
}

# Command: worker stop
cmd_worker_stop() {
    if [ ! -f "$INSTALL_DIR/worker.pid" ]; then
        echo -e "${YELLOW}Worker not running${NC}"
        exit 0
    fi
    
    pid=$(cat "$INSTALL_DIR/worker.pid")
    
    if ps -p $pid >/dev/null 2>&1; then
        echo -e "${YELLOW}Stopping worker (PID: $pid)...${NC}"
        kill $pid
        rm "$INSTALL_DIR/worker.pid"
        echo -e "${GREEN}✓ Worker stopped${NC}"
    else
        echo -e "${YELLOW}Worker not running (stale PID)${NC}"
        rm "$INSTALL_DIR/worker.pid"
    fi
}

# Command: worker status
cmd_worker_status() {
    if [ ! -f "$INSTALL_DIR/worker.pid" ]; then
        echo -e "${RED}Worker not running${NC}"
        exit 0
    fi
    
    pid=$(cat "$INSTALL_DIR/worker.pid")
    
    if ps -p $pid >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Worker running (PID: $pid)${NC}"
        echo ""
        echo "View logs: tail -f $INSTALL_DIR/logs/worker.log"
    else
        echo -e "${RED}Worker not running (stale PID)${NC}"
        rm "$INSTALL_DIR/worker.pid"
    fi
}

# Command: pool status
cmd_pool_status() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Not configured.${NC}"
        exit 1
    fi
    
    API_URL=$(grep -o '"apiUrl":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    
    response=$(curl -s "$API_URL/api/pool/status")
    
    echo -e "${CYAN}Pool Status:${NC}"
    echo "$response" | grep -o '"online":[0-9]*' | cut -d':' -f2 | xargs -I {} echo "  Online Workers: {}"
    echo "$response" | grep -o '"total":[0-9]*' | head -1 | cut -d':' -f2 | xargs -I {} echo "  Total Workers: {}"
}

# Main dispatcher
case "${1:-help}" in
    worker)
        case "${2:-help}" in
            start) cmd_worker_start ;;
            stop) cmd_worker_stop ;;
            status) cmd_worker_status ;;
            *) 
                echo "Usage: dxcloud worker {start|stop|status}"
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
    help|--help|-h)
        echo "DistributeX CLI"
        echo ""
        echo "Commands:"
        echo "  worker start   Start worker"
        echo "  worker stop    Stop worker"
        echo "  worker status  Check worker"
        echo "  pool status    Check pool"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'dxcloud help' for usage"
        exit 1
        ;;
esac
