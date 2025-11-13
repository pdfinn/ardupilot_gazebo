#!/bin/bash
#
# Local Video Stream Test
# Streams Gazebo camera video to localhost and displays in pop-up window
#
# This script is for LOCAL TESTING ONLY - no Android device required!
#
# What it does:
# 1. Starts Gazebo streaming to localhost (127.0.0.1:5600)
# 2. Opens GStreamer window displaying the live camera feed
# 3. Allows visual verification of camera without Android
#
# Usage: ./test_local_video.sh [world_name]
#   world_name: iris_runway (default) or iris_warehouse
#
# Press Ctrl+C to stop both Gazebo and video viewer.
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
GSTREAMER_PID=""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Stopping video test...${NC}"

    # Kill GStreamer viewer
    if [ -n "$GSTREAMER_PID" ]; then
        kill $GSTREAMER_PID 2>/dev/null || true
        echo "  Stopped video viewer"
    fi

    # Kill Gazebo
    if [ -n "$GAZEBO_PID" ]; then
        kill $GAZEBO_PID 2>/dev/null || true
        echo "  Stopped Gazebo"
    fi

    # Belt and suspenders cleanup
    pkill -9 -f "gz sim" 2>/dev/null || true
    pkill -9 -f "gst-launch" 2>/dev/null || true
    lsof -ti:9002 2>/dev/null | xargs kill -9 2>/dev/null || true
    lsof -ti:5600 2>/dev/null | xargs kill -9 2>/dev/null || true

    sleep 1

    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

trap cleanup EXIT INT TERM

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Local Video Stream Test                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Testing camera streaming to localhost${NC}"
echo -e "${BLUE}World: ${WORLD_NAME}${NC}"
echo ""

# Clean up any existing processes
echo -e "${YELLOW}Cleaning up old processes...${NC}"
cleanup

# Force streaming to localhost
export GZ_CAMERA_UDP_HOST="127.0.0.1"
export GZ_CAMERA_UDP_PORT="$VIDEO_PORT"

echo -e "${GREEN}✓ Camera configured to stream to: localhost:$VIDEO_PORT${NC}"
echo ""

# Set Gazebo environment
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib"
export GZ_SIM_SYSTEM_PLUGIN_PATH="$PWD/build"
export GZ_SIM_RESOURCE_PATH="$PWD/models:$PWD/worlds"
export GZ_VERSION=ionic

# Start Gazebo in background
echo -e "${YELLOW}Starting Gazebo...${NC}"
echo "  World: worlds/${WORLD_NAME}.sdf"
echo "  Verbose: level 4"
echo ""

gz sim -r -s "worlds/${WORLD_NAME}.sdf" -v 4 > /tmp/gazebo_local_test_$$.log 2>&1 &
GAZEBO_PID=$!

echo -e "${GREEN}✓ Gazebo started (PID: $GAZEBO_PID)${NC}"
echo ""

# Wait for Gazebo to initialize
echo -e "${YELLOW}Waiting for Gazebo to initialize...${NC}"
echo -n "  "
for i in {1..15}; do
    echo -n "."
    sleep 1

    # Check if Gazebo crashed
    if ! kill -0 $GAZEBO_PID 2>/dev/null; then
        echo ""
        echo -e "${RED}ERROR: Gazebo crashed during startup${NC}"
        echo "Log:"
        tail -30 /tmp/gazebo_local_test_$$.log
        exit 1
    fi
done
echo ""

# Verify plugin loaded
if grep -q "GstCameraPlugin: attached to sensor" /tmp/gazebo_local_test_$$.log; then
    echo -e "${GREEN}✓ GstCameraPlugin loaded${NC}"
else
    echo -e "${RED}ERROR: GstCameraPlugin did not load${NC}"
    echo "Check log: /tmp/gazebo_local_test_$$.log"
    exit 1
fi

# Verify auto-start
if grep -q "GstCameraPlugin: auto-starting video stream" /tmp/gazebo_local_test_$$.log; then
    echo -e "${GREEN}✓ Auto-start enabled${NC}"
else
    echo -e "${YELLOW}⚠ Auto-start may not be enabled${NC}"
fi

# Verify pipeline created
if grep -q "GstCameraPlugin: Pipeline ready" /tmp/gazebo_local_test_$$.log; then
    echo -e "${GREEN}✓ GStreamer pipeline created${NC}"
else
    echo -e "${RED}ERROR: GStreamer pipeline failed${NC}"
    exit 1
fi

echo ""

# Start GStreamer video viewer
echo -e "${YELLOW}Starting video viewer...${NC}"
echo "  Protocol: RTP/H.264"
echo "  Port: $VIDEO_PORT"
echo ""

echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Video window should open showing camera feed  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo "You should see:"
echo "  - Sky/horizon from drone camera"
echo "  - Runway or warehouse environment"
echo "  - Video updates in real-time"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop test${NC}"
echo ""

# Create SDP file to describe the RTP stream
SDP_FILE="/tmp/gazebo_camera_$$.sdp"
cat > "$SDP_FILE" << EOF
v=0
o=- 0 0 IN IP4 127.0.0.1
s=Gazebo Camera Stream
c=IN IP4 127.0.0.1
t=0 0
m=video $VIDEO_PORT RTP/AVP 96
a=rtpmap:96 H264/90000
a=fmtp:96 packetization-mode=1
EOF

echo -e "${GREEN}✓ Created SDP file: $SDP_FILE${NC}"

# Try VLC first (best RTP support), then ffplay as fallback
if command -v /Applications/VLC.app/Contents/MacOS/VLC &> /dev/null; then
    echo -e "${GREEN}✓ Using VLC for video display${NC}"
    echo ""

    /Applications/VLC.app/Contents/MacOS/VLC \
      "$SDP_FILE" \
      --network-caching=0 \
      --clock-jitter=0 \
      --live-caching=0 \
      --no-video-title-show &
    GSTREAMER_PID=$!

elif command -v vlc &> /dev/null; then
    echo -e "${GREEN}✓ Using VLC for video display${NC}"
    echo ""

    vlc "$SDP_FILE" \
      --network-caching=0 \
      --clock-jitter=0 \
      --live-caching=0 \
      --no-video-title-show &
    GSTREAMER_PID=$!

else
    echo -e "${YELLOW}⚠ VLC not found, trying ffplay...${NC}"
    echo ""

    if command -v ffplay &> /dev/null; then
        ffplay -protocol_whitelist file,udp,rtp \
          -i "$SDP_FILE" \
          -fflags nobuffer \
          -flags low_delay \
          -framedrop \
          -window_title "Gazebo Camera - ${WORLD_NAME}" \
          -x 640 -y 480 &
        GSTREAMER_PID=$!
    else
        echo -e "${RED}ERROR: No video player found${NC}"
        echo ""
        echo "Install VLC (recommended): brew install --cask vlc"
        echo "  OR"
        echo "Install ffmpeg: brew install ffmpeg"
        rm -f "$SDP_FILE"
        exit 1
    fi
fi

# Wait for user to stop
wait $GSTREAMER_PID 2>/dev/null || true

# Cleanup SDP file
rm -f "$SDP_FILE"
