#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# server_config.sh - Project-Specific Server Configuration
# ═══════════════════════════════════════════════════════════════════════════════
#
# Defines:
#   - Server languages and their properties (port, name, CPU core)
#   - How to start each server type
#   - API endpoints to benchmark
#   - Resource limits
#
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# Server Definitions
# ─────────────────────────────────────────────────────────────────────────────

# Available languages
SERVER_LANGS=(js py go rust)

# Get port for a language
server_get_port() {
    case $1 in
        js)   echo 3000 ;;
        py)   echo 3001 ;;
        go)   echo 3002 ;;
        rust) echo 3003 ;;
        *)    echo 0 ;;
    esac
}

# Get display name for a language
server_get_name() {
    case $1 in
        js)   echo "JavaScript" ;;
        py)   echo "Python" ;;
        go)   echo "Go" ;;
        rust) echo "Rust" ;;
        *)    echo "Unknown" ;;
    esac
}

# Get CPU core to pin for a language
server_get_core() {
    case $1 in
        js)   echo 0 ;;
        py)   echo 1 ;;
        go)   echo 2 ;;
        rust) echo 3 ;;
        *)    echo 0 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Resource Limits (can be overridden via server_start arguments)
# ─────────────────────────────────────────────────────────────────────────────

SERVER_CPU_QUOTA=50      # Default: 0.5 CPU core (50%)
SERVER_MEMORY_MAX=1G     # Default: 1GB RAM

# ─────────────────────────────────────────────────────────────────────────────
# API Endpoints
# ─────────────────────────────────────────────────────────────────────────────

# Endpoint definitions: name|path|method|body
SERVER_ENDPOINTS=(
    "root|/|GET|"
    "query|/something?name=test&value=123|GET|"
    "json|/something?name=test&json=true|GET|"
    "post|/something|POST|{\"test\":\"data\"}"
)

# Parse endpoint definition
# Args: $1=endpoint_def, $2=field (name|path|method|body)
server_parse_endpoint() {
    local def=$1 field=$2
    case $field in
        name)   echo "$def" | cut -d'|' -f1 ;;
        path)   echo "$def" | cut -d'|' -f2 ;;
        method) echo "$def" | cut -d'|' -f3 ;;
        body)   echo "$def" | cut -d'|' -f4 ;;
    esac
}

# Get endpoint by name
server_get_endpoint() {
    local name=$1
    for ep in "${SERVER_ENDPOINTS[@]}"; do
        local ep_name=$(server_parse_endpoint "$ep" "name")
        [[ "$ep_name" == "$name" ]] && { echo "$ep"; return; }
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Server Start Functions
# ─────────────────────────────────────────────────────────────────────────────

# Directory where server files are located
SERVER_DIR="${SERVER_DIR:-$(dirname "${BASH_SOURCE[0]}")}"

# Temporary storage for Go binary path
_GO_BINARY=""

# Start a server with resource limits
# Args: $1=lang, $2=log_file, $3=cpu_quota (optional, %), $4=memory_max (optional, e.g. 1G)
# Returns: PID via stdout, sets _GO_BINARY if Go
server_start() {
    local lang=$1 log_file=$2
    local cpu_quota=${3:-$SERVER_CPU_QUOTA}
    local memory_max=${4:-$SERVER_MEMORY_MAX}
    local port=$(server_get_port "$lang")
    local core=$(server_get_core "$lang")
    local pid=""
    
    # Free port if busy
    source "$(dirname "${BASH_SOURCE[0]}")/bench_lib.sh" 2>/dev/null
    bench_free_port "$port"
    
    # Calculate number of cores needed from percentage (100% = 1 core, 200% = 2 cores, etc.)
    # If cpu_quota is empty, use default (0.5 core = 50%)
    local num_cores
    if [[ -z "$cpu_quota" ]]; then
        num_cores=1  # Will use 0.5 core via taskset
    else
        num_cores=$(( (cpu_quota + 99) / 100 ))  # Round up
    fi
    [[ $num_cores -lt 1 ]] && num_cores=1
    
    # Build CPU affinity list (if > 100%, use multiple cores)
    local cpu_affinity=""
    if [[ $num_cores -eq 1 ]]; then
        cpu_affinity="$core"
    else
        # Use consecutive cores starting from the base core
        local cores=""
        for ((i=0; i<num_cores; i++)); do
            cores="${cores}$((core + i))"
            [[ $i -lt $((num_cores - 1)) ]] && cores="${cores},"
        done
        cpu_affinity="$cores"
    fi
    
    # Use systemd-run for resource limits if available, otherwise just taskset
    local run_cmd=""
    if command -v systemd-run &>/dev/null; then
        # systemd-run with CPU and memory limits
        # If CPU quota > 100%, allow multiple cores via taskset
        run_cmd="systemd-run --user --scope --quiet --property=CPUQuota=${cpu_quota}% --property=MemoryMax=${memory_max} taskset -c ${cpu_affinity}"
    else
        # Fallback to just taskset if systemd-run not available
        run_cmd="taskset -c ${cpu_affinity}"
    fi
    
    case $lang in
        js)
            $run_cmd node "$SERVER_DIR/server.js" > "$log_file" 2>&1 &
            pid=$!
            ;;
        py)
            $run_cmd python3 "$SERVER_DIR/server.py" > "$log_file" 2>&1 &
            pid=$!
            ;;
        go)
            # Pre-compile Go binary
            _GO_BINARY="/tmp/go_server_$$"
            go build -o "$_GO_BINARY" "$SERVER_DIR/server.go" 2>"$log_file"
            if [[ -f "$_GO_BINARY" ]]; then
                $run_cmd "$_GO_BINARY" >> "$log_file" 2>&1 &
                pid=$!
            fi
            ;;
        rust)
            # Compile and run Rust
            local rust_bin="/tmp/rust_server_$$"
            rustc -O "$SERVER_DIR/server.rs" -o "$rust_bin" 2>"$log_file"
            if [[ -f "$rust_bin" ]]; then
                $run_cmd "$rust_bin" >> "$log_file" 2>&1 &
                pid=$!
                rm -f "$rust_bin"  # Binary is loaded, can remove
            fi
            ;;
    esac
    
    echo "$pid"
}

# Wait for server to be ready
# Args: $1=port, $2=timeout_seconds
server_wait_ready() {
    local port=$1 timeout=${2:-10}
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s -o /dev/null "http://localhost:$port/" 2>/dev/null; then
            return 0
        fi
        sleep 0.2
        elapsed=$((elapsed + 1))
    done
    
    return 1
}

# Cleanup Go binary if exists
server_cleanup() {
    [[ -n "$_GO_BINARY" && -f "$_GO_BINARY" ]] && rm -f "$_GO_BINARY"
}

# Validate language
server_is_valid_lang() {
    local lang=$1
    for l in "${SERVER_LANGS[@]}"; do
        [[ "$l" == "$lang" ]] && return 0
    done
    return 1
}

