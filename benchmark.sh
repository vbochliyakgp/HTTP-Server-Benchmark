#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# benchmark.sh - High-Performance HTTP Server Benchmark using wrk
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bench_lib.sh"
source "$SCRIPT_DIR/server_config.sh"

# ─────────────────────────────────────────────────────────────────────────────
# State
# ─────────────────────────────────────────────────────────────────────────────

SERVER_PID=""
TEMP_DIR=""

cleanup() {
    bench_show_cursor
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    server_cleanup 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# Output Formatting
# ─────────────────────────────────────────────────────────────────────────────

# Colors (disable if not terminal)
if [[ -t 1 ]]; then
    BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
    GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; RED='\033[31m'
else
    BOLD=''; DIM=''; RESET=''; GREEN=''; YELLOW=''; CYAN=''; RED=''
fi

header() { echo -e "\n${BOLD}$1${RESET}"; }
info()   { echo -e "${CYAN}$1${RESET}"; }
ok()     { echo -e "${GREEN}✓${RESET} $1"; }
err()    { echo -e "${RED}✗${RESET} $1"; }

print_table_header() {
    echo "┌────────────┬───────────┬────────┬───────────┬─────────┬─────────┬─────────┬─────────┬─────────┐"
    echo "│ Endpoint   │  Requests │ Errors │   Req/s   │ Avg(ms) │ P50(ms) │ P90(ms) │ P99(ms) │ Max(ms) │"
    echo "├────────────┼───────────┼────────┼───────────┼─────────┼─────────┼─────────┼─────────┼─────────┤"
}

print_table_row() {
    printf "│ %-10s │ %9s │ %6s │ %9s │ %7s │ %7s │ %7s │ %7s │ %7s │\n" "$@"
}

print_table_footer() {
    echo "└────────────┴───────────┴────────┴───────────┴─────────┴─────────┴─────────┴─────────┴─────────┘"
}

# Format large numbers with commas
fmt_num() {
    printf "%'d" "${1:-0}" 2>/dev/null || echo "${1:-0}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat << 'EOF'
Usage: ./benchmark.sh -l <lang> [OPTIONS]

Required:
  -l, --lang         Language: js, py, go, rust

Options:
  -e, --endpoint     Endpoint: root, query, json, post, or "all" (default: all)
  -c, --connections  Concurrent connections (default: 50)
  -d, --duration     Duration per endpoint in seconds (default: 5)
  -t, --threads      wrk threads (default: auto-calculated)
  --cpu              CPU cores for server (default: 1)
  --mem              Memory limit for server (default: 1G)
  -h, --help         Show this help

Examples:
  ./benchmark.sh -l js                        # JS, 50 connections, 5s
  ./benchmark.sh -l go -c 200 -d 10           # Go, 200 connections, 10s
  ./benchmark.sh -l py --cpu 2 --mem 2G       # Python, 2 cores, 2GB RAM
  ./benchmark.sh -l rust -e root -c 100       # Rust, root endpoint only
EOF
    exit 0
}

main() {
    local lang="" endpoint="all" conns=50 duration=5 threads=""
    local cpu_cores="1" mem_limit="1G"
    
    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--lang)        lang="$2"; shift 2 ;;
            -e|--endpoint)    endpoint="$2"; shift 2 ;;
            -c|--connections) conns="$2"; shift 2 ;;
            -d|--duration)    duration="$2"; shift 2 ;;
            -t|--threads)     threads="$2"; shift 2 ;;
            --cpu)            cpu_cores="$2"; shift 2 ;;
            --mem)            mem_limit="$2"; shift 2 ;;
            -h|--help)        usage ;;
            *)                shift ;;
        esac
    done
    
    # Validate
    [[ -z "$lang" ]] && { err "Missing -l/--lang"; usage; }
    server_is_valid_lang "$lang" || { err "Invalid language: $lang"; exit 1; }
    
    # Auto-calculate threads (1 per 50 connections, max 4)
    if [[ -z "$threads" ]]; then
        threads=$(( (conns + 49) / 50 ))
        [[ $threads -gt 4 ]] && threads=4
        [[ $threads -lt 1 ]] && threads=1
    fi
    
    # Build endpoint list
    local -a endpoints=()
    if [[ "$endpoint" == "all" ]]; then
        for ep in "${SERVER_ENDPOINTS[@]}"; do
            endpoints+=("$(server_parse_endpoint "$ep" "name")")
        done
    else
        endpoints=("$endpoint")
    fi
    
    # Setup
    TEMP_DIR=$(mktemp -d)
    local port=$(server_get_port "$lang")
    local name=$(server_get_name "$lang")
    local cpu_quota=$(awk "BEGIN {printf \"%.0f\", $cpu_cores * 100}")
    
    # Header
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD} wrk Benchmark: $name${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${RESET}"
    
    # Check if resource limits are available
    local limits_available=false
    if command -v systemd-run &>/dev/null; then
        limits_available=true
    fi
    
    # Start server
    info "\n🚀 Starting $name server..."
    if $limits_available; then
        info "   Port: $port | CPU: ${cpu_cores} core(s) | RAM: $mem_limit"
    else
        info "   Port: $port | CPU/RAM limits: N/A (systemd-run not found)"
    fi
    
    SERVER_PID=$(server_start "$lang" "$TEMP_DIR/server.log" "$cpu_quota" "$mem_limit")
    
    if [[ -z "$SERVER_PID" ]]; then
        err "Failed to start server"
        [[ -f "$TEMP_DIR/server.log" ]] && cat "$TEMP_DIR/server.log"
        exit 1
    fi
    
    if ! server_wait_ready "$port" 30; then
        err "Server not ready after 30 retries"
        [[ -f "$TEMP_DIR/server.log" ]] && cat "$TEMP_DIR/server.log"
        exit 1
    fi
    
    SERVER_PID=$(bench_find_pid_by_port "$port")
    ok "Server running (PID: $SERVER_PID)"
    
    # Config summary
    info "\n📊 Benchmark Config"
    info "   Connections: $conns | Threads: $threads | Duration: ${duration}s/endpoint"
    info "   Endpoints: ${endpoints[*]}"
    
    # Warmup
    info "\n⏳ Warming up..."
    bench_warmup "http://localhost:$port/"
    sleep 0.5
    
    # Results storage
    local total_reqs=0 total_errs=0 total_rps=0
    
    # Run benchmarks
    header "📈 Results"
    print_table_header
    
    for ep_name in "${endpoints[@]}"; do
        local ep_def=$(server_get_endpoint "$ep_name")
        local path=$(server_parse_endpoint "$ep_def" "path")
        local method=$(server_parse_endpoint "$ep_def" "method")
        local body=$(server_parse_endpoint "$ep_def" "body")
        local url="http://localhost:$port$path"
        
        # Run benchmark
        local result=$(bench_wrk "$url" "$method" "$body" "$duration" "$conns" "$threads")
        read reqs errs rps avg p50 p90 p99 maxl <<< "$result"
        
        # Accumulate totals
        total_reqs=$((total_reqs + ${reqs%.*}))
        total_errs=$((total_errs + ${errs%.*}))
        total_rps=$(awk "BEGIN {print $total_rps + $rps}")
        
        # Format and print
        print_table_row "$ep_name" "$(fmt_num ${reqs%.*})" "${errs%.*}" \
            "$(printf "%.1f" "$rps")" \
            "$(printf "%.2f" "$avg")" \
            "$(printf "%.2f" "$p50")" \
            "$(printf "%.2f" "$p90")" \
            "$(printf "%.2f" "$p99")" \
            "$(printf "%.2f" "$maxl")"
    done
    
    print_table_footer
    
    # Summary
    local res=$(bench_get_resources "$SERVER_PID")
    read cpu mem <<< "$res"
    
    header "📊 Summary"
    echo "   Total Requests: $(fmt_num $total_reqs)"
    echo "   Total Errors:   $(fmt_num $total_errs)"
    echo "   Avg Throughput: $(printf "%.1f" "$total_rps") req/s (sum across endpoints)"
    echo "   Server CPU:     ${cpu}%"
    echo "   Server Memory:  ${mem} MB"
    
    echo -e "\n${GREEN}✅ Benchmark complete!${RESET}\n"
}

main "$@"
