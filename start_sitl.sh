#!/bin/bash
# Start ArduPilot SITL with Gazebo
# Run this in a separate terminal AFTER starting Gazebo with ./run_gazebo.sh

set -e

ARDUPILOT_DIR="${ARDUPILOT_DIR:-$HOME/ardupilot}"

if [ ! -x "$ARDUPILOT_DIR/Tools/autotest/sim_vehicle.py" ]; then
    echo "ERROR: ArduPilot not found at $ARDUPILOT_DIR" >&2
    echo "  Set ARDUPILOT_DIR to your ardupilot checkout." >&2
    exit 1
fi

cd "$ARDUPILOT_DIR"
Tools/autotest/sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON --out 127.0.0.1:14551
