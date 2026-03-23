gc_disable()
# -----------------------------------------
# editor_grid.sage - Infinite ground grid for Sage Engine Editor
# Unreal-style dark viewport with grid lines and axis colors
# -----------------------------------------

import gpu

proc create_editor_grid(render_pass):
    let g = {}
    # Load shaders
    let vert = gpu.load_shader("shaders/engine_grid.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_grid.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "GRID ERROR: Failed to load grid shaders"
        return nil
    # Push constants: mat4 viewProj (64) + vec4 params (16) = 80 bytes
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    let pipe_layout = gpu.create_pipeline_layout([], 80, stage_flags)
    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = render_pass
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_NONE
    cfg["front_face"] = gpu.FRONT_CCW
    cfg["depth_test"] = true
    cfg["depth_write"] = true
    cfg["vertex_bindings"] = []
    cfg["vertex_attribs"] = []
    let pipeline = gpu.create_graphics_pipeline(cfg)
    if pipeline < 0:
        print "GRID ERROR: Failed to create grid pipeline"
        return nil
    g["pipeline"] = pipeline
    g["pipe_layout"] = pipe_layout
    g["grid_size"] = 1.0
    g["fade_start"] = 30.0
    g["fade_end"] = 80.0
    g["line_width"] = 0.02
    g["initialized"] = true
    return g

proc draw_editor_grid(g, cmd, vp_matrix):
    if g == nil or g["initialized"] == false:
        return nil
    gpu.cmd_bind_graphics_pipeline(cmd, g["pipeline"])
    # Pack push constants: mat4 (16 floats) + vec4 params (4 floats) = 20 floats
    let pc = []
    let i = 0
    while i < 16:
        push(pc, vp_matrix[i])
        i = i + 1
    push(pc, g["grid_size"])
    push(pc, g["fade_start"])
    push(pc, g["fade_end"])
    push(pc, g["line_width"])
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    gpu.cmd_push_constants(cmd, g["pipe_layout"], stage_flags, pc)
    # Draw 6 vertices (fullscreen ground quad, no vertex buffer)
    gpu.cmd_draw(cmd, 6, 1, 0, 0)
