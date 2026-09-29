#!/usr/bin/env bash
# Builds and deploys the co-op server to Fly.io. Needs flyctl, logged in.
# First time only: fly apps create deep-time-coop
set -euo pipefail
cd "$(dirname "$0")/.."
./tools/build_server.sh
cd server
fly deploy --remote-only
