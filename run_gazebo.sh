#!/bin/bash

set -e

# Cleanup function - kills ALL Gazebo processes
cleanup() {
    echo ""
    echo "Cleaning up Gazebo processes..."

    # Kill by name
    pkill -9 -f "gz sim" 2>/dev/null || true

    # Kill by port (belt and suspenders)
    lsof -ti:9002 2>/dev/null | xargs kill -9 2>/dev/null || true

    sleep 1

    # Verify clean
    if pgrep -f "gz sim" > /dev/null; then
        echo "⚠ Warning: Some Gazebo processes still running"
        ps aux | grep "gz sim" | grep -v grep
    else
        echo "✓ All Gazebo processes stopped"
    fi
}

# Clean up ANY existing processes before starting
echo "Cleaning up old Gazebo processes..."
cleanup

# Ensure cleanup on exit
trap cleanup EXIT INT TERM

# Auto-detect Android IP for camera streaming
echo "Detecting Android device for camera streaming..."
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
            echo "✓ Android device detected: $CAMERA_IP"
        else
            echo "⚠ Android device found but no IP - using localhost"
        fi
    else
        echo "⚠ No Android device detected - streaming to localhost"
    fi
else
    echo "⚠ adb not found - streaming to localhost"
fi

# Export camera streaming configuration
export GZ_CAMERA_UDP_HOST="$CAMERA_IP"
export GZ_CAMERA_UDP_PORT="$CAMERA_PORT"
echo "Camera streaming configured: udp://$CAMERA_IP:$CAMERA_PORT"
echo ""

export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib"
export GZ_SIM_SYSTEM_PLUGIN_PATH="$PWD/build"
export GZ_SIM_RESOURCE_PATH="$PWD/models:$PWD/worlds"

echo "Starting Gazebo runway world..."
gz sim -r -s worlds/iris_runway.sdf -v 4
