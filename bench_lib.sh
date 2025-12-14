#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# bench_lib.sh - High-Performance HTTP Benchmarking Library using wrk
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# wrk Benchmark
# ─────────────────────────────────────────────────────────────────────────────

# Run wrk and return parsed stats
# Args: $1=url $2=method $3=body $4=duration $5=connections $6=threads
# Output: "requests errors rps avg_ms p50_ms p90_ms p99_ms max_ms"
bench_wrk() {
    local url=$1 method=${2:-GET} body=$3 duration=${4:-5} conns=${5:-10} threads=${6:-2}
    local lua_script="" wrk_output=""
    
    # Create Lua script for POST
    if [[ "$method" == "POST" ]]; then
        lua_script=$(mktemp --suffix=.lua)
        cat > "$lua_script" <<EOF
wrk.method = "POST"
wrk.body = [=[$body]=]
wrk.headers["Content-Type"] = "application/json"
EOF
    fi
    
    # Run wrk
    if [[ -n "$lua_script" ]]; then
        wrk_output=$(wrk -t"$threads" -c"$conns" -d"${duration}s" --latency -s "$lua_script" "$url" 2>&1)
        rm -f "$lua_script"
    else
        wrk_output=$(wrk -t"$threads" -c"$conns" -d"${duration}s" --latency "$url" 2>&1)
    fi
    
    # Parse output
    echo "$wrk_output" | awk '
    function to_ms(val) {
        if (val ~ /us$/) { gsub(/us$/, "", val); return val / 1000 }
        if (val ~ /ms$/) { gsub(/ms$/, "", val); return val + 0 }
        if (val ~ /s$/)  { gsub(/s$/, "", val); return val * 1000 }
        return val + 0
    }
    
    BEGIN { reqs=0; errs=0; rps=0; avg=0; p50=0; p90=0; p99=0; maxl=0 }
    
    # Connection error
    /unable to connect|Connection refused/ { reqs=0; errs=-1; exit }
    
    # Latency stats line (not "Latency Distribution")
    /^[[:space:]]+Latency[[:space:]]/ && $2 ~ /[0-9]/ { avg = to_ms($2); maxl = to_ms($4) }
    
    # Percentiles
    /50%/  { p50 = to_ms($2) }
    /90%/  { p90 = to_ms($2) }
    /99%/  { p99 = to_ms($2) }
    
    # Total requests
    /requests in/ { reqs = $1 + 0 }
    
    # Errors
    /Socket errors/ { for(i=1;i<=NF;i++) if($i~/^[0-9]+$/) errs+=$i }
    /Non-2xx/ { errs += $3 + 0 }
    
    # RPS
    /Requests\/sec:/ { rps = $2 + 0 }
    
    END {
        if (errs == -1) { print "0 0 0.00 0.00 0.00 0.00 0.00 0.00"; exit }
        if (p50 == 0) p50 = avg
        if (p90 == 0) p90 = (p99 > 0 ? p99 : maxl)
        if (p99 == 0) p99 = maxl
        printf "%d %d %.2f %.2f %.2f %.2f %.2f %.2f\n", reqs, errs, rps, avg, p50, p90, p99, maxl
    }'
}

# Warmup: single request to prime server
bench_warmup() {
    local url=$1
    curl -s -o /dev/null "$url" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Resource Monitoring
# ─────────────────────────────────────────────────────────────────────────────

# Get CPU% and MEM(MB) for process tree
bench_get_resources() {
    local pid=$1
    [[ -z "$pid" || ! -d "/proc/$pid" ]] && { echo "0.00 0"; return; }
    
    local pids="$pid $(pgrep -P "$pid" 2>/dev/null | tr '\n' ' ')"
    ps -p $pids -o %cpu=,rss= 2>/dev/null | awk '
        { cpu += $1; mem += $2 }
        END { printf "%.2f %.0f\n", cpu+0, (mem+0)/1024 }
    ' || echo "0.00 0"
}

# Find PID on port
bench_find_pid_by_port() {
    local port=$1
    if command -v lsof &>/dev/null; then
        lsof -ti ":$port" -sTCP:LISTEN 2>/dev/null | head -1
    elif command -v ss &>/dev/null; then
        ss -tlnp "sport = :$port" 2>/dev/null | awk -F'pid=' 'NR>1{print $2}' | cut -d',' -f1 | head -1
    fi
}

# Kill process on port
bench_free_port() {
    local pid=$(bench_find_pid_by_port "$1")
    [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null && sleep 0.2
}

# ─────────────────────────────────────────────────────────────────────────────
# Display
# ─────────────────────────────────────────────────────────────────────────────

bench_hide_cursor() { tput civis 2>/dev/null || true; }
bench_show_cursor() { tput cnorm 2>/dev/null || true; }
