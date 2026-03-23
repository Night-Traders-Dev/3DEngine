#!/bin/bash
# run.sh - Run a Sage Engine program
# Usage: ./run.sh [script.sage]  (default: examples/demo.sage)

SAGE_DIR="$(cd "$(dirname "$0")/../sagelang" && pwd)"
SAGE="$SAGE_DIR/sage"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SAGE" ]; then
    echo "Error: sage binary not found at $SAGE"
    echo "Expected sagelang at: $SAGE_DIR"
    exit 1
fi

SCRIPT="${1:-examples/demo.sage}"

if [ ! -f "$ENGINE_DIR/$SCRIPT" ]; then
    echo "Error: Script not found: $SCRIPT"
    exit 1
fi

cd "$ENGINE_DIR"
exec "$SAGE" "$SCRIPT"
