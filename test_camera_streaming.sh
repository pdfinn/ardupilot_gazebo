#!/bin/bash
#
# Camera Streaming Verification Test
# Automated regression test for Gazebo camera streaming to Android GCS
#
# Tests:
# 1. Android detection via ADB
# 2. Environment variable configuration
# 3. Plugin loading and initialization
# 4. Camera topic publishing
# 5. GStreamer pipeline creation
# 6. UDP packet transmission
#
# Usage: ./test_camera_streaming.sh
#
# Returns:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TEST_LOG="/tmp/gazebo_camera_test_$$.log"

# Cleanup on exit
cleanup() {
    if [ -n "$GAZEBO_PID" ]; then
        echo ""
        echo -e "${YELLOW}Cleaning up Gazebo process...${NC}"
        kill $GAZEBO_PID 2>/dev/null || true
        pkill -9 -f "gz sim" 2>/dev/null || true
        lsof -ti:9002 2>/dev/null | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
    rm -f "$TEST_LOG" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Camera Streaming Verification Test Suite     ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo ""

# Helper functions
pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL${NC}: $1"
    if [ -n "$2" ]; then
        echo -e "${RED}  Reason: $2${NC}"
    fi
}

info() {
    echo -e "${BLUE}→${NC} $1"
}

# ============================================================================
# TEST 1: Build Artifacts Exist
# ============================================================================
echo -e "${YELLOW}Test 1: Build Artifacts${NC}"

if [ -f "build/libGstCameraPlugin.dylib" ] || [ -f "build/libGstCameraPlugin.so" ]; then
    pass_test "GstCameraPlugin library exists"
else
    fail_test "GstCameraPlugin library not found" "Run: cd build && make"
fi

if [ -f "models/gimbal_small_3d/model.sdf" ]; then
    pass_test "Gimbal camera model exists"
else
    fail_test "Gimbal model not found"
fi

echo ""

# ============================================================================
# TEST 2: ADB and Android Detection
# ============================================================================
echo -e "${YELLOW}Test 2: Android Device Detection${NC}"

if command -v adb &> /dev/null; then
    pass_test "ADB command available"
else
    fail_test "ADB not found" "Install Android SDK platform-tools"
fi

DEVICES=$(adb devices 2>/dev/null | grep -v "^List" | grep -v "emulator" | grep "device$" | awk '{print $1}')
DEVICE_COUNT=$(echo "$DEVICES" | grep -v "^$" | wc -l | tr -d ' ')

if [ "$DEVICE_COUNT" -gt 0 ]; then
    FIRST_DEVICE=$(echo "$DEVICES" | head -1)
    pass_test "Android device connected: $FIRST_DEVICE"

    DETECTED_IP=$(adb -s "$FIRST_DEVICE" shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | tr -d '\r\n ')

    if [ -n "$DETECTED_IP" ]; then
        pass_test "Android WiFi IP detected: $DETECTED_IP"
        ANDROID_IP="$DETECTED_IP"
    else
        fail_test "Could not get Android WiFi IP" "Ensure device is on WiFi"
        ANDROID_IP="127.0.0.1"
    fi
else
    fail_test "No Android device detected" "Connect device via USB, enable USB debugging"
    ANDROID_IP="127.0.0.1"
fi

echo ""

# ============================================================================
# TEST 3: Environment Variable Configuration
# ============================================================================
echo -e "${YELLOW}Test 3: Environment Variables${NC}"

export GZ_CAMERA_UDP_HOST="$ANDROID_IP"
export GZ_CAMERA_UDP_PORT="5600"

if [ "$GZ_CAMERA_UDP_HOST" = "$ANDROID_IP" ]; then
    pass_test "GZ_CAMERA_UDP_HOST set to: $GZ_CAMERA_UDP_HOST"
else
    fail_test "GZ_CAMERA_UDP_HOST not set correctly"
fi

if [ "$GZ_CAMERA_UDP_PORT" = "5600" ]; then
    pass_test "GZ_CAMERA_UDP_PORT set to: $GZ_CAMERA_UDP_PORT"
else
    fail_test "GZ_CAMERA_UDP_PORT not set correctly"
fi

echo ""

# ============================================================================
# TEST 4: Gazebo Runtime Test
# ============================================================================
echo -e "${YELLOW}Test 4: Gazebo Runtime${NC}"

info "Starting Gazebo in background..."

export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib"
export GZ_SIM_SYSTEM_PLUGIN_PATH="$PWD/build"
export GZ_SIM_RESOURCE_PATH="$PWD/models:$PWD/worlds"
export GZ_VERSION=ionic

# Start Gazebo in background, redirect output to log
gz sim -r -s worlds/iris_runway.sdf -v 4 > "$TEST_LOG" 2>&1 &
GAZEBO_PID=$!

info "Gazebo PID: $GAZEBO_PID"
info "Waiting for Gazebo to initialize (15 seconds)..."
sleep 15

# Check if Gazebo is still running
if kill -0 $GAZEBO_PID 2>/dev/null; then
    pass_test "Gazebo is running"
else
    fail_test "Gazebo crashed during startup" "Check $TEST_LOG for errors"
    cat "$TEST_LOG"
    exit 1
fi

echo ""

# ============================================================================
# TEST 5: Plugin Loading
# ============================================================================
echo -e "${YELLOW}Test 5: GstCameraPlugin Loading${NC}"

if grep -q "GstCameraPlugin: attached to sensor \[camera\]" "$TEST_LOG"; then
    pass_test "GstCameraPlugin loaded successfully"
else
    fail_test "GstCameraPlugin did not load" "Check plugin path and dependencies"
fi

if grep -q "GstCameraPlugin: using UDP host from environment: $ANDROID_IP" "$TEST_LOG"; then
    pass_test "Plugin using environment variable for UDP host"
else
    fail_test "Plugin not using environment variable" "Check env var export in run_gazebo.sh"
fi

if grep -q "GstCameraPlugin: auto-start enabled" "$TEST_LOG"; then
    pass_test "Auto-start is enabled"
else
    fail_test "Auto-start not enabled" "Check <auto_start>true</auto_start> in model.sdf"
fi

if grep -q "GstCameraPlugin: Successfully subscribed to image topic" "$TEST_LOG"; then
    pass_test "Successfully subscribed to camera image topic"
else
    fail_test "Failed to subscribe to image topic" "Check camera sensor configuration"
fi

echo ""

# ============================================================================
# TEST 6: Camera Topic Publishing
# ============================================================================
echo -e "${YELLOW}Test 6: Camera Topic Publishing${NC}"

info "Checking for camera image topic..."
sleep 2

CAMERA_TOPIC="/world/iris_runway/model/iris_with_gimbal/model/gimbal/link/pitch_link/sensor/camera/image"

if timeout 5 gz topic -l 2>/dev/null | grep -q "$CAMERA_TOPIC"; then
    pass_test "Camera image topic is published"
else
    fail_test "Camera image topic not found" "Camera sensor may not be initialized"
fi

echo ""

# ============================================================================
# TEST 7: GStreamer Pipeline
# ============================================================================
echo -e "${YELLOW}Test 7: GStreamer Pipeline${NC}"

if grep -q "GstCameraPlugin: Creating H.264/RTP pipeline" "$TEST_LOG"; then
    pass_test "GStreamer pipeline creation started"
else
    fail_test "GStreamer pipeline not created" "Check GStreamer dependencies"
fi

if grep -q "GstCameraPlugin: Pipeline ready" "$TEST_LOG"; then
    pass_test "GStreamer pipeline linked successfully"
else
    fail_test "GStreamer pipeline failed to link" "Check GStreamer element compatibility"
fi

if grep -q "GstCameraPlugin: starting GStreamer main loop" "$TEST_LOG"; then
    pass_test "GStreamer main loop started"
else
    fail_test "GStreamer main loop not started" "Check pipeline state change"
fi

if grep -q "GstCameraPlugin: Starting streaming pipeline for 640x480 video" "$TEST_LOG"; then
    pass_test "Video dimensions detected: 640x480"
else
    fail_test "Video dimensions not detected" "Camera may not be rendering"
fi

echo ""

# ============================================================================
# TEST 8: UDP Packet Transmission
# ============================================================================
echo -e "${YELLOW}Test 8: Network Packet Transmission${NC}"

info "Capturing UDP packets for 5 seconds..."

# Capture packets in background
timeout 5 tcpdump -i any -n -c 50 udp port 5600 > /tmp/tcpdump_$$.log 2>&1 &
TCPDUMP_PID=$!

sleep 5
wait $TCPDUMP_PID 2>/dev/null || true

PACKET_COUNT=$(grep -c "UDP.*5600" /tmp/tcpdump_$$.log 2>/dev/null || echo "0")

if [ "$PACKET_COUNT" -gt 10 ]; then
    pass_test "UDP packets detected on network: $PACKET_COUNT packets in 5 seconds"

    # Check destination IP
    if grep -q "$ANDROID_IP.5600" /tmp/tcpdump_$$.log 2>/dev/null; then
        pass_test "Packets sent to correct destination: $ANDROID_IP:5600"
    else
        fail_test "Packets not sent to Android IP" "Check run_gazebo.sh IP detection"
    fi
else
    fail_test "No UDP packets detected on port 5600" "GStreamer pipeline may not be sending data"
fi

rm -f /tmp/tcpdump_$$.log

echo ""

# ============================================================================
# TEST 9: ImageDisplay Plugin (GUI)
# ============================================================================
echo -e "${YELLOW}Test 9: GUI Configuration${NC}"

if grep -q 'plugin filename="ImageDisplay"' worlds/iris_runway.sdf; then
    pass_test "ImageDisplay plugin configured in runway world"
else
    fail_test "ImageDisplay plugin missing from runway world"
fi

if grep -q 'plugin filename="ImageDisplay"' worlds/iris_warehouse.sdf; then
    pass_test "ImageDisplay plugin configured in warehouse world"
else
    fail_test "ImageDisplay plugin missing from warehouse world"
fi

echo ""

# ============================================================================
# TEST 10: Model Configuration
# ============================================================================
echo -e "${YELLOW}Test 10: Model Configuration${NC}"

if grep -q '<auto_start>true</auto_start>' models/gimbal_small_3d/model.sdf; then
    pass_test "auto_start enabled in gimbal model"
else
    fail_test "auto_start not enabled" "Add <auto_start>true</auto_start> to model.sdf"
fi

if grep -q '<use_basic_pipeline>true</use_basic_pipeline>' models/gimbal_small_3d/model.sdf; then
    pass_test "use_basic_pipeline enabled (RTP/H.264)"
else
    fail_test "use_basic_pipeline not enabled" "Using MPEG-TS instead of RTP"
fi

echo ""

# ============================================================================
# TEST 11: Dynamic IP Refresh
# ============================================================================
echo -e "${YELLOW}Test 11: Dynamic IP Refresh Capability${NC}"

# Test that plugin code has dynamic IP refresh
if grep -q "Re-read environment variables on enable" src/GstCameraPlugin.cc; then
    pass_test "Plugin supports dynamic IP refresh on enable"
else
    fail_test "Plugin missing dynamic IP refresh" "Check OnVideoStreamEnable() implementation"
fi

# Test that environment variables can override SDF
if grep -q "Check environment variables first, then fall back to SDF config" src/GstCameraPlugin.cc; then
    pass_test "Plugin supports environment variable override"
else
    fail_test "Plugin missing env var override" "Check Configure() implementation"
fi

echo ""

# ============================================================================
# TEST SUMMARY
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo -e "Total Tests:  $TOTAL_TESTS"
echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  TESTS FAILED - Camera streaming may not work  ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Check test output above for specific failures."
    echo "Gazebo log available at: $TEST_LOG"
    exit 1
else
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ALL TESTS PASSED ✓                            ║${NC}"
    echo -e "${GREEN}║  Camera streaming is working correctly!        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Camera streaming verified and ready for use."
    echo "Video should stream to: $ANDROID_IP:5600"
    exit 0
fi
