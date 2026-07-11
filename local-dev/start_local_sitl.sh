#!/bin/bash
#
# Start ArduPilot SITL for local-dev work — derived from start_sitl_gazebo.sh
# but with no NERVA/hephaestus assumptions. The collaborator's TAK Server is
# configured inside ATAK on the handset, not here.
#
# Sequence:
#   T1: ./run_local_gazebo.sh
#   T2: ./start_local_sitl.sh         (auto-detects handset via adb)
#       ./start_local_sitl.sh -w      (wipe params, fresh EEPROM)
#       ANDROID_IP=127.0.0.1 ./start_local_sitl.sh   (loopback only)

set -e

REPO_DIR="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Source local-dev/.env if present
[ -f "$REPO_DIR/local-dev/.env" ] && set -a && . "$REPO_DIR/local-dev/.env" && set +a

ARDUPILOT_DIR="${ARDUPILOT_DIR:-$HOME/ardupilot}"
ANDROID_IP="${ANDROID_IP:-auto}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

# Parse args
WIPE_PARAMS=""
SHOW_MAP="--map"
SHOW_CONSOLE="--console"
while [ $# -gt 0 ]; do
    case $1 in
        -w|--wipe)        WIPE_PARAMS="-w"; shift ;;
        --no-map)         SHOW_MAP=""; shift ;;
        --no-console)     SHOW_CONSOLE=""; shift ;;
        --android-ip)     ANDROID_IP="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,12p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Sanity checks
if [ ! -x "$ARDUPILOT_DIR/Tools/autotest/sim_vehicle.py" ]; then
    echo -e "${RED}ERROR: ArduPilot not found at $ARDUPILOT_DIR${NC}" >&2
    echo "  Set ARDUPILOT_DIR in local-dev/.env or your shell." >&2
    exit 1
fi

if ! pgrep -f "gz sim" >/dev/null; then
    echo -e "${RED}ERROR: Gazebo not running.${NC}" >&2
    echo "  Start it first in another terminal: ./run_local_gazebo.sh" >&2
    exit 1
fi
echo -e "${GREEN}✓ Gazebo is running${NC}"

# Resolve Android IP
RESOLVED_PORT=14550
if [ "$ANDROID_IP" = "auto" ]; then
    if command -v adb >/dev/null 2>&1; then
        DEVICES=$(adb devices 2>/dev/null | grep -v "^List" | grep "device$" | awk '{print $1}')
        DEVICE=$(echo "$DEVICES" | head -1)
        if [ -n "$DEVICE" ]; then
            DETECTED=$(adb -s "$DEVICE" shell ip addr show wlan0 2>/dev/null \
                | grep "inet " | awk '{print $2}' | cut -d/ -f1 | tr -d '\r\n ')
            if [ -n "$DETECTED" ]; then
                ANDROID_IP="$DETECTED"
                echo -e "${GREEN}✓ Detected handset: $ANDROID_IP${NC}"
            else
                echo -e "${YELLOW}Handset detected but no wlan0 IP — falling back to loopback${NC}"
                ANDROID_IP="127.0.0.1"; RESOLVED_PORT=14551
            fi
        else
            echo -e "${YELLOW}No adb device — using loopback (127.0.0.1:14551)${NC}"
            ANDROID_IP="127.0.0.1"; RESOLVED_PORT=14551
        fi
    else
        echo -e "${YELLOW}adb not installed — using loopback${NC}"
        ANDROID_IP="127.0.0.1"; RESOLVED_PORT=14551
    fi
fi

echo -e "${BLUE}Configuration:${NC}"
echo "  Vehicle:        ArduCopter"
echo "  Frame:          gazebo-iris"
echo "  Model:          JSON"
echo "  MAVLink out:    udp:${ANDROID_IP}:${RESOLVED_PORT}"
echo "  Gazebo plugin:  127.0.0.1:9002"
echo ""

# MAVProxy init — prevent telemetry loops
cat > "$HOME/.mavinit.scr" <<'EOF'
set fwdpos True
set shownoise False
EOF

cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up SITL processes...${NC}"
    pkill -9 -f "arducopter" 2>/dev/null || true
    pkill -9 -f "mavproxy"   2>/dev/null || true
    for p in 5760 5762 5763; do
        lsof -ti:$p 2>/dev/null | xargs kill -9 2>/dev/null || true
    done
    rm -f /tmp/ArduCopter.log
}

echo -e "${YELLOW}Cleaning stale SITL processes...${NC}"
cleanup
trap cleanup EXIT INT TERM

cd "$ARDUPILOT_DIR"
exec Tools/autotest/sim_vehicle.py \
    -v ArduCopter \
    -f gazebo-iris \
    --model JSON \
    $SHOW_CONSOLE $SHOW_MAP \
    --out=udp:${ANDROID_IP}:${RESOLVED_PORT} \
    --no-rebuild \
    $WIPE_PARAMS
