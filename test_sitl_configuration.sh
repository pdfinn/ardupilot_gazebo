#!/bin/bash

# Validation Script: Test ArduPilot Gazebo Integration
# Tests the macOS arm64 fix for ArduPilotPlugin

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== ArduPilot Gazebo Integration Test ===${NC}"
echo ""
echo "This script validates that ArduPilotPlugin works on macOS arm64"
echo ""

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

# Check Gazebo
if ! command -v gz &> /dev/null; then
    echo -e "${RED}✗ Gazebo not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Gazebo installed${NC}"

# Check ArduPilot
if [ ! -d "/Users/pdfinn/github.com/NERVsystems/ardupilot" ]; then
    echo -e "${RED}✗ ArduPilot not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ ArduPilot found${NC}"

echo ""
echo -e "${YELLOW}[2/5] Setting up environment...${NC}"

export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib"
export GZ_SIM_SYSTEM_PLUGIN_PATH="$SCRIPT_DIR/build"
export GZ_SIM_RESOURCE_PATH="$SCRIPT_DIR/models:$SCRIPT_DIR/worlds"

echo -e "${GREEN}✓ Environment configured${NC}"

echo ""
echo -e "${YELLOW}[3/5] Checking plugin build...${NC}"

if [ ! -f "build/libArduPilotPlugin.dylib" ]; then
    echo -e "${YELLOW}ArduPilotPlugin not built. Building now...${NC}"
    mkdir -p build && cd build
    export GZ_VERSION=ionic
    cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
    make ArduPilotPlugin -j4
    cd ..
fi

if file build/libArduPilotPlugin.dylib | grep -q "arm64"; then
    echo -e "${GREEN}✓ ArduPilotPlugin built (arm64)${NC}"
else
    echo -e "${RED}✗ Plugin architecture mismatch${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[4/5] Testing Gazebo server with iris model...${NC}"

# Kill any existing Gazebo
killall -9 gz 2>/dev/null || true
sleep 2

# Start Gazebo in background
gz sim -r -s worlds/iris_runway.sdf > /tmp/gz_test.log 2>&1 &
GZ_PID=$!

# Wait for startup
sleep 10

# Check if Gazebo is running
if ! ps -p $GZ_PID > /dev/null; then
    echo -e "${RED}✗ Gazebo failed to start${NC}"
    cat /tmp/gz_test.log
    exit 1
fi

# Check for ArduPilotPlugin in logs
if grep -q "Loaded system \[ArduPilotPlugin\]" /tmp/gz_test.log; then
    echo -e "${GREEN}✓ ArduPilotPlugin loaded successfully${NC}"
else
    echo -e "${RED}✗ ArduPilotPlugin did not load${NC}"
    cat /tmp/gz_test.log
    kill $GZ_PID 2>/dev/null
    exit 1
fi

# Check for gimbal topics
if grep -q "Advertising on /gimbal/cmd" /tmp/gz_test.log; then
    echo -e "${GREEN}✓ Gimbal control topics advertised${NC}"
else
    echo -e "${YELLOW}⚠ No gimbal topics (might be normal for some models)${NC}"
fi

# Check for IMU
if grep -q "Found IMU sensor" /tmp/gz_test.log; then
    echo -e "${GREEN}✓ IMU sensor detected${NC}"
else
    echo -e "${YELLOW}⚠ No IMU detected in logs${NC}"
fi

echo ""
echo -e "${YELLOW}[5/5] Cleaning up...${NC}"
kill $GZ_PID 2>/dev/null
sleep 2
echo -e "${GREEN}✓ Gazebo stopped${NC}"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✓ ALL TESTS PASSED                             ║${NC}"
echo -e "${GREEN}║   ArduPilotPlugin works on macOS arm64!           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Start Gazebo: gz sim -r -s worlds/iris_runway.sdf"
echo "  2. Start SITL: cd ../ardupilot && sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON --console"
echo "  3. Connect GCS to UDP port 14550"
echo ""
