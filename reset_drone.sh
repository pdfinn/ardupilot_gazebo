#!/bin/bash
# Reset drone to safe starting position above ground

export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib"

echo "Resetting drone to starting position..."

gz service -s /world/iris_runway/set_pose \
  --reqtype gz.msgs.Pose \
  --reptype gz.msgs.Boolean \
  --timeout 2000 \
  --req "name: 'iris_with_gimbal', position: {x: 0, y: 0, z: 0.5}, orientation: {x: 0, y: 0, z: 0.7071068, w: 0.7071068}"

echo "✓ Drone reset to 0.5m above ground, facing east"
echo "You can now arm and takeoff again"
