# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Gazebo plugin for ArduPilot SITL (Software In The Loop) simulation. It enables ArduPilot vehicle firmware to interact with Gazebo physics simulator, providing realistic 3D vehicle simulation with sensor data exchange via JSON protocol.

**Supported Gazebo Versions**: Garden, Harmonic (LTS), Ionic, Jetty (LTS)
**Communication Protocol**: JSON over UDP (default port 9002)
**Vehicle Types**: Copter, Plane, Rover (models in separate SITL_Models repo)

## Build System

### Prerequisites
Must set `GZ_VERSION` environment variable before building:
```bash
export GZ_VERSION=harmonic  # or garden, ionic, jetty
```

### Build Commands
```bash
# Clean build
rm -rf build && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j4

# Return to project root
cd ..
```

### Platform-Specific Notes

**macOS arm64**:
- Requires abseil library linking for protobuf 22+ compatibility (already configured in CMakeLists.txt:115-135)
- Known issue: ArduCopter crashes after 15-45 minutes due to floating-point exception handling (see MACOS_STATUS.md)
- Both `iris_runway.sdf` and `iris_warehouse.sdf` worlds run stably

**Ubuntu**:
- Install dependencies: `libgz-sim8-dev rapidjson-dev libopencv-dev libgstreamer1.0-dev`

### Environment Setup
After building, set these variables (or use the launch scripts):
```bash
export GZ_SIM_SYSTEM_PLUGIN_PATH=$PWD/build:$GZ_SIM_SYSTEM_PLUGIN_PATH
export GZ_SIM_RESOURCE_PATH=$PWD/models:$PWD/worlds:$GZ_SIM_RESOURCE_PATH
```

## Running Simulations

### Using Launch Scripts (Recommended for macOS)
```bash
# Terminal 1: Start Gazebo
./run_gazebo.sh

# Terminal 2: Start ArduPilot SITL (wait 10 seconds after Gazebo starts)
./start_sitl_gazebo.sh

# Optional Terminal 3: GUI
./start_gui.sh
```

**Script Features**:
- Automatic cleanup of stale processes on start and exit
- Port conflict prevention
- Android device auto-detection for MAVLink output
- Self-contained (each manages its own processes)

### Manual Launch
```bash
# Terminal 1: Gazebo
gz sim -v4 -r iris_runway.sdf

# Terminal 2: ArduPilot SITL
cd /path/to/ardupilot
sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON --map --console
```

### Common Worlds
- `iris_runway.sdf` - Iris quadcopter on runway with gimbal (includes camera)
- `iris_warehouse.sdf` - Indoor warehouse environment (includes camera)
- `zephyr_runway.sdf` - Fixed-wing aircraft with speedup support
- `gimbal.sdf` - 3DOF gimbal with camera streaming demo

## Code Architecture

### Core Plugin: ArduPilotPlugin (src/ArduPilotPlugin.cc)

**Data Flow**:
1. Gazebo sensors → JSON encoding → UDP socket → ArduPilot SITL
2. ArduPilot SITL → JSON motor commands → UDP socket → Gazebo actuators

**Key Components**:
- `SocketUDP` class handles bidirectional JSON communication on port 9002
- Control objects manage individual motors/servos with PID controllers
- Sensor data collection from IMU, GPS, rangefinder, camera
- Frame counter synchronization with SITL (handles uint32 wraparound)

**JSON Message Format**:
- Outbound (to SITL): timestamp, IMU data, GPS, pose, velocity, rangefinder, camera
- Inbound (from SITL): frame_count, pwm values per motor channel

### Additional Plugins
- `ParachutePlugin.cc` - Parachute deployment physics
- `CameraZoomPlugin.cc` - Dynamic camera zoom control
- `GstCameraPlugin.cc` - GStreamer video streaming (H.264 over UDP)

### Models Structure
Models in `models/` directory follow SDF format with `<plugin>` elements:
- `iris_with_ardupilot/` - Quadcopter with IMU and ArduPilotPlugin config
- `iris_with_gimbal/` - Includes 3DOF gimbal with camera
- `zephyr_with_ardupilot/` - Fixed-wing aircraft

## Development Workflow

### Testing SITL Communication
1. Check Gazebo loads plugin: Look for `[Msg] Loaded system [ArduPilotPlugin]`
2. Verify JSON socket: Port 9002 should be listening
3. Check SITL connection: Look for `JSON received` in verbose output (`-v4`)
4. Monitor sensor data flow: IMU updates should appear in SITL console

### Debugging Tips
- Use `-v4` flag with `gz sim` for verbose logging
- Enable DEBUG_JSON_IO in ArduPilotPlugin.cc:65 to see raw JSON packets
- Check frame counter sync: Plugin resets counter on SITL restart
- Monitor cleanup: Scripts use traps to kill processes on exit

### Common Issues
- **Plugin not loading**: Check `GZ_SIM_SYSTEM_PLUGIN_PATH` includes `build/` directory
- **No sensor data**: Verify IMU sensor in model SDF has correct topic name
- **Port conflicts**: Scripts clean up ports 9002, 5760, 5762, 5763 on start
- **GUI not updating**: Click "Follow" on vehicle in Entity Tree (cosmetic only)

### Code Style
- C++14 standard
- Cpplint configured in CPPLINT.cfg
- GitHub Actions run: ubuntu-build, ccplint, cppcheck

## MAVLink Integration

**Default Ports**:
- 14550: GCS connection (bidirectional UDP)
- 14551: Localhost fallback
- 5760-5763: MAVProxy internal ports

**Android Device Detection**:
The `start_sitl_gazebo.sh` script auto-detects Android devices via ADB and configures MAVLink output to their WiFi IP address.

**MAVProxy Configuration**:
Scripts create `~/.mavinit.scr` with:
- `set fwdpos True` - Forward position data
- `set shownoise False` - Reduce console spam

## Key Files to Understand

- `src/ArduPilotPlugin.cc` - Main plugin implementation, sensor/actuator interface
- `src/SocketUDP.cc` - UDP communication layer
- `CMakeLists.txt` - Build configuration, platform-specific linking
- `models/iris_with_ardupilot/model.sdf` - Reference vehicle configuration
- `config/gazebo-iris-gimbal.parm` - ArduPilot parameters for gimbal control

## Branch Status

Current branch: `fix/macos-arm64-abseil-linking`

This branch contains:
- macOS arm64 linking fixes (abseil integration)
- Enhanced launch scripts with cleanup handlers
- Warehouse world integration
- Documentation updates (MACOS_STATUS.md, VALIDATION_GUIDE.md)

Modified files:
- `src/ArduPilotPlugin.cc` - Enhanced logging, counter reset handling
- Several new launch scripts (`.sh` files in root)

Intended for PR to main branch.
