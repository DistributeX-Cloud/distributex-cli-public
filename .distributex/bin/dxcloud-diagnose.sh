#!/bin/bash
# DistributeX Authentication Diagnostic Tool
# Save as: ~/.distributex/bin/dxcloud-diagnose.sh

set -e

INSTALL_DIR="$HOME/.distributex"
CONFIG_FILE="$INSTALL_DIR/config/auth.json"
API_URL="${DISTRIBUTEX_API_URL:-https://distributex-api.distributex.workers.dev}"
COORDINATOR_URL="${DISTRIBUTEX_COORDINATOR_URL:-wss://distributex-coordinator.distributex.workers.dev/ws}"

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "════════════════════════════════════════"
echo "  DistributeX Authentication Diagnostic"
echo "════════════════════════════════════════"
echo -e "${NC}\n"

# Check 1: Config file exists
echo -e "${BOLD}1. Checking config file...${NC}"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}✓ Config file exists${NC}"
    echo "  Location: $CONFIG_FILE"
    
    # Extract info
    TOKEN=$(grep '"token"' "$CONFIG_FILE" | cut -d'"' -f4)
    USER_ID=$(grep '"user_id"' "$CONFIG_FILE" | cut -d'"' -f4)
    EMAIL=$(grep '"email"' "$CONFIG_FILE" | cut -d'"' -f4)
    
    if [ -n "$TOKEN" ]; then
        TOKEN_PREVIEW="${TOKEN:0:20}..."
        echo -e "  Token: ${CYAN}$TOKEN_PREVIEW${NC}"
    else
        echo -e "${RED}✗ Token not found in config${NC}"
    fi
    
    if [ -n "$USER_ID" ]; then
        echo -e "  User ID: ${CYAN}$USER_ID${NC}"
    else
        echo -e "${RED}✗ User ID not found in config${NC}"
    fi
    
    if [ -n "$EMAIL" ]; then
        echo -e "  Email: ${CYAN}$EMAIL${NC}"
    else
        echo -e "${YELLOW}⚠ Email not found in config${NC}"
    fi
else
    echo -e "${RED}✗ Config file not found${NC}"
    echo ""
    echo "You need to login first:"
    echo "  dxcloud login"
    echo ""
    echo "Or create an account:"
    echo "  dxcloud signup"
    exit 1
fi

echo ""

# Check 2: Validate token with API
echo -e "${BOLD}2. Validating token with API...${NC}"
if [ -n "$TOKEN" ]; then
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        "$API_URL/api/auth/me")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✓ Token is valid${NC}"
        echo "  HTTP Status: $http_code"
        
        # Try to extract user info
        user_email=$(echo "$body" | grep -o '"email":"[^"]*"' | cut -d'"' -f4)
        user_role=$(echo "$body" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$user_email" ]; then
            echo "  Authenticated as: $user_email"
        fi
        if [ -n "$user_role" ]; then
            echo "  Role: $user_role"
        fi
    elif [ "$http_code" = "401" ]; then
        echo -e "${RED}✗ Token is invalid or expired${NC}"
        echo "  HTTP Status: $http_code"
        echo ""
        echo "Your token has expired. Please login again:"
        echo "  ${CYAN}dxcloud login${NC}"
    else
        echo -e "${YELLOW}⚠ Unexpected response${NC}"
        echo "  HTTP Status: $http_code"
        echo "  Response: $body"
    fi
else
    echo -e "${RED}✗ No token to validate${NC}"
fi

echo ""

# Check 3: Test WebSocket connection
echo -e "${BOLD}3. Testing WebSocket connection...${NC}"
echo "  Coordinator URL: $COORDINATOR_URL"

# Note: This requires wscat or similar tool
if command -v wscat >/dev/null 2>&1; then
    echo "  Testing connection (5 second timeout)..."
    
    # Try to connect with auth
    timeout 5 wscat -c "$COORDINATOR_URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "X-Worker-Id: $USER_ID" \
        2>&1 | head -n 5 &
    
    sleep 2
    pkill -P $$ wscat 2>/dev/null || true
    
    echo -e "${YELLOW}⚠ Manual WebSocket test recommended${NC}"
else
    echo -e "${YELLOW}⚠ wscat not installed (npm install -g wscat)${NC}"
    echo "  Cannot test WebSocket directly"
fi

echo ""

# Check 4: Verify Docker access
echo -e "${BOLD}4. Checking Docker access...${NC}"
if command -v docker >/dev/null 2>&1; then
    if docker ps >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker daemon accessible${NC}"
        
        # Get Docker info
        containers=$(docker ps -q | wc -l)
        echo "  Running containers: $containers"
        
        version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        echo "  Docker version: $version"
    else
        echo -e "${RED}✗ Cannot access Docker daemon${NC}"
        echo ""
        echo "Possible fixes:"
        echo "  1. Start Docker:"
        echo "     sudo systemctl start docker"
        echo ""
        echo "  2. Add user to docker group:"
        echo "     sudo usermod -aG docker $USER"
        echo "     newgrp docker"
    fi
else
    echo -e "${RED}✗ Docker not installed${NC}"
    echo "  Install: curl -fsSL https://get.docker.com | sh"
fi

echo ""

# Check 5: Network connectivity
echo -e "${BOLD}5. Checking network connectivity...${NC}"

# Test API
echo "  Testing API endpoint..."
api_response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$API_URL/health" 2>/dev/null || echo "000")
if [ "$api_response" = "200" ]; then
    echo -e "  ${GREEN}✓ API reachable${NC} (HTTP $api_response)"
elif [ "$api_response" = "000" ]; then
    echo -e "  ${RED}✗ API unreachable${NC} (timeout or connection error)"
else
    echo -e "  ${YELLOW}⚠ API responded with HTTP $api_response${NC}"
fi

# Test Coordinator (HTTP check since WS is harder)
coordinator_http=$(echo "$COORDINATOR_URL" | sed 's/wss:/https:/' | sed 's/\/ws$//')
coord_response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$coordinator_http/health" 2>/dev/null || echo "000")
if [ "$coord_response" = "200" ]; then
    echo -e "  ${GREEN}✓ Coordinator reachable${NC} (HTTP $coord_response)"
elif [ "$coord_response" = "000" ]; then
    echo -e "  ${YELLOW}⚠ Coordinator HTTP unreachable${NC} (WS might still work)"
else
    echo -e "  ${YELLOW}⚠ Coordinator responded with HTTP $coord_response${NC}"
fi

echo ""

# Summary and recommendations
echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}"
echo -e "${BOLD}Summary & Recommendations${NC}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}\n"

if [ "$http_code" = "401" ] || [ -z "$TOKEN" ]; then
    echo -e "${YELLOW}⚠ Authentication issue detected${NC}\n"
    echo "Recommended actions:"
    echo "  1. Login again:"
    echo -e "     ${CYAN}dxcloud login${NC}\n"
    echo "  2. If that fails, create new account:"
    echo -e "     ${CYAN}dxcloud signup${NC}\n"
    echo "  3. Then restart worker:"
    echo -e "     ${CYAN}dxcloud worker start${NC}\n"
elif [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Authentication looks good!${NC}\n"
    echo "If worker still fails to connect, check:"
    echo "  1. Worker logs:"
    echo -e "     ${CYAN}tail -f $INSTALL_DIR/logs/worker.log${NC}\n"
    echo "  2. Try restarting worker:"
    echo -e "     ${CYAN}dxcloud worker stop${NC}"
    echo -e "     ${CYAN}dxcloud worker start${NC}\n"
else
    echo -e "${YELLOW}⚠ Could not verify authentication${NC}\n"
    echo "Try logging in again:"
    echo -e "  ${CYAN}dxcloud login${NC}\n"
fi

echo "For more help:"
echo "  • View logs: tail -f $INSTALL_DIR/logs/worker.log"
echo "  • Status page: https://distributex-status-page.distributex.workers.dev/"
echo "  • Config location: $CONFIG_FILE"
echo ""
