#!/bin/bash

# Phase 2 Test Script - Multi-Container Runtime
# This script demonstrates the supervisor managing 2+ containers

set -e

cd "$(dirname "$0")"

echo "=== Phase 2: Multi-Container Runtime Test ==="
echo ""
echo "This test will:"
echo "  1. Start the supervisor"
echo "  2. Spawn 2 containers (alpha and beta)"
echo "  3. Show container metadata via 'ps' command"
echo "  4. Let containers run for ~10 seconds"
echo "  5. Gracefully shut down all containers"
echo ""
echo "Building engine..."
cd boilerplate
make

echo ""
echo "Starting supervisor with rootfs-base..."
echo "Commands will be:"
echo "  - start alpha ./rootfs-alpha 'sleep 20'"
echo "  - start beta ./rootfs-beta 'sleep 20'"
echo "  - ps (to view all containers)"
echo "  - quit (to shut down)"
echo ""
echo "=== SUPERVISOR OUTPUT BEGINS ==="
echo ""

# Create a here-document with commands to send to the supervisor
{
    sleep 1
    echo "start alpha ../rootfs-alpha 'sleep 20'"
    sleep 1
    echo "start beta ../rootfs-beta 'sleep 20'"
    sleep 2
    echo "ps"
    sleep 10
    echo "quit"
} | sudo ./engine supervisor ../rootfs-base

echo ""
echo "=== TEST COMPLETE ==="
echo "Check logs/ directory for per-container logs if implemented"
ls -la logs/ 2>/dev/null || echo "(No logs yet - Phase 4 feature)"
