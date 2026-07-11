#!/bin/bash
# Pre-flight check for local-dev: verifies the simulator stack is ready to launch.
# No NERVA/hephaestus dependencies — collaborator-friendly.

set -e

REPO_DIR="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
[ -f "$REPO_DIR/local-dev/.env" ] && set -a && . "$REPO_DIR/local-dev/.env" && set +a

ARDUPILOT_DIR="${ARDUPILOT_DIR:-$HOME/ardupilot}"
EXPECTED_GZ_VERSION="${GZ_VERSION:-ionic}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0
ok()   { echo -e "  ${GREEN}✓${NC} $*"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✗${NC} $*"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}!${NC} $*"; WARN=$((WARN+1)); }

echo -e "${BLUE}Local-dev preflight${NC}"
echo "  Repo:      $REPO_DIR"
echo "  ArduPilot: $ARDUPILOT_DIR"
echo "  GZ:        $EXPECTED_GZ_VERSION"
echo ""

echo -e "${BLUE}Plugin build${NC}"
if [ -f "$REPO_DIR/build/libArduPilotPlugin.dylib" ] || [ -f "$REPO_DIR/build/libArduPilotPlugin.so" ]; then
    ok "ArduPilotPlugin built"
else
    fail "ArduPilotPlugin not built — see local-dev/README.md (Build the plugin)"
fi

echo ""
echo -e "${BLUE}ArduPilot SITL${NC}"
if [ -x "$ARDUPILOT_DIR/Tools/autotest/sim_vehicle.py" ]; then
    ok "sim_vehicle.py present"
else
    fail "sim_vehicle.py missing — set ARDUPILOT_DIR or clone ArduPilot/ardupilot"
fi
if [ -x "$ARDUPILOT_DIR/build/sitl/bin/arducopter" ]; then
    ok "arducopter binary built"
else
    fail "arducopter binary missing — see local-dev/README.md (Build SITL)"
fi

echo ""
echo -e "${BLUE}Gazebo${NC}"
if command -v gz >/dev/null 2>&1; then
    ok "gz on PATH"
else
    fail "gz not on PATH — install Gazebo $EXPECTED_GZ_VERSION"
fi

case "$EXPECTED_GZ_VERSION" in
    garden)   GZ_MAJOR=7 ;;
    harmonic) GZ_MAJOR=8 ;;
    ionic)    GZ_MAJOR=9 ;;
    *)        GZ_MAJOR= ;;
esac
if [ -n "$GZ_MAJOR" ] && command -v brew >/dev/null 2>&1; then
    if brew list "gz-sim$GZ_MAJOR" >/dev/null 2>&1; then
        ok "gz-sim$GZ_MAJOR matches GZ_VERSION=$EXPECTED_GZ_VERSION"
    else
        warn "gz-sim$GZ_MAJOR not in brew list — make sure your Gazebo install matches GZ_VERSION"
    fi
fi

echo ""
echo -e "${BLUE}Android handset (optional)${NC}"
if command -v adb >/dev/null 2>&1; then
    DEV=$(adb devices 2>/dev/null | grep -v "^List" | grep -c "device$" || true)
    if [ "$DEV" -gt 0 ]; then
        ok "adb sees $DEV device(s)"
    else
        warn "adb installed, no device connected — fine if you're using loopback"
    fi
else
    warn "adb not installed — fine if you're not forwarding to a handset"
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "  Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}  Warnings: ${YELLOW}$WARN${NC}"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "Ready. Launch:"
    echo "  T1:  ./run_local_gazebo.sh"
    echo "  T2:  ./start_local_sitl.sh"
    exit 0
else
    echo ""
    echo "Fix the failures above, then re-run."
    exit 1
fi
