#!/bin/bash
# Development Environment Setup for DistributeX Platform

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[Setup]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[Warning]${NC} $1"
}

error() {
    echo -e "${RED}[Error]${NC} $1"
    exit 1
}

echo "╔═══════════════════════════════════════╗"
echo "║  DistributeX Development Setup       ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# Check Node.js
log "Checking Node.js version..."
if ! command -v node &> /dev/null; then
    error "Node.js not found. Please install Node.js 20+ from https://nodejs.org/"
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
    error "Node.js version must be 20 or higher. Current: $(node -v)"
fi
log "Node.js version: $(node -v) ✓"

# Check npm
log "Checking npm..."
if ! command -v npm &> /dev/null; then
    error "npm not found. Please install npm."
fi
log "npm version: $(npm -v) ✓"

# Check Docker
log "Checking Docker..."
if ! command -v docker &> /dev/null; then
    warn "Docker not found. Install Docker to run workers: https://docs.docker.com/get-docker/"
else
    log "Docker version: $(docker --version) ✓"
fi

# Check PostgreSQL
log "Checking PostgreSQL..."
if ! command -v psql &> /dev/null; then
    warn "PostgreSQL client not found. You'll need PostgreSQL 16+ for the database."
    warn "Install from: https://www.postgresql.org/download/"
else
    log "PostgreSQL client found ✓"
fi

# Install dependencies
log "Installing npm dependencies..."
npm install

# Setup environment file
if [ ! -f .env ]; then
    log "Creating .env file..."
    cat > .env <<EOF
# DistributeX Development Environment

NODE_ENV=development
PORT=5000

# Database
DATABASE_URL=postgresql://distributex:password@localhost:5432/distributex

# Authentication
JWT_SECRET=$(openssl rand -base64 64)
SESSION_SECRET=$(openssl rand -base64 64)

# Optional: Redis for caching
# REDIS_URL=redis://localhost:6379
EOF
    log ".env file created with secure secrets ✓"
else
    log ".env file already exists ✓"
fi

# Setup PostgreSQL database
read -p "Do you want to setup the PostgreSQL database? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Setting up PostgreSQL database..."
    
    read -p "PostgreSQL host (default: localhost): " DB_HOST
    DB_HOST=${DB_HOST:-localhost}
    
    read -p "PostgreSQL port (default: 5432): " DB_PORT
    DB_PORT=${DB_PORT:-5432}
    
    read -p "PostgreSQL user (default: distributex): " DB_USER
    DB_USER=${DB_USER:-distributex}
    
    read -sp "PostgreSQL password: " DB_PASS
    echo
    
    # Create database
    PGPASSWORD=$DB_PASS createdb -h $DB_HOST -p $DB_PORT -U $DB_USER distributex 2>/dev/null || true
    
    # Update .env
    sed -i "s|DATABASE_URL=.*|DATABASE_URL=postgresql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/distributex|g" .env
    
    log "Database created ✓"
fi

# Run migrations
log "Running database migrations..."
npm run db:push
npm run db:migrate

log "Database schema initialized ✓"

# Build client
log "Building client..."
npm run build:client

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║  Setup Complete! 🎉                  ║"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "To start development:"
echo "  npm run dev"
echo ""
echo "The platform will be available at:"
echo "  http://localhost:5000"
echo ""
echo "API documentation:"
echo "  http://localhost:5000/api-docs"
echo ""
echo "Database studio:"
echo "  npm run db:studio"
echo ""
