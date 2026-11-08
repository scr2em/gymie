#!/usr/bin/env bash
# One-time setup of Gymie's local pose engine (MediaPipe + FastAPI from PoseServer/).
# Creates a Python virtualenv in ~/Library/Application Support/Gymie/pose-venv.
# Usage: setup-pose-server.sh [path-to-PoseServer]   (Gymie.app passes its bundled copy)
set -euo pipefail

SERVER_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/PoseServer}"
VENV="$HOME/Library/Application Support/Gymie/pose-venv"

PY=""
for candidate in python3.12 python3.11 python3.10 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /usr/local/bin/python3.12; do
  if command -v "$candidate" >/dev/null 2>&1; then PY="$(command -v "$candidate")"; break; fi
done
if [ -z "$PY" ]; then
  echo "Need Python 3.10-3.12 (MediaPipe has no wheels for newer versions). Try: brew install python@3.12" >&2
  exit 1
fi

echo "Using $PY"
mkdir -p "$(dirname "$VENV")"
"$PY" -m venv "$VENV"
"$VENV/bin/python" -m pip install --upgrade pip --quiet
"$VENV/bin/python" -m pip install -r "$SERVER_DIR/requirements.txt"
"$VENV/bin/python" -c "import mediapipe, fastapi, uvicorn, cv2; print('Pose engine ready:', mediapipe.__version__)"
