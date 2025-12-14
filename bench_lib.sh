#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# bench_lib.sh - Generic HTTP Benchmarking Library
# ═══════════════════════════════════════════════════════════════════════════════
# 
# Provides reusable functions for:
#   - HTTP requests with timing
#   - Concurrent request execution
#   - Statistics calculation
#   - Resource monitoring
#   - Live terminal display
#
# Usage: source this file in your benchmark script
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# HTTP Requests
# ─────────────────────────────────────────────────────────────────────────────

# Make a single HTTP request and return "status latency_ms"
# Args: $1=url, $2=method (GET/POST), $3=body (optional)
bench_request() {
    local url=$1 method=${2:-GET} body=$3
    local start end status ms
    
    start=$(date +%s%N)
    if [[ "$method" == "POST" ]]; then
        status=$(curl -s -o /dev/null -w "%{http_code}" -X POST -d "$body" "$url" 2>/dev/null)
    else
        status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    fi
    end=$(date +%s%N)
    
    ms=$(( (end - start) / 1000000 ))
    [[ -z "$status" || "$status" == "000" ]] && status=0
    
    echo "$status $ms"
}

# Run N requests to an endpoint, with concurrency limit
# Args: $1=url, $2=method, $3=body, $4=num_requests, $5=concurrency, $6=output_file
# Uses HTTP keep-alive to reuse connections and avoid network stack saturation
bench_run_requests() {
    local url=$1 method=$2 body=$3 num=$4 conc=$5 outfile=$6
    
    > "$outfile"  # Clear output file
    
    # Create temp directory for worker files to avoid I/O contention
    local tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT
    
    # For efficiency with large request counts, use xargs for parallelism
    # Each worker writes to its own temp file to avoid lock contention
    # Uses HTTP keep-alive to reuse connections (reduces network overhead)
    local worker='
        url="$1"; method="$2"; body="$3"; tmpdir="$4"; worker_id="$5"
        worker_file="${tmpdir}/worker_${worker_id}.txt"
        > "$worker_file"
        
        start=$(date +%s%N)
        if [[ "$method" == "POST" ]]; then
            status=$(curl -s -o /dev/null -w "%{http_code}" --keepalive-time 30 --tcp-nodelay -X POST -d "$body" "$url" 2>/dev/null)
        else
            status=$(curl -s -o /dev/null -w "%{http_code}" --keepalive-time 30 --tcp-nodelay "$url" 2>/dev/null)
        fi
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        [[ -z "$status" || "$status" == "000" ]] && status=0
        ok=0
        [[ "$status" -ge 200 && "$status" -lt 300 ]] && ok=1
        echo "$ok $ms" > "$worker_file"
    '
    
    # Generate sequence and run with xargs (each gets unique worker ID)
    seq 1 "$num" | xargs -P "$conc" -I {} bash -c "$worker" _ "$url" "$method" "$body" "$tmpdir" "{}"
    
    # Merge all worker files into output file (fast, no contention)
    cat "$tmpdir"/worker_*.txt 2>/dev/null > "$outfile"
    
    # Cleanup
    rm -rf "$tmpdir"
    trap - EXIT
}

# ─────────────────────────────────────────────────────────────────────────────
# Statistics
# ─────────────────────────────────────────────────────────────────────────────

# Calculate stats from result file
# Args: $1=result_file, $2=total_time_ms
# Returns: "done failed rps min avg p50 p95 max"
bench_calc_stats() {
    local file=$1 total_ms=$2
    
    [[ ! -f "$file" || ! -s "$file" ]] && { echo "0 0 0 0 0 0 0 0"; return; }
    
    awk -v total_ms="$total_ms" '
    BEGIN { ok=0; fail=0; n=0 }
    {
        if ($1 == 1) ok++; else fail++
        times[n++] = $2
    }
    END {
        if (n == 0) { print "0 0 0 0 0 0 0 0"; exit }
        
        # Sort times
        for (i=0; i<n; i++) {
            for (j=i+1; j<n; j++) {
                if (times[i] > times[j]) {
                    t = times[i]; times[i] = times[j]; times[j] = t
                }
            }
        }
        
        # Calculate
        sum = 0
        for (i=0; i<n; i++) sum += times[i]
        
        min = times[0]
        max = times[n-1]
        avg = int(sum / n)
        p50 = times[int(n * 0.5)]
        p95 = times[int(n * 0.95)]
        
        rps = (total_ms > 0) ? sprintf("%.2f", ok * 1000.0 / total_ms) : 0
        
        printf "%d %d %s %d %d %d %d %d\n", ok, fail, rps, min, avg, p50, p95, max
    }' "$file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Resource Monitoring
# ─────────────────────────────────────────────────────────────────────────────

# Get CPU% and MEM(MB) for a process and its children
# Args: $1=pid
# Returns: "cpu mem"
bench_get_resources() {
    local pid=$1
    [[ -z "$pid" ]] && { echo "0.00 0"; return; }
    
    # Get process and children
    local all_pids="$pid"
    local children=$(pgrep -P "$pid" 2>/dev/null | tr '\n' ' ')
    [[ -n "$children" ]] && all_pids="$pid $children"
    
    local cpu=$(ps -p $all_pids -o %cpu= 2>/dev/null | awk '{sum+=$1} END {printf "%.2f", sum+0}')
    local mem=$(ps -p $all_pids -o rss= 2>/dev/null | awk '{sum+=$1} END {printf "%.0f", sum/1024}')
    
    [[ -z "$cpu" ]] && cpu="0.00"
    [[ -z "$mem" ]] && mem="0"
    
    echo "$cpu $mem"
}

# Find PID listening on a port
# Args: $1=port
bench_find_pid_by_port() {
    local port=$1
    local pid=""
    
    if command -v lsof &>/dev/null; then
        pid=$(lsof -ti ":$port" -sTCP:LISTEN 2>/dev/null | head -1)
    elif command -v ss &>/dev/null; then
        pid=$(ss -tlnp "sport = :$port" 2>/dev/null | awk -F'pid=' 'NR>1 {print $2}' | cut -d',' -f1 | head -1)
    elif command -v netstat &>/dev/null; then
        pid=$(netstat -tlnp 2>/dev/null | awk -v p="$port" '$4 ~ ":"p"$" {print $7}' | cut -d'/' -f1 | head -1)
    fi
    
    echo "$pid"
}

# Kill process on port if busy
# Args: $1=port
bench_free_port() {
    local port=$1
    local pid=$(bench_find_pid_by_port "$port")
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null && sleep 0.5
}

# ─────────────────────────────────────────────────────────────────────────────
# Display Utilities
# ─────────────────────────────────────────────────────────────────────────────

# Track cursor position for live updates
_BENCH_FIRST_DRAW=true
_BENCH_TABLE_LINES=0

# Move cursor up for redraw
bench_cursor_up() {
    local lines=$1
    [[ $lines -gt 0 ]] && tput cuu "$lines"
}

# Hide/show cursor
bench_hide_cursor() { tput civis 2>/dev/null; }
bench_show_cursor() { tput cnorm 2>/dev/null; }

# Print a simple progress line
# Args: $1=done, $2=total, $3=label
bench_print_progress() {
    local done=$1 total=$2 label=$3
    local pct=$((done * 100 / total))
    printf "\r%-20s [%3d%%] %d/%d" "$label" "$pct" "$done" "$total"
}

