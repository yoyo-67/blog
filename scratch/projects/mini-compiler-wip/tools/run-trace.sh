#!/bin/bash
#
# Run eBPF tracing on the compiler in a Linux Docker container
#
# Requirements:
#   - Docker with privileged container support
#   - Linux kernel with eBPF support (the host kernel is used)
#
# Usage:
#   ./tools/run-trace.sh                    # Trace default example
#   ./tools/run-trace.sh path/to/file.mini  # Trace specific file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Building Docker image ==="
docker build -f "$SCRIPT_DIR/Dockerfile.trace" -t compiler-trace "$PROJECT_DIR"

echo ""
echo "=== Running eBPF trace ==="
echo "(Requires privileged mode for eBPF access)"
echo ""

if [ -n "$1" ]; then
    # Custom file provided
    docker run --privileged \
        -v /sys/kernel/debug:/sys/kernel/debug:ro \
        -v "$(realpath "$1"):/app/input.mini:ro" \
        compiler-trace \
        bpftrace tools/trace.bt -c "./zig-out/bin/comp build /app/input.mini"
else
    # Use default example
    docker run --privileged \
        -v /sys/kernel/debug:/sys/kernel/debug:ro \
        compiler-trace
fi
