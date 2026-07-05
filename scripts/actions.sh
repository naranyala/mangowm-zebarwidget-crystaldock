#!/bin/bash
# actions.sh — Dispatcher for modular action scripts

if [ -z "$1" ]; then
    echo "Usage: actions.sh <action_name> [args...]"
    exit 1
fi

ACTION="$1"
shift

SCRIPT="$HOME/.local/bin/actions/${ACTION}.sh"

if [ -x "$SCRIPT" ]; then
    exec "$SCRIPT" "$@"
else
    echo "Error: Action '$ACTION' not found at $SCRIPT"
    # Fallback to try without .sh in case it's named differently
    SCRIPT_NO_EXT="$HOME/.local/bin/actions/${ACTION}"
    if [ -x "$SCRIPT_NO_EXT" ]; then
        exec "$SCRIPT_NO_EXT" "$@"
    else
        exit 1
    fi
fi
