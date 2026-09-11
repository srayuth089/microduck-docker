#!/usr/bin/env bash
# microduck-docker entrypoint — start the simulator, or hand over to a tool.
#
# Design rule: a newcomer types ONE command and sees a walking robot. Anything
# that can go wrong should explain itself in plain language, because the person
# reading it may be twelve years old and this may be their first container.
set -euo pipefail

LAB_PORT="${LAB_PORT:-8788}"
VIEWER_PORT="${VIEWER_PORT:-63317}"
POLICY_DIR=/app/policies
RUNS_DIR=/data/runs

# The lab writes runs, captures and its roster next to the CWD, so working out
# of /data is what makes `-v` actually preserve a user's training.
mkdir -p "$RUNS_DIR" /data/captures
cd /data

say()  { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }

# Ducks to load: DUCKS env (space/comma separated) wins, else a sensible pair
# so the very first run shows both a walker and a stander.
default_ducks() {
  if [ -n "${DUCKS:-}" ]; then
    printf '%s' "$DUCKS" | tr ',' ' '
  else
    printf '%s %s' "$POLICY_DIR/BEST_alpha_walking.onnx" \
                   "$POLICY_DIR/BEST_alpha_stand.onnx"
  fi
}

# Resolve a bare name ("roulade") to a shipped policy path, so users never have
# to know where files live inside the image.
resolve() {
  for tok in "$@"; do
    if [ -e "$tok" ]; then printf '%s ' "$tok"
    elif [ -e "$POLICY_DIR/$tok" ]; then printf '%s ' "$POLICY_DIR/$tok"
    elif [ -e "$POLICY_DIR/$tok.onnx" ]; then printf '%s ' "$POLICY_DIR/$tok.onnx"
    elif [ -e "$RUNS_DIR/$tok" ]; then printf '%s ' "$RUNS_DIR/$tok"
    else warn "⚠  skipping '$tok' — no such policy (try: microduck-docker policies)" >&2
    fi
  done
}

cmd_serve() {
  local ducks; ducks="$(resolve $(default_ducks))"
  [ -n "${ducks// /}" ] || ducks="$POLICY_DIR/BEST_alpha_walking.onnx"

  say "🦆 Starting the Microduck lab…"
  duck-lab --host 0.0.0.0 --port "$LAB_PORT" --fresh $ducks &
  local lab_pid=$!

  # Wait for physics to be up before the viewer, so the page never loads into
  # an empty socket and shows a scary error to a first-time user.
  local i
  for i in $(seq 1 120); do
    curl -fsS "http://127.0.0.1:${LAB_PORT}/scene" >/dev/null 2>&1 && break
    kill -0 "$lab_pid" 2>/dev/null || { echo "the physics engine exited"; wait "$lab_pid"; }
    sleep 1
  done

  say "🌐 Starting the 3D viewer…"
  ( cd /app/viewer && PORT="$VIEWER_PORT" HOSTNAME=0.0.0.0 exec node server.js ) &
  local web_pid=$!

  # printf, not a heredoc: a heredoc cannot pad, and the URL row has to stay
  # aligned whatever port the user mapped. Interior width is 48 columns; the
  # duck emoji is one character but TWO columns wide, so its row is padded one
  # space short on purpose.
  local url="http://localhost:${VIEWER_PORT}"
  printf '\n'
  printf '  ┌%s┐\n' "────────────────────────────────────────────────"
  printf '  │  🦆  Microduck is running!                     │\n'
  printf '  │                                                │\n'
  printf '  │  Open this in your browser:                    │\n'
  printf '  │%s│\n' "$(printf '      %-42s' "$url")"
  printf '  │                                                │\n'
  printf '  │  Press Ctrl+C here to stop.                    │\n'
  printf '  └%s┘\n' "────────────────────────────────────────────────"
  printf '\n'

  ┌────────────────────────────────────────────────┐
  │  🦆  Microduck is running!                     │
  │                                                │
  │  Open this in your browser:                    │
  │      %-42s│
  │                                                │
  │  Press Ctrl+C here to stop.                    │
  └────────────────────────────────────────────────┘

BANNER

  # If either half dies, stop the other rather than leaving a half-lab up.
  trap 'kill "$lab_pid" "$web_pid" 2>/dev/null || true' INT TERM
  wait -n "$lab_pid" "$web_pid"
  kill "$lab_pid" "$web_pid" 2>/dev/null || true
}

cmd_policies() {
  say "Policies baked into this image (use the name with DUCKS=…):"
  for f in "$POLICY_DIR"/*.onnx; do printf '  %s\n' "$(basename "$f" .onnx)"; done
  if compgen -G "$RUNS_DIR/*" >/dev/null; then
    say ""; say "Policies you trained yourself (in /data/runs):"
    for d in "$RUNS_DIR"/*/; do printf '  %s\n' "$(basename "$d")"; done
  fi
}

case "${1:-serve}" in
  serve)     shift || true; cmd_serve ;;
  policies)  cmd_policies ;;
  version)   cat /app/VERSION.txt ;;
  train)     shift; exec train-walk "$@" ;;
  behavior)  shift; exec train-behavior "$@" ;;
  export)    shift; exec export-walk "$@" ;;
  eval)      shift; exec eval-walk "$@" ;;
  render)    shift; exec render-rollout "$@" ;;
  bench)     shift; exec bench-walk "$@" ;;
  shell)     exec /bin/bash ;;
  *)         exec "$@" ;;
esac
