#!/bin/bash
# DistributeX CLI Tool - /usr/local/bin/dxcloud
set -e

VERSION="2.0.0"
CONFIG_DIR="$HOME/.distributex"
CONFIG_FILE="$CONFIG_DIR/config.json"
API_URL="https://distributex-api.distributex.workers.dev"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Detect docker compose command
if docker compose version &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}Error: Docker Compose not found${NC}"
    exit 1
fi

show_help() {
    cat << EOF
${BOLD}dxcloud${NC} - DistributeX CLI v${VERSION}

${BOLD}USAGE:${NC}
    dxcloud <command> [options]

${BOLD}WORKER COMMANDS:${NC}
    ${CYAN}worker status${NC}        Show worker status
    ${CYAN}worker logs${NC}          View worker logs [-f for follow]
    ${CYAN}worker start${NC}         Start worker
    ${CYAN}worker stop${NC}          Stop worker
    ${CYAN}worker restart${NC}       Restart worker
    ${CYAN}worker update${NC}        Update to latest version
    ${CYAN}worker remove${NC}        Remove worker

${BOLD}SYSTEM COMMANDS:${NC}
    ${CYAN}version${NC}              Show version
    ${CYAN}help${NC}                 Show this help

${BOLD}EXAMPLES:${NC}
    # View worker status
    dxcloud worker status

    # View live logs
    dxcloud worker logs -f

    # Restart worker
    dxcloud worker restart

EOF
}

cmd_worker() {
    local subcmd="$1"
    
    case "$subcmd" in
        status)
            if docker ps | grep -q distributex-worker; then
                echo -e "${GREEN}✓ Worker: Running${NC}"
                
                if [ -f "$CONFIG_FILE" ]; then
                    WORKER_ID=$(jq -r '.workerId' "$CONFIG_FILE")
                    echo -e "Worker ID: ${CYAN}$WORKER_ID${NC}"
                fi
                
                echo ""
                docker ps --filter "name=distributex-worker" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
            else
                echo -e "${YELLOW}✗ Worker: Not running${NC}"
            fi
            ;;
            
        logs)
            local follow="${2:-}"
            if [ "$follow" == "-f" ]; then
                docker logs -f distributex-worker
            else
                docker logs --tail 100 distributex-worker
            fi
            ;;
            
        start)
            echo -e "${BLUE}Starting worker...${NC}"
            cd "$CONFIG_DIR"
            $DOCKER_COMPOSE_CMD up -d
            echo -e "${GREEN}✓ Worker started${NC}"
            ;;
            
        stop)
            echo -e "${BLUE}Stopping worker...${NC}"
            cd "$CONFIG_DIR"
            $DOCKER_COMPOSE_CMD down
            echo -e "${GREEN}✓ Worker stopped${NC}"
            ;;
            
        restart)
            echo -e "${BLUE}Restarting worker...${NC}"
            cd "$CONFIG_DIR"
            $DOCKER_COMPOSE_CMD restart
            echo -e "${GREEN}✓ Worker restarted${NC}"
            ;;
            
        update)
            echo -e "${BLUE}Updating worker...${NC}"
            cd "$CONFIG_DIR"
            
            # Pull latest files
            echo "Downloading latest Dockerfile..."
            curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/Dockerfile -o Dockerfile
            
            echo "Downloading latest worker script..."
            curl -fsSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/packages/worker-node/distributex-worker.js -o distributex-worker.js
            
            # Rebuild and restart
            echo "Rebuilding image..."
            $DOCKER_COMPOSE_CMD build
            
            echo "Restarting container..."
            $DOCKER_COMPOSE_CMD up -d
            
            echo -e "${GREEN}✓ Worker updated${NC}"
            ;;
            
        remove)
            echo -e "${YELLOW}This will remove the worker container and image${NC}"
            read -p "Are you sure? (y/n) " confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                cd "$CONFIG_DIR"
                $DOCKER_COMPOSE_CMD down
                docker rmi distributex-worker:latest 2>/dev/null || true
                echo -e "${GREEN}✓ Worker removed${NC}"
            else
                echo "Cancelled"
            fi
            ;;
            
        *)
            echo -e "${RED}Unknown worker command: $subcmd${NC}"
            exit 1
            ;;
    esac
}

# Main
case "${1:-}" in
    worker) shift; cmd_worker "$@" ;;
    version) echo "dxcloud v$VERSION" ;;
    help|--help|-h|"") show_help ;;
    *) echo -e "${RED}Unknown command: $1${NC}"; show_help; exit 1 ;;
esac
