#!/usr/bin/env bash
# Exports the headless co-op server binary to server/deeptime.x86_64.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/server
touch build/.gdignore
godot4 --headless --path . --export-release "Server" build/server/deeptime.x86_64 2>&1 | grep -E "ERROR|SCRIPT" | grep -v X509 || true
cp build/server/deeptime.x86_64 server/deeptime.x86_64
echo "built: $(du -sh server/deeptime.x86_64 | cut -f1)"
