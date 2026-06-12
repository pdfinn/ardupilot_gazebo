#!/bin/bash

set -e

# Cleanup function - kills ALL Gazebo processes
cleanup() {
    echo ""
    echo "Cleaning up Gazebo processes..."

    # Kill by name
    pkill -9 -f "gz sim" 2>/dev/null || true

    # Kill the stale LISTENER only (belt and suspenders). NEVER the
    # whole port: arducopter is the CLIENT on 9002, and killing it from
    # a stale wrapper's exit trap assassinated live benches (2026-06-12).
    lsof -tiTCP:9002 -sTCP:LISTEN 2>/dev/null | xargs kill -9 2>/dev/null || true

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

# Cleanup on interrupt/terminate ONLY — an EXIT trap on a wrapper that
# outlived its child fired LATE and pkilled the NEXT bench's processes.
trap cleanup INT TERM

# macOS: prepend Homebrew prefix if present (supports Apple Silicon and Intel)
if [ "$(uname)" = "Darwin" ]; then
    if command -v brew >/dev/null 2>&1; then
        BREW_PREFIX="$(brew --prefix)"
    elif [ -d /opt/homebrew ]; then
        BREW_PREFIX=/opt/homebrew
    elif [ -d /usr/local/Homebrew ]; then
        BREW_PREFIX=/usr/local
    fi
    if [ -n "${BREW_PREFIX:-}" ]; then
        [ -d "$BREW_PREFIX/opt/ruby/bin" ] && export PATH="$BREW_PREFIX/opt/ruby/bin:$PATH"
        export DYLD_LIBRARY_PATH="$BREW_PREFIX/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
    fi
fi

# Force gz-transport discovery onto loopback unicast. This Mac has multiple
# virtual interfaces (feth*, bridge100 from VMs / Internet Sharing) that install
# multicast reject routes (224.0.0/4 ... !), which makes gz-transport's default
# multicast peer discovery fail with "No route to host" and prevents any gz
# process (server, GUI, video bridge) from discovering each other. All sim
# processes are on this host, so loopback is sufficient; video to the handset
# goes out via GStreamer UDP, which is unaffected by this.
export GZ_IP="${GZ_IP:-127.0.0.1}"
export GZ_RELAY="${GZ_RELAY:-127.0.0.1}"

export GZ_SIM_SYSTEM_PLUGIN_PATH="$PWD/build${GZ_SIM_SYSTEM_PLUGIN_PATH:+:$GZ_SIM_SYSTEM_PLUGIN_PATH}"
export GZ_SIM_RESOURCE_PATH="$PWD/models:$PWD/worlds${GZ_SIM_RESOURCE_PATH:+:$GZ_SIM_RESOURCE_PATH}"

echo "Starting Gazebo runway world..."
gz sim -r -s worlds/iris_runway.sdf -v 4
