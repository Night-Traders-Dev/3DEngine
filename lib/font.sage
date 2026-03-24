gc_disable()
# -----------------------------------------
# font.sage - TrueType font rendering for Forge Engine
# Uses gpu.load_font (stb_truetype) for rasterization
# Renders text as textured quads with proper anti-aliasing
# -----------------------------------------

import gpu

# ============================================================================
# Font renderer (manages pipeline + descriptor for font atlas texture)
# ============================================================================
proc create_font_renderer(render_pass):
    let fr = {}
    # Text shader (samples font atlas)
    let vert = gpu.load_shader("shaders/engine_ui_text.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_ui_text.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "FONT ERROR: Failed to load text shaders"
        return nil

    # Descriptor layout: binding 0 = font atlas sampler
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_COMBINED_SAMPLER
    b0["stage"] = gpu.STAGE_FRAGMENT
    b0["count"] = 1
    let desc_layout = gpu.create_descriptor_layout([b0])

    # Pipeline: push = 16 bytes (screenSize + pad), blend enabled
    let pipe_layout = gpu.create_pipeline_layout([desc_layout], 16, gpu.STAGE_VERTEX)

    # Vertex: pos(2f) + uv(2f) + color(4f) = 32 bytes
    let vb = {}
    vb["binding"] = 0
    vb["stride"] = 32
    vb["rate"] = gpu.INPUT_RATE_VERTEX
    let a0 = {}
    a0["location"] = 0
    a0["binding"] = 0
    a0["format"] = gpu.ATTR_VEC2
    a0["offset"] = 0
    let a1 = {}
    a1["location"] = 1
    a1["binding"] = 0
    a1["format"] = gpu.ATTR_VEC2
    a1["offset"] = 8
    let a2 = {}
    a2["location"] = 2
    a2["binding"] = 0
    a2["format"] = gpu.ATTR_VEC4
    a2["offset"] = 16

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
    cfg["vertex_attribs"] = [a0, a1, a2]
    let pipeline = gpu.create_graphics_pipeline(cfg)
    if pipeline < 0:
        print "FONT ERROR: Failed to create text pipeline"
        return nil

    # Descriptor pool (max 4 fonts)
    let ps = {}
    ps["type"] = gpu.DESC_COMBINED_SAMPLER
    ps["count"] = 4
    let pool = gpu.create_descriptor_pool(4, [ps])

    # Vertex buffer (max 512 chars = 3072 verts = 98304 bytes)
    let mem = gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT
    let vbuf = gpu.create_buffer(98304, gpu.BUFFER_VERTEX, mem)

    fr["pipeline"] = pipeline
    fr["pipe_layout"] = pipe_layout
    fr["desc_layout"] = desc_layout
    fr["pool"] = pool
    fr["vbuf"] = vbuf
    fr["fonts"] = {}
    fr["initialized"] = true
    return fr

# ============================================================================
# Load a font (TTF file at specified pixel size)
# ============================================================================
proc load_font(fr, name, ttf_path, pixel_size):
    let handle = gpu.load_font(ttf_path, pixel_size)
    if handle < 0:
        print "FONT ERROR: Failed to load font '" + name + "'"
        return nil
    let atlas = gpu.font_atlas(handle)
    if atlas == nil:
        return nil
    # Create descriptor set and bind font texture
    let ds = gpu.allocate_descriptor_set(fr["pool"], fr["desc_layout"])
    gpu.update_descriptor_image(ds, 0, atlas["texture"], atlas["sampler"])
    let font = {}
    font["handle"] = handle
    font["desc_set"] = ds
    font["atlas"] = atlas
    font["pixel_size"] = pixel_size
    fr["fonts"][name] = font
    return font

# ============================================================================
# Draw text using loaded font
# ============================================================================
proc draw_text(fr, cmd, font_name, text, x, y, r, g, b, a, screen_w, screen_h):
    if fr == nil or fr["initialized"] == false:
        return nil
    if dict_has(fr["fonts"], font_name) == false:
        return nil
    let font = fr["fonts"][font_name]
    # Get vertex data from native font rasterizer
    let verts = gpu.font_text_verts(font["handle"], text, x, y, r, g, b, a)
    if verts == nil or len(verts) == 0:
        return nil
    let vert_count = len(verts) / 8
    if vert_count > 3072:
        vert_count = 3072
    # Upload and draw
    gpu.buffer_upload(fr["vbuf"], verts)
    gpu.cmd_bind_graphics_pipeline(cmd, fr["pipeline"])
    gpu.cmd_bind_descriptor_set(cmd, fr["pipe_layout"], 0, font["desc_set"])
    let pc = [screen_w, screen_h, 0.0, 0.0]
    gpu.cmd_push_constants(cmd, fr["pipe_layout"], gpu.STAGE_VERTEX, pc)
    gpu.cmd_bind_vertex_buffer(cmd, fr["vbuf"])
    gpu.cmd_draw(cmd, vert_count, 1, 0, 0)

# ============================================================================
# Measure text
# ============================================================================
proc measure_font_text(fr, font_name, text):
    if dict_has(fr["fonts"], font_name) == false:
        return [0.0, 0.0]
    let font = fr["fonts"][font_name]
    let m = gpu.font_measure(font["handle"], text)
    if m == nil:
        return [0.0, 0.0]
    return [m["width"], m["height"]]
