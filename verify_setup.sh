#!/bin/bash
# Verify build/runtime prerequisites for the ArduPilot Gazebo plugin.
#
# Usage:
#   ARDUPILOT_DIR=/path/to/ardupilot ./verify_setup.sh
#
# Defaults: ARDUPILOT_DIR=$HOME/ardupilot, GZ_VERSION=ionic on macOS.

set -e

REPO_DIR="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || cd "$(dirname "$0")" && pwd)"
ARDUPILOT_DIR="${ARDUPILOT_DIR:-$HOME/ardupilot}"
EXPECTED_GZ_VERSION="${GZ_VERSION:-ionic}"

echo "Checking ArduPilot Gazebo setup..."
echo "  Repo:         $REPO_DIR"
echo "  ArduPilot:    $ARDUPILOT_DIR"
echo "  GZ_VERSION:   $EXPECTED_GZ_VERSION"
echo ""

ERRORS=0
fail() { echo "FAIL: $*"; ERRORS=$((ERRORS + 1)); }
ok()   { echo "OK:   $*"; }
warn() { echo "WARN: $*"; }

# Plugin built
if [ -f "$REPO_DIR/build/libArduPilotPlugin.dylib" ] || \
   [ -f "$REPO_DIR/build/libArduPilotPlugin.so" ]; then
    ok "ArduPilotPlugin built"
else
    fail "ArduPilotPlugin not built — run: cd build && cmake .. && make -j4"
fi

# ArduPilot SITL binary
if [ -x "$ARDUPILOT_DIR/build/sitl/bin/arducopter" ]; then
    ok "arducopter binary present"
else
    fail "arducopter not found at $ARDUPILOT_DIR/build/sitl/bin/arducopter"
fi

# sim_vehicle.py
if [ -x "$ARDUPILOT_DIR/Tools/autotest/sim_vehicle.py" ]; then
    ok "sim_vehicle.py present"
else
    fail "sim_vehicle.py not found in $ARDUPILOT_DIR/Tools/autotest"
fi

# gz on PATH
if command -v gz >/dev/null 2>&1; then
    ok "gz on PATH ($(command -v gz))"
else
    fail "gz not on PATH — install Gazebo for $EXPECTED_GZ_VERSION"
fi

# Installed gz-sim major version vs GZ_VERSION
case "$EXPECTED_GZ_VERSION" in
    garden)   EXPECTED_MAJOR=7 ;;
    harmonic) EXPECTED_MAJOR=8 ;;
    ionic)    EXPECTED_MAJOR=9 ;;
    jetty)    EXPECTED_MAJOR= ;;
    *)        warn "Unknown GZ_VERSION=$EXPECTED_GZ_VERSION"; EXPECTED_MAJOR= ;;
esac

if [ -n "$EXPECTED_MAJOR" ] && command -v brew >/dev/null 2>&1; then
    if brew list "gz-sim$EXPECTED_MAJOR" >/dev/null 2>&1; then
        ok "gz-sim$EXPECTED_MAJOR installed (matches GZ_VERSION=$EXPECTED_GZ_VERSION)"
    else
        warn "gz-sim$EXPECTED_MAJOR not installed via Homebrew (may be installed elsewhere)"
    fi
fi

# Optional: GZ_VERSION env var set in current shell (only relevant for build)
if [ -z "${GZ_VERSION:-}" ]; then
    warn "GZ_VERSION not set in environment — required for cmake build"
fi

# adb (optional, for Android handset path)
if command -v adb >/dev/null 2>&1; then
    DEV_COUNT=$(adb devices 2>/dev/null | grep -c "device$" || true)
    if [ "$DEV_COUNT" -gt 0 ]; then
        ok "adb sees $DEV_COUNT device(s)"
    else
        warn "adb installed but no device connected (fine if not using handset path)"
    fi
else
    warn "adb not on PATH (fine if not using Android handset path)"
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "All required checks passed."
    exit 0
else
    echo "$ERRORS check(s) failed."
    exit 1
fi
