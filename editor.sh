#!/bin/bash
# editor.sh - Launch Sage Engine Editor (suppresses interpreter noise)
SAGE_DIR="$(cd "$(dirname "$0")/../sagelang" && pwd)"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ENGINE_DIR"
exec "$SAGE_DIR/sage" editor.sage 2>/dev/null
