# Worker management (Docker-based)
dxcloud worker start        # Start Docker container with GPU detection
dxcloud worker stop         # Stop container
dxcloud worker restart      # Restart container
dxcloud worker status       # Check both local and server status
dxcloud worker logs [-f]    # View container logs
dxcloud worker update       # Pull latest image and restart

# Pool management
dxcloud pool status         # View global pool status

# Diagnostics
dxcloud diagnose           # Comprehensive system check
dxcloud info              # Worker information
