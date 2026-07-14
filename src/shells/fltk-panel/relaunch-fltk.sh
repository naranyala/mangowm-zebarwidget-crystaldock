#!/bin/sh
# Stop and relaunch fltk-cpp-shell (combined top panel + bottom dock)
#
# Usage:
#   ./relaunch-fltk.sh          # stop + relaunch from local build
#   ./relaunch-fltk.sh build    # rebuild first, then relaunch
#   ./relaunch-fltk.sh install  # install to ~/.local/bin/ then relaunch
#
# Notes:
#   - Uses the locally built binary in this directory by default.
#   - If the local binary is missing, falls back to ~/.local/bin/.
#   - Sets LD_LIBRARY_PATH so the vendored FLTK shared libs are found.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FLTK_BUILD="$PROJECT_DIR/sources/fltk/build"
export LD_LIBRARY_PATH="$FLTK_BUILD/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

ACTION="${1:-}"

# Optional: rebuild
if [ "$ACTION" = "build" ]; then
  echo "==> Rebuilding fltk-cpp-shell..."
  make -C "$SCRIPT_DIR" clean all
fi

# Optional: install
if [ "$ACTION" = "install" ]; then
  echo "==> Installing to ~/.local/bin/..."
  install -Dm755 "$SCRIPT_DIR/fltk-cpp-shell" "$HOME/.local/bin/fltk-cpp-shell"
  install -Dm644 "$SCRIPT_DIR/widgets.conf.example" \
    "$HOME/.config/fltk-panel/widgets.conf"
  echo "==> Installed default config to ~/.config/fltk-panel/widgets.conf"
fi

# Pick binary location: prefer local build, fall back to installed
shell_bin="$SCRIPT_DIR/fltk-cpp-shell"
if [ ! -x "$shell_bin" ]; then shell_bin="$HOME/.local/bin/fltk-cpp-shell"; fi

if [ ! -x "$shell_bin" ]; then
  echo "error: fltk-cpp-shell not found (run './relaunch-fltk.sh build' first)" >&2
  exit 1
fi

# Step 1: stop existing instances
echo "==> Stopping running instances..."
for p in fltk-cpp-shell fltk-panel fltk-dock; do
  for pid in $(pgrep -x "$p" 2>/dev/null); do
    kill "$pid" 2>/dev/null && echo "  killed $p (pid $pid)"
  done
done
# brief wait for clean exit
sleep 0.5

# Safety net: force-kill anything still alive
for p in fltk-cpp-shell fltk-panel fltk-dock; do
  for pid in $(pgrep -x "$p" 2>/dev/null); do
    kill -9 "$pid" 2>/dev/null || true
  done
done

# Step 2: relaunch
echo "==> Launching fltk-cpp-shell (top panel + bottom dock)..."
nohup "$shell_bin" > /tmp/fltk-cpp-shell.log 2>&1 &
echo "  fltk-cpp-shell pid=$!"

sleep 1

echo ""
echo "=== Status ==="
pgrep -a fltk-cpp-shell || echo "  fltk-cpp-shell: NOT running"
echo ""
echo "Logs: /tmp/fltk-cpp-shell.log"
