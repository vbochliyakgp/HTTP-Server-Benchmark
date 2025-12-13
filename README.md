# Simple HTTP Servers

Minimal HTTP servers in 4 languages using only standard libraries — no frameworks.

## Servers

| Language   | File        | Port | CPU Core | Run Command                   |
|------------|-------------|------|----------|-------------------------------|
| JavaScript | `server.js` | 3000 | 0        | `node server.js`              |
| Python     | `server.py` | 3001 | 1        | `python3 server.py`           |
| Go         | `server.go` | 3002 | 2        | `go run server.go`            |
| Rust       | `server.rs` | 3003 | 3        | `rustc server.rs && ./server` |

**Resource Limits (configurable via benchmark args):**
- CPU: Pinned to specific core(s) via `taskset`, with quota limits via `systemd-run`
- Memory: Limited via `systemd-run` (default: 1GB)
- Go is pre-compiled to binary for proper PID tracking
- Each server runs isolated on its own CPU core(s)

## API Endpoints

### GET `/`
```
Hello from {Language}!
```

### GET `/something?params`
**String:** `Route: /something, Query: {name: value}`

**JSON** (`?json=true`):
```json
{"route":"/something","query":{"json":"true","key":"value"}}
```

### POST `/something`
```json
{"route":"/something","body":{"hello":"world"}}
```

## Testing

### Quick Test
```bash
./test.sh
```
Starts all servers on separate CPU cores, tests each endpoint with latency.

### Benchmark
```bash
./benchmark.sh -l <lang> [options] <num_requests>
```

**Options:**
| Flag | Description | Default |
|------|-------------|---------|
| `-l, --lang` | Language: `js`, `py`, `go`, or `rust` (required) | - |
| `-e, --endpoint` | Endpoint: `root`, `query`, `json`, `post`, or `all` | `all` |
| `-c, --concurrency` | Concurrent requests: number or `all` | `1` |
| `--cpu-lmt-cores` | Number of CPU cores (e.g., `0.5`, `1`, `2`, `4`) | `0.5` |
| `--mem-lmt` | Memory limit (e.g., `1G`, `512M`, `2G`) | `1G` |
| `-h, --help` | Show help | - |

**Examples:**
```bash
# JavaScript server, 100 sequential requests (default: 0.5 core, 1GB RAM)
./benchmark.sh -l js 100

# Go server, 1000 requests with 50 concurrent
./benchmark.sh -l go -c 50 1000

# Python, all requests concurrent
./benchmark.sh -l py -c all 500

# Rust, root endpoint only, 10 concurrent
./benchmark.sh -l rust -e root -c 10 200

# 2 CPU cores, 2GB RAM
./benchmark.sh -l js --cpu-lmt-cores 2 --mem-lmt 2G 1000

# 4 CPU cores, 512MB RAM
./benchmark.sh -l go --cpu-lmt-cores 4 --mem-lmt 512M 5000

# Large scale: 10000 requests with 4 cores
./benchmark.sh -l js --cpu-lmt-cores 4 -c 100 10000
```

## Live Display

The benchmark shows **real-time updates every 0.5 seconds**:

```
🚀 Starting JavaScript server on port 3000 (CPU core 0, 2 core(s), 2G RAM)...
   PID: 123456

📊 Benchmark: 1000 requests per endpoint, concurrent (×50)
   Endpoints: root query json post

JavaScript    CPU: 5.20    MEM: 58   MB                                                     
┌────────────┬────────┬────────┬──────────┬────────┬────────┬────────┬────────┬────────┐
│ Endpoint   │   Done │ Failed │   Req/s  │ Min ms │ Avg ms │ P50 ms │ P95 ms │ Max ms │
├────────────┼────────┼────────┼──────────┼────────┼────────┼────────┼────────┼────────┤
│ root       │    250 │      - │        - │      - │      - │      - │      - │      - │
│ query      │      - │      - │        - │      - │      - │      - │      - │      - │
│ json       │      - │      - │        - │      - │      - │      - │      - │      - │
│ post       │      - │      - │        - │      - │      - │      - │      - │      - │
└────────────┴────────┴────────┴──────────┴────────┴────────┴────────┴────────┴────────┘
```

**Live columns:**
| Column | Description |
|--------|-------------|
| Done | Completed requests (live count while running) |
| Failed | Failed requests |
| Req/s | Requests per second (shown when endpoint completes) |
| Min/Avg/P50/P95/Max | Latency statistics in milliseconds |
| CPU% | Current CPU usage (2 decimal places) |
| MEM MB | Current memory usage in MB |

**Status:**
- `-` = Pending (not started)
- `N` = Running (live count updates every 0.5s)
- Final stats shown when endpoint completes

## Architecture

### Modular Design

The project uses a clean, modular architecture:

```
├── bench_lib.sh        # Generic benchmarking library (reusable)
│   ├── HTTP Requests   # Single request, batch execution
│   ├── Statistics      # Min/max/avg/p50/p95 calculation
│   ├── Resource Monitor # CPU/MEM sampling
│   └── Display Utils   # Cursor control, progress
│
├── server_config.sh    # Project-specific configuration
│   ├── Server Defs     # Ports, names, CPU cores
│   ├── Endpoints       # API endpoint definitions
│   ├── Server Start    # How to start each language
│   └── Resource Limits # CPU/memory constraints
│
└── benchmark.sh        # Main orchestrator
    ├── Argument Parsing
    ├── Server Management
    ├── Benchmark Execution
    └── Live Display
```

**Benefits:**
- `bench_lib.sh` can be reused for any HTTP benchmarking project
- `server_config.sh` isolates project-specific details
- `benchmark.sh` is simple and focused on orchestration

### Server Execution

Each server:
- Pinned to specific CPU core(s) via `taskset -c N` (or `N,M` for multiple cores)
- Resource limits enforced via `systemd-run` (CPU quota and memory max)
- When `--cpu-lmt-cores > 1`, uses multiple consecutive cores (e.g., 2 cores = cores 0,1 for JS)
- Runs one language at a time (simplified from parallel execution)
- Endpoints tested sequentially per language

**CPU Core Assignment:**
- `--cpu-lmt-cores 0.5` → 1 core at 50% quota (core 0 for JS)
- `--cpu-lmt-cores 1` → 1 full core (core 0 for JS)
- `--cpu-lmt-cores 2` → 2 full cores (cores 0,1 for JS)
- `--cpu-lmt-cores 4` → 4 full cores (cores 0,1,2,3 for JS)

### Performance

- **Efficient for large request counts**: Uses `xargs -P` for parallel execution instead of spawning thousands of subshells
- **Handles 10000+ requests**: Optimized to avoid process overhead
- **Live updates**: Table refreshes every 0.5 seconds with current progress

## Requirements

- **Languages**: Node.js, Python 3, Go, Rust
- **Tools**: `curl`, `xargs` (GNU coreutils)
- **System**: 
  - `taskset` (util-linux, for CPU pinning)
  - `systemd-run` (for resource limits - CPU quota and memory max)

## File Structure

```
.
├── server.js          # JavaScript server
├── server.py          # Python server
├── server.go          # Go server
├── server.rs          # Rust server
├── test.sh            # Functional test script
├── benchmark.sh       # Benchmark orchestrator
├── bench_lib.sh       # Generic benchmarking library
├── server_config.sh   # Project-specific config
└── README.md          # This file
```
