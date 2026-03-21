#!/bin/bash
#
# NERVA2 UAS Demo - Video Stream to Android
# Streams Gazebo gimbal camera to ATAK on Android via USB
#
# Based on parent directory's gazebo_video_bridge.py and start_video_stream.sh
# Uses the same Python bridge but targets the Android device IP
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
BRIDGE_SCRIPT="$SCRIPT_DIR/gazebo_video_bridge_h264.py"

# Configuration
CAMERA_TOPIC="world/iris_runway/model/iris_with_gimbal/model/gimbal/link/pitch_link/sensor/camera/image"
UDP_PORT="5600"
ANDROID_IP=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --android-ip)
            ANDROID_IP="$2"
            shift 2
            ;;
        --port)
            UDP_PORT="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--android-ip IP] [--port PORT]"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  NERVA2 UAS Demo - Video Stream${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""

# Check if Gazebo is running
if ! pgrep -f "gz sim" > /dev/null; then
    echo -e "${RED}ERROR: Gazebo not running${NC}"
    echo "Start Gazebo first with ./run_gazebo.sh"
    exit 1
fi
echo -e "${GREEN}✓ Gazebo is running${NC}"

# Check bridge script exists
if [ ! -f "$BRIDGE_SCRIPT" ]; then
    echo -e "${RED}ERROR: Video bridge not found at $BRIDGE_SCRIPT${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Video bridge script found${NC}"

# Auto-detect Android IP if not provided (same logic as SITL script)
if [ -z "$ANDROID_IP" ]; then
    echo -e "${YELLOW}Auto-detecting Android device IP...${NC}"

    DEVICES=$(adb devices | grep -v "^List" | grep -v "emulator" | grep "device$" | awk '{print $1}')
    DEVICE_COUNT=$(echo "$DEVICES" | grep -v "^$" | wc -l | tr -d ' ')

    if [ "$DEVICE_COUNT" -eq 0 ]; then
        echo -e "${RED}ERROR: No Android device found!${NC}"
        echo "Connect your device via USB and ensure adb is working."
        exit 1
    elif [ "$DEVICE_COUNT" -gt 1 ]; then
        FIRST_DEVICE=$(echo "$DEVICES" | head -1)
        ANDROID_IP=$(adb -s "$FIRST_DEVICE" shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | tr -d '\r\n ')
    else
        DEVICE=$(echo "$DEVICES" | head -1)
        ANDROID_IP=$(adb -s "$DEVICE" shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | tr -d '\r\n ')
    fi

    if [ -z "$ANDROID_IP" ]; then
        echo -e "${RED}ERROR: Could not detect Android device IP${NC}"
        echo "Try: adb shell ip addr show wlan0"
        echo "Or specify manually: $0 --android-ip 192.168.x.x"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Android device: $ANDROID_IP${NC}"

# Check camera topic
echo -e "${YELLOW}Checking for camera topic...${NC}"
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib"

if ! gz topic -l 2>/dev/null | grep -q "$CAMERA_TOPIC"; then
    echo -e "${RED}ERROR: Camera topic not found${NC}"
    echo "Expected: $CAMERA_TOPIC"
    echo ""
    echo "Available camera topics:"
    gz topic -l 2>/dev/null | grep camera || echo "No camera topics found"
    echo ""
    echo "Make sure the iris_with_gimbal model is loaded in Gazebo."
    exit 1
fi
echo -e "${GREEN}✓ Camera topic found${NC}"

echo ""
echo -e "${BLUE}Streaming video:${NC}"
echo "  Camera: $CAMERA_TOPIC"
echo "  Target: udp://$ANDROID_IP:$UDP_PORT"
echo ""

# Run the bridge script, targeting Android device
exec "$BRIDGE_SCRIPT" \
    --topic "$CAMERA_TOPIC" \
    --host "$ANDROID_IP" \
    --port "$UDP_PORT"
