gc_disable()
# -----------------------------------------
# ui_renderer.sage - GPU UI rendering for Sage Engine
# Batches UI quads into a vertex buffer and draws them
# -----------------------------------------

import gpu
from ui_core import collect_quads, compute_layout

# ============================================================================
# UI Renderer
# ============================================================================
proc create_ui_renderer(render_pass):
    let ur = {}

    # Load shaders
    let vert = gpu.load_shader("shaders/engine_ui.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_ui.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "UI ERROR: Failed to load UI shaders"
        return nil

    # Pipeline layout: push = 16 bytes (screenSize vec2 + pad vec2)
    let pipe_layout = gpu.create_pipeline_layout([], 16, gpu.STAGE_VERTEX)

    # Vertex format: pos(2f) + uv(2f) + color(4f) = 32 bytes per vertex
    let vb = {}
    vb["binding"] = 0
    vb["stride"] = 32
    vb["rate"] = gpu.INPUT_RATE_VERTEX

    let a_pos = {}
    a_pos["location"] = 0
    a_pos["binding"] = 0
    a_pos["format"] = gpu.ATTR_VEC2
    a_pos["offset"] = 0

    let a_uv = {}
    a_uv["location"] = 1
    a_uv["binding"] = 0
    a_uv["format"] = gpu.ATTR_VEC2
    a_uv["offset"] = 8

    let a_color = {}
    a_color["location"] = 2
    a_color["binding"] = 0
    a_color["format"] = gpu.ATTR_VEC4
    a_color["offset"] = 16

    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = render_pass
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_NONE
    cfg["front_face"] = gpu.FRONT_CCW
    cfg["depth_test"] = false
    cfg["depth_write"] = false
    cfg["blend"] = true
    cfg["vertex_bindings"] = [vb]
    cfg["vertex_attribs"] = [a_pos, a_uv, a_color]
    let pipeline = gpu.create_graphics_pipeline(cfg)
    if pipeline < 0:
        print "UI ERROR: Failed to create UI pipeline"
        return nil

    # Pre-allocate vertex buffer (max 512 quads = 3072 verts = 98304 bytes)
    let max_verts = 3072
    let buf_size = max_verts * 32
    let mem = gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT
    let vbuf = gpu.create_buffer(buf_size, gpu.BUFFER_VERTEX, mem)

    ur["pipeline"] = pipeline
    ur["pipe_layout"] = pipe_layout
    ur["vbuf"] = vbuf
    ur["max_verts"] = max_verts
    ur["initialized"] = true
    print "UI renderer initialized"
    return ur

# ============================================================================
# Build vertex data from quads
# Each quad = 6 vertices (2 triangles)
# vertex = [px, py, u, v, r, g, b, a] = 8 floats
# ============================================================================
proc build_ui_vertices(quads):
    let verts = []
    let i = 0
    while i < len(quads):
        let q = quads[i]
        let x0 = q["x"]
        let y0 = q["y"]
        let x1 = x0 + q["w"]
        let y1 = y0 + q["h"]
        let cr = q["color"][0]
        let cg = q["color"][1]
        let cb = q["color"][2]
        let ca = q["color"][3]
        # Triangle 1: top-left, top-right, bottom-right
        push(verts, x0)
        push(verts, y0)
        push(verts, 0.0)
        push(verts, 0.0)
        push(verts, cr)
        push(verts, cg)
        push(verts, cb)
        push(verts, ca)

        push(verts, x1)
        push(verts, y0)
        push(verts, 1.0)
        push(verts, 0.0)
        push(verts, cr)
        push(verts, cg)
        push(verts, cb)
        push(verts, ca)

        push(verts, x1)
        push(verts, y1)
        push(verts, 1.0)
        push(verts, 1.0)
        push(verts, cr)
        push(verts, cg)
        push(verts, cb)
        push(verts, ca)

        # Triangle 2: top-left, bottom-right, bottom-left
        push(verts, x0)
        push(verts, y0)
        push(verts, 0.0)
        push(verts, 0.0)
        push(verts, cr)
        push(verts, cg)
        push(verts, cb)
        push(verts, ca)

        push(verts, x1)
        push(verts, y1)
        push(verts, 1.0)
        push(verts, 1.0)
        push(verts, cr)
        push(verts, cg)
        push(verts, cb)
        push(verts, ca)

        push(verts, x0)
        push(verts, y1)
        push(verts, 0.0)
        push(verts, 1.0)
        push(verts, cr)
        push(verts, cg)
        push(verts, cb)
        push(verts, ca)
        i = i + 1
    return verts

# ============================================================================
# Draw UI
# ============================================================================
proc draw_ui(ur, cmd, root_widget, screen_w, screen_h):
    if ur == nil or ur["initialized"] == false:
        return nil

    # Compute layout
    compute_layout(root_widget, 0.0, 0.0, screen_w, screen_h)

    # Collect quads
    let quads = []
    collect_quads(root_widget, quads)
    if len(quads) == 0:
        return nil

    # Build vertex data
    let verts = build_ui_vertices(quads)
    let vert_count = len(quads) * 6
    if vert_count > ur["max_verts"]:
        vert_count = ur["max_verts"]

    # Upload
    gpu.buffer_upload(ur["vbuf"], verts)

    # Draw
    gpu.cmd_bind_graphics_pipeline(cmd, ur["pipeline"])
    let push_data = [screen_w, screen_h, 0.0, 0.0]
    gpu.cmd_push_constants(cmd, ur["pipe_layout"], gpu.STAGE_VERTEX, push_data)
    gpu.cmd_bind_vertex_buffer(cmd, ur["vbuf"])
    gpu.cmd_draw(cmd, vert_count, 1, 0, 0)
