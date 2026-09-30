#!/usr/bin/env bash
#
# App-quit survival smoke test for managed services (design notes, section 6.5).
#
# Phase 1 launches a real managed service through the production manager in one
# test process and lets that process exit, simulating quitting Port Manager
# without stopping the child. The script then proves the child is still alive,
# still listening and still writing output seconds later.
#
# Phase 2 reloads the profile in a fresh process, reconciles against a real port
# scan and requires the survivor to be reported as a Conflict this app does not
# own.
#
# Usage: ./scripts/smoke-service-survival.sh

set -euo pipefail

cd "$(dirname "$0")/.."

PORT="${SMOKE_PORT:-$(( (RANDOM % 10000) + 40000 ))}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/portkiller-survival.XXXXXX")"
INFO="$WORKDIR/info.txt"
SCRIPT="$WORKDIR/spam_server.py"

cleanup() {
  if [ -f "$INFO" ]; then
    pid="$(sed -n 's/^pid=//p' "$INFO")"
    if [ -n "${pid:-}" ]; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

cat > "$SCRIPT" <<'PY'
import socket
import sys
import threading
import time

port = int(sys.argv[1])
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", port))
server.listen(8)


def spam():
    i = 0
    while True:
        i += 1
        print(f"stdout tick {i}", flush=True)
        print(f"stderr tick {i}", file=sys.stderr, flush=True)
        time.sleep(0.2)


threading.Thread(target=spam, daemon=True).start()
print(f"listening on {port}", flush=True)
while True:
    time.sleep(1)
PY

echo "==> phase 1: launch through the production manager, then let that process exit"
PORTKILLER_SURVIVAL_SMOKE=launch \
PORTKILLER_SURVIVAL_PORT="$PORT" \
PORTKILLER_SURVIVAL_SCRIPT="$SCRIPT" \
PORTKILLER_SURVIVAL_INFO="$INFO" \
  ./scripts/test.sh --filter ManagedServiceSurvivalSmokeTests 2>&1 | tail -25

test -f "$INFO" || { echo "FAILED: launch did not report a runtime"; exit 1; }
PID="$(sed -n 's/^pid=//p' "$INFO")"
STDOUT_LOG="$(sed -n 's/^stdout=//p' "$INFO")"
echo "==> Port Manager process exited; surviving child pid=$PID port=$PORT"

sleep 1
kill -0 "$PID" 2>/dev/null || { echo "FAILED: child died with Port Manager"; exit 1; }
lsof -nP -a -p "$PID" -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || {
  echo "FAILED: child is no longer listening on $PORT"; exit 1; }

SIZE_BEFORE="$(stat -f%z "$STDOUT_LOG")"
sleep 3
kill -0 "$PID" 2>/dev/null || { echo "FAILED: child died within 3s of app exit"; exit 1; }
lsof -nP -a -p "$PID" -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || {
  echo "FAILED: child stopped listening within 3s"; exit 1; }
SIZE_AFTER="$(stat -f%z "$STDOUT_LOG")"
if [ "$SIZE_AFTER" -le "$SIZE_BEFORE" ]; then
  echo "FAILED: child stopped writing stdout after app exit ($SIZE_BEFORE -> $SIZE_AFTER)"
  exit 1
fi
echo "==> child alive, listening and writing after app exit (stdout $SIZE_BEFORE -> $SIZE_AFTER bytes)"

echo "==> phase 2: relaunch must detect the survivor as Conflict"
PORTKILLER_SURVIVAL_SMOKE=relaunch \
PORTKILLER_SURVIVAL_PORT="$PORT" \
PORTKILLER_SURVIVAL_INFO="$INFO" \
  ./scripts/test.sh --filter ManagedServiceSurvivalSmokeTests 2>&1 | tail -25

echo "==> PASS: child outlived Port Manager, kept listening/writing, and is a Conflict on relaunch"
