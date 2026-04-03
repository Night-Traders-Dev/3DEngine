#!/bin/bash
# test_dist_play_smoke.sh - Packaged editor launcher + Play-In-Editor smoke test

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pass_count=0
fail_count=0

check_pass() {
    pass_count=$((pass_count + 1))
}

check_fail() {
    echo "  FAIL: $1"
    fail_count=$((fail_count + 1))
}

echo "=== Dist Play Smoke Checks ==="

if ! command -v xdotool >/dev/null 2>&1; then
    echo "xdotool not available; skipping packaged play smoke."
    exit 0
fi

if [[ -z "${DISPLAY:-}" ]]; then
    echo "DISPLAY is not set; skipping packaged play smoke."
    exit 0
fi

build_log="/tmp/forge_dist_play_build.log"
if (cd "$ROOT_DIR" && ./build_dist.sh >"$build_log" 2>&1); then
    check_pass
else
    cat "$build_log"
    check_fail "distribution build succeeds"
fi

play_log="/tmp/forge_dist_play_smoke.log"
rm -f "$play_log"

(
    cd "$ROOT_DIR" || exit 1
    FORGE_TEMPLATE=voxel stdbuf -oL -eL ./build/dist/forge_engine >"$play_log" 2>&1 &
    pid=$!
    cleanup() {
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    }
    trap cleanup EXIT

    loaded=0
    tries=0
    while [[ $tries -lt 20 ]]; do
        if rg -q "Applied voxel template scene" "$play_log" && rg -q "Editor loaded with" "$play_log"; then
            loaded=1
            break
        fi
        sleep 1
        tries=$((tries + 1))
    done

    if [[ $loaded -eq 1 ]]; then
    wid="$(xdotool search --name "Forge Engine" 2>/dev/null | tail -n 1)"
    xdotool windowactivate --sync "$wid" >/dev/null 2>&1
        sleep 1
        xdotool key --window "$wid" --delay 200 Return >/dev/null 2>&1

        sleep 2
        xdotool key --window "$wid" --delay 200 Return >/dev/null 2>&1

        sleep 3
    fi
    if kill -0 "$pid" 2>/dev/null; then
        echo alive >/tmp/forge_dist_play_smoke.status
    else
        wait "$pid" || true
        echo exited >/tmp/forge_dist_play_smoke.status
    fi
)

if [[ "$(cat /tmp/forge_dist_play_smoke.status 2>/dev/null)" == "alive" ]]; then
    check_pass
else
    check_fail "packaged editor stays alive through launcher and play toggle"
fi

if rg -q "Runtime Error:|signal 11|killed|crash" "$play_log"; then
    cat "$play_log"
    check_fail "packaged editor emits no runtime error or crash markers"
else
    check_pass
fi

if rg -q "Applied voxel template scene" "$play_log" && rg -q "Play mode started" "$play_log" && rg -q "Play mode stopped" "$play_log"; then
    check_pass
else
    cat "$play_log"
    check_fail "packaged editor boots voxel template and toggles Play-In-Editor via Enter"
fi

echo ""
echo "Results: $pass_count passed, $fail_count failed"
if [[ $fail_count -gt 0 ]]; then
    exit 1
fi
echo "All dist play smoke checks passed!"
