#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
# Simple HTTP Server Test
# ═══════════════════════════════════════════════════════════════════════════════

GO_BINARY=""
declare -a PIDS=()

get_port() {
    case $1 in js) echo 3000;; py) echo 3001;; go) echo 3002;; rust) echo 3003;; esac
}

get_name() {
    case $1 in js) echo "JavaScript";; py) echo "Python";; go) echo "Go";; rust) echo "Rust";; esac
}

get_core() {
    case $1 in js) echo 0;; py) echo 1;; go) echo 2;; rust) echo 3;; esac
}

cleanup() {
    echo -e "\n🧹 Cleaning up..."
    for pid in "${PIDS[@]}"; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
    done
    [[ -n "$GO_BINARY" && -f "$GO_BINARY" ]] && rm -f "$GO_BINARY"
}
trap cleanup EXIT INT TERM

find_pid_by_port() {
    local port=$1
    if command -v lsof &>/dev/null; then
        lsof -ti:"$port" 2>/dev/null | head -1
    elif command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -oP "(?<=:$port ).*pid=\K\d+" | head -1
    else
        echo ""
    fi
}

start_server() {
    local lang=$1 logfile=$2
    local port=$(get_port "$lang")
    local core=$(get_core "$lang")
    
    case $lang in
        js)
            taskset -c "$core" node server.js >"$logfile" 2>&1 &
            ;;
        py)
            taskset -c "$core" python3 server.py >"$logfile" 2>&1 &
            ;;
        go)
            GO_BINARY="/tmp/go_test_$$"
            go build -o "$GO_BINARY" server.go 2>/dev/null || return 1
            taskset -c "$core" "$GO_BINARY" >"$logfile" 2>&1 &
            ;;
        rust)
            [[ ! -f server || server.rs -nt server ]] && { 
                echo "🔨 Compiling Rust..."
                rustc server.rs -o server 2>/dev/null || return 1
            }
            taskset -c "$core" ./server >"$logfile" 2>&1 &
            ;;
    esac
    
    # Wait for server to bind to port
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
        echo "❌ Failed"
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
    timed_curl -X POST "http://localhost:$port/something" -d '{"hello":"world"}'
}

main() {
    cd "$(dirname "$0")"
    
    echo "🚀 Starting servers (pinned to CPU cores 0-3)..."
    
    local -a errors=()
    local -a started=()
    
    for lang in js py go rust; do
        if command -v "$(echo "$lang" | sed 's/js/node/;s/py/python3/;s/rust/rustc/')" &>/dev/null || [[ "$lang" == "go" ]]; then
            if start_server "$lang" "/tmp/${lang}_server.log"; then
                local pid=$(find_pid_by_port "$(get_port "$lang")")
                echo "   $(get_name "$lang") → core $(get_core "$lang"), PID $pid"
                started+=("$lang")
            else
                echo "   ❌ $(get_name "$lang") failed to start"
                errors+=("$lang")
            fi
        else
            echo "   ❌ $(get_name "$lang") - runtime not found"
            errors+=("$lang")
        fi
    done
    
    [[ ${#started[@]} -eq 0 ]] && { echo "❌ No servers started!"; exit 1; }
    
    echo "✅ ${#started[@]} servers ready!"
    
    for lang in "${started[@]}"; do
        test_server "$(get_name "$lang")" "$(get_port "$lang")"
    done
    
    echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ ${#errors[@]} -eq 0 ]]; then
        echo "✅ All tests complete!"
    else
        echo "⚠️  Tests complete (failed: ${errors[*]})"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
