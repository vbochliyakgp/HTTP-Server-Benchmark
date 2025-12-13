#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# benchmark.sh - HTTP Server Benchmark Runner
# ═══════════════════════════════════════════════════════════════════════════════
#
# Benchmarks a single server at a time with live-updating display.
#
# Usage: ./benchmark.sh -l <lang> [-e <endpoint>] [-c <concurrency>] <num_requests>
#
# ═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

# Load modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bench_lib.sh"
source "$SCRIPT_DIR/server_config.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Global State
# ─────────────────────────────────────────────────────────────────────────────

TEMP_DIR=""
SERVER_PID=""
FIRST_DRAW=true
TABLE_START_LINE=0

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────

cleanup() {
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    server_cleanup
    bench_show_cursor
}
trap cleanup EXIT INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# Display
# ─────────────────────────────────────────────────────────────────────────────

print_table() {
    local lang=$1 endpoints=$2 num=$3
    local name=$(server_get_name "$lang")
    local port=$(server_get_port "$lang")
    
    # Get current CPU/MEM
    local pid=$(bench_find_pid_by_port "$port")
    local cpu="0.00" mem="0"
    if [[ -n "$pid" ]]; then
        read cpu mem <<< "$(bench_get_resources "$pid")"
    fi
    
    # Calculate total lines
    local num_eps=$(echo "$endpoints" | wc -w)
    local total_lines=$((5 + num_eps + 1))  # header(5) + rows + footer(1)
    
    if [[ "$FIRST_DRAW" == "true" ]]; then
        FIRST_DRAW=false
        # Save starting position
        tput sc 2>/dev/null
    else
        # Restore to saved position
        tput rc 2>/dev/null
    fi
    
    # Header
    printf "%-12s  CPU: %-6s  MEM: %-4s MB\n" "$name" "$cpu" "$mem"
    echo "┌────────────┬────────┬────────┬──────────┬────────┬────────┬────────┬────────┬────────┐"
    echo "│ Endpoint   │   Done │ Failed │   Req/s  │ Min ms │ Avg ms │ P50 ms │ P95 ms │ Max ms │"
    echo "├────────────┼────────┼────────┼──────────┼────────┼────────┼────────┼────────┼────────┤"
    
    for ep_name in $endpoints; do
        local status_file="$TEMP_DIR/status_${ep_name}.txt"
        local data_file="$TEMP_DIR/data_${ep_name}.txt"
        local final_file="$TEMP_DIR/final_${ep_name}.txt"
        
        local status=$(cat "$status_file" 2>/dev/null || echo "pending")
        
        if [[ "$status" == "done" ]]; then
            local stats=$(cat "$final_file" 2>/dev/null || echo "0 0 0 0 0 0 0 0")
            read done_count failed rps min avg p50 p95 max <<< "$stats"
            printf "│ %-10s │ %6s │ %6s │ %8s │ %6s │ %6s │ %6s │ %6s │ %6s │\n" \
                "$ep_name" "$done_count" "$failed" "$rps" "$min" "$avg" "$p50" "$p95" "$max"
        elif [[ "$status" == "running" ]]; then
            local count=$(wc -l < "$data_file" 2>/dev/null || echo 0)
            printf "│ %-10s │ %6s │ %6s │ %8s │ %6s │ %6s │ %6s │ %6s │ %6s │\n" \
                "$ep_name" "$count" "-" "-" "-" "-" "-" "-" "-"
        else
            printf "│ %-10s │ %6s │ %6s │ %8s │ %6s │ %6s │ %6s │ %6s │ %6s │\n" \
                "$ep_name" "-" "-" "-" "-" "-" "-" "-" "-"
        fi
    done
    
    echo "└────────────┴────────┴────────┴──────────┴────────┴────────┴────────┴────────┴────────┘"
    
    # Clear any remaining lines below
    tput ed 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Benchmark Logic
# ─────────────────────────────────────────────────────────────────────────────

run_endpoint_benchmark() {
    local port=$1 ep_name=$2 num=$3 conc=$4
    
    local ep_def=$(server_get_endpoint "$ep_name")
    local path=$(server_parse_endpoint "$ep_def" "path")
    local method=$(server_parse_endpoint "$ep_def" "method")
    local body=$(server_parse_endpoint "$ep_def" "body")
    local url="http://localhost:$port$path"
    
    local data_file="$TEMP_DIR/data_${ep_name}.txt"
    local final_file="$TEMP_DIR/final_${ep_name}.txt"
    local status_file="$TEMP_DIR/status_${ep_name}.txt"
    
    echo "running" > "$status_file"
    
    local start=$(date +%s%N)
    bench_run_requests "$url" "$method" "$body" "$num" "$conc" "$data_file"
    local end=$(date +%s%N)
    local total_ms=$(( (end - start) / 1000000 ))
    [[ $total_ms -lt 1 ]] && total_ms=1
    
    bench_calc_stats "$data_file" "$total_ms" > "$final_file"
    echo "done" > "$status_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat << 'EOF'
Usage: ./benchmark.sh [OPTIONS] <num_requests>

Options:
  -l, --lang         Language: js, py, go, rust (required)
  -e, --endpoint     Endpoint: root, query, json, post, or "all" (default: all)
  -c, --concurrency  Concurrent requests (default: 1)
  --cpu-lmt-cores    Number of CPU cores (default: 0.5)
  --mem-lmt          Memory limit (e.g., 1G, 512M) (default: 1G)
  -h, --help         Show this help

Examples:
  ./benchmark.sh -l js 100                              # JS server, 100 sequential requests
  ./benchmark.sh -l go -c 10 500                        # Go server, 500 requests, 10 concurrent
  ./benchmark.sh -l rust -e root -c 5 200               # Rust, root endpoint only, 5 concurrent
  ./benchmark.sh -l js --cpu-lmt-cores 2 --mem-lmt 2G 1000  # 2 cores, 2GB RAM
EOF
    exit 0
}

main() {
    local LANG="" ENDPOINT="all" CONC=1 NUM=""
    local CPU_CORES="" MEMORY_LIMIT=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--lang) LANG="$2"; shift 2 ;;
            -e|--endpoint) ENDPOINT="$2"; shift 2 ;;
            -c|--concurrency) CONC="$2"; shift 2 ;;
            --cpu-lmt-cores) CPU_CORES="$2"; shift 2 ;;
            --mem-lmt) MEMORY_LIMIT="$2"; shift 2 ;;
            -h|--help) usage ;;
            -*) echo "Unknown option: $1"; exit 1 ;;
            *) NUM="$1"; shift ;;
        esac
    done
    
    # Validate
    [[ -z "$LANG" ]] && { echo "Error: -l/--lang is required"; usage; }
    [[ -z "$NUM" ]] && { echo "Error: num_requests is required"; usage; }
    
    if ! server_is_valid_lang "$LANG"; then
        echo "Error: Invalid language '$LANG'. Use: js, py, go, rust"
        exit 1
    fi
    
    # Build endpoint list
    local ep_list=""
    if [[ "$ENDPOINT" == "all" ]]; then
        for ep in "${SERVER_ENDPOINTS[@]}"; do
            ep_list="$ep_list $(server_parse_endpoint "$ep" "name")"
        done
    else
        ep_list="$ENDPOINT"
    fi
    ep_list=$(echo "$ep_list" | xargs)  # Trim
    
    # "all" concurrency means all at once
    [[ "$CONC" == "all" ]] && CONC=$NUM
    
    # Setup
    TEMP_DIR=$(mktemp -d)
    for ep_name in $ep_list; do
        echo "pending" > "$TEMP_DIR/status_${ep_name}.txt"
        > "$TEMP_DIR/data_${ep_name}.txt"
    done
    
    local port=$(server_get_port "$LANG")
    local name=$(server_get_name "$LANG")
    local core=$(server_get_core "$LANG")
    
    # Start server with resource limits
    # Convert cores to percentage for systemd (1 core = 100%, 0.5 core = 50%, etc.)
    local cpu_quota=""
    if [[ -n "$CPU_CORES" ]]; then
        # Multiply by 100 to get percentage (e.g., 2 cores = 200%, 0.5 = 50%)
        cpu_quota=$(awk "BEGIN {printf \"%.0f\", $CPU_CORES * 100}")
    fi
    
    local cpu_info="CPU core $core"
    [[ -n "$CPU_CORES" ]] && cpu_info="$cpu_info, ${CPU_CORES} core(s)"
    [[ -n "$MEMORY_LIMIT" ]] && cpu_info="$cpu_info, ${MEMORY_LIMIT} RAM"
    echo "🚀 Starting $name server on port $port ($cpu_info)..."
    SERVER_PID=$(server_start "$LANG" "$TEMP_DIR/server.log" "$cpu_quota" "$MEMORY_LIMIT")
    
    if [[ -z "$SERVER_PID" ]]; then
        echo "❌ Failed to start server"
        cat "$TEMP_DIR/server.log" 2>/dev/null
        exit 1
    fi
    
    # Wait for ready
    if ! server_wait_ready "$port" 10; then
        echo "❌ Server failed to start"
        cat "$TEMP_DIR/server.log" 2>/dev/null
        exit 1
    fi
    
    # Get actual PID (after taskset)
    SERVER_PID=$(bench_find_pid_by_port "$port")
    echo "   PID: $SERVER_PID"
    
    local mode="sequential"
    [[ $CONC -gt 1 ]] && mode="concurrent (×$CONC)"
    [[ $CONC -eq $NUM ]] && mode="all concurrent"
    
    echo ""
    echo "📊 Benchmark: $NUM requests per endpoint, $mode"
    echo "   Endpoints: $ep_list"
    echo ""
    
    bench_hide_cursor
    
    # Start benchmark in background
    (
        for ep_name in $ep_list; do
            run_endpoint_benchmark "$port" "$ep_name" "$NUM" "$CONC"
        done
    ) &
    local bench_pid=$!
    
    # Live update loop
    print_table "$LANG" "$ep_list" "$NUM"
    
    while kill -0 "$bench_pid" 2>/dev/null; do
        sleep 0.5
        print_table "$LANG" "$ep_list" "$NUM"
    done
    
    wait "$bench_pid" 2>/dev/null
    
    # Final draw
    print_table "$LANG" "$ep_list" "$NUM"
    
    bench_show_cursor
    echo ""
    echo "✅ Benchmark complete!"
}

main "$@"
