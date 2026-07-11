# Building Gazebo Harmonic from Source on macOS arm64

## Why Build from Source?

Based on feedback from @srmainwaring (PR #150), the abseil linking issue appears to be specific to the Homebrew binary distribution (bottles). Building from source should resolve this because:

1. **Version consistency**: All libraries compile together with the same protobuf version
2. **No bottle mismatches**: Homebrew bottles can get out of sync with current protobuf versions
3. **Proven to work**: @srmainwaring reports no issues building from source on arm64 Mac

## Known Gotchas to Avoid

### 1. Protobuf Version Mismatches
- **Issue**: Homebrew doesn't pin specific protobuf versions in formulas
- **Result**: Pre-built bottles may be incompatible with current `brew install protobuf`
- **Solution**: Building from source eliminates this entirely

### 2. Apple Silicon CMake Flags
- **Critical**: Must use special CMake args for ARM64 builds
- **Flags required**: `-DCMAKE_MACOSX_RPATH=FALSE -DCMAKE_INSTALL_NAME_DIR=$(pwd)/install/lib`
- **Symptom if omitted**: Path conflicts and runtime loading issues

### 3. Abseil ARM64 Compatibility
- **Issue**: Abseil can fail with `-msse4.1` errors (Intel-specific flag)
- **Affects**: Protobuf 5.27.0+ which depends on abseil/20240116.2
- **Note**: Homebrew's protobuf handles this, but watch for build errors

### 4. Qt5 Path Configuration
- **Required**: Must unlink qt and set CMAKE_PREFIX_PATH to qt@5
- **Why**: Gazebo needs qt@5 specifically, not latest qt

### 5. Build Time and Resources
- **Duration**: Expect 30-60+ minutes for full build on M1/M2
- **Memory**: Can hit OOM on low-RAM systems (8GB may struggle)
- **Recommendation**: Use `--merge-install` to reduce disk usage

## System Requirements

- **macOS**: Big Sur (11), Monterey (12), Ventura (13), or later
- **Xcode**: Command Line Tools (minimum Xcode 10 equivalent)
- **Disk space**: ~5-10GB for source + build artifacts
- **RAM**: 16GB recommended (8GB may work with fewer parallel jobs)

## Step-by-Step Build Process

### 1. Install Prerequisites

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Set up Homebrew simulation tap
brew tap osrf/simulation
brew update

# Install Python 3 and build tools
brew install python3
python3 -m pip install -U colcon-common-extensions vcstool
```

### 2. Install Dependencies

```bash
# XQuartz (required for Ogre rendering)
brew install --cask xquartz

# Core dependencies (this will take a while!)
brew install assimp boost bullet cmake cppzmq dartsim doxygen eigen \
  fcl ffmpeg flann freeimage freetype gdal gflags google-benchmark \
  gts ipopt jsoncpp libccd libyaml libzzip libzip nlopt ode \
  open-scene-graph ossp-uuid ogre1.9 ogre2.3 pkg-config protobuf \
  qt@5 qwt-qt5 rapidjson ruby tbb tinyxml tinyxml2 urdfdom zeromq

# Configure Qt5 path (CRITICAL)
export CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH:+$CMAKE_PREFIX_PATH:}`brew --prefix qt@5`
brew unlink qt  # Prevent qt6 conflicts
```

**Note**: Add the Qt5 export to your `~/.zshrc` for persistence:
```bash
echo 'export CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH:+$CMAKE_PREFIX_PATH:}'"`brew --prefix qt@5`" >> ~/.zshrc
```

### 3. Download Gazebo Source

```bash
# Create workspace
mkdir -p ~/workspace/src
cd ~/workspace/src

# Download Gazebo Harmonic collection
curl -OL https://raw.githubusercontent.com/gazebo-tooling/gazebodistro/master/collection-harmonic.yaml

# Clone all repositories
vcs import < collection-harmonic.yaml
```

This downloads all Gazebo libraries: gz-cmake, gz-common, gz-fuel-tools, gz-gui, gz-launch, gz-math, gz-msgs, gz-physics, gz-plugin, gz-rendering, gz-sensors, gz-sim, gz-tools, gz-transport, gz-utils, and sdformat.

### 4. Build Gazebo (Apple Silicon)

```bash
cd ~/workspace

# CRITICAL: Use ARM64-specific flags
colcon build \
  --cmake-args \
    -DCMAKE_MACOSX_RPATH=FALSE \
    -DCMAKE_INSTALL_NAME_DIR=$(pwd)/install/lib \
    -DBUILD_TESTING=OFF \
  --merge-install \
  --parallel-workers 4
```

**Build options explained**:
- `--cmake-args -DCMAKE_MACOSX_RPATH=FALSE`: Prevents RPATH issues on macOS
- `-DCMAKE_INSTALL_NAME_DIR=$(pwd)/install/lib`: Sets absolute install paths
- `-DBUILD_TESTING=OFF`: Skips test compilation (saves ~30% build time)
- `--merge-install`: Consolidates all packages into single install directory
- `--parallel-workers 4`: Limits parallel jobs (adjust based on CPU cores/RAM)

**Performance tuning**:
- More cores/RAM: Increase `--parallel-workers` (e.g., 8 on M1 Pro/Max)
- Less RAM: Decrease to `--parallel-workers 2`
- Full build with tests: Remove `-DBUILD_TESTING=OFF`

**Expected build time**: 30-60 minutes on M1/M2 with 4 parallel workers

### 5. Environment Setup

```bash
# Source the workspace (zsh - default macOS shell)
source ~/workspace/install/setup.zsh

# Or for bash users
# source ~/workspace/install/setup.bash
```

**Make it permanent**: Add to `~/.zshrc`:
```bash
echo 'source ~/workspace/install/setup.zsh' >> ~/.zshrc
```

### 6. Verify Installation

```bash
# Check Gazebo version
gz sim --version

# Test with shapes demo
gz sim shapes.sdf -v4
```

**Expected output**:
```
Gazebo Sim, version 8.x.x
...
[Msg] Loaded system [Physics]
[Msg] Loaded system [UserCommands]
...
```

## Integration with ArduPilot Plugin

### 1. Update Environment Variables

The from-source build changes where Gazebo looks for plugins. Update your launch scripts:

```bash
# Use the from-source install path
export GZ_SIM_SYSTEM_PLUGIN_PATH=$HOME/workspace/install/lib/gz-sim-8/plugins:$PWD/build
export GZ_SIM_RESOURCE_PATH=$HOME/workspace/install/share:$PWD/models:$PWD/worlds

# Launch Gazebo
gz sim -v4 -r iris_runway.sdf
```

### 2. Rebuild ArduPilot Plugin

Your plugin needs to link against the from-source Gazebo:

```bash
cd /Users/pdfinn/github.com/NERVsystems/ardupilot_gazebo

# Clean rebuild
rm -rf build
mkdir build && cd build

# Configure - CMake should find from-source install
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo

# Build
make -j4

cd ..
```

### 3. Test for Abseil Issue

After rebuilding the plugin against from-source Gazebo:

```bash
# Terminal 1: Launch Gazebo
./run_gazebo.sh

# Terminal 2: Launch SITL (wait 10 seconds)
./start_sitl_gazebo.sh
```

**What to check**:
1. Plugin loads without abseil/protobuf errors
2. Gazebo runs without crashes
3. SITL connects and receives sensor data
4. No floating-point exceptions (or at least consistent with --debug mode)

## Troubleshooting

### Build Failures

**"No such file or directory: qt5"**
```bash
# Ensure qt@5 is in CMAKE_PREFIX_PATH
export CMAKE_PREFIX_PATH=`brew --prefix qt@5`:$CMAKE_PREFIX_PATH
```

**"unsupported option '-msse4.1' for target 'arm64'"**
- This is the abseil ARM64 issue
- Ensure you have latest Homebrew protobuf: `brew upgrade protobuf`
- Try cleaning and rebuilding: `rm -rf build install log`

**Out of memory during build**
```bash
# Reduce parallel workers
colcon build --parallel-workers 2 ... (rest of args)
```

### Runtime Issues

**"Library not loaded: @rpath/libgz-..."**
- Missing the `-DCMAKE_MACOSX_RPATH=FALSE` flag
- Rebuild with correct CMake args

**Plugin not found**
```bash
# Verify plugin path includes from-source location
echo $GZ_SIM_SYSTEM_PLUGIN_PATH

# Should include: /Users/[you]/workspace/install/lib/gz-sim-8/plugins
```

**Qt platform plugin error**
```bash
# Ensure XQuartz is installed and running
open -a XQuartz
```

## Next Steps After Successful Build

1. **Test stability**: Run the warehouse world for 45+ minutes to check for crashes
2. **Compare with Homebrew**: Document any behavior differences
3. **Update PR**: If abseil issue disappears, this confirms it's a Homebrew bottle issue
4. **Upstream reporting**: Consider filing issue with osrf/simulation tap if confirmed

## Additional Resources

- [Official Gazebo Harmonic Source Install Guide](https://gazebosim.org/docs/harmonic/install_osx_src/)
- [Gazebo GitHub Discussions](https://github.com/gazebosim/gz-sim/discussions)
- [@srmainwaring's Metal rendering fixes](https://github.com/srmainwaring/gz-rendering/tree/gz-rendering10-metal)
- [@srmainwaring's GUI fixes](https://github.com/srmainwaring/gz-gui/tree/gz-gui10-metal)

## Metal Rendering Improvements (Optional)

@srmainwaring mentioned patches for macOS Metal rendering issues (z-order, etc.):
- [gz-rendering10-metal branch](https://github.com/srmainwaring/gz-rendering/tree/gz-rendering10-metal)
- [gz-gui10-metal branch](https://github.com/srmainwaring/gz-gui/tree/gz-gui10-metal)

These fix runway world z-order issues and other Metal-specific rendering problems. Not yet upstreamed to OSRF.

To use these instead of official releases:
1. Clone the forks in `~/workspace/src/`
2. Check out the metal branches
3. Rebuild with `colcon build` as above

## Estimated Time Investment

- **Setup (steps 1-3)**: 15-30 minutes
- **Build (step 4)**: 30-60 minutes
- **Testing (steps 5-6)**: 10 minutes
- **Plugin rebuild**: 5 minutes
- **Total**: ~1-2 hours

Much of this is unattended compilation time - perfect for grabbing coffee!
