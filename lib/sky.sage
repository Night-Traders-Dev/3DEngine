gc_disable()
# -----------------------------------------
# sky.sage - Procedural sky renderer for Sage Engine
# Gradient sky with sun disc, glow, and horizon haze
# Renders as fullscreen pass (no vertex buffer needed)
# -----------------------------------------

import gpu
import math
from math3d import vec3, v3_normalize, mat4_identity, mat4_rotate_x, mat4_rotate_y, mat4_mul, radians

# ============================================================================
# Sky settings
# ============================================================================
proc create_sky():
    let s = {}
    # Sun
    s["sun_dir"] = v3_normalize(vec3(0.3, 0.6, 0.5))
    s["sun_intensity"] = 1.0
    s["sun_size"] = 3.0
    # Colors
    s["sky_top"] = vec3(0.15, 0.3, 0.65)
    s["sky_horizon"] = vec3(0.6, 0.75, 0.9)
    s["ground_color"] = vec3(0.2, 0.18, 0.15)
    # GPU state
    s["pipeline"] = -1
    s["pipe_layout"] = -1
    s["initialized"] = false
    return s

# ============================================================================
# Presets
# ============================================================================
proc sky_preset_day(s):
    s["sun_dir"] = v3_normalize(vec3(0.3, 0.8, 0.5))
    s["sun_intensity"] = 1.0
    s["sky_top"] = vec3(0.15, 0.3, 0.65)
    s["sky_horizon"] = vec3(0.6, 0.75, 0.9)
    s["ground_color"] = vec3(0.2, 0.18, 0.15)

proc sky_preset_vibrant_day(s):
    s["sun_dir"] = v3_normalize(vec3(0.34, 0.72, 0.46))
    s["sun_intensity"] = 1.14
    s["sun_size"] = 3.9
    s["sky_top"] = vec3(0.11, 0.30, 0.78)
    s["sky_horizon"] = vec3(0.44, 0.68, 0.96)
    s["ground_color"] = vec3(0.14, 0.11, 0.09)

proc sky_preset_sunset(s):
    s["sun_dir"] = v3_normalize(vec3(0.8, 0.15, 0.3))
    s["sun_intensity"] = 1.2
    s["sky_top"] = vec3(0.1, 0.15, 0.4)
    s["sky_horizon"] = vec3(0.9, 0.5, 0.2)
    s["ground_color"] = vec3(0.15, 0.1, 0.08)

proc sky_preset_night(s):
    s["sun_dir"] = v3_normalize(vec3(0.3, -0.5, 0.5))
    s["sun_intensity"] = 0.1
    s["sky_top"] = vec3(0.01, 0.01, 0.05)
    s["sky_horizon"] = vec3(0.03, 0.04, 0.08)
    s["ground_color"] = vec3(0.02, 0.02, 0.02)

proc sky_preset_overcast(s):
    s["sun_dir"] = v3_normalize(vec3(0.3, 0.6, 0.5))
    s["sun_intensity"] = 0.2
    s["sky_top"] = vec3(0.45, 0.48, 0.52)
    s["sky_horizon"] = vec3(0.55, 0.58, 0.6)
    s["ground_color"] = vec3(0.25, 0.23, 0.2)

# ============================================================================
# Initialize GPU resources
# ============================================================================
proc init_sky_gpu(s, render_pass):
    let vert = gpu.load_shader("shaders/engine_sky.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_sky.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "ERROR: Failed to load sky shaders"
        return false

    # Push constants: 6 vec4s + mat4 = 24 + 64 = 160 bytes ... actually
    # sunDir(16) + skyTop(16) + skyHoriz(16) + ground(16) + params(16) + invViewRot(64) = 144 bytes
    let push_size = 144
    let pipe_layout = gpu.create_pipeline_layout([], push_size, gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT)

    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = render_pass
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_NONE
    cfg["front_face"] = gpu.FRONT_CCW
    cfg["depth_test"] = true
    cfg["depth_write"] = false
    cfg["vertex_bindings"] = []
    cfg["vertex_attribs"] = []
    let pipeline = gpu.create_graphics_pipeline(cfg)
    if pipeline < 0:
        print "ERROR: Failed to create sky pipeline"
        return false

    s["pipeline"] = pipeline
    s["pipe_layout"] = pipe_layout
    s["vert"] = vert
    s["frag"] = frag
    s["initialized"] = true
    print "Sky renderer initialized"
    return true

# ============================================================================
# Build inverse view rotation matrix (strip translation from view matrix)
# ============================================================================
proc extract_inv_view_rotation(view_matrix):
    # View matrix has rotation in upper-left 3x3
    # We need the inverse = transpose of the rotation part
    let m = view_matrix
    let inv = mat4_identity()
    # Transpose the 3x3 rotation
    inv[0] = m[0]
    inv[1] = m[4]
    inv[2] = m[8]
    inv[4] = m[1]
    inv[5] = m[5]
    inv[6] = m[9]
    inv[8] = m[2]
    inv[9] = m[6]
    inv[10] = m[10]
    return inv

# ============================================================================
# Draw sky (call during render, before or after geometry)
# ============================================================================
proc draw_sky(s, cmd, view_matrix, aspect, fov, time):
    if s["initialized"] == false:
        return nil

    let inv_view = extract_inv_view_rotation(view_matrix)

    gpu.cmd_bind_graphics_pipeline(cmd, s["pipeline"])

    # Pack push constants: 5 vec4s + 1 mat4 = 80 + 64 = 144 bytes (36 floats)
    let push_data = []

    # sunDir (xyz + intensity)
    push(push_data, s["sun_dir"][0])
    push(push_data, s["sun_dir"][1])
    push(push_data, s["sun_dir"][2])
    push(push_data, s["sun_intensity"])

    # skyColorTop (rgb + unused)
    push(push_data, s["sky_top"][0])
    push(push_data, s["sky_top"][1])
    push(push_data, s["sky_top"][2])
    push(push_data, 0.0)

    # skyColorHoriz (rgb + unused)
    push(push_data, s["sky_horizon"][0])
    push(push_data, s["sky_horizon"][1])
    push(push_data, s["sky_horizon"][2])
    push(push_data, 0.0)

    # groundColor (rgb + unused)
    push(push_data, s["ground_color"][0])
    push(push_data, s["ground_color"][1])
    push(push_data, s["ground_color"][2])
    push(push_data, 0.0)

    # params (aspect, fov, time, sun_size)
    push(push_data, aspect)
    push(push_data, fov)
    push(push_data, time)
    push(push_data, s["sun_size"])

    # invViewRot mat4 (16 floats)
    let vi = 0
    while vi < 16:
        push(push_data, inv_view[vi])
        vi = vi + 1

    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    gpu.cmd_push_constants(cmd, s["pipe_layout"], stage_flags, push_data)

    # Draw fullscreen triangle (3 vertices, no vertex buffer)
    gpu.cmd_draw(cmd, 3, 1, 0, 0)

# ============================================================================
# Cubemap skybox loading
# ============================================================================
proc create_cubemap_sky(face_paths):
    # face_paths = [right, left, top, bottom, front, back]
    let cm = {}
    cm["type"] = "cubemap"
    if len(face_paths) == 6:
        cm["cubemap"] = gpu.create_cubemap(face_paths[0], face_paths[1], face_paths[2], face_paths[3], face_paths[4], face_paths[5])
        cm["sampler"] = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)
    else:
        cm["cubemap"] = -1
        cm["sampler"] = -1
    return cm

proc has_cubemap_sky(cm):
    return cm["cubemap"] >= 0
