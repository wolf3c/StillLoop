#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.build/mlx-runtime"

echo "Creating MLX development runtime at $RUNTIME_DIR"
python3 -m venv "$RUNTIME_DIR"

echo "Installing mlx-vlm into the project-local runtime"
"$RUNTIME_DIR/bin/python3" -m pip install --upgrade pip
"$RUNTIME_DIR/bin/python3" -m pip install --upgrade mlx-vlm

"$RUNTIME_DIR/bin/python3" -c "import mlx_vlm"

if [[ "${STILLLOOP_INSTALL_RAPID_MLX:-0}" == "1" ]]; then
  echo "Installing rapid-mlx into the project-local runtime"
  "$RUNTIME_DIR/bin/python3" -m pip install --upgrade rapid-mlx
fi

echo "MLX development runtime ready: $RUNTIME_DIR/bin/python3"
