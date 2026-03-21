#!/bin/bash
#
# NERVA2 UAS Demo - Preflight Check
# Validates all demo components before launch
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "  ${GREEN}✓ $1${NC}"
    PASS=$((PASS + 1))
}

check_fail() {
    echo -e "  ${RED}✗ $1${NC}"
    FAIL=$((FAIL + 1))
}

check_warn() {
    echo -e "  ${YELLOW}⚠ $1${NC}"
    WARN=$((WARN + 1))
}

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  NERVA2 UAS Demo - Preflight Check${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# ── Local Environment ──────────────────────────────────────────────
echo -e "${BLUE}Local Environment${NC}"

# ArduPilot binary
ARDUPILOT_DIR="${ARDUPILOT_DIR:-/Users/pdfinn/github.com/NERVsystems/ardupilot}"
if [ -f "$ARDUPILOT_DIR/build/sitl/bin/arducopter" ]; then
    check_pass "ArduCopter binary found"
else
    check_fail "ArduCopter binary not found at $ARDUPILOT_DIR/build/sitl/bin/arducopter"
fi

# Gazebo plugin
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PARENT_DIR/build/libArduPilotPlugin.dylib" ]; then
    check_pass "ArduPilot Gazebo plugin built"
else
    check_fail "ArduPilot Gazebo plugin not found"
fi

# GZ_VERSION
if [ "$GZ_VERSION" = "ionic" ]; then
    check_pass "GZ_VERSION=ionic"
else
    check_warn "GZ_VERSION not set to 'ionic' (currently: '${GZ_VERSION:-unset}')"
fi

# Anaconda contamination check
if ls /opt/anaconda3/lib/libQt5*.dylib 2>/dev/null | grep -q .; then
    check_warn "Anaconda Qt5 libs present (OK for running, bad for rebuilding)"
else
    check_pass "No Anaconda Qt5 contamination"
fi

# Video bridge
if [ -f "$PARENT_DIR/gazebo_video_bridge.py" ]; then
    check_pass "Video bridge script found"
else
    check_fail "Video bridge script not found"
fi

echo ""

# ── Android Device ─────────────────────────────────────────────────
echo -e "${BLUE}Android Device${NC}"

if command -v adb &>/dev/null; then
    check_pass "adb available"

    DEVICES=$(adb devices | grep -v "^List" | grep -v "emulator" | grep "device$" | awk '{print $1}')
    DEVICE_COUNT=$(echo "$DEVICES" | grep -v "^$" | wc -l | tr -d ' ')

    if [ "$DEVICE_COUNT" -gt 0 ]; then
        DEVICE=$(echo "$DEVICES" | head -1)
        check_pass "Android device connected: $DEVICE"

        ANDROID_IP=$(adb -s "$DEVICE" shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | tr -d '\r\n ')
        if [ -n "$ANDROID_IP" ]; then
            check_pass "Android WiFi IP: $ANDROID_IP"
        else
            check_warn "Could not detect Android WiFi IP (may need --android-ip flag)"
        fi
    else
        check_fail "No Android device connected"
    fi
else
    check_fail "adb not found"
fi

echo ""

# ── Hephaestus (Edge Device) ──────────────────────────────────────
echo -e "${BLUE}Hephaestus (Edge Device)${NC}"

if ssh -o ConnectTimeout=5 -o BatchMode=yes hephaestus "echo ok" &>/dev/null; then
    check_pass "SSH connectivity to hephaestus"

    # Check TAK Server
    TAK_STATUS=$(ssh -o ConnectTimeout=5 hephaestus "docker inspect --format '{{.State.Health.Status}}' tak-server 2>/dev/null" || echo "not found")
    if [ "$TAK_STATUS" = "healthy" ]; then
        check_pass "TAK Server: healthy"
    else
        check_fail "TAK Server: $TAK_STATUS"
    fi

    # Check NERVA2
    NERVA_STATUS=$(ssh -o ConnectTimeout=5 hephaestus "docker inspect --format '{{.State.Health.Status}}' nerva2 2>/dev/null" || echo "not found")
    if [ "$NERVA_STATUS" = "healthy" ]; then
        check_pass "NERVA2: healthy"
    else
        check_fail "NERVA2: $NERVA_STATUS"
    fi

    # Check TAK Connector
    TC_STATUS=$(ssh -o ConnectTimeout=5 hephaestus "docker inspect --format '{{.State.Health.Status}}' takconnector 2>/dev/null" || echo "not found")
    if [ "$TC_STATUS" = "healthy" ]; then
        check_pass "TAK Connector: healthy"
    else
        check_fail "TAK Connector: $TC_STATUS"
    fi

    # Check UASMCP binary inside nerva2
    UASMCP=$(ssh -o ConnectTimeout=5 hephaestus "docker exec nerva2 test -f /app/bin/uasmcp && echo yes || echo no" 2>/dev/null || echo "unknown")
    if [ "$UASMCP" = "yes" ]; then
        check_pass "UASMCP binary present in nerva2"
    else
        check_fail "UASMCP binary not found in nerva2 container"
    fi

    # Check ZeroTier IP
    ZT_IP=$(ssh -o ConnectTimeout=5 hephaestus "ip addr show ztmosj76hc 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" || echo "")
    if [ -n "$ZT_IP" ]; then
        check_pass "ZeroTier IP: $ZT_IP"
    else
        check_warn "ZeroTier interface not found"
    fi

else
    check_fail "Cannot SSH to hephaestus"
    echo -e "    ${RED}All edge checks skipped${NC}"
fi

echo ""

# ── Summary ────────────────────────────────────────────────────────
echo -e "${BLUE}════════════════════════════════════════${NC}"
TOTAL=$((PASS + FAIL + WARN))
echo -e "  ${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}  ${YELLOW}Warnings: $WARN${NC}  Total: $TOTAL"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo -e "  ${GREEN}All checks passed. Ready for demo.${NC}"
    echo ""
    echo -e "  ${BLUE}Next steps:${NC}"
    echo "    1. Terminal 1: demo/run_demo_gazebo.sh"
    echo "    2. Terminal 2: demo/start_demo_sitl.sh"
    echo "    3. Open Android Studio device mirror"
    echo "    4. Launch ATAK on Android"
else
    echo ""
    echo -e "  ${RED}Fix failed checks before running demo.${NC}"
    exit 1
fi
