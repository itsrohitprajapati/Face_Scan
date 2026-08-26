#!/usr/bin/env bash
# Create/refresh the FastAPI backend virtualenv with all dependencies.
#
# Safe to re-run. Works on macOS/Linux with Python 3.11-3.14 using binary wheels
# only (no cmake/compiler required). Override the interpreter with e.g.
#   PYTHON=python3.12 ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

PYTHON="${PYTHON:-python3}"
VENV=".venv"

echo "==> Using $("$PYTHON" --version) at $(command -v "$PYTHON")"

if [ ! -x "$VENV/bin/python" ]; then
  echo "==> Creating virtualenv in $VENV"
  "$PYTHON" -m venv "$VENV"
fi

echo "==> Upgrading pip / wheel"
"$VENV/bin/python" -m pip install -q -U pip wheel

echo "==> Installing pinned dependencies (binary wheels only)"
"$VENV/bin/python" -m pip install -q -r requirements.txt

echo "==> Installing face-recognition (no deps; dlib provided by dlib-bin)"
"$VENV/bin/python" -m pip install -q --no-deps face-recognition

if [ ! -f .env ]; then
  echo "==> Creating .env from .env.example (set a real JWT_SECRET for non-demo use)"
  cp .env.example .env
fi

echo "==> Verifying imports"
"$VENV/bin/python" - <<'PY'
import cv2, dlib, face_recognition, fastapi
from app.main import app  # noqa: F401  (ensures routers import cleanly)
print(f"OK: cv2 {cv2.__version__} | dlib {dlib.__version__} | fastapi {fastapi.__version__}")
PY

echo "==> Done. Start the backend with ./run.sh"
