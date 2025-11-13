#!/bin/bash
#
# Camera Configuration Test (No Hardware Required)
# Fast regression test for camera streaming configuration
#
# Tests code and configuration without running Gazebo or requiring Android.
# Safe to run in CI/CD pipelines.
#
# Usage: ./test_camera_config.sh
#

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $1"
    [ -n "$2" ] && echo -e "  ${RED}→ $2${NC}"
}

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Camera Streaming Configuration Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ============================================================================
# Test Plugin Source Code
# ============================================================================
echo -e "${YELLOW}Plugin Source Code Tests${NC}"

# Test 1: Environment variable support
if grep -q "std::getenv(\"GZ_CAMERA_UDP_HOST\")" src/GstCameraPlugin.cc; then
    pass_test "Plugin reads GZ_CAMERA_UDP_HOST environment variable"
else
    fail_test "Missing GZ_CAMERA_UDP_HOST support in plugin"
fi

if grep -q "std::getenv(\"GZ_CAMERA_UDP_PORT\")" src/GstCameraPlugin.cc; then
    pass_test "Plugin reads GZ_CAMERA_UDP_PORT environment variable"
else
    fail_test "Missing GZ_CAMERA_UDP_PORT support in plugin"
fi

# Test 2: Auto-start support
if grep -q "auto_start" src/GstCameraPlugin.cc; then
    pass_test "Plugin supports auto_start parameter"
else
    fail_test "Missing auto_start parameter support"
fi

# Test 3: Dynamic IP refresh
if grep -q "Re-read environment variables on enable" src/GstCameraPlugin.cc; then
    pass_test "Plugin supports dynamic IP refresh on enable signal"
else
    fail_test "Missing dynamic IP refresh capability"
fi

# Test 4: Error handling
if grep -q "gst_buffer_unref(buffer)" src/GstCameraPlugin.cc; then
    pass_test "Plugin has proper GStreamer buffer cleanup"
else
    fail_test "Missing buffer cleanup - potential memory leak"
fi

# Test 5: UDP sink configuration
if grep -q "g_object_set(G_OBJECT(sink), \"host\", udpHost.c_str()" src/GstCameraPlugin.cc; then
    pass_test "Plugin configures udpsink with host and port"
else
    fail_test "Missing udpsink configuration"
fi

echo ""

# ============================================================================
# Test Model Configuration
# ============================================================================
echo -e "${YELLOW}Model Configuration Tests${NC}"

# Test 6: GstCameraPlugin in model
if grep -q 'plugin name="GstCameraPlugin"' models/gimbal_small_3d/model.sdf; then
    pass_test "GstCameraPlugin configured in gimbal model"
else
    fail_test "GstCameraPlugin not found in gimbal model"
fi

# Test 7: Auto-start enabled
if grep -q '<auto_start>true</auto_start>' models/gimbal_small_3d/model.sdf; then
    pass_test "auto_start=true in gimbal model"
else
    fail_test "auto_start not enabled in model"
fi

# Test 8: Port configuration
if grep -q '<udp_port>5600</udp_port>' models/gimbal_small_3d/model.sdf; then
    pass_test "Default port 5600 configured"
else
    fail_test "Port configuration missing or incorrect"
fi

# Test 9: Camera sensor exists
if grep -q '<sensor name="camera" type="camera">' models/gimbal_small_3d/model.sdf; then
    pass_test "Camera sensor defined in gimbal model"
else
    fail_test "Camera sensor not found in model"
fi

echo ""

# ============================================================================
# Test World Files
# ============================================================================
echo -e "${YELLOW}World File Tests${NC}"

# Test 10: Gimbal model included in runway
if grep -q 'model://iris_with_gimbal' worlds/iris_runway.sdf; then
    pass_test "iris_with_gimbal included in runway world"
else
    fail_test "Gimbal model not included in runway world"
fi

# Test 11: Gimbal model included in warehouse
if grep -q 'model://iris_with_gimbal' worlds/iris_warehouse.sdf; then
    pass_test "iris_with_gimbal included in warehouse world"
else
    fail_test "Gimbal model not included in warehouse world"
fi

# Test 12: ImageDisplay in runway
if grep -q 'plugin filename="ImageDisplay"' worlds/iris_runway.sdf; then
    pass_test "ImageDisplay plugin in runway world"
else
    fail_test "ImageDisplay plugin missing from runway world"
fi

# Test 13: ImageDisplay in warehouse
if grep -q 'plugin filename="ImageDisplay"' worlds/iris_warehouse.sdf; then
    pass_test "ImageDisplay plugin in warehouse world"
else
    fail_test "ImageDisplay plugin missing from warehouse world"
fi

echo ""

# ============================================================================
# Test Launch Scripts
# ============================================================================
echo -e "${YELLOW}Launch Script Tests${NC}"

# Test 14: run_gazebo.sh exists and is executable
if [ -x "run_gazebo.sh" ]; then
    pass_test "run_gazebo.sh is executable"
else
    fail_test "run_gazebo.sh not found or not executable"
fi

# Test 15: Android detection in run_gazebo.sh
if grep -q "adb devices" run_gazebo.sh; then
    pass_test "run_gazebo.sh has Android detection logic"
else
    fail_test "Android detection missing from run_gazebo.sh"
fi

# Test 16: Environment variable export
if grep -q "export GZ_CAMERA_UDP_HOST" run_gazebo.sh; then
    pass_test "run_gazebo.sh exports GZ_CAMERA_UDP_HOST"
else
    fail_test "Missing GZ_CAMERA_UDP_HOST export in run_gazebo.sh"
fi

if grep -q "export GZ_CAMERA_UDP_PORT" run_gazebo.sh; then
    pass_test "run_gazebo.sh exports GZ_CAMERA_UDP_PORT"
else
    fail_test "Missing GZ_CAMERA_UDP_PORT export in run_gazebo.sh"
fi

echo ""

# ============================================================================
# Test Dependencies
# ============================================================================
echo -e "${YELLOW}Dependency Tests${NC}"

# Test 17: GStreamer installed
if command -v gst-launch-1.0 &> /dev/null; then
    GST_VERSION=$(gst-launch-1.0 --version 2>&1 | head -1 | awk '{print $4}')
    pass_test "GStreamer installed: version $GST_VERSION"
else
    fail_test "GStreamer not found" "Install with: brew install gstreamer"
fi

# Test 18: x264 encoder available
export PATH="/opt/homebrew/bin:$PATH"
if gst-inspect-1.0 x264enc &> /dev/null; then
    pass_test "x264enc encoder available"
else
    fail_test "x264enc not found" "Install with: brew install gst-plugins-ugly"
fi

# Test 19: rtph264pay payloader available
if gst-inspect-1.0 rtph264pay &> /dev/null; then
    pass_test "rtph264pay payloader available"
else
    fail_test "rtph264pay not found" "Install with: brew install gst-plugins-good"
fi

# Test 20: OpenCV available
if [ -d "/opt/homebrew/include/opencv4" ] || [ -d "/usr/local/include/opencv4" ]; then
    pass_test "OpenCV headers found"
else
    fail_test "OpenCV not found" "Install with: brew install opencv"
fi

echo ""

# ============================================================================
# Test Documentation
# ============================================================================
echo -e "${YELLOW}Documentation Tests${NC}"

# Test 21: Camera guide exists
if [ -f "CAMERA_STREAMING_GUIDE.md" ]; then
    pass_test "CAMERA_STREAMING_GUIDE.md exists"
else
    fail_test "Camera streaming guide missing"
fi

# Test 22: Video integration report exists
if [ -f "VIDEO_INTEGRATION_REPORT.md" ]; then
    pass_test "VIDEO_INTEGRATION_REPORT.md exists"
else
    fail_test "Video integration report missing"
fi

# Test 23: CLAUDE.md updated
if grep -q "camera" CLAUDE.md; then
    pass_test "CLAUDE.md mentions camera streaming"
else
    fail_test "CLAUDE.md not updated with camera info"
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Total: $TOTAL_TESTS  |  ${GREEN}Passed: $TESTS_PASSED${NC}  |  ${RED}Failed: $TESTS_FAILED${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All configuration tests passed!${NC}"
    echo "Camera streaming code is properly configured."
    echo ""
    echo "Next: Run ./test_camera_streaming.sh to verify runtime behavior."
    exit 0
else
    echo -e "${RED}✗ Some tests failed!${NC}"
    echo "Fix the issues above before deploying camera streaming."
    exit 1
fi
