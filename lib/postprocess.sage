gc_disable()
# -----------------------------------------
# postprocess.sage - HDR scene buffer + bloom + tonemap composite
# Used by the voxel sandbox and editor preview to push the look closer to
# Minecraft-style shader packs: brighter skies, bloom, and graded color.
# -----------------------------------------

import gpu

let TONEMAP_REINHARD = 0
let TONEMAP_ACES = 1
let TONEMAP_UNCHARTED2 = 2

proc bloom_dimensions(width, height):
    let bw = width / 2
    let bh = height / 2
    if bw < 1:
        bw = 1
    if bh < 1:
        bh = 1
    return [bw, bh]

proc build_bloom_extract_push_data(pp):
    return [pp["bloom_threshold"], pp["bloom_soft_knee"], 1.0, pp["highlight_saturation"]]

proc build_bloom_blur_push_data(pp, horizontal):
    let dir = 0.0
    if horizontal:
        dir = 1.0
    return [1.0 / pp["bloom_width"], 1.0 / pp["bloom_height"], dir, pp["bloom_radius"]]

proc build_tonemap_push_data(pp):
    return [
        pp["exposure"],
        pp["bloom_intensity"],
        pp["tonemap_mode"],
        pp["gamma"],
        pp["contrast"],
        pp["saturation"],
        pp["warmth"],
        pp["vignette_strength"]
    ]

proc create_postprocess_target(width, height, hdr, with_depth):
    let format = gpu.FORMAT_RGBA8
    if hdr:
        format = gpu.FORMAT_RGBA16F
    return gpu.create_offscreen_target(width, height, format, with_depth)

proc create_hdr_target(width, height):
    return create_postprocess_target(width, height, true, true)

proc _destroy_target(target):
    if target == nil:
        return
    if dict_has(target, "framebuffer") and target["framebuffer"] != nil and target["framebuffer"] >= 0:
        gpu.destroy_framebuffer(target["framebuffer"])
    if dict_has(target, "render_pass") and target["render_pass"] != nil and target["render_pass"] >= 0:
        gpu.destroy_render_pass(target["render_pass"])
    if dict_has(target, "depth") and target["depth"] != nil and target["depth"] >= 0:
        gpu.destroy_image(target["depth"])
    if dict_has(target, "image") and target["image"] != nil and target["image"] >= 0:
        gpu.destroy_image(target["image"])

proc _destroy_fullscreen_pipeline(fp):
    if fp == nil:
        return
    if dict_has(fp, "pipeline") and fp["pipeline"] != nil and fp["pipeline"] >= 0:
        gpu.destroy_pipeline(fp["pipeline"])
    if dict_has(fp, "vert") and fp["vert"] != nil and fp["vert"] >= 0:
        gpu.destroy_shader(fp["vert"])
    if dict_has(fp, "frag") and fp["frag"] != nil and fp["frag"] >= 0:
        gpu.destroy_shader(fp["frag"])

proc destroy_postprocess(pp):
    if pp == nil:
        return
    _destroy_fullscreen_pipeline(pp["extract_pipeline"])
    _destroy_fullscreen_pipeline(pp["blur_pipeline_a"])
    _destroy_fullscreen_pipeline(pp["blur_pipeline_b"])
    _destroy_fullscreen_pipeline(pp["tonemap_pipeline"])
    _destroy_target(pp["scene_target"])
    _destroy_target(pp["bloom_a"])
    _destroy_target(pp["bloom_b"])
    if dict_has(pp, "sampler") and pp["sampler"] != nil and pp["sampler"] >= 0:
        gpu.destroy_sampler(pp["sampler"])

proc _create_single_sampler_layout():
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_COMBINED_SAMPLER
    b0["stage"] = gpu.STAGE_FRAGMENT
    b0["count"] = 1
    return gpu.create_descriptor_layout([b0])

proc _create_dual_sampler_layout():
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_COMBINED_SAMPLER
    b0["stage"] = gpu.STAGE_FRAGMENT
    b0["count"] = 1
    let b1 = {}
    b1["binding"] = 1
    b1["type"] = gpu.DESC_COMBINED_SAMPLER
    b1["stage"] = gpu.STAGE_FRAGMENT
    b1["count"] = 1
    return gpu.create_descriptor_layout([b0, b1])

proc create_fullscreen_pipeline(render_pass, desc_layout, push_size, frag_shader_path):
    let vert = gpu.load_shader("shaders/engine_fullscreen.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader(frag_shader_path, gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "ERROR: Failed to load fullscreen shaders: " + frag_shader_path
        return nil
    let pipe_layout = gpu.create_pipeline_layout([desc_layout], push_size, gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT)
    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = render_pass
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_NONE
    cfg["depth_test"] = false
    cfg["depth_write"] = false
    cfg["vertex_bindings"] = []
    cfg["vertex_attribs"] = []
    let pipeline = gpu.create_graphics_pipeline(cfg)
    if pipeline < 0:
        print "ERROR: Failed to create fullscreen pipeline"
        return nil
    let result = {}
    result["pipeline"] = pipeline
    result["pipe_layout"] = pipe_layout
    result["vert"] = vert
    result["frag"] = frag
    return result

proc draw_fullscreen(cmd, fp, push_data, desc_set):
    gpu.cmd_bind_graphics_pipeline(cmd, fp["pipeline"])
    gpu.cmd_push_constants(cmd, fp["pipe_layout"], gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT, push_data)
    if desc_set >= 0:
        gpu.cmd_bind_descriptor_set(cmd, fp["pipe_layout"], 0, desc_set, 0)
    gpu.cmd_draw(cmd, 3, 1, 0, 0)

proc _refresh_postprocess_descriptors(pp):
    gpu.update_descriptor_image(pp["extract_set"], 0, pp["scene_target"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["blur_a_set"], 0, pp["bloom_a"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["blur_b_set"], 0, pp["bloom_b"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["tonemap_set"], 0, pp["scene_target"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["tonemap_set"], 1, pp["bloom_a"]["image"], pp["sampler"])

proc pfx_shaderpack_day(pp):
    pp["tonemap_mode"] = TONEMAP_ACES
    pp["exposure"] = 0.92
    pp["gamma"] = 2.2
    pp["contrast"] = 1.12
    pp["saturation"] = 1.20
    pp["warmth"] = 0.03
    pp["vignette_strength"] = 0.08
    pp["bloom_enabled"] = true
    pp["bloom_intensity"] = 0.22
    pp["bloom_threshold"] = 0.88
    pp["bloom_soft_knee"] = 0.22
    pp["bloom_radius"] = 1.0
    pp["highlight_saturation"] = 1.04

proc pfx_editor_preview(pp):
    pfx_shaderpack_day(pp)
    pp["exposure"] = 0.86
    pp["contrast"] = 1.08
    pp["saturation"] = 1.15
    pp["warmth"] = 0.01
    pp["bloom_intensity"] = 0.14
    pp["bloom_threshold"] = 0.98
    pp["vignette_strength"] = 0.05

proc create_postprocess(width, height, swapchain_render_pass):
    let pp = {}
    let dims = bloom_dimensions(width, height)
    pp["width"] = width
    pp["height"] = height
    pp["bloom_width"] = dims[0]
    pp["bloom_height"] = dims[1]
    pp["scene_target"] = create_hdr_target(width, height)
    pp["bloom_a"] = create_postprocess_target(pp["bloom_width"], pp["bloom_height"], true, false)
    pp["bloom_b"] = create_postprocess_target(pp["bloom_width"], pp["bloom_height"], true, false)
    pp["sampler"] = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)

    pp["single_layout"] = _create_single_sampler_layout()
    let ps0 = {}
    ps0["type"] = gpu.DESC_COMBINED_SAMPLER
    ps0["count"] = 3
    pp["single_pool"] = gpu.create_descriptor_pool(3, [ps0])
    pp["extract_set"] = gpu.allocate_descriptor_set(pp["single_pool"], pp["single_layout"])
    pp["blur_a_set"] = gpu.allocate_descriptor_set(pp["single_pool"], pp["single_layout"])
    pp["blur_b_set"] = gpu.allocate_descriptor_set(pp["single_pool"], pp["single_layout"])

    pp["dual_layout"] = _create_dual_sampler_layout()
    let ps1 = {}
    ps1["type"] = gpu.DESC_COMBINED_SAMPLER
    ps1["count"] = 2
    pp["dual_pool"] = gpu.create_descriptor_pool(1, [ps1])
    pp["tonemap_set"] = gpu.allocate_descriptor_set(pp["dual_pool"], pp["dual_layout"])

    pfx_shaderpack_day(pp)
    _refresh_postprocess_descriptors(pp)

    pp["extract_pipeline"] = create_fullscreen_pipeline(pp["bloom_a"]["render_pass"], pp["single_layout"], 16, "shaders/engine_bloom_extract.frag.spv")
    pp["blur_pipeline_a"] = create_fullscreen_pipeline(pp["bloom_b"]["render_pass"], pp["single_layout"], 16, "shaders/engine_bloom_blur.frag.spv")
    pp["blur_pipeline_b"] = create_fullscreen_pipeline(pp["bloom_a"]["render_pass"], pp["single_layout"], 16, "shaders/engine_bloom_blur.frag.spv")
    pp["tonemap_pipeline"] = create_fullscreen_pipeline(swapchain_render_pass, pp["dual_layout"], 32, "shaders/engine_tonemap.frag.spv")
    return pp

proc recreate_postprocess(pp, width, height, swapchain_render_pass):
    destroy_postprocess(pp)
    return create_postprocess(width, height, swapchain_render_pass)

proc begin_scene_pass(pp, cmd, clear_color):
    let cc = [0.02, 0.03, 0.06, 1.0]
    if clear_color != nil:
        cc = clear_color
    gpu.cmd_begin_render_pass(cmd, pp["scene_target"]["render_pass"], pp["scene_target"]["framebuffer"], [cc, [1.0, 0.0, 0.0, 0.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, pp["width"], pp["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, pp["width"], pp["height"])

proc end_scene_pass(cmd):
    gpu.cmd_end_render_pass(cmd)

proc _draw_post_target(cmd, target, fp, push_data, desc_set):
    gpu.cmd_begin_render_pass(cmd, target["render_pass"], target["framebuffer"], [[0.0, 0.0, 0.0, 1.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, target["width"], target["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, target["width"], target["height"])
    draw_fullscreen(cmd, fp, push_data, desc_set)
    gpu.cmd_end_render_pass(cmd)

proc run_bloom_chain(pp, cmd):
    if pp == nil or pp["bloom_enabled"] == false:
        return false
    _draw_post_target(cmd, pp["bloom_a"], pp["extract_pipeline"], build_bloom_extract_push_data(pp), pp["extract_set"])
    _draw_post_target(cmd, pp["bloom_b"], pp["blur_pipeline_a"], build_bloom_blur_push_data(pp, true), pp["blur_a_set"])
    _draw_post_target(cmd, pp["bloom_a"], pp["blur_pipeline_b"], build_bloom_blur_push_data(pp, false), pp["blur_b_set"])
    return true

proc draw_tonemap(cmd, pp):
    draw_fullscreen(cmd, pp["tonemap_pipeline"], build_tonemap_push_data(pp), pp["tonemap_set"])
