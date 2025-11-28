#!/bin/bash
#
# DistributeX Complete Installer - ALWAYS-ON VERSION
# Usage: curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
#
# FIXED: Docker container always restarts, even when user is inactive

set -e

# Configuration
DISTRIBUTEX_API_URL="${DISTRIBUTEX_API_URL:-https://distributex-cloud-network.pages.dev}"
DOCKER_IMAGE="distributexcloud/worker:latest"
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging Functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"; }

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        ██████╗ ██╗███████╗████████╗██████╗ ██╗██╗         ║
║        ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║╚██╗        ║
║        ██║  ██║██║███████╗   ██║   ██████╔╝██║ ██║        ║
║        ██║  ██║██║╚════██║   ██║   ██╔══██╗██║ ██║        ║
║        ██████╔╝██║███████║   ██║   ██║  ██║██║██╔╝        ║
║        ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝         ║
║                                                           ║
║              DistributeX Cloud Network                    ║
║           Distributed Computing Platform                  ║
║                                                           ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
}

# Get MAC Address
get_mac_address() {
    local mac=""
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    if [ "$os" = "linux" ]; then
        mac=$(ip link show | awk '/link\/ether/ {print $2; exit}')
    elif [ "$os" = "darwin" ]; then
        mac=$(ifconfig en0 2>/dev/null | awk '/ether/ {print $2; exit}')
        [ -z "$mac" ] && mac=$(ifconfig en1 2>/dev/null | awk '/ether/ {print $2; exit}')
    fi
    
    if [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        echo "$mac"
    else
        echo ""
    fi
}

# Generate Device ID
generate_device_id() {
    local mac=$(get_mac_address)
    
    if [ -z "$mac" ]; then
        error "Could not detect MAC address for device identification."
    fi
    
    echo "$mac" | tr '[:upper:]' '[:lower:]' | tr -d ':'
}

# Check Requirements
check_requirements() {
    section "Checking System Requirements"
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Install from: https://docs.docker.com/get-docker/"
    fi
    
    if ! docker ps &> /dev/null; then
        error "Docker daemon is not running. Please start Docker and try again."
    fi
    
    local missing=()
    for cmd in curl jq bc; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required commands: ${missing[*]}"
    fi
    
    log "All requirements satisfied"
    log "Docker version: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
}

# User Authentication (same as before)
authenticate_user() {
    section "User Authentication"
    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_DIR/token" ]; then
        API_TOKEN=$(cat "$CONFIG_DIR/token")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $API_TOKEN" \
            "$DISTRIBUTEX_API_URL/api/auth/user")
        
        if [ "$HTTP_CODE" = "200" ]; then
            log "Using existing authentication"
            return 0
        else
            warn "Existing token expired, please log in again"
            rm -f "$CONFIG_DIR/token"
        fi
    fi

    echo ""
    echo -e "${CYAN}Choose an option:${NC}"
    echo "  1) Sign up (New user)"
    echo "  2) Login (Existing user)"
    echo ""
    
    while true; do
        read -r -p "Enter choice [1-2]: " choice </dev/tty
        case "$choice" in
            1) signup_user; break ;;
            2) login_user; break ;;
            *) echo -e "${RED}Invalid choice. Please enter 1 or 2${NC}" ;;
        esac
    done
}

signup_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}     Create Your Account${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local first_name last_name email password password_confirm
    
    read -r -p "First Name: " first_name </dev/tty
    read -r -p "Last Name: " last_name </dev/tty
    read -r -p "Email: " email </dev/tty
    
    while true; do
        read -s -r -p "Password (min 8 chars): " password </dev/tty
        echo ""
        
        if [ ${#password} -lt 8 ]; then
            warn "Password must be at least 8 characters"
            continue
        fi
        
        read -s -r -p "Confirm Password: " password_confirm </dev/tty
        echo ""
        
        if [ "$password" != "$password_confirm" ]; then
            warn "Passwords do not match. Please try again."
            continue
        fi
        break
    done

    echo ""
    info "Creating account..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"firstName\":\"$first_name\",\"lastName\":\"$last_name\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
        error "Signup failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message // "Unknown error"')"
    fi

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No authentication token returned"
    fi
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Account created successfully!"
    echo ""
    sleep 1
}

login_user() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}     Login to Your Account${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local email password
    
    read -r -p "Email: " email </dev/tty
    read -s -r -p "Password: " password </dev/tty
    echo ""
    echo ""
    
    info "Logging in..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISTRIBUTEX_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    
    HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" != "200" ]; then
        error "Login failed ($HTTP_CODE): $(echo $HTTP_BODY | jq -r '.message // "Invalid credentials"')"
    fi

    API_TOKEN=$(echo "$HTTP_BODY" | jq -r '.token')
    if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
        error "No authentication token returned"
    fi
    
    echo "$API_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
    log "Logged in successfully!"
    echo ""
    sleep 1
}

# Select Role
select_role() {
    section "Select Your Role"
    
    echo ""
    echo -e "${CYAN}How do you want to use DistributeX?${NC}"
    echo ""
    echo "  1) ${GREEN}Contributor${NC} - Share my computer's resources"
    echo "     • Earn by contributing CPU, RAM, GPU, Storage"
    echo "     • Lightweight agent runs 24/7 in background"
    echo "     • Zero impact on your daily use"
    echo ""
    echo "  2) ${BLUE}Developer${NC} - Use pooled computing resources"
    echo "     • Run scripts and code on distributed network"
    echo "     • Access global pool of CPU/GPU/Storage"
    echo "     • Pay-as-you-go or free tier available"
    echo ""
    
    while true; do
        read -r -p "Enter choice [1-2]: " ROLE_CHOICE </dev/tty
        case "$ROLE_CHOICE" in
            1)
                USER_ROLE="contributor"
                echo "$USER_ROLE" > "$CONFIG_DIR/role"
                log "Role set to: Contributor"
                break
                ;;
            2)
                USER_ROLE="developer"
                echo "$USER_ROLE" > "$CONFIG_DIR/role"
                log "Role set: Developer"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1 or 2${NC}"
                ;;
        esac
    done
    echo ""
}

# Detect system capabilities (same as before, omitted for brevity)
detect_system() {
    section "System Detection"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    
    if [ "$OS" = "linux" ]; then
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    elif [ "$OS" = "darwin" ]; then
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")
    else
        CPU_MODEL="Unknown CPU"
    fi
    
    if command -v free &> /dev/null; then
        RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    else
        RAM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 8192)
    fi
    
    STORAGE_TOTAL=$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo 100)
    DEVICE_ID=$(generate_device_id)
    
    log "System: $OS ($ARCH)"
    log "Device ID (MAC): $DEVICE_ID"
    log "CPU: $CPU_CORES cores - $CPU_MODEL"
    log "RAM: ${RAM_TOTAL}MB"
    log "Storage: ${STORAGE_TOTAL}GB"
}

# Register Worker (omitted for brevity - same as before)

# Setup Developer Environment
setup_developer() {
    section "Setting Up Developer Environment"
    
    info "Installing DistributeX CLI..."
    
    # Save API key
    echo "$API_TOKEN" > "$CONFIG_DIR/api-key"
    chmod 600 "$CONFIG_DIR/api-key"
    
    # Create CLI wrapper
    cat > "$CONFIG_DIR/distributex-cli" << 'EOF'
#!/bin/bash
# DistributeX CLI Wrapper
API_KEY=$(cat ~/.distributex/api-key)
export DISTRIBUTEX_API_KEY="$API_KEY"
# Add CLI commands here
echo "DistributeX Developer CLI"
echo "API Key configured: ${API_KEY:0:10}..."
EOF
    
    chmod +x "$CONFIG_DIR/distributex-cli"
    
    log "Developer environment configured"
    log "API Key saved to: $CONFIG_DIR/api-key"
    echo ""
    echo -e "${CYAN}Usage Examples:${NC}"
    echo "  • API Documentation: $DISTRIBUTEX_API_URL/docs"
    echo "  • Your API Key: ${API_TOKEN:0:20}..."
    echo ""
}

# Start Worker Container with ALWAYS-ON restart policy
start_contributor() {
    section "Starting Always-On Worker"
    
    pull_docker_image
    stop_existing_container
    
    info "Starting persistent worker container..."
    
    # CRITICAL: Use --restart always to ensure container always restarts
    docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        -e DISTRIBUTEX_API_URL="$DISTRIBUTEX_API_URL" \
        -v "$CONFIG_DIR:/config:ro" \
        $DOCKER_IMAGE \
        --api-key "$API_TOKEN" \
        --url "$DISTRIBUTEX_API_URL"
    
    sleep 2
    
    if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "Worker container started with ALWAYS-ON restart policy"
        echo ""
        info "Container will automatically restart:"
        echo "  ✓ After system reboot"
        echo "  ✓ If Docker daemon restarts"
        echo "  ✓ If container crashes"
        echo "  ✓ Even when you log out"
    else
        error "Container failed to start"
    fi
}

# Pull Docker Image
pull_docker_image() {
    info "Pulling Docker image..."
    docker pull $DOCKER_IMAGE || error "Failed to pull Docker image"
    log "Docker image ready"
}

# Stop Existing Container
stop_existing_container() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        warn "Stopping existing container..."
        docker stop $CONTAINER_NAME &> /dev/null || true
        docker rm $CONTAINER_NAME &> /dev/null || true
        log "Existing container removed"
    fi
}

# Save Configuration
save_config() {
    section "Saving Configuration"
    
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "version": "3.1.0",
  "role": "$USER_ROLE",
  "apiUrl": "$DISTRIBUTEX_API_URL",
  "deviceId": "$DEVICE_ID",
  "macAddress": "$(get_mac_address)",
  "restartPolicy": "always",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    chmod 600 "$CONFIG_DIR/config.json"
    log "Configuration saved"
}

# Create Management Script
create_management_script() {
    cat > "$CONFIG_DIR/manage.sh" <<'MGMT_EOF'
#!/bin/bash
CONTAINER_NAME="distributex-worker"
CONFIG_DIR="$HOME/.distributex"

case "$1" in
    start)
        echo "Starting worker..."
        docker start $CONTAINER_NAME
        ;;
    stop)
        echo "Stopping worker..."
        docker stop $CONTAINER_NAME
        ;;
    restart)
        echo "Restarting worker..."
        docker restart $CONTAINER_NAME
        ;;
    logs)
        docker logs ${2:--f} $CONTAINER_NAME
        ;;
    status)
        docker ps -f name=$CONTAINER_NAME
        echo ""
        echo "Restart policy:"
        docker inspect $CONTAINER_NAME --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "Container not found"
        ;;
    uninstall)
        echo "Uninstalling..."
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
        if [ "$2" = "--purge" ]; then
            rm -rf "$CONFIG_DIR"
        fi
        echo "Done!"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status|uninstall}"
        exit 1
        ;;
esac
MGMT_EOF
    
    chmod +x "$CONFIG_DIR/manage.sh"
    log "Management script created"
}

# Create systemd service for auto-start on boot (Linux only)
setup_autostart() {
    if [ "$OS" != "linux" ]; then
        return
    fi
    
    section "Setting Up Auto-Start on Boot"
    
    info "Creating systemd service..."
    
    sudo tee /etc/systemd/system/distributex-worker.service > /dev/null <<EOF
[Unit]
Description=DistributeX Worker Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start $CONTAINER_NAME
ExecStop=/usr/bin/docker stop $CONTAINER_NAME
User=$USER

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable distributex-worker.service
    
    log "Auto-start configured"
    info "Worker will automatically start on system boot"
}

# Show Completion
show_completion() {
    section "Installation Complete! 🎉"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     DistributeX Successfully Installed!               ║${NC}"
    if [ "$USER_ROLE" = "contributor" ]; then
        echo -e "${GREEN}║     ALWAYS-ON MODE: Worker runs 24/7                  ║${NC}"
    fi
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ "$USER_ROLE" = "contributor" ]; then
        log "Role: Contributor (Resource Sharing)"
        log "Device ID: $DEVICE_ID"
        log "Restart Policy: ALWAYS (survives reboots, logouts, crashes)"
        echo ""
        echo -e "${CYAN}Management Commands:${NC}"
        echo "  $CONFIG_DIR/manage.sh status   # Check worker status"
        echo "  $CONFIG_DIR/manage.sh logs     # View worker logs"
        echo "  $CONFIG_DIR/manage.sh restart  # Restart worker"
        echo ""
        echo -e "${CYAN}Container Details:${NC}"
        echo "  • Runs 24/7 in background"
        echo "  • Auto-restarts on system reboot"
        echo "  • Auto-restarts if it crashes"
        echo "  • Runs even when you log out"
        echo "  • Zero impact on system performance"
    else
        log "Role: Developer (Resource Consumer)"
        log "API Key: ${API_TOKEN:0:20}..."
        echo ""
        echo -e "${CYAN}Next Steps:${NC}"
        echo "  • View API Documentation: $DISTRIBUTEX_API_URL/docs"
        echo "  • Your API Key is saved in: $CONFIG_DIR/api-key"
        echo "  • Dashboard: $DISTRIBUTEX_API_URL/dashboard"
    fi
    
    echo ""
    echo -e "${GREEN}Thank you for joining DistributeX! 🚀${NC}"
    echo ""
}

# Main Installation Flow
main() {
    show_banner
    check_requirements
    authenticate_user
    select_role
    detect_system
    
    if [ "$USER_ROLE" = "contributor" ]; then
        start_contributor
        create_management_script
        setup_autostart

        # <-- FIX ADDED HERE
        info "Ensuring worker container is running..."
        docker start $CONTAINER_NAME >/dev/null 2>&1 || true
    else
        setup_developer
    fi
    
    save_config
    show_completion
}

# Run
main
