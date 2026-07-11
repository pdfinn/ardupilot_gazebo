#!/bin/bash
# Run Gazebo for local-dev: silences gz-transport multicast spam by binding
# discovery to loopback, then delegates to the root run_gazebo.sh.

set -e

REPO_DIR="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Source local-dev/.env if present (for GZ_VERSION etc.)
[ -f "$REPO_DIR/local-dev/.env" ] && set -a && . "$REPO_DIR/local-dev/.env" && set +a

# Bind gz-transport discovery to loopback. Stops the per-interface
# "Exception sending a multicast message:No route to host" log spam on hosts
# with many multicast-capable interfaces (Wi-Fi + USB tether + VPN + etc.).
# SITL talks to the plugin on 127.0.0.1:9002 anyway, so loopback is enough.
export GZ_IP=127.0.0.1

cd "$REPO_DIR"
exec ./run_gazebo.sh
