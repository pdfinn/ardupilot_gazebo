#!/bin/bash
#
# NERVA2 UAS Demo - Gazebo Launcher
# Wraps the parent run_gazebo.sh with Android camera streaming env vars
#
# The built GstCameraPlugin (Nov 12) reads GZ_CAMERA_UDP_HOST/PORT
# to stream H.264/RTP directly to ATAK on the Android device.
# No Python video bridge needed.
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  NERVA2 UAS Demo - Gazebo Launcher${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""

# Auto-detect Android IP for camera streaming
echo -e "${YELLOW}Detecting Android device for camera streaming...${NC}"
CAMERA_IP="127.0.0.1"
CAMERA_PORT="5600"

if command -v adb &> /dev/null; then
    DEVICES=$(adb devices | grep -v "^List" | grep -v "emulator" | grep "device$" | awk '{print $1}')
    DEVICE_COUNT=$(echo "$DEVICES" | grep -v "^$" | wc -l | tr -d ' ')

    if [ "$DEVICE_COUNT" -gt 0 ]; then
        FIRST_DEVICE=$(echo "$DEVICES" | head -1)
        DETECTED_IP=$(adb -s "$FIRST_DEVICE" shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | tr -d '\r\n ')

        if [ -n "$DETECTED_IP" ]; then
            CAMERA_IP="$DETECTED_IP"
            echo -e "${GREEN}✓ Android device detected: $CAMERA_IP${NC}"
        else
            echo -e "${YELLOW}⚠ Android device found but no IP - using localhost${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ No Android device detected - streaming to localhost${NC}"
    fi
else
    echo -e "${YELLOW}⚠ adb not found - streaming to localhost${NC}"
fi

# Export camera streaming configuration for GstCameraPlugin
export GZ_CAMERA_UDP_HOST="$CAMERA_IP"
export GZ_CAMERA_UDP_PORT="$CAMERA_PORT"
echo -e "${BLUE}Camera streaming: H.264/RTP -> udp://$CAMERA_IP:$CAMERA_PORT${NC}"
echo ""

# Run the parent Gazebo launcher from its own directory
cd "$PARENT_DIR"
exec ./run_gazebo.sh
