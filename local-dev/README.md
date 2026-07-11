# local-dev — standalone simulator stack for GCS plugin work

This folder packages the SITL + Gazebo + video stack so a collaborator can run
the simulator on their own laptop and develop the GCS plugin (`nerv-uas-kotlin`)
against their own TAK Server. **No NERVA, no hephaestus, no shared certs.**

## What this stack is

```
┌─────────────────────── your laptop (macOS) ────────────────────────┐
│                                                                    │
│  T1: ./run_local_gazebo.sh   →  Gazebo with iris + gimbal + camera │
│  T2: ./start_local_sitl.sh   →  ArduPilot SITL ↔ Gazebo (UDP 9002) │
│                                                                    │
│  ┌───────────────── USB tether ──────────────────┐                 │
│  │ Android handset (192.168.55.x)                │                 │
│  │   ATAK + nerv-uas-kotlin plugin               │                 │
│  │     ← MAVLink (UDP 14550)                     │                 │
│  │     ← H.264 RTP video (UDP 5600)              │                 │
│  │     ↔ TAK Server (your own, mTLS)             │                 │
│  └───────────────────────────────────────────────┘                 │
└────────────────────────────────────────────────────────────────────┘
```

The GCS plugin owns publishing UAS position to the TAK map (1 Hz CoT, in
`MAVLinkCotBroadcaster.kt`). Your TAK Server fans it out to any other ATAK
clients you connect. **You don't need anything from the NERVA stack** for that
loop to work end-to-end.

What you can't test standalone: the GCS plugin's command-receive path
(`b-t-f-c-u` `<uasCommand>` CoT events from `uasmcp`). Ask the upstream team
for sample CoT XMLs when you get to that work.

## Prerequisites (macOS)

```bash
brew install rapidjson opencv gstreamer
brew install gz-ionic       # or gz-harmonic; see "Pick a Gazebo line" below
```

You also need:

- **ArduPilot SITL** built locally (see "Build SITL" below).
- **Xcode Command Line Tools** (`xcode-select --install`).
- **adb** (`brew install android-platform-tools`) if you'll forward MAVLink/video
  to a USB-tethered handset. Optional otherwise.
- **Your own TAK Server** running and reachable from the handset. Cert SAN must
  include the address ATAK dials. Not covered here — bring your own.

### Pick a Gazebo line

`GZ_VERSION` selects which gz-sim line the plugin builds against. It must match
what's installed:

| `GZ_VERSION` | gz-sim major | Homebrew formula |
|---|---|---|
| `garden`   | 7 | `gz-garden`   |
| `harmonic` | 8 | `gz-harmonic` |
| `ionic`    | 9 | `gz-ionic`    |
| `jetty`    | * | `gz-jetty`    |

`ionic` is the verified target on macOS-arm64 in this checkout. Pick `ionic`
unless you have a reason to deviate.

## Build the plugin

```bash
git clone https://github.com/pdfinn/ardupilot_gazebo
cd ardupilot_gazebo
export GZ_VERSION=ionic
export CMAKE_PREFIX_PATH="$(brew --prefix qt@5):$(brew --prefix)"
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j4
```

Output: `build/libArduPilotPlugin.dylib`, plus `libParachutePlugin.dylib`,
`libCameraZoomPlugin.dylib`, `libGstCameraPlugin.dylib`.

## Build SITL

```bash
git clone https://github.com/ArduPilot/ardupilot $HOME/ardupilot
cd $HOME/ardupilot
git submodule update --init --recursive
./waf configure --board sitl       # release build — do NOT pass --debug
./waf copter
```

Builds `$HOME/ardupilot/build/sitl/bin/arducopter`.

## Configure local-dev

```bash
cd ardupilot_gazebo/local-dev
cp .env.example .env
# Edit .env if your ardupilot path or GZ version differs from defaults.
```

Variables (see `.env.example` for full descriptions):

- `ARDUPILOT_DIR` — where you cloned ArduPilot. Default `$HOME/ardupilot`.
- `GZ_VERSION` — must match installed gz-sim. Default `ionic`.
- `ANDROID_IP` — `auto` (adb-detect handset), `127.0.0.1` (loopback), or an IP.

## Run

```bash
cd local-dev
./preflight_local.sh        # one-time sanity check before each session
```

Then two terminals:

```bash
# T1 — Gazebo server
./run_local_gazebo.sh

# T2 — ArduPilot SITL  (in a separate terminal, after T1 is steady)
./start_local_sitl.sh
```

In ATAK on the handset, point the plugin's MAVLink endpoint at UDP 14550 (or
whatever `start_local_sitl.sh` printed). Telemetry CoT will then start
appearing on your TAK Server's map.

### Common variants

```bash
./start_local_sitl.sh -w                    # wipe params, fresh EEPROM
./start_local_sitl.sh --android-ip 1.2.3.4  # explicit handset IP
ANDROID_IP=127.0.0.1 ./start_local_sitl.sh  # loopback only (no handset)
./start_local_sitl.sh --no-map --no-console # quieter
```

### Optional GUI

`run_local_gazebo.sh` launches `gz sim -s` (server only — no GUI window). If
you want to *see* the drone, run a GUI client in a third terminal:

```bash
gz sim -g
```

## Troubleshooting

### "Exception sending a multicast message: No route to host" (lots of them)

Already silenced by `run_local_gazebo.sh` setting `GZ_IP=127.0.0.1`. If you see
this anyway, you launched `gz sim` directly without going through the wrapper.

### Drone won't appear / EKF errors / "5th dimension"

Stale SITL state. Wipe it:

```bash
rm -f $ARDUPILOT_DIR/{mav.parm,eeprom.bin,*.stg}
./start_local_sitl.sh -w
```

### Plugin won't load / abseil link errors on rebuild

macOS-only: if you have Anaconda installed, its Qt5/abseil/fmt dylibs in
`/opt/anaconda3/lib/` can poison cmake's library resolution at *build* time.
Running already-built binaries is fine. If a rebuild fails with mysterious
abseil or Qt errors, see `../WORKING_CONFIG.md` ("ANACONDA LIBRARY MANAGEMENT")
for the move-aside-then-restore procedure. Skip if you don't have Anaconda.

### `gz sim: command not found`

Gazebo not installed or not on PATH. Reinstall the Homebrew formula matching
`GZ_VERSION` and ensure `$(brew --prefix)/bin` is in `PATH`.

### Plugin not found at runtime ("Loaded system [...]" missing)

`run_local_gazebo.sh` sets `GZ_SIM_SYSTEM_PLUGIN_PATH` from `$PWD/build`. Make
sure the plugin built (check `build/libArduPilotPlugin.dylib`) and that you're
running the wrapper, not bare `gz sim`.

### `arducopter` not found

Either `ARDUPILOT_DIR` is wrong, or you haven't run `./waf copter` yet. The
preflight will tell you which.

### Video not reaching ATAK

`GstCameraPlugin` streams to UDP 5600 on `127.0.0.1` by default. If your ATAK
plugin reads video from a different address, override at runtime:

```bash
GZ_CAMERA_UDP_HOST=192.168.55.2 GZ_CAMERA_UDP_PORT=5600 ./run_local_gazebo.sh
```

Quick check from another terminal:

```bash
gst-launch-1.0 -v udpsrc port=5600 caps='application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264' \
  ! rtph264depay ! avdec_h264 ! videoconvert ! autovideosink sync=false
```

## Notes for upstream maintainer (not the collaborator)

- `local-dev/` was added 2026-05 to give an outside collaborator a clean
  setup for nerv-uas-kotlin GCS plugin work without exposing NERVA/hephaestus.
- Sibling `demo/` directory remains the canonical NERVA2 + hephaestus demo
  flow; do not converge them.
- If/when the collaborator needs to test the command-receive path, capture
  3-5 representative `<uasCommand>` CoT events from `uasmcp` in flight and
  drop them in `local-dev/sample_cot/`.
