#!/bin/bash
#
# Refresh Video Stream - Updates video streaming IP when network changes
#
# Usage: ./refresh_video.sh [world_name]
#   world_name: iris_runway (default) or iris_warehouse
#
# This script:
# 1. Detects new Android IP via ADB
# 2. Stops current video stream
# 3. Updates environment variable
# 4. Restarts video stream with new IP
#
# No need to restart Gazebo!

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Determine world name
WORLD_NAME="${1:-iris_runway}"

# Build camera topic path based on world
CAMERA_TOPIC="/world/${WORLD_NAME}/model/iris_with_gimbal/model/gimbal/link/pitch_link/sensor/camera/image"
ENABLE_TOPIC="${CAMERA_TOPIC}/enable_streaming"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Refresh Video Stream${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if Gazebo is running
if ! pgrep -f "gz sim" > /dev/null; then
    echo -e "${RED}ERROR: Gazebo is not running${NC}"
    echo "Start Gazebo first with: ./run_gazebo.sh"
    exit 1
fi

# Detect new Android IP
echo -e "${YELLOW}Detecting Android device...${NC}"

if ! command -v adb &> /dev/null; then
    echo -e "${RED}ERROR: adb not found${NC}"
    echo "Install Android Debug Bridge (adb) first"
    exit 1
fi

DEVICES=$(adb devices | grep -v "^List" | grep -v "emulator" | grep "device$" | awk '{print $1}')
DEVICE_COUNT=$(echo "$DEVICES" | grep -v "^$" | wc -l | tr -d ' ')

if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo -e "${RED}ERROR: No Android device detected${NC}"
    echo "Connect your Android device via USB and enable USB debugging"
    exit 1
fi

FIRST_DEVICE=$(echo "$DEVICES" | head -1)
DETECTED_IP=$(adb -s "$FIRST_DEVICE" shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | tr -d '\r\n ')

if [ -z "$DETECTED_IP" ]; then
    echo -e "${RED}ERROR: Could not get Android WiFi IP${NC}"
    echo "Make sure device is connected to WiFi"
    exit 1
fi

echo -e "${GREEN}✓ Android device: $FIRST_DEVICE${NC}"
echo -e "${GREEN}✓ WiFi IP: $DETECTED_IP${NC}"
echo ""

# Stop current video stream
echo -e "${YELLOW}Stopping video stream...${NC}"
gz topic -t "$ENABLE_TOPIC" -m gz.msgs.Boolean -p "data: false" 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not send stop message (video may not be running)${NC}"
}

sleep 1

# Update environment variable for current Gazebo process
# Note: This updates the script's env, not Gazebo's. Gazebo will re-read on next enable.
export GZ_CAMERA_UDP_HOST="$DETECTED_IP"
export GZ_CAMERA_UDP_PORT="5600"

echo -e "${GREEN}✓ Updated video target: $DETECTED_IP:5600${NC}"
echo ""

# Restart video stream - plugin will re-read env vars
echo -e "${YELLOW}Starting video stream to new IP...${NC}"
gz topic -t "$ENABLE_TOPIC" -m gz.msgs.Boolean -p "data: true" 2>/dev/null || {
    echo -e "${RED}ERROR: Could not send start message${NC}"
    echo "Check that camera topic exists: $ENABLE_TOPIC"
    exit 1
}

sleep 1

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Video stream refreshed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Video streaming to: ${DETECTED_IP}:5600"
echo ""
echo -e "${YELLOW}Note: If Gazebo was started before this network, you need to${NC}"
echo -e "${YELLOW}restart Gazebo OR run this script to update the target IP.${NC}"
