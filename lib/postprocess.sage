gc_disable()
# -----------------------------------------
# postprocess.sage - HDR + Bloom + Tone Mapping
# Post-processing pipeline for cinematic rendering
# -----------------------------------------

import gpu

# ============================================================================
# Tone mapping modes
# ============================================================================
let TONEMAP_REINHARD = 0
let TONEMAP_ACES = 1
let TONEMAP_UNCHARTED2 = 2
let TONEMAP_EXPOSURE = 3

# ============================================================================
# Create HDR render target (RGBA16F with depth)
# ============================================================================
proc create_hdr_target(width, height):
    return gpu.create_offscreen_target(width, height, gpu.FORMAT_RGBA16F, true)

# ============================================================================
# Create bloom pipeline components
# ============================================================================
proc create_bloom_chain(width, height, levels):
    let chain = []
    let w = width / 2
    let h = height / 2
    let i = 0
    while i < levels:
        let target = gpu.create_offscreen_target(w, h, gpu.FORMAT_RGBA16F, false)
        push(chain, target)
        w = w / 2
        if w < 1:
            w = 1
        h = h / 2
        if h < 1:
            h = 1
        i = i + 1
    return chain

# ============================================================================
# Post-process context — creates all GPU resources needed for HDR + bloom
# ============================================================================
proc create_postprocess(width, height):
    let pp = {}
    pp["width"] = width
    pp["height"] = height
    pp["hdr_target"] = create_hdr_target(width, height)
    if pp["hdr_target"] == nil:
        print "WARNING: HDR target creation failed — postprocess disabled"
        pp["enabled"] = false
        return pp
    pp["enabled"] = true

    # Bloom chain (3 levels of downsampled blur targets)
    pp["bloom_chain"] = create_bloom_chain(width, height, 3)

    # Bloom blur scratch target (same size as first bloom level)
    let bw = width / 2
    let bh = height / 2
    pp["blur_scratch"] = gpu.create_offscreen_target(bw, bh, gpu.FORMAT_RGBA16F, false)

    pp["tonemap_mode"] = TONEMAP_ACES
    pp["exposure"] = 1.2
    pp["bloom_intensity"] = 0.35
    pp["bloom_threshold"] = 0.8
    pp["bloom_knee"] = 0.3
    pp["gamma"] = 2.2
    pp["contrast"] = 1.05
    pp["saturation"] = 1.1
    pp["warmth"] = 0.0
    pp["vignette"] = 0.15

    # Sampler for reading offscreen textures
    let sampler = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)
    pp["sampler"] = sampler

    # Descriptor layouts
    # Single sampler layout (for bloom extract + blur passes)
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_COMBINED_SAMPLER
    b0["stage"] = gpu.STAGE_FRAGMENT
    b0["count"] = 1
    let single_layout = gpu.create_descriptor_layout([b0])
    pp["single_layout"] = single_layout

    # Tonemap layout (3 samplers: hdr, bloom, ssao)
    let tb0 = {}
    tb0["binding"] = 0
    tb0["type"] = gpu.DESC_COMBINED_SAMPLER
    tb0["stage"] = gpu.STAGE_FRAGMENT
    tb0["count"] = 1
    let tb1 = {}
    tb1["binding"] = 1
    tb1["type"] = gpu.DESC_COMBINED_SAMPLER
    tb1["stage"] = gpu.STAGE_FRAGMENT
    tb1["count"] = 1
    let tb2 = {}
    tb2["binding"] = 2
    tb2["type"] = gpu.DESC_COMBINED_SAMPLER
    tb2["stage"] = gpu.STAGE_FRAGMENT
    tb2["count"] = 1
    let tonemap_layout = gpu.create_descriptor_layout([tb0, tb1, tb2])
    pp["tonemap_layout"] = tonemap_layout

    # Descriptor pools and sets
    let ps0 = {}
    ps0["type"] = gpu.DESC_COMBINED_SAMPLER
    ps0["count"] = 12
    let pool = gpu.create_descriptor_pool(6, [ps0])
    pp["desc_pool"] = pool

    # Allocate descriptor sets
    pp["bloom_extract_set"] = gpu.allocate_descriptor_set(pool, single_layout)
    pp["bloom_blur_set_h"] = gpu.allocate_descriptor_set(pool, single_layout)
    pp["bloom_blur_set_v"] = gpu.allocate_descriptor_set(pool, single_layout)
    pp["tonemap_set"] = gpu.allocate_descriptor_set(pool, tonemap_layout)

    # Create 1x1 white image for dummy SSAO
    let dummy_img = gpu.create_image(1, 1, 1, gpu.FORMAT_RGBA8, gpu.IMAGE_SAMPLED | gpu.IMAGE_TRANSFER_DST)
    pp["dummy_white"] = dummy_img

    # Bind HDR image to bloom extract set
    gpu.update_descriptor_image(pp["bloom_extract_set"], 0, pp["hdr_target"]["image"], sampler)

    # Create fullscreen pipelines
    if len(pp["bloom_chain"]) > 0 and pp["bloom_chain"][0] != nil:
        pp["bloom_extract_pipe"] = _create_pp_pipeline(pp["bloom_chain"][0]["render_pass"],
                                                        single_layout, 16,
                                                        "shaders/engine_bloom_extract.frag.spv")
    else:
        pp["bloom_extract_pipe"] = nil

    if pp["blur_scratch"] != nil:
        pp["bloom_blur_pipe"] = _create_pp_pipeline(pp["blur_scratch"]["render_pass"],
                                                     single_layout, 16,
                                                     "shaders/engine_bloom_blur.frag.spv")
    else:
        pp["bloom_blur_pipe"] = nil

    return pp

# ============================================================================
# Internal: create fullscreen pipeline
# ============================================================================
proc _create_pp_pipeline(render_pass, desc_layout, push_size, frag_path):
    let vert = gpu.load_shader("shaders/engine_fullscreen.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader(frag_path, gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "ERROR: Failed to load shaders: " + frag_path
        return nil
    let pipe_layout = gpu.create_pipeline_layout([desc_layout], push_size, gpu.STAGE_ALL)
    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = render_pass
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_NONE
    cfg["depth_test"] = false
    cfg["depth_write"] = false
    let pipeline = gpu.create_graphics_pipeline(cfg)
    if pipeline < 0:
        print "ERROR: Failed to create postprocess pipeline"
        return nil
    return {"pipeline": pipeline, "pipe_layout": pipe_layout}

# ============================================================================
# Begin offscreen HDR pass — call INSTEAD of the normal begin_frame render pass
# ============================================================================
proc begin_hdr_pass(pp, cmd):
    if not pp["enabled"]:
        return
    let t = pp["hdr_target"]
    gpu.cmd_begin_render_pass(cmd, t["render_pass"], t["framebuffer"],
        [[0.0, 0.0, 0.0, 1.0], [1.0, 0.0, 0.0, 0.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, pp["width"], pp["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, pp["width"], pp["height"])

proc end_hdr_pass(cmd):
    gpu.cmd_end_render_pass(cmd)

# ============================================================================
# Execute bloom passes (extract bright → blur H → blur V)
# ============================================================================
proc execute_bloom(pp, cmd):
    if not pp["enabled"] or pp["bloom_extract_pipe"] == nil or pp["bloom_blur_pipe"] == nil:
        return
    if len(pp["bloom_chain"]) == 0 or pp["bloom_chain"][0] == nil:
        return

    let bc0 = pp["bloom_chain"][0]
    let scratch = pp["blur_scratch"]
    let sampler = pp["sampler"]

    # Pass 1: Extract bright pixels from HDR → bloom chain[0]
    gpu.cmd_begin_render_pass(cmd, bc0["render_pass"], bc0["framebuffer"],
        [[0.0, 0.0, 0.0, 1.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, bc0["width"], bc0["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, bc0["width"], bc0["height"])
    let ep = pp["bloom_extract_pipe"]
    gpu.cmd_bind_graphics_pipeline(cmd, ep["pipeline"])
    gpu.cmd_push_constants(cmd, ep["pipe_layout"], gpu.STAGE_ALL,
        [pp["bloom_threshold"], pp["bloom_knee"], 0.0, 1.2])
    gpu.cmd_bind_descriptor_set(cmd, ep["pipe_layout"], 0, pp["bloom_extract_set"], 0)
    gpu.cmd_draw(cmd, 3, 1, 0, 0)
    gpu.cmd_end_render_pass(cmd)

    # Pass 2: Horizontal blur (bloom chain[0] → scratch)
    gpu.update_descriptor_image(pp["bloom_blur_set_h"], 0, bc0["image"], sampler)
    gpu.cmd_begin_render_pass(cmd, scratch["render_pass"], scratch["framebuffer"],
        [[0.0, 0.0, 0.0, 1.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, scratch["width"], scratch["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, scratch["width"], scratch["height"])
    let bp = pp["bloom_blur_pipe"]
    gpu.cmd_bind_graphics_pipeline(cmd, bp["pipeline"])
    let tx = 1.0 / bc0["width"]
    let ty = 1.0 / bc0["height"]
    gpu.cmd_push_constants(cmd, bp["pipe_layout"], gpu.STAGE_ALL,
        [tx, ty, 1.0, 1.0])
    gpu.cmd_bind_descriptor_set(cmd, bp["pipe_layout"], 0, pp["bloom_blur_set_h"], 0)
    gpu.cmd_draw(cmd, 3, 1, 0, 0)
    gpu.cmd_end_render_pass(cmd)

    # Pass 3: Vertical blur (scratch → bloom chain[0])
    gpu.update_descriptor_image(pp["bloom_blur_set_v"], 0, scratch["image"], sampler)
    gpu.cmd_begin_render_pass(cmd, bc0["render_pass"], bc0["framebuffer"],
        [[0.0, 0.0, 0.0, 1.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, bc0["width"], bc0["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, bc0["width"], bc0["height"])
    gpu.cmd_bind_graphics_pipeline(cmd, bp["pipeline"])
    gpu.cmd_push_constants(cmd, bp["pipe_layout"], gpu.STAGE_ALL,
        [tx, ty, 0.0, 1.0])
    gpu.cmd_bind_descriptor_set(cmd, bp["pipe_layout"], 0, pp["bloom_blur_set_v"], 0)
    gpu.cmd_draw(cmd, 3, 1, 0, 0)
    gpu.cmd_end_render_pass(cmd)

# ============================================================================
# Create tonemap pipeline for the swapchain render pass
# ============================================================================
proc create_tonemap_pipeline(pp, swapchain_render_pass):
    if not pp["enabled"]:
        return nil
    pp["tonemap_pipe"] = _create_pp_pipeline(swapchain_render_pass,
                                              pp["tonemap_layout"], 32,
                                              "shaders/engine_tonemap.frag.spv")
    if pp["tonemap_pipe"] == nil:
        print "WARNING: Tonemap pipeline failed"
        return nil

    # Bind tonemap descriptor set: hdr scene + bloom + dummy ssao
    let bloom_img = pp["dummy_white"]
    if len(pp["bloom_chain"]) > 0 and pp["bloom_chain"][0] != nil:
        bloom_img = pp["bloom_chain"][0]["image"]

    let sampler = pp["sampler"]
    gpu.update_descriptor_image(pp["tonemap_set"], 0, pp["hdr_target"]["image"], sampler)
    gpu.update_descriptor_image(pp["tonemap_set"], 1, bloom_img, sampler)
    gpu.update_descriptor_image(pp["tonemap_set"], 2, pp["dummy_white"], sampler)

    return pp["tonemap_pipe"]

# ============================================================================
# Draw tonemap composite pass (call inside the swapchain render pass)
# ============================================================================
proc draw_tonemap(pp, cmd):
    if not pp["enabled"] or pp["tonemap_pipe"] == nil:
        return
    let tp = pp["tonemap_pipe"]
    gpu.cmd_bind_graphics_pipeline(cmd, tp["pipeline"])
    # params0: exposure, bloom_strength, tonemap_mode, gamma
    # params1: contrast, saturation, warmth, vignette_strength
    gpu.cmd_push_constants(cmd, tp["pipe_layout"], gpu.STAGE_ALL,
        [pp["exposure"], pp["bloom_intensity"], pp["tonemap_mode"], pp["gamma"],
         pp["contrast"], pp["saturation"], pp["warmth"], pp["vignette"]])
    gpu.cmd_bind_descriptor_set(cmd, tp["pipe_layout"], 0, pp["tonemap_set"], 0)
    gpu.cmd_draw(cmd, 3, 1, 0, 0)

# ============================================================================
# Convenience: full post-process pass (bloom + tonemap in swapchain)
# Call after end_hdr_pass, before end_frame's render pass
# ============================================================================
proc apply_postprocess(pp, cmd):
    if not pp["enabled"]:
        return
    execute_bloom(pp, cmd)

# ============================================================================
# Fullscreen pass infrastructure (legacy API)
# ============================================================================
proc create_fullscreen_pipeline(render_pass, desc_layout, push_size, frag_shader_path):
    return _create_pp_pipeline(render_pass, desc_layout, push_size, frag_shader_path)

proc draw_fullscreen(cmd, fp, push_data, desc_set):
    gpu.cmd_bind_graphics_pipeline(cmd, fp["pipeline"])
    gpu.cmd_push_constants(cmd, fp["pipe_layout"], gpu.STAGE_ALL, push_data)
    if desc_set >= 0:
        gpu.cmd_bind_descriptor_set(cmd, fp["pipe_layout"], 0, desc_set, 0)
    gpu.cmd_draw(cmd, 3, 1, 0, 0)

# ============================================================================
# Convenience
# ============================================================================
proc create_postprocess_target(width, height, hdr):
    let format = gpu.FORMAT_RGBA8
    if hdr:
        format = gpu.FORMAT_RGBA16F
    return gpu.create_offscreen_target(width, height, format, true)

proc tonemap_params(pp):
    return [pp["exposure"], pp["bloom_intensity"], pp["bloom_threshold"], pp["tonemap_mode"]]
