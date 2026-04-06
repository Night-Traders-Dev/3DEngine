gc_disable()
# profiler.sage — Runtime Performance Profiler
# Tracks frame time, system timings, draw calls, memory, and GPU stats.
# Displays an overlay with real-time graphs and metrics.
#
# Usage:
#   let prof = create_profiler()
#   begin_profile(prof, "physics")
#   # ... physics code ...
#   end_profile(prof, "physics")
#   update_profiler(prof, dt)
#   let overlay_text = profiler_overlay(prof)

import math

# ============================================================================
# Profiler
# ============================================================================

proc create_profiler():
    return {
        "enabled": true,
        "sections": {},          # name → {total_ms, calls, min_ms, max_ms, history}
        "frame_times": [],       # Last N frame times for graph
        "frame_history_size": 120,
        "frame_count": 0,
        "total_time": 0.0,
        "current_frame_start": 0.0,
        "draw_calls": 0,
        "triangles": 0,
        "gpu_memory_mb": 0.0,
        "entities": 0,
        "visible_entities": 0,
        # Timing stack for nested sections
        "stack": [],
        "frame_start": 0.0
    }

proc begin_frame_profile(prof):
    prof["frame_start"] = clock()
    prof["draw_calls"] = 0
    prof["triangles"] = 0
    # Reset per-frame section timings
    let keys = dict_keys(prof["sections"])
    let i = 0
    while i < len(keys):
        let s = prof["sections"][keys[i]]
        s["frame_ms"] = 0.0
        s["frame_calls"] = 0
        i = i + 1

proc end_frame_profile(prof):
    let frame_ms = (clock() - prof["frame_start"]) * 1000.0
    push(prof["frame_times"], frame_ms)
    if len(prof["frame_times"]) > prof["frame_history_size"]:
        # Remove oldest
        let new_times = []
        let i = 1
        while i < len(prof["frame_times"]):
            push(new_times, prof["frame_times"][i])
            i = i + 1
        prof["frame_times"] = new_times
    prof["frame_count"] = prof["frame_count"] + 1
    prof["total_time"] = prof["total_time"] + frame_ms / 1000.0

# ============================================================================
# Section Profiling
# ============================================================================

proc begin_profile(prof, section_name):
    if not prof["enabled"]:
        return
    push(prof["stack"], {"name": section_name, "start": clock()})

proc end_profile(prof, section_name):
    if not prof["enabled"] or len(prof["stack"]) == 0:
        return
    let entry = prof["stack"][len(prof["stack"]) - 1]
    pop(prof["stack"])
    let elapsed_ms = (clock() - entry["start"]) * 1000.0

    if not dict_has(prof["sections"], section_name):
        prof["sections"][section_name] = {
            "total_ms": 0.0,
            "calls": 0,
            "min_ms": 999999.0,
            "max_ms": 0.0,
            "avg_ms": 0.0,
            "frame_ms": 0.0,
            "frame_calls": 0,
            "history": []
        }
    let s = prof["sections"][section_name]
    s["total_ms"] = s["total_ms"] + elapsed_ms
    s["calls"] = s["calls"] + 1
    s["frame_ms"] = s["frame_ms"] + elapsed_ms
    s["frame_calls"] = s["frame_calls"] + 1
    if elapsed_ms < s["min_ms"]:
        s["min_ms"] = elapsed_ms
    if elapsed_ms > s["max_ms"]:
        s["max_ms"] = elapsed_ms
    s["avg_ms"] = s["total_ms"] / s["calls"]

    push(s["history"], elapsed_ms)
    if len(s["history"]) > 60:
        let new_hist = []
        let i = 1
        while i < len(s["history"]):
            push(new_hist, s["history"][i])
            i = i + 1
        s["history"] = new_hist

# ============================================================================
# Draw Call / Triangle Tracking
# ============================================================================

proc profile_draw_call(prof, triangle_count):
    prof["draw_calls"] = prof["draw_calls"] + 1
    prof["triangles"] = prof["triangles"] + triangle_count

proc set_entity_count(prof, total, visible):
    prof["entities"] = total
    prof["visible_entities"] = visible

# ============================================================================
# Overlay Text — formatted profiler output
# ============================================================================

proc profiler_overlay(prof):
    let lines = []
    # FPS
    let fps = 0.0
    if prof["total_time"] > 0:
        fps = prof["frame_count"] / prof["total_time"]

    let frame_ms = 0.0
    if len(prof["frame_times"]) > 0:
        frame_ms = prof["frame_times"][len(prof["frame_times"]) - 1]

    push(lines, "=== PROFILER ===")
    push(lines, "FPS: " + str(int(fps)) + " | Frame: " + str(int(frame_ms * 100) / 100.0) + "ms")
    push(lines, "Draw Calls: " + str(prof["draw_calls"]) + " | Tris: " + str(prof["triangles"]))
    push(lines, "Entities: " + str(prof["visible_entities"]) + "/" + str(prof["entities"]))
    push(lines, "")

    # Section breakdown
    let keys = dict_keys(prof["sections"])
    let i = 0
    while i < len(keys):
        let name = keys[i]
        let s = prof["sections"][name]
        let ms_str = str(int(s["frame_ms"] * 100) / 100.0)
        push(lines, "  " + name + ": " + ms_str + "ms (" + str(s["frame_calls"]) + " calls)")
        i = i + 1

    return lines

proc profiler_summary(prof):
    let fps = 0.0
    if prof["total_time"] > 0:
        fps = prof["frame_count"] / prof["total_time"]
    return {
        "fps": fps,
        "frame_ms": len(prof["frame_times"]) > 0 and prof["frame_times"][len(prof["frame_times"]) - 1] or 0.0,
        "draw_calls": prof["draw_calls"],
        "triangles": prof["triangles"],
        "entities": prof["entities"],
        "visible": prof["visible_entities"],
        "sections": prof["sections"]
    }

proc reset_profiler(prof):
    prof["sections"] = {}
    prof["frame_times"] = []
    prof["frame_count"] = 0
    prof["total_time"] = 0.0
