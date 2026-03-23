# test_game_loop.sage - Sanity checks for game loop timing
# Run: ./run.sh tests/test_game_loop.sage

from game_loop import create_loop_config, create_time_state, update_time

import math

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

proc approx(a, b):
    return math.abs(a - b) < 0.01

print "=== Game Loop Sanity Checks ==="

# --- Loop config ---
let cfg = create_loop_config()
check("config created", cfg != nil)
check("default fixed_dt is 1/60", approx(cfg["fixed_dt"], 1.0 / 60.0))
check("accumulator starts at 0", cfg["accumulator"] == 0.0)
check("running starts true", cfg["running"] == true)
check("frame starts at 0", cfg["frame"] == 0)

# --- Time state ---
let ts = create_time_state()
check("time state created", ts != nil)
check("dt starts at 0", ts["dt"] == 0.0)
check("total starts at 0", ts["total"] == 0.0)
check("frame_count starts at 0", ts["frame_count"] == 0)

# --- Update time ---
update_time(ts)
check("after first update, dt >= 0", ts["dt"] >= 0.0)
check("after first update, frame_count is 1", ts["frame_count"] == 1)
check("total >= 0", ts["total"] >= 0.0)

# --- Max frame time clamping ---
# Simulate a huge gap
ts["last"] = ts["now"] - 1.0
update_time(ts)
check("dt clamped to max 0.25", ts["dt"] <= 0.25)

# --- Accumulator simulation ---
cfg["accumulator"] = 0.0
cfg["accumulator"] = cfg["accumulator"] + 0.1
let fixed_dt = cfg["fixed_dt"]
let step_count = 0
while cfg["accumulator"] >= fixed_dt:
    step_count = step_count + 1
    cfg["accumulator"] = cfg["accumulator"] - fixed_dt
check("0.1s yields ~6 fixed steps", step_count == 6 or step_count == 5)
check("accumulator has remainder", cfg["accumulator"] >= 0.0 and cfg["accumulator"] < fixed_dt)

# --- Alpha interpolation ---
cfg["accumulator"] = fixed_dt * 0.5
let alpha = cfg["accumulator"] / fixed_dt
check("alpha at half step is ~0.5", approx(alpha, 0.5))

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Game loop sanity checks failed!"
else:
    print "All game loop sanity checks passed!"
