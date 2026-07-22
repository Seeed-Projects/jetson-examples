#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

pkill -f "build/yolo26_tensorrt" || true
rm -rf build yolo26n.engine yolo26n.engine.meta yolo26_tensorrt.log

echo "[ok] yolo26-tensorrt build artifacts cleaned."
