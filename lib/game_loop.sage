gc_disable()
# -----------------------------------------
# game_loop.sage - Fixed-timestep game loop for Sage Engine
# Separates physics/logic updates from rendering
# Uses semi-fixed timestep with accumulator
# -----------------------------------------

import sys

# ============================================================================
# Game Loop Configuration
# ============================================================================
proc create_loop_config():
    let cfg = {}
    cfg["fixed_dt"] = 1.0 / 60.0
    cfg["max_frame_time"] = 0.25
    cfg["target_fps"] = 0
    cfg["accumulator"] = 0.0
    cfg["time"] = 0.0
    cfg["frame"] = 0
    cfg["running"] = true
    return cfg

# ============================================================================
# Time tracking
# ============================================================================
proc create_time_state():
    let t = {}
    t["now"] = sys.clock()
    t["last"] = sys.clock()
    t["dt"] = 0.0
    t["total"] = 0.0
    t["frame_count"] = 0
    t["fps"] = 0.0
    t["fps_timer"] = 0.0
    t["fps_frames"] = 0
    return t

proc update_time(ts):
    ts["now"] = sys.clock()
    ts["dt"] = ts["now"] - ts["last"]
    if ts["dt"] > 0.25:
        ts["dt"] = 0.25
    ts["last"] = ts["now"]
    ts["total"] = ts["total"] + ts["dt"]
    ts["frame_count"] = ts["frame_count"] + 1
    # FPS counter (updates every second)
    ts["fps_timer"] = ts["fps_timer"] + ts["dt"]
    ts["fps_frames"] = ts["fps_frames"] + 1
    if ts["fps_timer"] >= 1.0:
        ts["fps"] = ts["fps_frames"] / ts["fps_timer"]
        ts["fps_timer"] = 0.0
        ts["fps_frames"] = 0

# ============================================================================
# Fixed timestep loop runner
# Calls fixed_update(world, fixed_dt) for physics/logic
# Calls render(world, alpha) once per frame with interpolation alpha
# ============================================================================
proc run_loop(config, time_state, world, fixed_update_fn, render_fn, should_continue_fn):
    while config["running"]:
        update_time(time_state)
        let frame_dt = time_state["dt"]

        if should_continue_fn(world) == false:
            config["running"] = false
            continue

        # Accumulate time for fixed updates
        config["accumulator"] = config["accumulator"] + frame_dt

        # Run fixed updates
        let fixed_dt = config["fixed_dt"]
        while config["accumulator"] >= fixed_dt:
            fixed_update_fn(world, fixed_dt)
            config["time"] = config["time"] + fixed_dt
            config["accumulator"] = config["accumulator"] - fixed_dt

        # Interpolation alpha for rendering
        let alpha = config["accumulator"] / fixed_dt

        # Render
        render_fn(world, alpha)

        config["frame"] = config["frame"] + 1
