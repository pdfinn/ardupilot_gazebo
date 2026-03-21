# NERVA2 UAS Demo

Demonstrates NERVA2 AI-controlled UAS operations using ArduPilot SITL + Gazebo (local) with TAK Server + NERVA2 (remote edge device: hephaestus).

## Architecture

```
┌─────────────── Laptop (macOS) ────────────────┐
│                                                │
│  Terminal 1: demo/run_demo_gazebo.sh           │
│  Terminal 2: demo/start_demo_sitl.sh           │
│  Android Studio: screen mirror of handset      │
│                                                │
│  ArduPilot SITL ◄──JSON──► Gazebo              │
│       │                       │                │
│       │ MAVLink               │ H.264 video    │
│       │ UDP :14550            │ UDP :5600       │
│       ▼                       ▼                │
│  ┌─────────────────────────────────────────┐   │
│  │     Android (USB-connected)             │   │
│  │     ATAK + UAS Tool plugin              │   │
│  │       ├─ MAVLink telemetry + commands   │   │
│  │       ├─ Video feed from gimbal camera  │   │
│  │       └─ CoT ◄──► TAK Server (mTLS)    │   │
│  └─────────────────────────────────────────┘   │
└────────────────────────────────────────────────┘
                        │
                   mTLS :8089
                        │
┌──── hephaestus (Jetson Orin AGX) ─────────────┐
│                                                │
│  TAK Server (:8089, :8443)                     │
│       │                                        │
│  TAK Connector (:7089) ◄── CoT stream          │
│       │                                        │
│  nerva2 (:7080) ── AI agent                    │
│    ├─ takmcp (stdio) ── situational awareness  │
│    ├─ uasmcp (stdio) ── UAS control via CoT    │
│    ├─ osmmcp (stdio) ── geospatial             │
│    ├─ terramcp (stdio) ── terrain              │
│    └─ examcp (stdio) ── web search             │
│                                                │
└────────────────────────────────────────────────┘
```

## Demo Flow

1. Operator opens ATAK on Android, connected to TAK Server on hephaestus
2. ArduPilot SITL + Gazebo running on laptop, streaming MAVLink to Android via USB
3. ATAK UAS Tool receives telemetry, publishes CoT to TAK Server
4. Operator sends chat to NERVA: "any UAS available?"
5. NERVA queries uasmcp, sees UAS telemetry via TAK Connector
6. NERVA responds: "I see UAS1 at [position], armed, battery 95%"
7. Operator: "connect to it and fly this mission"
8. NERVA sends commands via uasmcp -> TAK Connector -> TAK Server -> ATAK UAS Tool -> MAVLink -> SITL

## Prerequisites

- Working ArduPilot SITL + Gazebo setup (see parent directory WORKING_CONFIG.md)
- ATAK with UAS Tool plugin on Android handset
- Android connected via USB with adb working
- SSH access to hephaestus (`ssh hephaestus`)
- TAK Server + NERVA2 running on hephaestus
- Android Studio device mirror running

## Quick Start

```bash
# 1. Run preflight check
demo/preflight_check.sh

# 2. Terminal 1: Start Gazebo with camera streaming to Android
demo/run_demo_gazebo.sh

# 3. Terminal 2: Start SITL with demo config (forwards MAVLink to Android)
demo/start_demo_sitl.sh

# 4. Open Android Studio device mirror
# 5. Open ATAK on Android - verify UAS telemetry + video visible
# 6. Chat with NERVA via ATAK
```

## Network Configuration

| Service | Host | Port | Protocol |
|---------|------|------|----------|
| Gazebo Server | localhost | 9002 | JSON |
| MAVLink (to Android) | Android USB IP | 14550 | UDP |
| Video Stream | Android USB IP | 5600 | UDP/RTP |
| TAK Server | hephaestus | 8089 | TCP/mTLS |
| TAK Web Admin | hephaestus | 8443 | TCP/mTLS |
| NERVA2 | hephaestus (ZeroTier) | 7080 | HTTP |

## Differences from Local Setup

The existing scripts in the parent directory run everything locally (SITL + Gazebo + GCS all on laptop). This demo configuration:

- Uses a **demo-specific** Gazebo launcher (`run_demo_gazebo.sh`) that exports
  `GZ_CAMERA_UDP_HOST`/`GZ_CAMERA_UDP_PORT` env vars for the native GstCameraPlugin,
  then delegates to the parent `run_gazebo.sh`
- Uses a **demo-specific** SITL launcher that preserves the original Android USB detection logic
- Video streaming is handled natively by Gazebo's GstCameraPlugin (H.264/RTP, no Python bridge)
- Connects to remote TAK Server on hephaestus for the NERVA2 AI loop

The parent directory scripts are NOT modified.
