#!/bin/bash
#
# Android Video Stream Test
# Tests camera streaming on Android device independently of ATAK/GCS
#
# This script:
# 1. Starts Gazebo streaming to Android device
# 2. Pushes SDP file to Android
# 3. Opens VLC on Android to display stream
#
# Verifies the video stream works on Android without needing ATAK
#
# Usage: ./test_android_video.sh [world_name]
#   world_name: iris_runway (default) or iris_warehouse
#
# Requirements:
# - Android device connected via USB
# - Android on same WiFi as Mac
# - VLC installed on Android (will prompt if not)
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
WORLD_NAME="${1:-iris_runway}"
VIDEO_PORT="5600"
GAZEBO_PID=""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Stopping test...${NC}"

    # Kill Gazebo
    if [ -n "$GAZEBO_PID" ]; then
        kill $GAZEBO_PID 2>/dev/null || true
        echo "  Stopped Gazebo"
    fi

    # Cleanup
    pkill -9 -f "gz sim" 2>/dev/null || true
    lsof -ti:9002 2>/dev/null | xargs kill -9 2>/dev/null || true
    adb shell rm -f /sdcard/gazebo_camera.sdp 2>/dev/null || true

    sleep 1
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

trap cleanup EXIT INT TERM

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Android Video Stream Test                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Testing camera streaming directly to Android${NC}"
echo -e "${BLUE}World: ${WORLD_NAME}${NC}"
echo ""

# Check ADB
if ! command -v adb &> /dev/null; then
    echo -e "${RED}ERROR: adb not found${NC}"
    echo "Install Android SDK platform-tools"
    exit 1
fi

# Detect Android device
echo -e "${YELLOW}Detecting Android device...${NC}"

DEVICES=$(adb devices | grep -v "^List" | grep -v "emulator" | grep "device$" | awk '{print $1}')
DEVICE_COUNT=$(echo "$DEVICES" | grep -v "^$" | wc -l | tr -d ' ')

if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo -e "${RED}ERROR: No Android device detected${NC}"
    echo "Connect your Android device via USB and enable USB debugging"
    exit 1
fi

FIRST_DEVICE=$(echo "$DEVICES" | head -1)
echo -e "${GREEN}✓ Android device: $FIRST_DEVICE${NC}"

# Get Android WiFi IP
ANDROID_IP=$(adb -s "$FIRST_DEVICE" shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | tr -d '\r\n ')

if [ -z "$ANDROID_IP" ]; then
    echo -e "${RED}ERROR: Could not get Android WiFi IP${NC}"
    echo "Make sure device is connected to WiFi"
    exit 1
fi

echo -e "${GREEN}✓ Android WiFi IP: $ANDROID_IP${NC}"
echo ""

# Check if VLC is installed on Android
echo -e "${YELLOW}Checking for VLC on Android...${NC}"

if adb shell pm list packages | grep -q "org.videolan.vlc"; then
    echo -e "${GREEN}✓ VLC is installed on Android${NC}"
    HAS_VLC=true
else
    echo -e "${YELLOW}⚠ VLC not installed on Android${NC}"
    echo ""
    echo "To install VLC on Android:"
    echo "  1. Open Google Play Store on your device"
    echo "  2. Search for 'VLC for Android'"
    echo "  3. Install VLC media player by VideoLAN"
    echo ""
    echo -e "${YELLOW}Or install via adb (if you have the APK):${NC}"
    echo "  adb install vlc-android.apk"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    HAS_VLC=false
fi

echo ""

# Clean up old Gazebo
echo -e "${YELLOW}Cleaning up old Gazebo processes...${NC}"
cleanup

# Configure streaming to Android
export GZ_CAMERA_UDP_HOST="$ANDROID_IP"
export GZ_CAMERA_UDP_PORT="$VIDEO_PORT"

echo -e "${GREEN}✓ Camera configured to stream to: $ANDROID_IP:$VIDEO_PORT${NC}"
echo ""

# Set Gazebo environment
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib"
export GZ_SIM_SYSTEM_PLUGIN_PATH="$PWD/build"
export GZ_SIM_RESOURCE_PATH="$PWD/models:$PWD/worlds"
export GZ_VERSION=ionic

# Start Gazebo
echo -e "${YELLOW}Starting Gazebo...${NC}"
gz sim -r -s "worlds/${WORLD_NAME}.sdf" -v 4 > /tmp/gazebo_android_test_$$.log 2>&1 &
GAZEBO_PID=$!

echo -e "${GREEN}✓ Gazebo started (PID: $GAZEBO_PID)${NC}"
echo ""

# Wait for initialization
echo -e "${YELLOW}Waiting for Gazebo to initialize...${NC}"
echo -n "  "
for i in {1..15}; do
    echo -n "."
    sleep 1
    if ! kill -0 $GAZEBO_PID 2>/dev/null; then
        echo ""
        echo -e "${RED}ERROR: Gazebo crashed${NC}"
        exit 1
    fi
done
echo ""

# Verify plugin loaded
if grep -q "GstCameraPlugin: attached to sensor" /tmp/gazebo_android_test_$$.log; then
    echo -e "${GREEN}✓ GstCameraPlugin loaded and streaming to Android${NC}"
else
    echo -e "${RED}ERROR: GstCameraPlugin did not load${NC}"
    exit 1
fi

echo ""

# Create SDP file for Android
SDP_FILE="/tmp/gazebo_camera_android.sdp"
cat > "$SDP_FILE" << EOF
v=0
o=- 0 0 IN IP4 $ANDROID_IP
s=Gazebo Camera Stream
c=IN IP4 $ANDROID_IP
t=0 0
m=video $VIDEO_PORT RTP/AVP 96
a=rtpmap:96 H264/90000
a=fmtp:96 packetization-mode=1
EOF

echo -e "${GREEN}✓ Created SDP file${NC}"

# Push SDP file to Android
adb push "$SDP_FILE" /sdcard/gazebo_camera.sdp > /dev/null 2>&1

echo -e "${GREEN}✓ SDP file pushed to Android: /sdcard/gazebo_camera.sdp${NC}"
echo ""

# Verify streaming with tcpdump
echo -e "${YELLOW}Verifying UDP packets are being sent...${NC}"
PACKET_COUNT=$(timeout 3 tcpdump -i any -n -c 10 "udp port 5600 and dst host $ANDROID_IP" 2>&1 | grep -c "UDP" || echo "0")

if [ "$PACKET_COUNT" -gt 5 ]; then
    echo -e "${GREEN}✓ Video packets streaming to Android ($PACKET_COUNT packets captured)${NC}"
else
    echo -e "${RED}✗ No packets detected streaming to Android${NC}"
    echo "Stream may not be working properly"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Video is streaming to your Android device!   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$HAS_VLC" = true ]; then
    echo -e "${GREEN}Option 1: Open with VLC (Recommended)${NC}"
    echo ""
    echo "Opening VLC on Android..."

    # Try to open SDP file with VLC
    adb shell am start -a android.intent.action.VIEW \
      -d "file:///sdcard/gazebo_camera.sdp" \
      -t "application/sdp" \
      org.videolan.vlc 2>/dev/null || true

    echo ""
    echo "If VLC doesn't auto-open:"
    echo "  1. Open VLC app on your Android"
    echo "  2. Tap ☰ menu → 'Open Network Stream'"
    echo "  3. Browse to /sdcard/gazebo_camera.sdp"
    echo "  4. Video should start playing"
    echo ""
else
    echo -e "${GREEN}To view video on Android:${NC}"
    echo ""
    echo "Install VLC from Play Store, then:"
    echo "  1. Open VLC app on Android"
    echo "  2. Tap ☰ menu → 'Open Network Stream'"
    echo "  3. Enter: rtp://@:5600"
    echo "  4. OR browse to /sdcard/gazebo_camera.sdp"
    echo ""
fi

echo -e "${YELLOW}Alternative - Direct RTP URL:${NC}"
echo "  Open any video player that supports RTP and enter:"
echo -e "  ${BLUE}rtp://@:5600${NC}"
echo ""

echo -e "${GREEN}Stream details:${NC}"
echo "  Protocol: RTP/H.264"
echo "  Port: 5600 (UDP)"
echo "  Resolution: 640x480"
echo "  Frame rate: 10 fps"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop streaming${NC}"

# Keep Gazebo running
wait $GAZEBO_PID 2>/dev/null || true
