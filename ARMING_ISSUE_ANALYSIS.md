# ArduPilot SITL Arming Issue - Root Cause Analysis

**Date:** November 4, 2025
**Platform:** macOS ARM64 (Apple Silicon)
**Issue:** Drone fails to arm with EKF/AHRS errors

## Symptom

```
AP: PreArm: Gyros inconsistent
AP: PreArm: EKF attitude is bad
AP: PreArm: AHRS: not using configured AHRS type
```

## Root Cause

**ArduPilot SITL crashes within seconds** of receiving JSON data from Gazebo, preventing EKF initialization.

**Crash Location:**
- Function: `HALSITL::SITL_State::_update_airspeed(float)`
- Exception: `SIGILL` (Illegal Instruction)
- Type: Floating-point operation fault
- Platform-specific: macOS ARM64 only

## Debugging Journey

### Fixed Issues (Gazebo Plugin Side)

1. ✅ **Multicast Discovery Errors**
   - **Problem:** Gazebo transport layer failing with "Exception sending a multicast message: Can't assign requested address"
   - **Root Cause:** macOS doesn't support multicast on loopback interface
   - **Fix:** Added to `run_gazebo.sh`:
     ```bash
     export GZ_RELAY=0
     export GZ_DISCOVERY_MULTICAST=0
     export GZ_PARTITION=ardupilot_sim
     ```
   - **Result:** ZERO multicast errors, IMU subscription works

2. ✅ **Paused Simulation**
   - **Problem:** `iris_warehouse.sdf` had `<start_paused>true</start_paused>`
   - **Impact:** Physics engine not running, no sensor data generated
   - **Fix:** Changed to `<start_paused>false</start_paused>`
   - **Result:** IMU data flowing correctly

3. ✅ **Gazebo ↔ ArduPilot Communication**
   - **Status:** Working perfectly
   - **Evidence:** ArduCopter log shows:
     ```
     JSON received:
         timestamp
         imu: gyro
         imu: accel_body
         position
         quaternion
         velocity
     ```

### Attempted Fix (ArduPilot Side)

❌ **`--debug` Flag Did NOT Prevent Crashes**

ArduPilot developer suggested running with `--debug` flag to disable compiler optimizations and prevent floating-point crashes.

**Test Result:**
- Added `--debug` to `start_sitl_gazebo.sh`
- Removed `--no-rebuild` to allow debug build
- Rebuilt complete ArduCopter binary with debug flags
- **SITL still crashes within seconds**

**Crash Report Evidence:**
```
File: ~/Library/Logs/DiagnosticReports/arducopter-2025-11-03-172212.ips
Exception: SIGILL (Illegal instruction: 4)
Stack trace:
  HALSITL::SITL_State::_update_airspeed(float) +56
  HALSITL::SITL_State::_fdm_input_step() +100
  AP_InertialSensor::wait_for_sample() +224
```

## Key Findings for ArduPilot Developers

1. **`--debug` flag is ineffective** - Crash occurs even with debug build
2. **Crash is specific to Gazebo JSON backend** - Triggered by JSON data processing
3. **Airspeed calculation is the crash point** - Not general floating-point math
4. **Timing:** Crashes immediately after `"JSON received"` confirmation (2-5 seconds)

## Current Status

**Gazebo Plugin:** ✅ Fully functional
- Multicast discovery: Fixed
- IMU data generation: Working
- JSON communication: Working
- All sensor data flowing correctly

**ArduPilot SITL:** ❌ Unusable on macOS ARM64 with Gazebo
- Crashes before EKF initialization
- Cannot arm drone
- Platform-specific bug

## Files Modified

1. `run_gazebo.sh` - Added multicast discovery environment variables
2. `worlds/iris_warehouse.sdf` - Changed start_paused to false
3. `start_sitl_gazebo.sh` - Added --debug flag (ineffective)
4. `src/ArduPilotPlugin.cc` - Debug logging (committed then reverted, preserved in history)

## Recommendation

This is an **ArduPilot platform bug**, not a Gazebo plugin issue. The developer should:
1. Test with Gazebo JSON backend specifically (not other SITL backends)
2. Investigate `_update_airspeed()` function for ARM64-specific floating-point operations
3. Check if JSON data format triggers specific computation paths that crash
4. Consider that homebrew-installed SITL might behave differently than from-source builds

## Test Environment

- macOS: 15.5 (24F74)
- Hardware: Apple Silicon (ARM64)
- Gazebo: Installed via homebrew osrf/simulation tap
- ArduPilot: git commit f622ede2
- Gazebo Plugin: Branch fix/macos-arm64-abseil-linking
