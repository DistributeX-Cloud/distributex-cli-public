#!/bin/bash
# DistributeX Complete CLI - /usr/local/bin/dxcloud
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

# ==================== HELPER FUNCTIONS ====================
get_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}❌ Not configured. Run: dxcloud config init${NC}"
        exit 1
    fi
    AUTH_TOKEN=$(jq -r '.authToken' "$CONFIG_FILE")
    WORKER_ID=$(jq -r '.workerId' "$CONFIG_FILE")
}

api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    get_config
    
    if [ -n "$data" ]; then
        curl -s -X "$method" "$API_URL$endpoint" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" "$API_URL$endpoint" \
            -H "Authorization: Bearer $AUTH_TOKEN"
    fi
}

show_help() {
    cat << EOF
${BOLD}dxcloud${NC} - DistributeX CLI v${VERSION}

${BOLD}USAGE:${NC}
    dxcloud <command> [options]

${BOLD}CONTRIBUTOR COMMANDS:${NC}
    ${CYAN}worker status${NC}        Show worker status
    ${CYAN}worker logs${NC}          View worker logs [-f for follow]
    ${CYAN}worker start${NC}         Start worker
    ${CYAN}worker stop${NC}          Stop worker
    ${CYAN}worker restart${NC}       Restart worker
    ${CYAN}worker update${NC}        Update to latest version
    ${CYAN}worker remove${NC}        Remove worker from device
    ${CYAN}worker resources${NC}     Show resource usage

    ${CYAN}storage list${NC}         List connected storage devices
    ${CYAN}storage add${NC}          Add new storage device
    ${CYAN}storage remove <id>${NC}  Remove storage device

    ${CYAN}stats contribution${NC}   View contribution statistics
    ${CYAN}earnings${NC}             View earnings (coming soon)

${BOLD}DEVELOPER COMMANDS:${NC}
    ${CYAN}run <image> [cmd...]${NC} Quick run container
      Options:
        --cpu <n>          CPU cores (default: 1)
        --memory <n>       Memory in GB (default: 2)
        --storage <n>      Storage in GB (default: 10)
        --gpu              Request GPU
        --storage-required Needs external storage
        --timeout <sec>    Max runtime
        -e VAR=value       Environment variable

    ${CYAN}submit <file>${NC}        Submit workload from JSON file
    ${CYAN}submit --script <file>${NC} Submit with script file

    ${CYAN}workloads list${NC}       List all workloads
      Options:
        --status <status>  Filter by status
        --limit <n>        Number to show

    ${CYAN}workloads status <id>${NC} Get workload details
    ${CYAN}workloads logs <id>${NC}   View logs [-f for follow]
    ${CYAN}workloads cancel <id>${NC} Cancel workload
    ${CYAN}workloads delete <id>${NC} Delete workload
    ${CYAN}workloads download <id>${NC} Download results

    ${CYAN}stats usage${NC}          View usage statistics
    ${CYAN}stats cost${NC}           Estimate costs
    ${CYAN}stats balance${NC}        View resource balance

${BOLD}COMMON COMMANDS:${NC}
    ${CYAN}config init${NC}          Initialize configuration
    ${CYAN}config show${NC}          Show current config
    ${CYAN}config set <key> <val>${NC} Set config value

    ${CYAN}pool status${NC}          View network status
    ${CYAN}pool stats${NC}           Network statistics
    ${CYAN}pool resources${NC}       Available resources

    ${CYAN}devices list${NC}         List all your devices
    ${CYAN}version${NC}              Show version
    ${CYAN}help${NC}                 Show this help

${BOLD}EXAMPLES:${NC}
    # Run Python script
    dxcloud run python:3.11 --cpu 2 --memory 4 python script.py

    # Submit complex workload
    dxcloud submit workload.json

    # Monitor workload
    dxcloud workloads logs wl-12345 -f

    # Check network status
    dxcloud pool stats

EOF
}

# ==================== RUN COMMAND ====================
cmd_run() {
    local image="$1"
    shift
    
    if [ -z "$image" ]; then
        echo -e "${RED}Error: Image required${NC}"
        echo "Usage: dxcloud run <image> [command...]"
        exit 1
    fi
    
    # Parse options
    local cpu=1
    local memory=2
    local storage=10
    local gpu=false
    local storage_required=false
    local timeout=3600
    local env_vars=()
    local command_args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cpu) cpu="$2"; shift 2 ;;
            --memory) memory="$2"; shift 2 ;;
            --storage) storage="$2"; shift 2 ;;
            --gpu) gpu=true; shift ;;
            --storage-required) storage_required=true; shift ;;
            --timeout) timeout="$2"; shift 2 ;;
            -e)
                env_vars+=("$2")
                shift 2
                ;;
            *)
                command_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Build environment object
    local env_json="{"
    for env in "${env_vars[@]}"; do
        IFS='=' read -r key value <<< "$env"
        env_json+="\"$key\":\"$value\","
    done
    env_json="${env_json%,}}"
    
    # Build command array
    local cmd_json="["
    for arg in "${command_args[@]}"; do
        cmd_json+="\"$arg\","
    done
    cmd_json="${cmd_json%,}]"
    
    # Submit workload
    local payload=$(cat <<EOF
{
  "name": "quick-run-$(date +%s)",
  "image": "$image",
  "command": $cmd_json,
  "env": $env_json,
  "resources": {
    "cpu": $cpu,
    "memory": $memory,
    "storage": $storage
  },
  "storageNeeded": $storage_required,
  "timeout": $timeout
}
EOF
)
    
    echo -e "${BLUE}Submitting workload...${NC}"
    local response=$(api_call POST "/api/workloads/submit" "$payload")
    
    local workload_id=$(echo "$response" | jq -r '.workloadId')
    
    if [ "$workload_id" != "null" ]; then
        echo -e "${GREEN}✓ Workload submitted: $workload_id${NC}"
        echo ""
        echo "Monitor: dxcloud workloads logs $workload_id -f"
    else
        echo -e "${RED}✗ Failed to submit workload${NC}"
        echo "$response" | jq -r '.error'
        exit 1
    fi
}

# ==================== WORKLOADS COMMANDS ====================
cmd_workloads() {
    local subcmd="$1"
    shift
    
    case "$subcmd" in
        list)
            local status=""
            local limit=50
            
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --status) status="$2"; shift 2 ;;
                    --limit) limit="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            
            local endpoint="/api/workloads?limit=$limit"
            [ -n "$status" ] && endpoint+="&status=$status"
            
            local response=$(api_call GET "$endpoint")
            echo -e "${CYAN}Your Workloads${NC}\n"
            echo "$response" | jq -r '.workloads[] | "\(.id | .[0:12])  \(.name | .[0:30])  \(.status)  \(.created_at)"'
            ;;
            
        status)
            local id="$1"
            if [ -z "$id" ]; then
                echo -e "${RED}Error: Workload ID required${NC}"
                exit 1
            fi
            
            local response=$(api_call GET "/api/workloads/$id")
            echo -e "${CYAN}Workload Details${NC}\n"
            echo "$response" | jq -r '.workload | 
                "ID: \(.id)\n" +
                "Name: \(.name)\n" +
                "Status: \(.status)\n" +
                "Image: \(.image)\n" +
                "Progress: \(.progress)%\n" +
                "Allocated: \(.resources.allocated.cpu) CPU, \(.resources.allocated.memory) GB RAM\n" +
                "Started: \(.startedAt // "Not started")\n" +
                "Completed: \(.completedAt // "Not completed")"'
            ;;
            
        logs)
            local id="$1"
            local follow=false
            
            if [ -z "$id" ]; then
                echo -e "${RED}Error: Workload ID required${NC}"
                exit 1
            fi
            
            shift
            [ "$1" == "-f" ] && follow=true
            
            if $follow; then
                echo -e "${CYAN}Streaming logs (Ctrl+C to stop)...${NC}\n"
                while true; do
                    api_call GET "/api/workloads/$id/logs" | jq -r '.logs[] | "[\(.timestamp)] [\(.log_level)] \(.message)"'
                    sleep 2
                done
            else
                api_call GET "/api/workloads/$id/logs" | jq -r '.logs[] | "[\(.timestamp)] [\(.log_level)] \(.message)"'
            fi
            ;;
            
        cancel)
            local id="$1"
            if [ -z "$id" ]; then
                echo -e "${RED}Error: Workload ID required${NC}"
                exit 1
            fi
            
            echo -e "${YELLOW}Cancelling workload...${NC}"
            local response=$(api_call POST "/api/workloads/$id/cancel")
            
            if echo "$response" | jq -e '.success' > /dev/null; then
                echo -e "${GREEN}✓ Workload cancelled${NC}"
            else
                echo -e "${RED}✗ Failed to cancel${NC}"
                echo "$response" | jq -r '.error'
            fi
            ;;
            
        *)
            echo -e "${RED}Unknown workloads command: $subcmd${NC}"
            exit 1
            ;;
    esac
}

# ==================== WORKER COMMANDS ====================
cmd_worker() {
    local subcmd="$1"
    
    case "$subcmd" in
        status)
            if docker ps | grep -q distributex-worker; then
                echo -e "${GREEN}✓ Worker: Running${NC}"
                get_config
                echo -e "Worker ID: $WORKER_ID"
                
                # Get API status
                local response=$(api_call GET "/api/workers/$WORKER_ID")
                echo "$response" | jq -r '
                    "Status: \(.worker.status)\n" +
                    "CPU: \(.worker.cpu_cores) cores\n" +
                    "Memory: \(.worker.memory_gb) GB\n" +
                    "GPU: \(if .worker.gpu_available == 1 then "Yes" else "No" end)\n" +
                    "Last seen: \(.worker.last_heartbeat)"'
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
            docker start distributex-worker
            echo -e "${GREEN}✓ Worker started${NC}"
            ;;
            
        stop)
            echo -e "${BLUE}Stopping worker...${NC}"
            docker stop distributex-worker
            echo -e "${GREEN}✓ Worker stopped${NC}"
            ;;
            
        restart)
            echo -e "${BLUE}Restarting worker...${NC}"
            docker restart distributex-worker
            echo -e "${GREEN}✓ Worker restarted${NC}"
            ;;
            
        *)
            echo -e "${RED}Unknown worker command: $subcmd${NC}"
            exit 1
            ;;
    esac
}

# ==================== POOL COMMANDS ====================
cmd_pool() {
    local subcmd="$1"
    
    case "$subcmd" in
        status|stats)
            local response=$(api_call GET "/api/pool/stats")
            echo -e "${CYAN}DistributeX Network${NC}\n"
            echo "$response" | jq -r '
                "Workers: \(.network.onlineWorkers) online / \(.network.totalWorkers) total\n" +
                "Workers with Storage: \(.network.workersWithStorage)\n" +
                "\n" +
                "Resources:\n" +
                "  Total:     \(.resources.total.cpu) CPU, \(.resources.total.memory) GB RAM, \(.resources.total.storage) GB Storage\n" +
                "  Used:      \(.resources.used.cpu) CPU, \(.resources.used.memory) GB RAM\n" +
                "  Available: \(.resources.available.cpu) CPU, \(.resources.available.memory) GB RAM\n" +
                "\n" +
                "Workloads:\n" +
                "  Running: \(.workloads.running)\n" +
                "  Pending: \(.workloads.pending)\n" +
                "  Total:   \(.workloads.total)"'
            ;;
            
        *)
            echo -e "${RED}Unknown pool command: $subcmd${NC}"
            exit 1
            ;;
    esac
}

# ==================== STORAGE COMMANDS ====================
cmd_storage() {
    local subcmd="$1"
    shift
    
    case "$subcmd" in
        list)
            if [ -f "$CONFIG_DIR/storage_devices.json" ]; then
                echo -e "${CYAN}Connected Storage Devices${NC}\n"
                jq -r '.[] | "[\(.device)] \(.mountPoint) - \(.availableGb)/\(.totalGb) GB available"' "$CONFIG_DIR/storage_devices.json"
            else
                echo -e "${YELLOW}No storage devices configured${NC}"
            fi
            ;;
            
        *)
            echo -e "${YELLOW}Storage management coming soon${NC}"
            ;;
    esac
}

# ==================== CONFIG COMMANDS ====================
cmd_config() {
    local subcmd="$1"
    
    case "$subcmd" in
        show)
            if [ -f "$CONFIG_FILE" ]; then
                cat "$CONFIG_FILE" | jq '.'
            else
                echo -e "${YELLOW}No configuration found${NC}"
            fi
            ;;
            
        set)
            local key="$2"
            local value="$3"
            
            if [ -z "$key" ] || [ -z "$value" ]; then
                echo -e "${RED}Usage: dxcloud config set <key> <value>${NC}"
                exit 1
            fi
            
            get_config
            jq ".$key = \"$value\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
            mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            echo -e "${GREEN}✓ Configuration updated${NC}"
            ;;
            
        *)
            echo -e "${RED}Unknown config command: $subcmd${NC}"
            exit 1
            ;;
    esac
}

# ==================== STATS COMMANDS ====================
cmd_stats() {
    local subcmd="$1"
    
    case "$subcmd" in
        usage)
            local response=$(api_call GET "/api/stats/usage")
            echo -e "${CYAN}Usage Statistics${NC}\n"
            echo "$response" | jq -r '
                "Workloads:\n" +
                "  Completed: \(.usage.jobs_completed)\n" +
                "  Running:   \(.usage.jobs_running)\n" +
                "  Failed:    \(.usage.jobs_failed)\n" +
                "\n" +
                "Resources Used:\n" +
                "  CPU Hours:    \(.usage.cpu_hours)\n" +
                "  Memory GB·h:  \(.usage.memory_gb_hours)"'
            ;;
            
        contribution)
            get_config
            local response=$(api_call GET "/api/workers/$WORKER_ID")
            echo -e "${CYAN}Contribution Statistics${NC}\n"
            echo "$response" | jq -r '.worker | 
                "Resources Shared:\n" +
                "  CPU:     \(.cpu_cores) cores\n" +
                "  Memory:  \(.memory_gb) GB\n" +
                "  Storage: \(.storage_gb) GB\n" +
                "  GPU:     \(if .gpu_available == 1 then .gpu_model else "None" end)\n" +
                "\n" +
                "Statistics:\n" +
                "  Jobs Completed: \(.total_jobs_completed // 0)\n" +
                "  Compute Hours:  \(.total_compute_hours // 0)"'
            ;;
            
        *)
            echo -e "${YELLOW}Stats command coming soon${NC}"
            ;;
    esac
}

# ==================== MAIN ====================
case "${1:-}" in
    run) shift; cmd_run "$@" ;;
    workloads) shift; cmd_workloads "$@" ;;
    worker) shift; cmd_worker "$@" ;;
    pool) shift; cmd_pool "$@" ;;
    storage) shift; cmd_storage "$@" ;;
    config) shift; cmd_config "$@" ;;
    stats) shift; cmd_stats "$@" ;;
    version) echo "dxcloud v$VERSION" ;;
    help|--help|-h|"") show_help ;;
    *) echo -e "${RED}Unknown command: $1${NC}"; show_help; exit 1 ;;
esac
