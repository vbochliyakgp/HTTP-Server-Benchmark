# Simple HTTP Servers - Performance Comparison

A comprehensive performance comparison of minimal HTTP servers implemented in **JavaScript**, **Python**, **Go**, **Rust**, and **C++** using only standard libraries — no frameworks or external dependencies.

## Overview

This project implements identical HTTP servers in five different languages to compare their performance characteristics under load. Each server handles the same three endpoints:
- Simple GET request (`/`)
- Query parameter parsing (`/something?params`)
- JSON request/response (`/something` with `?json=true`)
- POST request with body parsing (`/something`)

All servers are benchmarked using `wrk`, a high-performance HTTP benchmarking tool, under identical conditions to ensure fair comparison.

## Quick Start

### Run Functional Tests

Test all servers to verify they work correctly:

```bash
./test.sh
```

This will:
1. Start all five servers on ports 3000-3004
2. Test each endpoint on each server
3. Display response times
4. Clean up automatically

### Run Performance Benchmark

Benchmark a specific language:

```bash
# Benchmark Go server with default settings (50 connections, 5 seconds)
./benchmark.sh -l go

# High-load test: 200 connections for 10 seconds
./benchmark.sh -l js -c 200 -d 10

# Test only root endpoint
./benchmark.sh -l rust -e root -c 100
```

### Compare Endpoint Across All Languages

Test a specific endpoint across all languages for comparison:

```bash
# Test root endpoint on all languages (100 connections, 5 seconds each)
for lang in js py go rust cpp; do
    echo "=== Testing $lang ==="
    ./benchmark.sh -l $lang -e root -c 100 -d 5
    echo ""
done

# Test POST endpoint on all languages
for lang in js py go rust cpp; do
    echo "=== Testing $lang POST ==="
    ./benchmark.sh -l $lang -e post -c 100 -d 5
    echo ""
done

# Test query endpoint with JSON response
for lang in js py go rust cpp; do
    echo "=== Testing $lang JSON ==="
    ./benchmark.sh -l $lang -e json -c 100 -d 5
    echo ""
done
```

**Quick comparison script** - Save as `compare_endpoint.sh`:

```bash
#!/bin/bash
ENDPOINT=${1:-root}  # Default to 'root' if not specified
CONNS=${2:-100}
DURATION=${3:-5}

echo "════════════════════════════════════════════════════════════════"
echo " Comparing $ENDPOINT endpoint across all languages"
echo " Config: $CONNS connections, ${DURATION}s duration"
echo "════════════════════════════════════════════════════════════════"
echo ""

for lang in js py go rust cpp; do
    ./benchmark.sh -l $lang -e $ENDPOINT -c $CONNS -d $DURATION 2>&1 | \
        grep -E "(wrk Benchmark|Endpoint|root|query|json|post|Req/s|Avg\(ms\)|Server CPU|Server Memory|✅)" | \
        head -8
    echo ""
done
```

Usage:
```bash
chmod +x compare_endpoint.sh
./compare_endpoint.sh root      # Compare root endpoint
./compare_endpoint.sh post 200  # Compare POST with 200 connections
./compare_endpoint.sh json 50 3 # Compare JSON endpoint, 50 conns, 3s
```

## Performance Testing

**Test Methodology:**
- **Connections**: Configurable concurrent connections (default: 50)
- **Duration**: Configurable test duration per endpoint (default: 5 seconds)
- **CPU**: Configurable CPU cores (default: 1)
- **Memory**: Configurable memory limit (default: 1GB)
- **Tool**: `wrk` with latency distribution enabled

Run benchmarks to see performance characteristics of each language:

```bash
./benchmark.sh -l go -c 100 -d 5
```

### Concurrency Models Explained

| Language | Model | Implementation | Overhead | Notes |
|----------|-------|----------------|----------|-------|
| **Go** | Goroutines | Lightweight coroutines | ~2KB stack | Near-zero overhead, handles millions of concurrent requests |
| **JavaScript** | Event Loop | Single-threaded async I/O | Minimal | Non-blocking I/O, efficient for I/O-bound workloads |
| **Rust** | OS Threads | One thread per request | ~2MB stack | High overhead (~3ms per thread spawn), no async in stdlib |
| **C++** | OS Threads | `std::thread` per request | ~2MB stack | High overhead, manual thread management |
| **Python** | ThreadingMixIn | OS threads with GIL | ~2MB stack | GIL prevents true parallelism, context switching overhead |

### Understanding the Metrics

- **Requests/sec (req/s)**: Throughput - how many requests the server can handle per second
- **Min Latency**: Fastest response time observed (best case)
- **P1**: 1st percentile latency - 1% of requests are faster than this
- **P50**: 50th percentile (median) - half of requests are faster than this
- **P90**: 90th percentile - 90% of requests are faster than this
- **P99**: 99th percentile - 99% of requests are faster than this
- **Max Latency**: Worst-case response time (slowest request)
- **Avg Latency**: Average response time across all requests
- **Memory**: Peak memory usage during benchmark

## Servers

Each server implements the same API using only standard libraries:

| Language | File | Port | Run Command | Compilation |
|----------|------|------|-------------|-------------|
| JavaScript | `server.js` | 3000 | `node server.js` | None (interpreted) |
| Python | `server.py` | 3001 | `python3 server.py` | None (interpreted) |
| Go | `server.go` | 3002 | `go run server.go` | Optional (or `go build`) |
| Rust | `server.rs` | 3003 | `rustc -O server.rs && ./server` | Required (optimized) |
| C++ | `server.cpp` | 3004 | `g++ -O3 server.cpp && ./a.out` | Required (optimized) |

### Server Details

- **JavaScript**: Uses Node.js `http` module with event-driven architecture
- **Python**: Uses `http.server` with `ThreadingMixIn` for concurrent requests
- **Go**: Uses `net/http` package with goroutines (automatic concurrency)
- **Rust**: Uses `std::net::TcpListener` with manual thread spawning
- **C++**: Uses POSIX sockets (`sys/socket.h`) with thread-per-request model

## API Endpoints

All servers implement identical endpoints:

### GET `/`

Simple hello endpoint.

**Request:**
```bash
curl http://localhost:3000/
```

**Response:**
```
Hello from JavaScript!
```

### GET `/something?params`

Query parameter parsing endpoint. Returns JSON if `?json=true`, otherwise plain text.

**Request:**
```bash
curl "http://localhost:3000/something?name=test&value=123"
```

**Response (plain text):**
```
Route: /something, Query: {"name":"test","value":"123"}
```

**Request (JSON):**
```bash
curl "http://localhost:3000/something?name=test&json=true"
```

**Response (JSON):**
```json
{"route":"/something","query":{"name":"test","json":"true"}}
```

### POST `/something`

POST endpoint that echoes the request body.

**Request:**
```bash
curl -X POST http://localhost:3000/something \
  -H "Content-Type: application/json" \
  -d '{"hello":"world","test":123}'
```

**Response:**
```json
{"route":"/something","body":{"hello":"world","test":123}}
```

## Benchmark Tool

The benchmark uses `wrk`, a modern HTTP benchmarking tool written in C. It's designed for high-performance testing and provides detailed latency statistics.

### Usage

```bash
./benchmark.sh -l <lang> [OPTIONS]
```

### Options

| Flag | Description | Default | Notes |
|------|-------------|---------|-------|
| `-l, --lang` | Language to benchmark | required | `js`, `py`, `go`, `rust`, or `cpp` |
| `-e, --endpoint` | Endpoint(s) to test | `all` | `root`, `query`, `json`, `post`, or `all` |
| `-c, --connections` | Concurrent connections | `50` | Number of simultaneous connections wrk maintains |
| `-d, --duration` | Test duration (seconds) | `5` | How long to run each endpoint test |
| `-t, --threads` | wrk threads | auto | Usually 1 thread per 50 connections (max 4) |
| `--cpu` | CPU cores for server* | `1` | Limits server CPU usage (0.5 = half core) |
| `--mem` | Memory limit for server* | `1G` | Maximum memory server can use |

*Requires `systemd-run` (Linux). Without it, CPU/memory limits are ignored and a warning is shown.

### How It Works

1. **Server Startup**: Starts the specified language server with resource limits
2. **Warmup**: Sends a single request to prime the server (JIT compilation, etc.)
3. **Benchmark**: Runs `wrk` against each endpoint for the specified duration
4. **Statistics**: Parses wrk output to extract latency percentiles and throughput
5. **Resource Monitoring**: Tracks CPU and memory usage during the test
6. **Cleanup**: Automatically stops the server and cleans up

### Examples

```bash
# Quick test: Go server, default settings
./benchmark.sh -l go

# High-load test: JavaScript, 200 connections, 10 seconds
./benchmark.sh -l js -c 200 -d 10

# Single endpoint: Rust, root endpoint only, 50 connections
./benchmark.sh -l rust -e root -c 50

# Resource limits: Python with 2 CPU cores and 2GB RAM
./benchmark.sh -l py --cpu 2 --mem 2G

# Custom threads: Go with 4 wrk threads
./benchmark.sh -l go -t 4 -c 200

# Compare specific endpoint across all languages
for lang in js py go rust cpp; do
    ./benchmark.sh -l $lang -e root -c 100 -d 5
done
```

### Understanding the Output

The benchmark displays:
- **Requests**: Total requests completed during the test duration
- **Errors**: Failed requests (connection errors, timeouts, non-2xx responses)
- **Req/s**: Average requests per second (throughput)
- **Min/P1/P50/P90/P99/Max/Avg**: Latency statistics in milliseconds
  - **Min**: Fastest response time
  - **P1**: 1st percentile (1% of requests faster)
  - **P50**: Median (50% of requests faster)
  - **P90**: 90th percentile (90% of requests faster)
  - **P99**: 99th percentile (99% of requests faster)
  - **Max**: Slowest response time
  - **Avg**: Average response time
- **Server CPU/Memory**: Resource usage during the benchmark

## Language Characteristics

### Go

**Strengths:**
- **Goroutines**: Extremely lightweight (~2KB stack vs 2MB for OS threads)
- **Built-in HTTP server**: Highly optimized, production-ready code
- **Efficient memory allocation**: Zero-cost abstractions, minimal GC pressure
- **Concurrent by default**: Automatically handles thousands of concurrent requests

**Trade-offs:**
- Requires Go runtime (larger binary size)
- Garbage collector adds some overhead

### JavaScript (Node.js)

**Strengths:**
- **V8 engine**: Highly optimized JIT compiler, competitive with compiled languages
- **Event loop**: Non-blocking I/O, efficient for I/O-bound workloads
- **Single-threaded**: No context switching overhead, no thread synchronization
- **Mature ecosystem**: Years of optimization in production environments

**Trade-offs:**
- Higher memory usage due to V8 runtime
- Single-threaded means CPU-bound tasks block the event loop
- Interpreted language (though JIT helps significantly)

### Rust

**Strengths:**
- **Zero-cost abstractions**: No GC, excellent for systems programming
- **Memory safety**: Compile-time guarantees without runtime overhead
- **Low memory usage**: Efficient resource utilization

**Current Implementation Limitations:**
- **Thread-per-request**: Each request spawns a new OS thread (high overhead)
- **No async in stdlib**: Would need `tokio` or similar for better performance
- **Thread overhead**: OS threads have ~2MB stack, expensive to create/destroy

**Potential Improvements:**
- With `tokio` async runtime, Rust could achieve much higher performance
- Async/await would eliminate thread spawning overhead

**Trade-offs:**
- Current implementation uses blocking I/O with threads
- Compilation time is slower than other languages
- Steeper learning curve

### C++

**Strengths:**
- **Zero-cost abstractions**: No runtime overhead, direct system calls
- **Maximum performance**: Compiled to native code, highly optimized
- **Low memory usage**: Manual memory management, no GC overhead
- **Standard library**: Rich STL for containers and algorithms

**Current Implementation:**
- **Thread-per-request**: Uses `std::thread` for concurrent requests
- **POSIX sockets**: Direct system calls for maximum control
- **Manual HTTP parsing**: Full control over request/response handling

**Trade-offs:**
- Thread-per-request has overhead (~2MB stack per thread)
- Manual memory management requires careful coding
- Compilation time can be slower
- More verbose than higher-level languages

### Python

**Strengths:**
- **Easiest to write and maintain**: Readable, expressive syntax
- **Excellent for rapid prototyping**: Fast development cycle
- **Rich ecosystem**: Extensive libraries and frameworks
- **Good enough for many applications**: Sufficient performance for typical web apps

**Limitations:**
- **Global Interpreter Lock (GIL)**: Prevents true parallelism, only one thread executes Python bytecode at a time
- **Interpreted language**: No JIT compilation (unlike JavaScript)
- **Thread overhead**: OS threads with GIL contention
- **Dynamic typing**: Runtime type checking adds overhead

**Trade-offs:**
- GIL limits CPU-bound parallelism
- Higher latency compared to compiled languages
- Not suitable for high-throughput microservices requiring maximum performance

## Requirements

### Languages

- **Node.js**: v14+ (for JavaScript server)
- **Python**: 3.7+ (for Python server)
- **Go**: 1.16+ (for Go server)
- **Rust**: 1.50+ with `rustc` (for Rust server)

### Tools

- **wrk**: HTTP benchmarking tool
  - Install: `apt install wrk` (Debian/Ubuntu) or `brew install wrk` (macOS)
  - Required for running benchmarks
- **curl**: HTTP client
  - Usually pre-installed on Linux/macOS
  - Used for functional testing

### Optional (for Resource Limits)

- **systemd-run**: Systemd service manager
  - Usually pre-installed on modern Linux systems
  - Required for `--cpu` and `--mem` options
  - Without it, resource limits are ignored
- **taskset**: CPU affinity tool
  - Part of `util-linux` package
  - Used for CPU core pinning (fallback without systemd)

### Installation

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install nodejs python3 golang-go rustc g++ wrk curl
```

**macOS:**
```bash
brew install node python go rust wrk
# g++/clang++ and curl are pre-installed
```

**Verify installations:**
```bash
node --version
python3 --version
go version
rustc --version
g++ --version  # or clang++ --version
wrk --version
```

## Architecture

### Project Structure

```
.
├── server.js          # JavaScript server (Node.js event loop)
├── server.py          # Python server (ThreadingMixIn)
├── server.go          # Go server (goroutines)
├── server.rs          # Rust server (OS threads)
├── server.cpp         # C++ server (OS threads)
├── benchmark.sh       # Main benchmark orchestrator
├── bench_lib.sh       # Benchmark library (wrk wrapper, stats parsing)
├── server_config.sh   # Server configuration (ports, start/stop logic)
├── test.sh            # Functional test suite
├── compare_endpoint.sh # Compare specific endpoint across all languages
└── README.md          # This file
```

### How Benchmarking Works

1. **benchmark.sh**: Main script that:
   - Parses command-line arguments
   - Starts the server with resource limits
   - Waits for server to be ready
   - Runs benchmarks for each endpoint
   - Displays formatted results

2. **bench_lib.sh**: Library functions for:
   - Running `wrk` benchmarks
   - Parsing wrk output (latency percentiles, throughput)
   - Resource monitoring (CPU, memory)
   - Port management

3. **server_config.sh**: Server-specific logic:
   - Language definitions (ports, names, CPU cores)
   - Server startup commands
   - Resource limit application
   - Endpoint definitions

### Resource Limits

When `systemd-run` is available:
- **CPU**: Uses `CPUQuota` to limit CPU usage (e.g., 50% = 0.5 cores)
- **Memory**: Uses `MemoryMax` to cap memory usage
- **CPU Pinning**: Uses `taskset` to pin server to specific CPU cores

Without `systemd-run`:
- Only CPU pinning works (via `taskset`)
- CPU quota and memory limits are ignored
- A warning is displayed

## Troubleshooting

### Server Won't Start

**Port already in use:**
```bash
# Find and kill process on port
lsof -ti :3000 | xargs kill -9
```

**Compilation errors:**
- **Go**: Ensure `go` is in PATH
- **Rust**: Check `rustc` is available (may need to fix rustup proxy issues)

### Benchmark Shows 0 Requests

- Server may not be ready - check server logs in `/tmp/*_server.log`
- Connection refused - verify server is listening on correct port
- Check firewall settings

### Resource Limits Not Working

- Verify `systemd-run` is installed: `which systemd-run`
- On macOS, resource limits don't work (no systemd)
- Check if running as user (systemd-run requires user session)

### Rust Compilation Fails

If you see "unknown proxy name: 'cursor'" error:
- The script automatically finds rustc in `~/.rustup/toolchains/`
- Or manually set: `export RUSTUP_TOOLCHAIN=stable`

## Contributing

This is a comparison project. To add a new language:

1. Create `server.{ext}` implementing the three endpoints
2. Add language to `server_config.sh` (port, name, core)
3. Add startup logic in `server_start()` function
4. Test with `./test.sh`
5. Benchmark with `./benchmark.sh -l <lang>`

## License

This project is for educational and comparison purposes. Feel free to use and modify as needed.
