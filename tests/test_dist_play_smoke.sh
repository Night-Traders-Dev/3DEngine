#!/bin/bash
# test_dist_play_smoke.sh - Packaged voxel-template Play-In-Editor smoke test

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

build_log="/tmp/forge_dist_play_build.log"
if (cd "$ROOT_DIR" && ./build_dist.sh >"$build_log" 2>&1); then
    check_pass
else
    cat "$build_log"
    check_fail "distribution build succeeds"
fi

play_log="/tmp/forge_dist_play_smoke.log"
rm -f "$play_log"

if (cd "$ROOT_DIR" && FORGE_TEMPLATE=voxel FORGE_AUTOPLAY=1 stdbuf -oL -eL timeout 8 ./build/dist/forge_engine >"$play_log" 2>&1); then
    check_fail "packaged editor stays alive until timeout instead of exiting early"
else
    status=$?
    if [[ $status -eq 124 ]]; then
        check_pass
    else
        cat "$play_log"
        check_fail "packaged editor stays alive until timeout instead of exiting early"
    fi
fi

if rg -q "Runtime Error:|signal 11|killed|crash" "$play_log"; then
    cat "$play_log"
    check_fail "packaged editor emits no runtime error or crash markers"
else
    check_pass
fi

if rg -q "Applied voxel template scene" "$play_log" && rg -q "Play mode started (auto)" "$play_log"; then
    check_pass
else
    cat "$play_log"
    check_fail "packaged editor boots the voxel template and enters Play-In-Editor"
fi

echo ""
echo "Results: $pass_count passed, $fail_count failed"
if [[ $fail_count -gt 0 ]]; then
    exit 1
fi
echo "All dist play smoke checks passed!"
