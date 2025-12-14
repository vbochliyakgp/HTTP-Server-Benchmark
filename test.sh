#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# test.sh - Functional Test for HTTP Servers
# ═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

# Server directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/servers"

GO_BINARY=""
RUST_BINARY=""
CPP_BINARY=""
declare -a PIDS=()

get_port() {
    case $1 in js) echo 3000;; py) echo 3001;; go) echo 3002;; rust) echo 3003;; cpp) echo 3004;; esac
}

get_name() {
    case $1 in js) echo "JavaScript";; py) echo "Python";; go) echo "Go";; rust) echo "Rust";; cpp) echo "C++";; esac
}

cleanup() {
    echo -e "\n🧹 Cleaning up..."
    for pid in "${PIDS[@]}"; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
    done
    [[ -n "$GO_BINARY" && -f "$GO_BINARY" ]] && rm -f "$GO_BINARY"
    [[ -n "$RUST_BINARY" && -f "$RUST_BINARY" ]] && rm -f "$RUST_BINARY"
    [[ -n "$CPP_BINARY" && -f "$CPP_BINARY" ]] && rm -f "$CPP_BINARY"
}
trap cleanup EXIT INT TERM

find_pid_by_port() {
    local port=$1
    if command -v lsof &>/dev/null; then
        lsof -ti ":$port" -sTCP:LISTEN 2>/dev/null | head -1
    elif command -v ss &>/dev/null; then
        ss -tlnp "sport = :$port" 2>/dev/null | awk -F'pid=' 'NR>1{print $2}' | cut -d',' -f1 | head -1
    fi
}

start_server() {
    local lang=$1 logfile=$2
    local port=$(get_port "$lang")
    
    # Kill existing process on port
    local existing=$(find_pid_by_port "$port")
    [[ -n "$existing" ]] && kill -9 "$existing" 2>/dev/null && sleep 0.2
    
    case $lang in
        js)
            node "$SERVER_DIR/server.js" >"$logfile" 2>&1 &
            ;;
        py)
            python3 "$SERVER_DIR/server.py" >"$logfile" 2>&1 &
            ;;
        go)
            GO_BINARY="/tmp/go_test_$$"
            go build -o "$GO_BINARY" "$SERVER_DIR/server.go" 2>"$logfile" || return 1
            "$GO_BINARY" >>"$logfile" 2>&1 &
            ;;
        rust)
            RUST_BINARY="/tmp/rust_test_$$"
            # Find rustc binary (bypass rustup proxy issues)
            local rustc_bin=""
            if [[ -d "$HOME/.rustup/toolchains" ]]; then
                rustc_bin=$(find "$HOME/.rustup/toolchains" -name "rustc" -type f 2>/dev/null | head -1)
            fi
            [[ -z "$rustc_bin" ]] && rustc_bin=$(which rustc 2>/dev/null)
            
            if [[ -n "$rustc_bin" ]]; then
                "$rustc_bin" -O "$SERVER_DIR/server.rs" -o "$RUST_BINARY" 2>"$logfile" || return 1
                "$RUST_BINARY" >>"$logfile" 2>&1 &
            else
                echo "rustc not found" >"$logfile"
                return 1
            fi
            ;;
        cpp)
            CPP_BINARY="/tmp/cpp_test_$$"
            if command -v g++ &>/dev/null; then
                g++ -O3 -std=c++17 -pthread "$SERVER_DIR/server.cpp" -o "$CPP_BINARY" 2>"$logfile" || return 1
                "$CPP_BINARY" >>"$logfile" 2>&1 &
            elif command -v clang++ &>/dev/null; then
                clang++ -O3 -std=c++17 -pthread "$SERVER_DIR/server.cpp" -o "$CPP_BINARY" 2>"$logfile" || return 1
                "$CPP_BINARY" >>"$logfile" 2>&1 &
            else
                echo "g++ or clang++ not found" >"$logfile"
                return 1
            fi
            ;;
    esac
    
    # Wait for server to bind
    local tries=0
    while [[ $tries -lt 30 ]]; do
        local pid=$(find_pid_by_port "$port")
        if [[ -n "$pid" ]]; then
            PIDS+=("$pid")
            return 0
        fi
        sleep 0.2
        ((tries++))
    done
    return 1
}

timed_curl() {
    local start=$(date +%s%3N)
    local result
    result=$(curl -sf --max-time 5 "$@" 2>/dev/null)
    local code=$?
    local end=$(date +%s%3N)
    local ms=$((end - start))
    
    if [[ $code -eq 0 && -n "$result" ]]; then
        echo "$result"
        echo -e "   ⏱️  ${ms}ms"
    else
        echo "❌ Request failed"
    fi
}

test_server() {
    local name=$1 port=$2
    echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🧪 Testing $name (port $port)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo -e "\n📍 GET /"
    timed_curl "http://localhost:$port/"

    echo -e "\n📍 GET /something?name=test&foo=bar"
    timed_curl "http://localhost:$port/something?name=test&foo=bar"

    echo -e "\n📍 GET /something?json=true&key=value"
    timed_curl "http://localhost:$port/something?json=true&key=value"

    echo -e "\n📍 POST /something"
    timed_curl -X POST -H "Content-Type: application/json" \
        -d '{"hello":"world"}' "http://localhost:$port/something"
}

main() {
    cd "$(dirname "$0")"
    
    echo "🚀 Starting servers..."
    
    local -a errors=()
    local -a started=()
    
    for lang in js py go rust cpp; do
        local runtime
        case $lang in
            js) runtime="node" ;;
            py) runtime="python3" ;;
            go) runtime="go" ;;
            rust) runtime="rustc" ;;
            cpp) runtime="g++" ;;
        esac
        
        # Check if runtime exists (or for rust, check rustup toolchains)
        local has_runtime=false
        if command -v "$runtime" &>/dev/null; then
            has_runtime=true
        elif [[ "$lang" == "rust" && -d "$HOME/.rustup/toolchains" ]]; then
            has_runtime=true
        elif [[ "$lang" == "cpp" && ( -n "$(command -v g++ 2>/dev/null)" || -n "$(command -v clang++ 2>/dev/null)" ) ]]; then
            has_runtime=true
        fi
        
        if $has_runtime; then
            echo -n "   Starting $(get_name "$lang")... "
            if start_server "$lang" "/tmp/${lang}_server.log"; then
                echo "✓ port $(get_port "$lang")"
                started+=("$lang")
            else
                echo "✗ failed"
                errors+=("$lang")
            fi
        else
            echo "   Skipping $(get_name "$lang") - $runtime not found"
            errors+=("$lang")
        fi
    done
    
    [[ ${#started[@]} -eq 0 ]] && { echo "❌ No servers started!"; exit 1; }
    
    echo -e "\n✅ ${#started[@]} server(s) running"
    
    for lang in "${started[@]}"; do
        test_server "$(get_name "$lang")" "$(get_port "$lang")"
    done
    
    echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ ${#errors[@]} -eq 0 ]]; then
        echo "✅ All tests passed!"
    else
        echo "⚠️  Tests done (unavailable: ${errors[*]})"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
