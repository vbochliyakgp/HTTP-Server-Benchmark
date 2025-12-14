#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# compare_endpoint.sh - Compare a specific endpoint across all languages
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage: ./compare_endpoint.sh [endpoint] [connections] [duration]
#
# Examples:
#   ./compare_endpoint.sh root           # Compare root endpoint (default: 100 conns, 5s)
#   ./compare_endpoint.sh post 200       # Compare POST with 200 connections
#   ./compare_endpoint.sh json 50 3      # Compare JSON endpoint, 50 conns, 3s
#
# ═══════════════════════════════════════════════════════════════════════════════

ENDPOINT=${1:-root}  # Default to 'root' if not specified
CONNS=${2:-100}      # Default to 100 connections
DURATION=${3:-5}     # Default to 5 seconds

# Validate endpoint
case $ENDPOINT in
    root|query|json|post)
        ;;
    *)
        echo "Error: Invalid endpoint '$ENDPOINT'"
        echo "Valid endpoints: root, query, json, post"
        exit 1
        ;;
esac

echo "═══════════════════════════════════════════════════════════════════════"
echo " Comparing '$ENDPOINT' endpoint across all languages"
echo " Config: $CONNS connections, ${DURATION}s duration per language"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

for lang in js py go rust cpp; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Testing: $lang"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ./benchmark.sh -l $lang -e $ENDPOINT -c $CONNS -d $DURATION 2>&1 | \
        grep -E "(wrk Benchmark|Endpoint|$ENDPOINT|Req/s|Avg\(ms\)|P50\(ms\)|P90\(ms\)|Server CPU|Server Memory|✅)" | \
        head -10
    echo ""
done

echo "═══════════════════════════════════════════════════════════════════════"
echo " Comparison complete!"
echo "═══════════════════════════════════════════════════════════════════════"

