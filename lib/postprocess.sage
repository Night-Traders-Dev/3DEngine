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

# Pseudo-random for noise generation
let _pseed = [12345.6789]

proc _prand():
    _pseed[0] = _pseed[0] * 1103515245.0 + 12345.0
    _pseed[0] = _pseed[0] - math.floor(_pseed[0] / 2147483648.0) * 2147483648.0
    return _pseed[0] / 2147483648.0

proc bloom_dimensions(width, height):
    let bw = width / 2
    let bh = height / 2
    if bw < 1:
        bw = 1
    if bh < 1:
        bh = 1
    return [bw, bh]

proc create_ssao_context(width, height):
    let ssao = {}
    ssao["width"] = width
    ssao["height"] = height
    ssao["target"] = create_postprocess_target(width, height, false, false)  # R8 format
    ssao["blur_target"] = create_postprocess_target(width, height, false, false)
    ssao["kernel_size"] = 32
    ssao["radius"] = 0.5
    ssao["bias"] = 0.025
    ssao["power"] = 2.0

    # Generate SSAO kernel (hemisphere samples)
    let kernel = []
    let i = 0
    while i < 32:
        let scale = i / 32.0
        scale = 0.1 + scale * scale * 0.9
        push(kernel, scale)
        i = i + 1
    ssao["kernel_scales"] = kernel
    return ssao

proc pack_ssao_params(ssao, projection, inv_projection, width, height):
    let data = []
    # Projection matrix (16 floats)
    let i = 0
    while i < 16:
        push(data, projection[i])
        i = i + 1
    # Inverse projection matrix (16 floats)
    i = 0
    while i < 16:
        push(data, inv_projection[i])
        i = i + 1
    # Params (4 floats)
    push(data, ssao["radius"])
    push(data, ssao["bias"])
    push(data, ssao["power"])
    push(data, ssao["kernel_size"])
    # Screen size (2 floats)
    push(data, width)
    push(data, height)
    return data

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

proc scene_pass_clear_values(clear_color):
    let cc = [0.02, 0.03, 0.06, 1.0]
    if clear_color != nil:
        cc = clear_color
    return [cc, [1.0, 0.0, 0.0, 0.0]]

proc scene_pass_load_values():
    return [[0.0, 0.0, 0.0, 1.0], [1.0, 0.0, 0.0, 0.0]]

proc _scene_color_attachment(format, load_op, initial_layout):
    let attach = {}
    attach["format"] = format
    attach["load_op"] = load_op
    attach["store_op"] = gpu.STORE_STORE
    attach["initial_layout"] = initial_layout
    attach["final_layout"] = gpu.LAYOUT_SHADER_READ
    return attach

proc _scene_depth_attachment(load_op, initial_layout):
    let attach = {}
    attach["format"] = gpu.FORMAT_DEPTH32F
    attach["load_op"] = load_op
    attach["store_op"] = gpu.STORE_STORE
    attach["initial_layout"] = initial_layout
    attach["final_layout"] = gpu.LAYOUT_DEPTH_ATTACH
    return attach

proc create_postprocess_target(width, height, hdr, with_depth):
    let format = gpu.FORMAT_RGBA8
    if hdr:
        format = gpu.FORMAT_RGBA16F
    return gpu.create_offscreen_target(width, height, format, with_depth)

proc create_hdr_target(width, height):
    return create_postprocess_target(width, height, true, true)

proc create_scene_target(width, height):
    let target = {}
    target["image"] = gpu.create_image(width, height, 1, gpu.FORMAT_RGBA16F, gpu.IMAGE_COLOR_ATTACH | gpu.IMAGE_SAMPLED)
    target["depth"] = gpu.create_image(width, height, 1, gpu.FORMAT_DEPTH32F, gpu.IMAGE_DEPTH_ATTACH)
    target["render_pass"] = gpu.create_render_pass([
        _scene_color_attachment(gpu.FORMAT_RGBA16F, gpu.LOAD_CLEAR, gpu.LAYOUT_UNDEFINED),
        _scene_depth_attachment(gpu.LOAD_CLEAR, gpu.LAYOUT_UNDEFINED)
    ])
    target["framebuffer"] = gpu.create_framebuffer(target["render_pass"], [target["image"], target["depth"]], width, height)
    target["load_render_pass"] = gpu.create_render_pass([
        _scene_color_attachment(gpu.FORMAT_RGBA16F, gpu.LOAD_LOAD, gpu.LAYOUT_SHADER_READ),
        _scene_depth_attachment(gpu.LOAD_LOAD, gpu.LAYOUT_DEPTH_ATTACH)
    ])
    target["load_framebuffer"] = gpu.create_framebuffer(target["load_render_pass"], [target["image"], target["depth"]], width, height)
    target["width"] = width
    target["height"] = height
    return target

proc _destroy_target(target):
    if target == nil:
        return
    if dict_has(target, "load_framebuffer") and target["load_framebuffer"] != nil and target["load_framebuffer"] >= 0:
        gpu.destroy_framebuffer(target["load_framebuffer"])
    if dict_has(target, "load_render_pass") and target["load_render_pass"] != nil and target["load_render_pass"] >= 0:
        gpu.destroy_render_pass(target["load_render_pass"])
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
    _destroy_fullscreen_pipeline(pp["copy_pipeline"])
    _destroy_fullscreen_pipeline(pp["extract_pipeline"])
    _destroy_fullscreen_pipeline(pp["blur_pipeline_a"])
    _destroy_fullscreen_pipeline(pp["blur_pipeline_b"])
    _destroy_fullscreen_pipeline(pp["tonemap_pipeline"])
    _destroy_target(pp["scene_target"])
    _destroy_target(pp["scene_copy"])
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

proc _create_triple_sampler_layout():
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
    let b2 = {}
    b2["binding"] = 2
    b2["type"] = gpu.DESC_COMBINED_SAMPLER
    b2["stage"] = gpu.STAGE_FRAGMENT
    b2["count"] = 1
    return gpu.create_descriptor_layout([b0, b1, b2])

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
    if push_data != nil and len(push_data) > 0:
        gpu.cmd_push_constants(cmd, fp["pipe_layout"], gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT, push_data)
    if desc_set >= 0:
        gpu.cmd_bind_descriptor_set(cmd, fp["pipe_layout"], 0, desc_set, 0)
    gpu.cmd_draw(cmd, 3, 1, 0, 0)

proc _refresh_postprocess_descriptors(pp):
    gpu.update_descriptor_image(pp["scene_copy_set"], 0, pp["scene_target"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["extract_set"], 0, pp["scene_target"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["blur_a_set"], 0, pp["bloom_a"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["blur_b_set"], 0, pp["bloom_b"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["tonemap_set"], 0, pp["scene_target"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["tonemap_set"], 1, pp["bloom_a"]["image"], pp["sampler"])
    gpu.update_descriptor_image(pp["tonemap_set"], 2, pp["ssao"]["blur_target"]["image"], pp["sampler"])
    # SSAO descriptors
    gpu.update_descriptor_image(pp["ssao_set"], 0, pp["scene_target"]["depth"], pp["sampler"])
    gpu.update_descriptor_image(pp["ssao_set"], 1, pp["ssao_noise"], pp["sampler"])
    gpu.update_descriptor_image(pp["ssao_blur_set"], 0, pp["ssao"]["target"]["image"], pp["sampler"])

proc pfx_shaderpack_day(pp):
    pp["tonemap_mode"] = TONEMAP_ACES
    pp["exposure"] = 0.84
    pp["gamma"] = 2.2
    pp["contrast"] = 1.18
    pp["saturation"] = 1.28
    pp["warmth"] = 0.05
    pp["vignette_strength"] = 0.08
    pp["bloom_enabled"] = true
    pp["bloom_intensity"] = 0.18
    pp["bloom_threshold"] = 0.94
    pp["bloom_soft_knee"] = 0.18
    pp["bloom_radius"] = 1.1
    pp["highlight_saturation"] = 1.10
    pp["ssao_enabled"] = true

proc pfx_editor_preview(pp):
    pfx_shaderpack_day(pp)
    pp["exposure"] = 0.80
    pp["contrast"] = 1.12
    pp["saturation"] = 1.18
    pp["warmth"] = 0.01
    pp["bloom_intensity"] = 0.12
    pp["bloom_threshold"] = 1.02
    pp["vignette_strength"] = 0.05

proc create_postprocess(width, height, swapchain_render_pass):
    let pp = {}
    let dims = bloom_dimensions(width, height)
    pp["width"] = width
    pp["height"] = height
    pp["bloom_width"] = dims[0]
    pp["bloom_height"] = dims[1]
    pp["scene_target"] = create_scene_target(width, height)
    pp["scene_copy"] = create_postprocess_target(width, height, true, false)
    pp["bloom_a"] = create_postprocess_target(pp["bloom_width"], pp["bloom_height"], true, false)
    pp["bloom_b"] = create_postprocess_target(pp["bloom_width"], pp["bloom_height"], true, false)
    pp["ssao"] = create_ssao_context(width, height)
    pp["sampler"] = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)

    pp["single_layout"] = _create_single_sampler_layout()
    let ps0 = {}
    ps0["type"] = gpu.DESC_COMBINED_SAMPLER
    ps0["count"] = 4
    pp["single_pool"] = gpu.create_descriptor_pool(4, [ps0])
    pp["scene_copy_set"] = gpu.allocate_descriptor_set(pp["single_pool"], pp["single_layout"])
    pp["extract_set"] = gpu.allocate_descriptor_set(pp["single_pool"], pp["single_layout"])
    pp["blur_a_set"] = gpu.allocate_descriptor_set(pp["single_pool"], pp["single_layout"])
    pp["blur_b_set"] = gpu.allocate_descriptor_set(pp["single_pool"], pp["single_layout"])

    pp["dual_layout"] = _create_dual_sampler_layout()
    let ps1 = {}
    ps1["type"] = gpu.DESC_COMBINED_SAMPLER
    ps1["count"] = 2
    pp["dual_pool"] = gpu.create_descriptor_pool(1, [ps1])
    pp["tonemap_set"] = gpu.allocate_descriptor_set(pp["dual_pool"], pp["dual_layout"])

    # Triple layout for tonemap (scene, bloom, ssao)
    pp["triple_layout"] = _create_triple_sampler_layout()
    let ps3 = {}
    ps3["type"] = gpu.DESC_COMBINED_SAMPLER
    ps3["count"] = 3
    pp["triple_pool"] = gpu.create_descriptor_pool(1, [ps3])
    pp["tonemap_set"] = gpu.allocate_descriptor_set(pp["triple_pool"], pp["triple_layout"])

    # SSAO descriptors
    pp["ssao_layout"] = _create_single_sampler_layout()
    let ps2 = {}
    ps2["type"] = gpu.DESC_COMBINED_SAMPLER
    ps2["count"] = 2
    pp["ssao_pool"] = gpu.create_descriptor_pool(2, [ps2])
    pp["ssao_set"] = gpu.allocate_descriptor_set(pp["ssao_pool"], pp["ssao_layout"])
    pp["ssao_blur_set"] = gpu.allocate_descriptor_set(pp["ssao_pool"], pp["ssao_layout"])

    # SSAO noise texture (4x4 random rotations)
    let noise_data = []
    let i = 0
    while i < 16:
        push(noise_data, _prand() * 2.0 - 1.0)
        push(noise_data, _prand() * 2.0 - 1.0)
        push(noise_data, 0.0)
        push(1.0)
        i = i + 1
    pp["ssao_noise"] = gpu.create_image(4, 4, 1, gpu.FORMAT_RGBA16F, gpu.IMAGE_SAMPLED, noise_data)

    pfx_shaderpack_day(pp)
    _refresh_postprocess_descriptors(pp)

    pp["copy_pipeline"] = create_fullscreen_pipeline(pp["scene_copy"]["render_pass"], pp["single_layout"], 0, "shaders/engine_scene_copy.frag.spv")
    pp["extract_pipeline"] = create_fullscreen_pipeline(pp["bloom_a"]["render_pass"], pp["single_layout"], 16, "shaders/engine_bloom_extract.frag.spv")
    pp["blur_pipeline_a"] = create_fullscreen_pipeline(pp["bloom_b"]["render_pass"], pp["single_layout"], 16, "shaders/engine_bloom_blur.frag.spv")
    pp["blur_pipeline_b"] = create_fullscreen_pipeline(pp["bloom_a"]["render_pass"], pp["single_layout"], 16, "shaders/engine_bloom_blur.frag.spv")
    pp["tonemap_pipeline"] = create_fullscreen_pipeline(swapchain_render_pass, pp["triple_layout"], 32, "shaders/engine_tonemap.frag.spv")

    # SSAO pipelines (assuming shaders exist)
    pp["ssao_pipeline"] = create_fullscreen_pipeline(pp["ssao"]["target"]["render_pass"], pp["ssao_layout"], 32 + 64 + 16 + 8, "shaders/engine_ssao_forward.frag.spv")
    pp["ssao_blur_pipeline"] = create_fullscreen_pipeline(pp["ssao"]["blur_target"]["render_pass"], pp["ssao_layout"], 0, "shaders/engine_ssao_blur.frag.spv")

    return pp

proc recreate_postprocess(pp, width, height, swapchain_render_pass):
    destroy_postprocess(pp)
    return create_postprocess(width, height, swapchain_render_pass)

proc begin_scene_pass(pp, cmd, clear_color):
    gpu.cmd_begin_render_pass(cmd, pp["scene_target"]["render_pass"], pp["scene_target"]["framebuffer"], scene_pass_clear_values(clear_color))
    gpu.cmd_set_viewport(cmd, 0, 0, pp["width"], pp["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, pp["width"], pp["height"])

proc end_scene_pass(cmd):
    gpu.cmd_end_render_pass(cmd)

proc begin_transparent_scene_pass(pp, cmd):
    gpu.cmd_begin_render_pass(cmd, pp["scene_target"]["load_render_pass"], pp["scene_target"]["load_framebuffer"], scene_pass_load_values())
    gpu.cmd_set_viewport(cmd, 0, 0, pp["width"], pp["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, pp["width"], pp["height"])

proc end_transparent_scene_pass(cmd):
    gpu.cmd_end_render_pass(cmd)

proc _draw_post_target(cmd, target, fp, push_data, desc_set):
    gpu.cmd_begin_render_pass(cmd, target["render_pass"], target["framebuffer"], [[0.0, 0.0, 0.0, 1.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, target["width"], target["height"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, target["width"], target["height"])
    draw_fullscreen(cmd, fp, push_data, desc_set)
    gpu.cmd_end_render_pass(cmd)

proc copy_scene_color(pp, cmd):
    _draw_post_target(cmd, pp["scene_copy"], pp["copy_pipeline"], nil, pp["scene_copy_set"])

proc run_bloom_chain(pp, cmd):
    if pp == nil or pp["bloom_enabled"] == false:
        return false
    _draw_post_target(cmd, pp["bloom_a"], pp["extract_pipeline"], build_bloom_extract_push_data(pp), pp["extract_set"])
    _draw_post_target(cmd, pp["bloom_b"], pp["blur_pipeline_a"], build_bloom_blur_push_data(pp, true), pp["blur_a_set"])
    _draw_post_target(cmd, pp["bloom_a"], pp["blur_pipeline_b"], build_bloom_blur_push_data(pp, false), pp["blur_b_set"])
    return true

proc run_ssao_chain(pp, cmd, projection, inv_projection, width, height):
    if pp == nil or pp["ssao_enabled"] == false:
        return false
    _draw_post_target(cmd, pp["ssao"]["target"], pp["ssao_pipeline"], pack_ssao_params(pp["ssao"], projection, inv_projection, width, height), pp["ssao_set"])
    _draw_post_target(cmd, pp["ssao"]["blur_target"], pp["ssao_blur_pipeline"], nil, pp["ssao_blur_set"])
    return true

proc draw_tonemap(cmd, pp):
    draw_fullscreen(cmd, pp["tonemap_pipeline"], build_tonemap_push_data(pp), pp["tonemap_set"])
