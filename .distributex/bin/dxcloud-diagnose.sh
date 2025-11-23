#!/bin/bash
# DistributeX Diagnostic and Fix Script

set -e

echo "🔍 DistributeX System Diagnostics"
echo "=================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CONFIG_FILE="$HOME/.distributex/config.json"

echo -e "${BLUE}1. Checking Configuration...${NC}"
if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}❌ Configuration file not found at $CONFIG_FILE${NC}"
  echo "Please run setup first: curl -fsSL https://get.distributex.cloud | bash"
  exit 1
fi

echo -e "${GREEN}✓ Configuration file found${NC}"
echo ""

# Parse configuration
API_URL=$(cat "$CONFIG_FILE" | grep -o '"apiUrl":"[^"]*"' | cut -d'"' -f4)
AUTH_TOKEN=$(cat "$CONFIG_FILE" | grep -o '"authToken":"[^"]*"' | cut -d'"' -f4)
WORKER_ID=$(cat "$CONFIG_FILE" | grep -o '"workerId":"[^"]*"' | cut -d'"' -f4)

echo "Configuration:"
echo "  API URL: $API_URL"
echo "  Worker ID: $WORKER_ID"
echo "  Auth Token: ${AUTH_TOKEN:0:20}..."
echo ""

# Determine coordinator URL
if echo "$API_URL" | grep -q "localhost"; then
  COORDINATOR_URL="ws://localhost:8788"
else
  COORDINATOR_URL=$(echo "$API_URL" | sed 's/https:\/\/distributex-api/wss:\/\/distributex-coordinator/')
fi

echo "Derived Coordinator URL: $COORDINATOR_URL"
echo ""

echo -e "${BLUE}2. Testing API Connectivity...${NC}"

# Test API root
echo "Testing: $API_URL"
if curl -sf "$API_URL" > /dev/null; then
  echo -e "${GREEN}✓ API root is accessible${NC}"
else
  echo -e "${RED}❌ API root is not accessible${NC}"
  echo "This may indicate the API service is down or URL is incorrect."
fi

# Test API health
echo "Testing: $API_URL/health"
HEALTH_RESPONSE=$(curl -sf "$API_URL/health" 2>&1 || echo "failed")
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
  echo -e "${GREEN}✓ API health endpoint is working${NC}"
else
  echo -e "${RED}❌ API health endpoint failed${NC}"
  echo "Response: $HEALTH_RESPONSE"
fi

# Test pool status
echo "Testing: $API_URL/api/pool/status"
POOL_RESPONSE=$(curl -sf "$API_URL/api/pool/status" 2>&1 || echo "failed")
if echo "$POOL_RESPONSE" | grep -q "workers"; then
  echo -e "${GREEN}✓ Pool status endpoint is working${NC}"
else
  echo -e "${RED}❌ Pool status endpoint failed${NC}"
  echo "Response: $POOL_RESPONSE"
fi

echo ""

echo -e "${BLUE}3. Testing Worker Authentication...${NC}"

# Try to register a test worker (should succeed if auth is valid)
REGISTER_RESPONSE=$(curl -sf -X POST "$API_URL/api/workers/register" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"nodeName":"diagnostic-test","cpuCores":1,"memoryGb":1}' 2>&1 || echo "failed")

if echo "$REGISTER_RESPONSE" | grep -q "workerId"; then
  echo -e "${GREEN}✓ Worker authentication is working${NC}"
  echo "Your auth token is valid."
elif echo "$REGISTER_RESPONSE" | grep -q "401"; then
  echo -e "${RED}❌ Authentication failed (401 Unauthorized)${NC}"
  echo "Your auth token or worker ID may be invalid."
  echo ""
  echo "Fix: Re-register your worker:"
  echo "  1. Stop the worker: Ctrl+C"
  echo "  2. Re-run setup: curl -fsSL https://get.distributex.cloud | bash"
  exit 1
elif echo "$REGISTER_RESPONSE" | grep -q "409"; then
  echo -e "${YELLOW}⚠ Worker already registered (this is normal)${NC}"
else
  echo -e "${RED}❌ Worker registration failed${NC}"
  echo "Response: $REGISTER_RESPONSE"
fi

echo ""

echo -e "${BLUE}4. Testing Coordinator WebSocket...${NC}"

# Test if coordinator is accessible (HTTP first)
COORDINATOR_HTTP=$(echo "$COORDINATOR_URL" | sed 's/wss:/https:/' | sed 's/ws:/http:/')
echo "Testing: $COORDINATOR_HTTP"

if curl -sf "$COORDINATOR_HTTP" > /dev/null; then
  echo -e "${GREEN}✓ Coordinator HTTP endpoint is accessible${NC}"
else
  echo -e "${RED}❌ Coordinator is not accessible${NC}"
  echo "The coordinator service may be down."
fi

# Test coordinator health
echo "Testing: $COORDINATOR_HTTP/health"
COORD_HEALTH=$(curl -sf "$COORDINATOR_HTTP/health" 2>&1 || echo "failed")
if echo "$COORD_HEALTH" | grep -q "healthy"; then
  echo -e "${GREEN}✓ Coordinator health endpoint is working${NC}"
else
  echo -e "${YELLOW}⚠ Coordinator health endpoint not found${NC}"
  echo "Response: $COORD_HEALTH"
fi

echo ""

echo -e "${BLUE}5. Checking Worker Logs...${NC}"
LOG_FILE="$HOME/.distributex/logs/worker.log"

if [ -f "$LOG_FILE" ]; then
  echo "Last 10 log entries:"
  tail -n 10 "$LOG_FILE"
  echo ""
  
  # Check for common errors
  if grep -q "401" "$LOG_FILE"; then
    echo -e "${RED}Found 401 errors in logs - authentication is failing${NC}"
  fi
  
  if grep -q "ECONNREFUSED" "$LOG_FILE"; then
    echo -e "${RED}Found connection refused errors - coordinator may be down${NC}"
  fi
  
  if grep -q "timeout" "$LOG_FILE"; then
    echo -e "${YELLOW}Found timeout errors - network may be slow${NC}"
  fi
else
  echo -e "${YELLOW}No log file found at $LOG_FILE${NC}"
fi

echo ""

echo -e "${BLUE}6. Docker Status...${NC}"
if command -v docker &> /dev/null; then
  echo -e "${GREEN}✓ Docker is installed${NC}"
  
  if docker ps &> /dev/null; then
    echo -e "${GREEN}✓ Docker daemon is running${NC}"
    CONTAINER_COUNT=$(docker ps -q | wc -l)
    echo "  Running containers: $CONTAINER_COUNT"
  else
    echo -e "${RED}❌ Docker daemon is not running${NC}"
    echo "Start Docker and try again."
    exit 1
  fi
else
  echo -e "${RED}❌ Docker is not installed${NC}"
  exit 1
fi

echo ""
echo "=================================="
echo -e "${BLUE}Diagnostic Summary${NC}"
echo "=================================="
echo ""

# Provide recommendations
ISSUES=0

if ! curl -sf "$API_URL/health" | grep -q "healthy"; then
  echo -e "${RED}• API Service Issue: Cannot connect to API${NC}"
  echo "  Fix: Check if API is deployed: cd packages/api && wrangler deploy"
  ISSUES=$((ISSUES + 1))
fi

if ! echo "$REGISTER_RESPONSE" | grep -qE "workerId|409"; then
  echo -e "${RED}• Authentication Issue: Worker cannot authenticate${NC}"
  echo "  Fix: Re-register worker with valid credentials"
  ISSUES=$((ISSUES + 1))
fi

if ! curl -sf "$COORDINATOR_HTTP" > /dev/null; then
  echo -e "${RED}• Coordinator Issue: Cannot connect to coordinator${NC}"
  echo "  Fix: Deploy coordinator: cd packages/coordinator && wrangler deploy"
  ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
  echo -e "${GREEN}✅ All systems operational!${NC}"
  echo ""
  echo "Your worker should be able to connect successfully."
  echo ""
  echo "Start/restart your worker:"
  echo "  node ~/.distributex/distributex-worker.js"
else
  echo ""
  echo -e "${YELLOW}Found $ISSUES issue(s) that need attention.${NC}"
  echo ""
  echo "Common fixes:"
  echo "  1. Re-deploy services:"
  echo "     cd packages/api && wrangler deploy"
  echo "     cd packages/coordinator && wrangler deploy"
  echo ""
  echo "  2. Re-register worker:"
  echo "     curl -fsSL https://get.distributex.cloud | bash"
fi

echo ""
echo "For more help, visit: https://github.com/yourusername/distributex"
echo ""
