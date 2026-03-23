gc_disable()
# -----------------------------------------
# engine.sage - Core engine module for Forge Engine
# Creates and manages the engine context: world, renderer, input, events, time
# -----------------------------------------

import gpu
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, aspect_ratio, check_resize, update_title_fps
from ecs import create_world, spawn, destroy, add_component, get_component, has_component, query, tick_systems, flush_dead, register_system
from events import create_event_bus, subscribe, emit, flush_events
from input import create_input, update_input, default_fps_bindings
from game_loop import create_loop_config, create_time_state, update_time
from components import TransformComponent, NameComponent
from engine_math import transform_to_matrix

# ============================================================================
# Engine Context - the top-level container
# ============================================================================
proc create_engine(title, width, height):
    let eng = {}

    # Renderer
    let r = create_renderer(width, height, title)
    if r == nil:
        print "ENGINE ERROR: Failed to create Vulkan renderer"
        return nil
    eng["renderer"] = r
    eng["title"] = title

    # ECS world
    eng["world"] = create_world()

    # Event bus
    eng["events"] = create_event_bus()

    # Input system
    eng["input"] = create_input()
    default_fps_bindings(eng["input"])

    # Time
    eng["time"] = create_time_state()
    eng["loop"] = create_loop_config()

    # Registered update/render callbacks
    eng["update_callbacks"] = []
    eng["render_callbacks"] = []

    print "Forge Engine initialized (" + str(width) + "x" + str(height) + ")"
    print "GPU: " + gpu.device_name()
    return eng

# ============================================================================
# Register user callbacks
# ============================================================================
proc on_update(eng, callback):
    push(eng["update_callbacks"], callback)

proc on_render(eng, callback):
    push(eng["render_callbacks"], callback)

# ============================================================================
# Transform system - updates model matrices for dirty transforms
# ============================================================================
proc _transform_system(world, entities, dt):
    let i = 0
    while i < len(entities):
        let e = entities[i]
        let t = get_component(world, e, "transform")
        if t["dirty"]:
            t["matrix"] = transform_to_matrix(t)
            t["dirty"] = false
        i = i + 1

# ============================================================================
# Run engine main loop
# ============================================================================
proc run(eng):
    let world = eng["world"]
    let r = eng["renderer"]
    let inp = eng["input"]
    let events = eng["events"]
    let time_state = eng["time"]
    let loop_cfg = eng["loop"]

    # Register built-in systems
    register_system(world, "transform", ["transform"], _transform_system)

    print "Starting engine loop..."

    while loop_cfg["running"]:
        update_time(time_state)
        let dt = time_state["dt"]

        # Check window close
        check_resize(r)

        # Input
        update_input(inp)

        # Fixed timestep updates
        loop_cfg["accumulator"] = loop_cfg["accumulator"] + dt
        let fixed_dt = loop_cfg["fixed_dt"]
        while loop_cfg["accumulator"] >= fixed_dt:
            # ECS systems
            tick_systems(world, fixed_dt)

            # User update callbacks
            let ui = 0
            while ui < len(eng["update_callbacks"]):
                eng["update_callbacks"][ui](eng, fixed_dt)
                ui = ui + 1

            # Flush events
            flush_events(events)

            loop_cfg["accumulator"] = loop_cfg["accumulator"] - fixed_dt
            loop_cfg["time"] = loop_cfg["time"] + fixed_dt

        # Cleanup dead entities
        flush_dead(world)

        # Render
        let frame = begin_frame(r)
        if frame == nil:
            loop_cfg["running"] = false
            continue

        let cmd = frame["cmd"]

        # User render callbacks
        let ri = 0
        while ri < len(eng["render_callbacks"]):
            eng["render_callbacks"][ri](eng, frame)
            ri = ri + 1

        end_frame(r, frame)

        # FPS title
        update_title_fps(r, eng["title"])
        loop_cfg["frame"] = loop_cfg["frame"] + 1

    print "Engine shutting down..."
    shutdown_renderer(r)
    let elapsed = time_state["total"]
    let frames = loop_cfg["frame"]
    if elapsed > 0:
        print "Total: " + str(frames) + " frames in " + str(elapsed) + "s (avg " + str(frames / elapsed) + " FPS)"

# ============================================================================
# Shutdown
# ============================================================================
proc shutdown(eng):
    eng["loop"]["running"] = false
