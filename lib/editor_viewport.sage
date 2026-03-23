gc_disable()
# -----------------------------------------
# editor_viewport.sage - Interactive editor viewport for Sage Engine
# Separate editor camera, entity picking, gizmo interaction
# -----------------------------------------

import gpu
import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_cross
from math3d import mat4_look_at, mat4_perspective, mat4_mul, radians
from engine_math import clamp
from collision import ray_vs_aabb
from scene_editor import select_by_ray, apply_gizmo_delta, select_entity
from gizmo import gizmo_hit_test, begin_gizmo_drag, end_gizmo_drag, update_gizmo_drag, cycle_gizmo_mode

# ============================================================================
# Editor Camera (orbit + pan + zoom)
# ============================================================================
proc create_editor_camera():
    let ec = {}
    ec["target"] = vec3(0.0, 1.0, 0.0)
    ec["distance"] = 15.0
    ec["yaw"] = 0.5
    ec["pitch"] = 0.4
    ec["min_distance"] = 1.0
    ec["max_distance"] = 200.0
    ec["orbit_speed"] = 0.005
    ec["pan_speed"] = 0.01
    ec["zoom_speed"] = 1.0
    return ec

proc editor_camera_view(ec):
    let cy = math.cos(ec["yaw"])
    let sy = math.sin(ec["yaw"])
    let cp = math.cos(ec["pitch"])
    let sp = math.sin(ec["pitch"])
    let d = ec["distance"]
    let eye = vec3(ec["target"][0] + d * cp * sy, ec["target"][1] + d * sp, ec["target"][2] + d * cp * cy)
    return mat4_look_at(eye, ec["target"], vec3(0.0, 1.0, 0.0))

proc editor_camera_position(ec):
    let cy = math.cos(ec["yaw"])
    let sy = math.sin(ec["yaw"])
    let cp = math.cos(ec["pitch"])
    let sp = math.sin(ec["pitch"])
    let d = ec["distance"]
    return vec3(ec["target"][0] + d * cp * sy, ec["target"][1] + d * sp, ec["target"][2] + d * cp * cy)

proc editor_camera_forward(ec):
    let pos = editor_camera_position(ec)
    return v3_normalize(v3_sub(ec["target"], pos))

# ============================================================================
# Editor Viewport
# ============================================================================
proc create_editor_viewport(editor):
    let vp = {}
    vp["editor"] = editor
    vp["camera"] = create_editor_camera()
    vp["fov"] = 60.0
    vp["mode"] = "select"
    vp["orbiting"] = false
    vp["panning"] = false
    vp["gizmo_active"] = false
    vp["last_mx"] = 0.0
    vp["last_my"] = 0.0
    vp["grid_visible"] = true
    vp["stats_visible"] = true
    return vp

# ============================================================================
# Update viewport from input
# ============================================================================
proc update_editor_viewport(vp, inp, dt):
    from input import mouse_delta, mouse_position, scroll_value
    from input import action_held, action_just_pressed, action_just_released

    let cam = vp["camera"]
    let md = mouse_delta(inp)
    let mp = mouse_position(inp)
    let sv = scroll_value(inp)

    # Orbit (right mouse)
    if action_held(inp, "orbit"):
        cam["yaw"] = cam["yaw"] + md[0] * cam["orbit_speed"]
        cam["pitch"] = cam["pitch"] + md[1] * cam["orbit_speed"]
        cam["pitch"] = clamp(cam["pitch"], -1.5, 1.5)

    # Pan (middle mouse)
    if action_held(inp, "pan"):
        let cy = math.cos(cam["yaw"])
        let sy = math.sin(cam["yaw"])
        let right = vec3(cy, 0.0, 0.0 - sy)
        let up = vec3(0.0, 1.0, 0.0)
        let pan_x = md[0] * cam["pan_speed"] * cam["distance"] * 0.1
        let pan_y = md[1] * cam["pan_speed"] * cam["distance"] * 0.1
        cam["target"] = v3_add(cam["target"], v3_scale(right, 0.0 - pan_x))
        cam["target"] = v3_add(cam["target"], v3_scale(up, pan_y))

    # Zoom (scroll)
    if sv[1] != 0.0:
        cam["distance"] = cam["distance"] - sv[1] * cam["zoom_speed"]
        cam["distance"] = clamp(cam["distance"], cam["min_distance"], cam["max_distance"])

    # Focus on selected (F key handled externally)
    # Gizmo mode cycle (handled externally)

# ============================================================================
# Handle mouse click for selection/gizmo
# ============================================================================
proc editor_viewport_click(vp, mx, my, screen_w, screen_h):
    let cam = vp["camera"]
    let ed = vp["editor"]
    # Build pick ray from mouse position
    let ray_origin = editor_camera_position(cam)
    let fov = radians(vp["fov"])
    let aspect = screen_w / screen_h
    # NDC
    let ndc_x = (mx / screen_w) * 2.0 - 1.0
    let ndc_y = 1.0 - (my / screen_h) * 2.0
    # View space ray
    let tan_half = math.tan(fov * 0.5)
    let rx = ndc_x * aspect * tan_half
    let ry = ndc_y * tan_half
    # Transform by inverse view rotation
    let cy = math.cos(cam["yaw"])
    let sy = math.sin(cam["yaw"])
    let cp = math.cos(cam["pitch"])
    let sp = math.sin(cam["pitch"])
    let forward = v3_normalize(v3_sub(cam["target"], ray_origin))
    let right = v3_normalize(v3_cross(forward, vec3(0.0, 1.0, 0.0)))
    let up = v3_cross(right, forward)
    let ray_dir = v3_normalize(v3_add(v3_add(v3_scale(right, rx), v3_scale(up, ry)), forward))
    # First check gizmo
    if ed["selected"] >= 0:
        let axis = gizmo_hit_test(ed["gizmo"], ray_origin, ray_dir)
        if axis != "none":
            begin_gizmo_drag(ed["gizmo"], axis, ray_origin)
            vp["gizmo_active"] = true
            return nil
    # Then pick entity
    select_by_ray(ed, ray_origin, ray_dir)

proc editor_viewport_release(vp):
    if vp["gizmo_active"]:
        end_gizmo_drag(vp["editor"]["gizmo"])
        vp["gizmo_active"] = false

# ============================================================================
# Focus camera on selected entity
# ============================================================================
proc focus_selected(vp):
    let ed = vp["editor"]
    if ed["selected"] < 0:
        return nil
    from ecs import get_component, has_component
    if has_component(ed["world"], ed["selected"], "transform"):
        let t = get_component(ed["world"], ed["selected"], "transform")
        vp["camera"]["target"] = vec3(t["position"][0], t["position"][1], t["position"][2])
