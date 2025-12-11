#!/bin/bash
#
# DistributeX Complete Uninstaller v3.5.0
# Safely removes DistributeX worker and optionally all configuration
#
# Usage: 
#   curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/uninstall.sh | bash
#   OR
#   ~/.distributex/manage.sh uninstall
#

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"
DOCKER_IMAGE="distributexcloud/worker"

# ============================================================================
# COLORS
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================
log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; }

# ============================================================================
# BANNER
# ============================================================================
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          DistributeX Uninstaller v3.5.0              ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# CHECK WHAT'S INSTALLED
# ============================================================================
WORKER_ROLE=""
if [ -f "$CONFIG_DIR/role" ]; then
    WORKER_ROLE=$(cat "$CONFIG_DIR/role")
fi

HAS_DOCKER=false
if command -v docker &> /dev/null; then
    HAS_DOCKER=true
fi

HAS_CONTAINER=false
if $HAS_DOCKER && docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    HAS_CONTAINER=true
fi

HAS_CONFIG=false
if [ -d "$CONFIG_DIR" ]; then
    HAS_CONFIG=true
fi

# ============================================================================
# DISPLAY CURRENT STATE
# ============================================================================
echo -e "${CYAN}${BOLD}Current Installation:${NC}"
echo ""

if [ -n "$WORKER_ROLE" ]; then
    echo "  Role: $WORKER_ROLE"
fi

if $HAS_CONTAINER; then
    CONTAINER_STATUS=$(docker ps -a -f name=$CONTAINER_NAME --format "{{.Status}}")
    echo "  Container: ${GREEN}Installed${NC} ($CONTAINER_STATUS)"
else
    echo "  Container: ${YELLOW}Not found${NC}"
fi

if $HAS_CONFIG; then
    CONFIG_SIZE=$(du -sh "$CONFIG_DIR" 2>/dev/null | cut -f1)
    echo "  Config: ${GREEN}Exists${NC} ($CONFIG_SIZE)"
else
    echo "  Config: ${YELLOW}Not found${NC}"
fi

echo ""

# ============================================================================
# NOTHING TO UNINSTALL
# ============================================================================
if ! $HAS_CONTAINER && ! $HAS_CONFIG; then
    info "DistributeX is not installed on this system"
    echo ""
    echo "Nothing to uninstall."
    echo ""
    exit 0
fi

# ============================================================================
# UNINSTALL OPTIONS
# ============================================================================
echo -e "${CYAN}${BOLD}Uninstall Options:${NC}"
echo ""
echo " 1) ${YELLOW}Remove worker only${NC} (keep config & API key)"
echo "    • Stop and remove Docker container"
echo "    • Preserve authentication and settings"
echo "    • Quick reinstall possible"
echo ""
echo " 2) ${RED}Complete removal${NC} (remove everything)"
echo "    • Stop and remove Docker container"
echo "    • Delete all configuration files"
echo "    • Delete API keys and tokens"
echo "    • Requires re-authentication to reinstall"
echo ""
echo " 3) ${GREEN}Cancel${NC} (keep everything)"
echo ""

while true; do
    read -r -p "Enter choice [1-3]: " choice </dev/tty
    case "$choice" in
        1)
            REMOVE_CONFIG=false
            break
            ;;
        2)
            REMOVE_CONFIG=true
            break
            ;;
        3)
            echo ""
            info "Uninstall cancelled"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1, 2, or 3${NC}"
            ;;
    esac
done

echo ""

# ============================================================================
# CONFIRM COMPLETE REMOVAL
# ============================================================================
if $REMOVE_CONFIG; then
    echo -e "${RED}${BOLD}⚠️  WARNING: Complete Removal${NC}"
    echo ""
    echo "This will permanently delete:"
    echo "  • All worker data"
    echo "  • API keys and authentication tokens"
    echo "  • Configuration files"
    echo "  • Installation history"
    echo ""
    echo -e "${YELLOW}You will need to authenticate again if you reinstall.${NC}"
    echo ""
    
    read -r -p "Are you absolutely sure? (yes/no): " confirm </dev/tty
    
    if [ "$confirm" != "yes" ]; then
        echo ""
        warn "Complete removal cancelled"
        info "Switching to worker-only removal instead"
        echo ""
        REMOVE_CONFIG=false
        sleep 2
    fi
fi

# ============================================================================
# STOP WORKER (if contributor)
# ============================================================================
if $HAS_DOCKER && $HAS_CONTAINER; then
    echo ""
    info "Stopping worker container..."
    
    # Try graceful stop first
    if docker stop $CONTAINER_NAME 2>/dev/null; then
        log "Container stopped gracefully"
    else
        warn "Container was not running or already stopped"
    fi
    
    # Remove container
    info "Removing container..."
    if docker rm $CONTAINER_NAME 2>/dev/null; then
        log "Container removed"
    else
        warn "Container already removed"
    fi
fi

# ============================================================================
# REMOVE DOCKER IMAGE (optional)
# ============================================================================
if $HAS_DOCKER; then
    echo ""
    
    # Check if image exists
    if docker images | grep -q "$DOCKER_IMAGE"; then
        read -r -p "Remove Docker image? This saves disk space (~200MB) but requires re-download [y/N]: " remove_image </dev/tty
        
        if [[ "$remove_image" =~ ^[Yy]$ ]]; then
            info "Removing Docker image..."
            
            # Get all tags for this image
            IMAGE_IDS=$(docker images --format "{{.ID}}" "$DOCKER_IMAGE" 2>/dev/null || true)
            
            if [ -n "$IMAGE_IDS" ]; then
                for img_id in $IMAGE_IDS; do
                    docker rmi "$img_id" 2>/dev/null || true
                done
                log "Docker image removed"
            fi
        else
            info "Docker image kept"
        fi
    fi
fi

# ============================================================================
# REMOVE SYSTEMD SERVICE (Linux only)
# ============================================================================
if [ -f "/etc/systemd/system/distributex-worker.service" ]; then
    echo ""
    info "Removing systemd service..."
    
    sudo systemctl stop distributex-worker.service 2>/dev/null || true
    sudo systemctl disable distributex-worker.service 2>/dev/null || true
    sudo rm /etc/systemd/system/distributex-worker.service 2>/dev/null || true
    sudo systemctl daemon-reload 2>/dev/null || true
    
    log "Systemd service removed"
fi

# ============================================================================
# HANDLE CONFIGURATION
# ============================================================================
echo ""

if $REMOVE_CONFIG; then
    if [ -d "$CONFIG_DIR" ]; then
        info "Removing all configuration..."
        
        # Show what will be deleted
        echo ""
        echo -e "${YELLOW}Removing:${NC}"
        ls -lah "$CONFIG_DIR" 2>/dev/null | tail -n +2 | sed 's/^/  /'
        echo ""
        
        rm -rf "$CONFIG_DIR"
        log "All configuration removed"
    else
        info "No configuration found"
    fi
else
    if [ -d "$CONFIG_DIR" ]; then
        # Keep config but clean up temporary files
        info "Preserving configuration at: $CONFIG_DIR"
        
        # Remove only temporary/cache files
        rm -f "$CONFIG_DIR/worker_id" 2>/dev/null || true
        rm -f "$CONFIG_DIR/mac_address" 2>/dev/null || true
        rm -f "$CONFIG_DIR/.cache" 2>/dev/null || true
        
        log "Authentication and settings preserved"
        
        echo ""
        echo -e "${CYAN}Preserved files:${NC}"
        if [ -f "$CONFIG_DIR/token" ]; then
            echo "  ✓ Authentication token"
        fi
        if [ -f "$CONFIG_DIR/api-key" ]; then
            echo "  ✓ API key"
        fi
        if [ -f "$CONFIG_DIR/role" ]; then
            echo "  ✓ Role preference ($WORKER_ROLE)"
        fi
        if [ -f "$CONFIG_DIR/config.json" ]; then
            echo "  ✓ Configuration"
        fi
    fi
fi

# ============================================================================
# COMPLETION
# ============================================================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Uninstall Complete!                            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

log "DistributeX worker has been removed from your system"
echo ""

if $REMOVE_CONFIG; then
    echo -e "${CYAN}${BOLD}Complete Removal:${NC}"
    echo "  • All files deleted"
    echo "  • No traces left on system"
    echo ""
    echo -e "${YELLOW}To reinstall:${NC}"
    echo "  curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash"
    echo "  ${RED}Note: You will need to authenticate again${NC}"
else
    echo -e "${CYAN}${BOLD}Worker Removed:${NC}"
    echo "  • Container stopped and removed"
    echo "  • Authentication preserved"
    echo "  • Configuration kept"
    echo ""
    echo -e "${GREEN}To reinstall:${NC}"
    echo "  curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash"
    echo "  ${GREEN}Note: You won't need to log in again${NC}"
    echo ""
    echo -e "${YELLOW}To remove all data later:${NC}"
    echo "  rm -rf $CONFIG_DIR"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Thank you for using DistributeX!"
echo ""
