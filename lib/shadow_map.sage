gc_disable()
# -----------------------------------------
# shadow_map.sage - Shadow mapping for Sage Engine
# Depth-only pass from light's perspective, PCF sampling
# -----------------------------------------

import gpu
import math
from math3d import vec3, v3_normalize, mat4_ortho, mat4_look_at, mat4_mul, mat4_identity
from math3d import mat4_mul_vec4
from mesh import mesh_vertex_binding, mesh_vertex_attribs, build_skin_palette_uniform_data
from mesh import MAX_SKIN_JOINTS

let SKIN_UBO_FLOATS = MAX_SKIN_JOINTS * 16
let SKIN_UBO_BYTES = SKIN_UBO_FLOATS * 4
let SHADOW_UBO_FLOATS = 20
let SHADOW_UBO_BYTES = SHADOW_UBO_FLOATS * 4

proc build_shadow_uniform_data(light_vp, enabled, resolution, light_index):
    let data = []
    let mat = light_vp
    if mat == nil or len(mat) != 16:
        mat = mat4_identity()
    let i = 0
    while i < 16:
        push(data, mat[i])
        i = i + 1
    if enabled:
        push(data, 1.0)
    else:
        push(data, 0.0)
    let texel = 1.0
    if resolution > 0.5:
        texel = 1.0 / resolution
    push(data, texel)
    push(data, 0.003)
    push(data, light_index + 0.0)
    return data

proc primary_shadow_light(ls):
    let fallback = {"index": -1, "direction": vec3(-0.3, -0.8, -0.5)}
    if ls == nil or dict_has(ls, "lights") == false:
        return fallback
    let i = 0
    while i < len(ls["lights"]):
        let light = ls["lights"][i]
        let casts = true
        if light != nil and dict_has(light, "cast_shadows"):
            casts = light["cast_shadows"]
        if light != nil and light["enabled"] and light["type"] == 1 and casts:
            return {"index": i, "direction": light["position"]}
        i = i + 1
    return fallback

proc _create_skin_binding():
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_UNIFORM_BUFFER
    b0["stage"] = gpu.STAGE_VERTEX
    b0["count"] = 1
    let layout = gpu.create_descriptor_layout([b0])
    let ps0 = {}
    ps0["type"] = gpu.DESC_UNIFORM_BUFFER
    ps0["count"] = 1
    let pool = gpu.create_descriptor_pool(1, [ps0])
    let desc_set = gpu.allocate_descriptor_set(pool, layout)
    let ubo = gpu.create_uniform_buffer(SKIN_UBO_BYTES)
    gpu.update_descriptor(desc_set, 0, gpu.DESC_UNIFORM_BUFFER, ubo)
    gpu.update_uniform(ubo, build_skin_palette_uniform_data(nil))
    return {"layout": layout, "pool": pool, "desc_set": desc_set, "ubo": ubo}

proc _update_skin_binding(binding, joint_palette):
    if binding == nil or dict_has(binding, "ubo") == false:
        return nil
    gpu.update_uniform(binding["ubo"], build_skin_palette_uniform_data(joint_palette))
    return binding["ubo"]

# ============================================================================
# Shadow map renderer
# ============================================================================
proc create_shadow_renderer(resolution):
    let sr = {}
    sr["resolution"] = resolution

    # Create depth image for shadow map
    let depth_img = gpu.create_image(resolution, resolution, 1, gpu.FORMAT_DEPTH32F, gpu.IMAGE_DEPTH_ATTACH | gpu.IMAGE_SAMPLED)
    sr["depth_image"] = depth_img

    # Sampler for reading shadow map
    sr["sampler"] = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)

    # Render pass for depth only
    let depth_attach = {}
    depth_attach["format"] = gpu.FORMAT_DEPTH32F
    depth_attach["load_op"] = gpu.LOAD_CLEAR
    depth_attach["store_op"] = gpu.STORE_STORE
    depth_attach["initial_layout"] = gpu.LAYOUT_UNDEFINED
    depth_attach["final_layout"] = gpu.LAYOUT_SHADER_READ
    sr["render_pass"] = gpu.create_render_pass([depth_attach])

    # Framebuffer
    sr["framebuffer"] = gpu.create_framebuffer(sr["render_pass"], [depth_img], resolution, resolution)

    # Dedicated command resources keep shadow prepass separate from the swapchain frame.
    sr["cmd_pool"] = gpu.create_command_pool()
    sr["cmd"] = gpu.create_command_buffer(sr["cmd_pool"])
    sr["fence"] = gpu.create_fence(true)

    # Load depth-only shaders
    let vert = gpu.load_shader("shaders/engine_shadow_depth.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_shadow_depth.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "SHADOW ERROR: Failed to load shadow shaders"
        return nil

    let skin_binding = _create_skin_binding()

    # Pipeline: depth only, push constants = 64 bytes (lightMVP mat4)
    let pipe_layout = gpu.create_pipeline_layout([skin_binding["layout"]], 64, gpu.STAGE_VERTEX)
    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = sr["render_pass"]
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    # Keep compatibility with Sage GPU builds that do not expose CULL_FRONT.
    cfg["cull_mode"] = gpu.CULL_BACK
    cfg["front_face"] = gpu.FRONT_CCW
    cfg["depth_test"] = true
    cfg["depth_write"] = true
    cfg["vertex_bindings"] = [mesh_vertex_binding()]
    cfg["vertex_attribs"] = mesh_vertex_attribs()
    let pipeline = gpu.create_graphics_pipeline(cfg)
    if pipeline < 0:
        print "SHADOW ERROR: Failed to create shadow pipeline"
        return nil

    sr["pipeline"] = pipeline
    sr["pipe_layout"] = pipe_layout
    sr["skin_layout"] = skin_binding["layout"]
    sr["skin_pool"] = skin_binding["pool"]
    sr["skin_desc_set"] = skin_binding["desc_set"]
    sr["skin_ubo"] = skin_binding["ubo"]
    sr["light_vp"] = nil
    sr["light_index"] = -1
    sr["initialized"] = true
    print "Shadow renderer initialized (" + str(resolution) + "x" + str(resolution) + ")"
    return sr

# ============================================================================
# Compute light view-projection for directional light
# ============================================================================
proc shadow_texel_world_size(scene_radius, resolution):
    let r = math.abs(scene_radius)
    if r < 0.0001:
        r = 0.0001
    let span = r * 2.0
    if resolution < 1.0:
        return span
    return span / resolution

proc snap_shadow_view_center(light_view, scene_center, scene_radius, resolution):
    let stable_view = []
    let i = 0
    while i < len(light_view):
        push(stable_view, light_view[i])
        i = i + 1
    if len(stable_view) != 16:
        return stable_view
    let texel = shadow_texel_world_size(scene_radius, resolution)
    if texel <= 0.000001:
        return stable_view
    let center_ls = mat4_mul_vec4(stable_view, [scene_center[0], scene_center[1], scene_center[2], 1.0])
    let snapped_x = math.floor(center_ls[0] / texel + 0.5) * texel
    let snapped_y = math.floor(center_ls[1] / texel + 0.5) * texel
    stable_view[12] = stable_view[12] + (snapped_x - center_ls[0])
    stable_view[13] = stable_view[13] + (snapped_y - center_ls[1])
    return stable_view

proc compute_light_vp_stable(light_dir, scene_center, scene_radius, resolution):
    let dir = v3_normalize(light_dir)
    let r = math.abs(scene_radius)
    if r < 0.1:
        r = 0.1
    let light_pos = vec3(scene_center[0] - dir[0] * r, scene_center[1] - dir[1] * r, scene_center[2] - dir[2] * r)
    let light_view = mat4_look_at(light_pos, scene_center, vec3(0.0, 1.0, 0.0))
    light_view = snap_shadow_view_center(light_view, scene_center, r, resolution)
    let light_proj = mat4_ortho(0.0 - r, r, 0.0 - r, r, 0.1, r * 3.0)
    return mat4_mul(light_proj, light_view)

proc compute_light_vp(light_dir, scene_center, scene_radius):
    return compute_light_vp_stable(light_dir, scene_center, scene_radius, 2048.0)

# ============================================================================
# Begin/end a dedicated shadow frame
# ============================================================================
proc begin_shadow_frame(sr, light_vp, light_index):
    gpu.wait_fence(sr["fence"])
    gpu.reset_fence(sr["fence"])
    sr["light_vp"] = light_vp
    sr["light_index"] = light_index
    let cmd = sr["cmd"]
    gpu.begin_commands(cmd)
    begin_shadow_pass(sr, cmd, light_vp)
    return cmd

proc end_shadow_frame(sr, cmd):
    end_shadow_pass(sr, cmd)
    gpu.end_commands(cmd)
    gpu.submit(cmd, nil, nil, sr["fence"])
    gpu.wait_fence(sr["fence"])
    return true

# ============================================================================
# Begin shadow pass
# ============================================================================
proc begin_shadow_pass(sr, cmd, light_vp):
    sr["light_vp"] = light_vp
    gpu.cmd_begin_render_pass(cmd, sr["render_pass"], sr["framebuffer"], [[1.0, 0.0, 0.0, 0.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, sr["resolution"], sr["resolution"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, sr["resolution"], sr["resolution"])
    gpu.cmd_bind_graphics_pipeline(cmd, sr["pipeline"])

# ============================================================================
# Draw mesh into shadow map
# ============================================================================
proc shadow_draw_mesh(sr, cmd, mesh_gpu, model_matrix):
    shadow_draw_mesh_skinned(sr, cmd, mesh_gpu, model_matrix, nil)

proc shadow_draw_mesh_skinned(sr, cmd, mesh_gpu, model_matrix, skin_draw):
    let light_mvp = mat4_mul(sr["light_vp"], model_matrix)
    let joint_palette = nil
    if skin_draw != nil and dict_has(skin_draw, "joint_palette"):
        joint_palette = skin_draw["joint_palette"]
    _update_skin_binding(sr, joint_palette)
    gpu.cmd_bind_descriptor_set(cmd, sr["pipe_layout"], 0, sr["skin_desc_set"], 0)
    gpu.cmd_push_constants(cmd, sr["pipe_layout"], gpu.STAGE_VERTEX, light_mvp)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed(cmd, mesh_gpu["index_count"], 1, 0, 0, 0)

# ============================================================================
# End shadow pass
# ============================================================================
proc end_shadow_pass(sr, cmd):
    gpu.cmd_end_render_pass(cmd)

# ============================================================================
# Get shadow map texture handle for binding
# ============================================================================
proc get_shadow_texture(sr):
    return sr["depth_image"]

proc get_shadow_sampler(sr):
    return sr["sampler"]

proc get_light_vp(sr):
    return sr["light_vp"]

proc get_light_index(sr):
    return sr["light_index"]
