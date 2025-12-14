#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# server_config.sh - Server Configuration and Management
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# Server Definitions
# ─────────────────────────────────────────────────────────────────────────────

SERVER_LANGS=(js py go rust cpp)

server_get_port() {
    case $1 in
        js)   echo 3000 ;;
        py)   echo 3001 ;;
        go)   echo 3002 ;;
        rust) echo 3003 ;;
        cpp)  echo 3004 ;;
        *)    echo 0 ;;
    esac
}

server_get_name() {
    case $1 in
        js)   echo "JavaScript" ;;
        py)   echo "Python" ;;
        go)   echo "Go" ;;
        rust) echo "Rust" ;;
        cpp)  echo "C++" ;;
        *)    echo "Unknown" ;;
    esac
}

server_get_core() {
    case $1 in
        js)   echo 0 ;;
        py)   echo 1 ;;
        go)   echo 2 ;;
        rust) echo 3 ;;
        cpp)  echo 4 ;;
        *)    echo 0 ;;
    esac
}

server_is_valid_lang() {
    local lang=$1
    for l in "${SERVER_LANGS[@]}"; do
        [[ "$l" == "$lang" ]] && return 0
    done
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# API Endpoints
# ─────────────────────────────────────────────────────────────────────────────

SERVER_ENDPOINTS=(
    "root|/|GET|"
    "query|/something?name=test&value=123|GET|"
    "json|/something?name=test&json=true|GET|"
    "post|/something|POST|{\"test\":\"data\"}"
)

server_parse_endpoint() {
    local def=$1 field=$2
    case $field in
        name)   echo "$def" | cut -d'|' -f1 ;;
        path)   echo "$def" | cut -d'|' -f2 ;;
        method) echo "$def" | cut -d'|' -f3 ;;
        body)   echo "$def" | cut -d'|' -f4 ;;
    esac
}

server_get_endpoint() {
    local name=$1
    for ep in "${SERVER_ENDPOINTS[@]}"; do
        [[ "$(echo "$ep" | cut -d'|' -f1)" == "$name" ]] && { echo "$ep"; return; }
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Server Management
# ─────────────────────────────────────────────────────────────────────────────

SERVER_DIR="${SERVER_DIR:-$(dirname "${BASH_SOURCE[0]}")/servers}"
_GO_BINARY=""
_RUST_BINARY=""
_CPP_BINARY=""

# Start server with resource limits
# Args: $1=lang $2=log_file $3=cpu_quota(%) $4=memory_max
# Returns: PID
server_start() {
    local lang=$1 log_file=$2 cpu_quota=${3:-100} memory_max=${4:-1G}
    local port=$(server_get_port "$lang")
    local core=$(server_get_core "$lang")
    local pid=""
    
    # Ensure port is free
    local existing_pid
    existing_pid=$(lsof -ti ":$port" -sTCP:LISTEN 2>/dev/null | head -1) || true
    [[ -n "$existing_pid" ]] && kill -9 "$existing_pid" 2>/dev/null && sleep 0.3
    
    # Calculate cores needed
    local num_cores=$(( (cpu_quota + 99) / 100 ))
    [[ $num_cores -lt 1 ]] && num_cores=1
    
    # Build affinity (single core or range)
    local affinity="$core"
    if [[ $num_cores -gt 1 ]]; then
        local end_core=$((core + num_cores - 1))
        affinity="$core-$end_core"
    fi
    
    # Build run command with limits
    local run_cmd="taskset -c $affinity"
    if command -v systemd-run &>/dev/null; then
        run_cmd="systemd-run --user --scope --quiet -p CPUQuota=${cpu_quota}% -p MemoryMax=$memory_max $run_cmd"
    fi
    
    case $lang in
        js)
            $run_cmd node "$SERVER_DIR/server.js" >"$log_file" 2>&1 &
            pid=$!
            ;;
        py)
            $run_cmd python3 "$SERVER_DIR/server.py" >"$log_file" 2>&1 &
            pid=$!
            ;;
        go)
            _GO_BINARY="/tmp/go_server_$$"
            if go build -o "$_GO_BINARY" "$SERVER_DIR/server.go" 2>"$log_file"; then
                $run_cmd "$_GO_BINARY" >>"$log_file" 2>&1 &
                pid=$!
            fi
            ;;
        rust)
            _RUST_BINARY="/tmp/rust_server_$$"
            # Try to find actual rustc binary (bypass rustup proxy)
            local rustc_bin=""
            if [[ -d "$HOME/.rustup/toolchains" ]]; then
                rustc_bin=$(find "$HOME/.rustup/toolchains" -name "rustc" -type f 2>/dev/null | head -1)
            fi
            [[ -z "$rustc_bin" ]] && rustc_bin=$(which rustc 2>/dev/null || echo "")
            
            # Try direct rustc call with bypass
            if [[ -n "$rustc_bin" ]] && "$rustc_bin" -O "$SERVER_DIR/server.rs" -o "$_RUST_BINARY" 2>>"$log_file" 2>/dev/null; then
                $run_cmd "$_RUST_BINARY" >>"$log_file" 2>&1 &
                pid=$!
            elif command -v rustc &>/dev/null; then
                # Last resort: try rustc anyway (may fail)
                if RUSTUP_TOOLCHAIN=stable rustc -O "$SERVER_DIR/server.rs" -o "$_RUST_BINARY" 2>>"$log_file" 2>/dev/null; then
                    $run_cmd "$_RUST_BINARY" >>"$log_file" 2>&1 &
                    pid=$!
                fi
            fi
            ;;
        cpp)
            _CPP_BINARY="/tmp/cpp_server_$$"
            # Compile C++ with optimizations
            if command -v g++ &>/dev/null; then
                if g++ -O3 -std=c++17 -pthread "$SERVER_DIR/server.cpp" -o "$_CPP_BINARY" 2>"$log_file"; then
                    $run_cmd "$_CPP_BINARY" >>"$log_file" 2>&1 &
                    pid=$!
                fi
            elif command -v clang++ &>/dev/null; then
                if clang++ -O3 -std=c++17 -pthread "$SERVER_DIR/server.cpp" -o "$_CPP_BINARY" 2>"$log_file"; then
                    $run_cmd "$_CPP_BINARY" >>"$log_file" 2>&1 &
                    pid=$!
                fi
            fi
            ;;
    esac
    
    echo "$pid"
}

# Wait for server to respond
# Args: $1=port $2=max_retries (default 30)
server_wait_ready() {
    local port=$1 max_retries=${2:-30}
    local i=0
    
    while [[ $i -lt $max_retries ]]; do
        if curl -sf -o /dev/null --max-time 1 "http://localhost:$port/" 2>/dev/null; then
            return 0
        fi
        sleep 0.2
        ((i++))
    done
    return 1
}

# Cleanup binaries
server_cleanup() {
    [[ -n "$_GO_BINARY" && -f "$_GO_BINARY" ]] && rm -f "$_GO_BINARY"
    [[ -n "$_RUST_BINARY" && -f "$_RUST_BINARY" ]] && rm -f "$_RUST_BINARY"
    [[ -n "$_CPP_BINARY" && -f "$_CPP_BINARY" ]] && rm -f "$_CPP_BINARY"
}
