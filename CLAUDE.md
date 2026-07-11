# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Gazebo plugin set that connects [ArduPilot SITL](https://ardupilot.org/dev/) to Gazebo (Garden / Harmonic / Ionic / Jetty) over a JSON UDP protocol on port 9002. The repo also ships example models, worlds, and launcher scripts.

The fork additionally contains NERVA2 demo scripting (`demo/`) that wires the SITL+Gazebo stack to an Android ATAK handset and a remote TAK Server / NERVA2 stack on `hephaestus`.

## Build

`GZ_VERSION` selects which Gazebo line `CMakeLists.txt` resolves against — `harmonic` (default), `garden`, `ionic`, or `jetty`. Set it before invoking cmake or the wrong `gz-sim<N>` will be linked.

```bash
export GZ_VERSION=ionic   # this checkout's verified target on macOS arm64
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j4
```

On macOS the build also needs:

```bash
export CMAKE_PREFIX_PATH="/opt/homebrew/opt/qt@5:/opt/homebrew"
```

`CMakeLists.txt` adds explicit links to a number of `libabsl_*.dylib` from the Homebrew prefix when `APPLE` is true (protobuf 22+ requires them). If you're touching link flags on macOS, check `CMakeLists.txt:117-136`.

There is no `make test` — `tests/` only contains SDF worlds (`tests/worlds/`) used to manually exercise plugins. CI runs `cpplint` and `cppcheck`, not a unit test suite.

## Lint

CI mirrors what you should run locally:

```bash
cpplint ./include/*.hh ./src/*.cc          # config in CPPLINT.cfg
cppcheck --std=c++17 ./include/*.hh ./src/*.cc
```

`CPPLINT.cfg` disables several Google-style rules to match Gazebo's brace / access-specifier conventions — don't reformat against stock cpplint defaults.

## Run (the standard two-terminal pattern)

```bash
# T1 — Gazebo server (this repo)
./run_gazebo.sh                    # iris_runway.sdf, sets GZ_SIM_*_PATH from $PWD

# T2 — ArduPilot SITL (separate repo at ~/github.com/NERVsystems/ardupilot)
sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON --console --map
```

The `-f gazebo-*` frame + `--model JSON` flags are what makes SITL talk to this plugin instead of its built-in physics. `start_sitl_gazebo.sh` is the production launcher — it auto-detects an adb-connected Android device and forwards MAVLink to it on UDP 14550, falling back to localhost:14551.

`start_sitl.sh` is the trivial localhost-only variant. `reset_drone.sh` clears stuck SITL state. `demo/` scripts are NERVA2-demo-specific and delegate back to the parent launchers.

## Code architecture

Four independent shared libraries are built, each a Gazebo `System` plugin loaded from SDF via `<plugin filename="…">`:

- **ArduPilotPlugin** (`src/ArduPilotPlugin.cc`, `src/SocketUDP.cc`, `src/Util.cc`) — the core. Receives `servo_packet_16` / `servo_packet_32` over UDP from SITL, drives joints/PIDs in Gazebo, then sends fdm state (IMU, GPS, sensors) back as JSON. The plugin XML schema (control blocks, sensor mappings, IMU/GPS params) is documented in the header comment of `include/ArduPilotPlugin.hh` — read that before editing the protocol or adding a new sensor.
- **ParachutePlugin** (`src/ParachutePlugin.cc`) — detach/release joint behaviour for chute deploy.
- **CameraZoomPlugin** (`src/CameraZoomPlugin.cc`) — runtime FOV manipulation on a `gz-rendering` camera.
- **GstCameraPlugin** (`src/GstCameraPlugin.cc`) — captures a Gazebo camera sensor and pushes H.264/RTP via GStreamer (default `udp_host=127.0.0.1`, `udp_port=5600`). Honours `GZ_CAMERA_UDP_HOST`/`GZ_CAMERA_UDP_PORT` env overrides — that's how `demo/run_demo_gazebo.sh` redirects the stream to an Android device without editing SDF.

Models in `models/` (notably `iris_with_ardupilot`, `iris_with_gimbal`, `zephyr_with_ardupilot`, `gimbal_small_*d`, `parachute_small`) reference these plugins by `filename=` and are picked up via `GZ_SIM_RESOURCE_PATH`. Worlds in `worlds/` compose them.

## macOS-specific gotchas (this checkout)

These are project-specific landmines, not generic dev advice — read `WORKING_CONFIG.md` before touching the build environment:

- **Anaconda libs poison cmake.** If `/opt/anaconda3/lib/libQt5*.dylib`, `libabsl*.dylib`, `libfmt*.dylib`, or `cmake/` are present, cmake mixes them with Homebrew at link time and produces broken `.dylib`s. Move them to `/opt/anaconda3/lib/backup_for_gazebo/` before any rebuild of this plugin or any `gz-*` Homebrew formula. Running existing binaries is fine (deps are baked in); only **rebuilds** require the move. Restore the backup afterwards for normal Python/Jupyter work.
- **eigen@3 must be linked, not eigen 5.** `brew link eigen@3 --force`.
- **Don't `brew install` / `brew upgrade` casually.** `gz-sim9` / `gz-physics8` / `gz-rendering9` are pinned at known-good versions in the user's Homebrew. An incidental `brew upgrade` rebuilt the whole gz-* graph against a new fmt/eigen and broke the stack — keep `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_INSTALL_UPGRADE=1` in scope when running brew commands.
- **The user cannot run `sudo` or `brew install`** (per global instructions). If a fix needs them, ask the user to run it in a `! command` line.
- **Don't build ArduPilot with `--debug`.** Release SITL is the only configuration verified to initialise correctly against this plugin on arm64.
- **Stale SITL state file corruption** (`mav.parm`, `eeprom.bin`, `*.stg` in the ArduPilot tree) presents as "EKF won't converge / drone in 5th dimension". Delete and relaunch with `start_sitl_gazebo.sh -w`.

`verify_setup.sh` checks the most common breakages (commits, Anaconda contamination, eigen link, GZ_VERSION) and is the fastest way to triage a "why won't it build/run" report.

## Protocol cheat-sheet

| Endpoint | Purpose | Default |
| --- | --- | --- |
| UDP 9002 | SITL ↔ ArduPilotPlugin (servo packets in, fdm JSON out) | bound by plugin |
| UDP 14550 / 14551 | MAVLink to GCS / ATAK / MAVProxy fanout | set by sim_vehicle.py |
| UDP 5600 | GstCameraPlugin H.264/RTP video | overridable via env |
| TCP 5760/5762/5763 | SITL MAVLink TCP (cleaned up by `start_sitl_gazebo.sh`) | sim_vehicle.py default |
