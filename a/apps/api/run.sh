#!/usr/bin/env bash
# Start PostgreSQL (via docker compose) if needed, then run the FastAPI backend
# on all interfaces so the Flutter app on a phone or emulator can reach it.
#
# Override with HOST=... PORT=... ./run.sh
set -euo pipefail
cd "$(dirname "$0")"                    # apps/api
REPO_ROOT="$(cd ../.. && pwd)"          # repo root (holds docker-compose.yml)

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"

if [ ! -x ".venv/bin/python" ]; then
  echo "No .venv found — run ./setup.sh first." >&2
  exit 1
fi

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; }

# Ensure PostgreSQL is listening (compose service lives at the repo root).
if ! port_open 5432; then
  echo "==> Starting PostgreSQL via docker compose"
  ( cd "$REPO_ROOT" && docker compose up -d postgres )
  for _ in $(seq 1 30); do port_open 5432 && break; sleep 1; done
fi

# Refuse to double-bind the API port (avoids a second, stale server).
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is already serving. Existing listener:" >&2
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2
  echo "Stop it before starting a new one." >&2
  exit 1
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
[ -z "${LAN_IP:-}" ] && LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

echo "==> API (this machine): http://localhost:$PORT   health: /health   docs: /docs"
[ -n "${LAN_IP:-}" ] && \
echo "==> Flutter on a phone:  http://$LAN_IP:$PORT   (same Wi-Fi)"
echo "==> Flutter on Android emulator: http://10.0.2.2:$PORT"
echo

exec .venv/bin/python -m uvicorn app.main:app --host "$HOST" --port "$PORT" --reload
