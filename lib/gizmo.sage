gc_disable()
# -----------------------------------------
# gizmo.sage - Transform gizmos for Sage Engine Editor
# Visual handles for translate, rotate, scale
# Rendered as colored lines/boxes in 3D
# -----------------------------------------

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot
from collision import ray_vs_aabb

# ============================================================================
# Gizmo modes
# ============================================================================
let GIZMO_NONE = "none"
let GIZMO_TRANSLATE = "translate"
let GIZMO_ROTATE = "rotate"
let GIZMO_SCALE = "scale"

# ============================================================================
# Gizmo state
# ============================================================================
proc create_gizmo():
    let g = {}
    g["mode"] = GIZMO_TRANSLATE
    g["active_axis"] = "none"
    g["visible"] = true
    g["position"] = vec3(0.0, 0.0, 0.0)
    g["scale_factor"] = 1.0
    g["axis_length"] = 2.0
    g["handle_size"] = 0.15
    g["dragging"] = false
    g["drag_start"] = vec3(0.0, 0.0, 0.0)
    g["drag_offset"] = vec3(0.0, 0.0, 0.0)
    # Axis colors
    g["color_x"] = [1.0, 0.2, 0.2, 1.0]
    g["color_y"] = [0.2, 1.0, 0.2, 1.0]
    g["color_z"] = [0.2, 0.2, 1.0, 1.0]
    g["color_active"] = [1.0, 1.0, 0.2, 1.0]
    return g

# ============================================================================
# Set gizmo mode
# ============================================================================
proc set_gizmo_mode(g, mode):
    g["mode"] = mode
    g["active_axis"] = "none"
    g["dragging"] = false

proc cycle_gizmo_mode(g):
    if g["mode"] == GIZMO_TRANSLATE:
        g["mode"] = GIZMO_ROTATE
    else:
        if g["mode"] == GIZMO_ROTATE:
            g["mode"] = GIZMO_SCALE
        else:
            g["mode"] = GIZMO_TRANSLATE
    g["active_axis"] = "none"
    g["dragging"] = false

# ============================================================================
# Raycast hit test against gizmo handles
# Returns "x", "y", "z", or "none"
# ============================================================================
proc gizmo_hit_test(g, ray_origin, ray_dir):
    let pos = g["position"]
    let len_ax = g["axis_length"] * g["scale_factor"]
    let hs = g["handle_size"] * g["scale_factor"]
    # X axis handle
    let x_center = v3_add(pos, vec3(len_ax, 0.0, 0.0))
    let x_hit = ray_vs_aabb(ray_origin, ray_dir, x_center, vec3(hs, hs, hs))
    # Y axis handle
    let y_center = v3_add(pos, vec3(0.0, len_ax, 0.0))
    let y_hit = ray_vs_aabb(ray_origin, ray_dir, y_center, vec3(hs, hs, hs))
    # Z axis handle
    let z_center = v3_add(pos, vec3(0.0, 0.0, len_ax))
    let z_hit = ray_vs_aabb(ray_origin, ray_dir, z_center, vec3(hs, hs, hs))
    # Find closest hit
    let best = "none"
    let best_t = 999999.0
    if x_hit != nil and x_hit["t"] < best_t:
        best_t = x_hit["t"]
        best = "x"
    if y_hit != nil and y_hit["t"] < best_t:
        best_t = y_hit["t"]
        best = "y"
    if z_hit != nil and z_hit["t"] < best_t:
        best_t = z_hit["t"]
        best = "z"
    return best

# ============================================================================
# Begin drag on an axis
# ============================================================================
proc begin_gizmo_drag(g, axis, start_pos):
    g["active_axis"] = axis
    g["dragging"] = true
    g["drag_start"] = vec3(start_pos[0], start_pos[1], start_pos[2])
    g["drag_offset"] = vec3(0.0, 0.0, 0.0)

proc end_gizmo_drag(g):
    g["dragging"] = false
    g["active_axis"] = "none"
    g["drag_offset"] = vec3(0.0, 0.0, 0.0)

# ============================================================================
# Update drag (returns delta movement along constrained axis)
# ============================================================================
proc update_gizmo_drag(g, current_pos):
    if g["dragging"] == false:
        return vec3(0.0, 0.0, 0.0)
    let delta = v3_sub(current_pos, g["drag_start"])
    let axis = g["active_axis"]
    let result = vec3(0.0, 0.0, 0.0)
    if g["mode"] == GIZMO_TRANSLATE:
        if axis == "x":
            result = vec3(delta[0], 0.0, 0.0)
        if axis == "y":
            result = vec3(0.0, delta[1], 0.0)
        if axis == "z":
            result = vec3(0.0, 0.0, delta[2])
    if g["mode"] == GIZMO_SCALE:
        let mag = v3_length(delta) * 0.1
        if v3_dot(delta, vec3(1.0, 1.0, 1.0)) < 0.0:
            mag = 0.0 - mag
        if axis == "x":
            result = vec3(mag, 0.0, 0.0)
        if axis == "y":
            result = vec3(0.0, mag, 0.0)
        if axis == "z":
            result = vec3(0.0, 0.0, mag)
    if g["mode"] == GIZMO_ROTATE:
        let angle = v3_length(delta) * 0.02
        if axis == "x":
            result = vec3(angle, 0.0, 0.0)
        if axis == "y":
            result = vec3(0.0, angle, 0.0)
        if axis == "z":
            result = vec3(0.0, 0.0, angle)
    g["drag_offset"] = result
    return result

# ============================================================================
# Get axis quads for rendering gizmo as colored boxes
# Returns list of {position, size, color} for each axis handle
# ============================================================================
proc get_gizmo_visuals(g):
    if g["visible"] == false:
        return []
    let pos = g["position"]
    let len_ax = g["axis_length"] * g["scale_factor"]
    let hs = g["handle_size"] * g["scale_factor"]
    let shaft = hs * 0.4
    let visuals = []
    # Axis lines (thin boxes along each axis)
    let cx = g["color_x"]
    let cy = g["color_y"]
    let cz = g["color_z"]
    if g["active_axis"] == "x":
        cx = g["color_active"]
    if g["active_axis"] == "y":
        cy = g["color_active"]
    if g["active_axis"] == "z":
        cz = g["color_active"]
    # X shaft
    push(visuals, {"pos": v3_add(pos, vec3(len_ax * 0.5, 0.0, 0.0)), "half": vec3(len_ax * 0.5, shaft, shaft), "color": cx})
    # X handle
    push(visuals, {"pos": v3_add(pos, vec3(len_ax, 0.0, 0.0)), "half": vec3(hs, hs, hs), "color": cx})
    # Y shaft
    push(visuals, {"pos": v3_add(pos, vec3(0.0, len_ax * 0.5, 0.0)), "half": vec3(shaft, len_ax * 0.5, shaft), "color": cy})
    # Y handle
    push(visuals, {"pos": v3_add(pos, vec3(0.0, len_ax, 0.0)), "half": vec3(hs, hs, hs), "color": cy})
    # Z shaft
    push(visuals, {"pos": v3_add(pos, vec3(0.0, 0.0, len_ax * 0.5)), "half": vec3(shaft, shaft, len_ax * 0.5), "color": cz})
    # Z handle
    push(visuals, {"pos": v3_add(pos, vec3(0.0, 0.0, len_ax)), "half": vec3(hs, hs, hs), "color": cz})
    return visuals
