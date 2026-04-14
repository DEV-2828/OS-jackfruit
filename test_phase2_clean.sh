#!/bin/bash

# Phase 2 Clean Test - Multi-Container Runtime Demonstration

cd "$(dirname "$0")"
cd boilerplate

echo "==================================="
echo "Phase 2: Multi-Container Runtime"
echo "==================================="
echo ""
echo "Starting supervisor with 2 containers..."
echo ""

# Create commands in proper format
{
    sleep 1
    echo "start alpha ../rootfs-alpha echo hello-from-alpha"
    sleep 1
    echo "start beta ../rootfs-beta echo hello-from-beta"
    sleep 2
    echo "ps"
    sleep 5
    echo "quit"
} | sudo ./engine supervisor ../rootfs-base

echo ""
echo "=== Phase 2 Test Complete ==="
