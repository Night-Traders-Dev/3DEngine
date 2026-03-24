gc_disable()
# -----------------------------------------
# shadow_map.sage - Shadow mapping for Sage Engine
# Depth-only pass from light's perspective, PCF sampling
# -----------------------------------------

import gpu
from math3d import vec3, v3_normalize, mat4_ortho, mat4_look_at, mat4_mul
from mesh import mesh_vertex_binding, mesh_vertex_attribs

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
    depth_attach["final_layout"] = gpu.LAYOUT_DEPTH_ATTACH
    sr["render_pass"] = gpu.create_render_pass([depth_attach])

    # Framebuffer
    sr["framebuffer"] = gpu.create_framebuffer(sr["render_pass"], [depth_img], resolution, resolution)

    # Load depth-only shaders
    let vert = gpu.load_shader("shaders/engine_shadow_depth.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_shadow_depth.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "SHADOW ERROR: Failed to load shadow shaders"
        return nil

    # Pipeline: depth only, push constants = 64 bytes (lightMVP mat4)
    let pipe_layout = gpu.create_pipeline_layout([], 64, gpu.STAGE_VERTEX)
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
    sr["light_vp"] = nil
    sr["initialized"] = true
    print "Shadow renderer initialized (" + str(resolution) + "x" + str(resolution) + ")"
    return sr

# ============================================================================
# Compute light view-projection for directional light
# ============================================================================
proc compute_light_vp(light_dir, scene_center, scene_radius):
    let dir = v3_normalize(light_dir)
    let light_pos = vec3(scene_center[0] - dir[0] * scene_radius, scene_center[1] - dir[1] * scene_radius, scene_center[2] - dir[2] * scene_radius)
    let light_view = mat4_look_at(light_pos, scene_center, vec3(0.0, 1.0, 0.0))
    let r = scene_radius
    let light_proj = mat4_ortho(0.0 - r, r, 0.0 - r, r, 0.1, r * 3.0)
    return mat4_mul(light_proj, light_view)

# ============================================================================
# Begin shadow pass
# ============================================================================
proc begin_shadow_pass(sr, cmd, light_vp):
    sr["light_vp"] = light_vp
    gpu.begin_commands(cmd)
    gpu.cmd_begin_render_pass(cmd, sr["render_pass"], sr["framebuffer"], [[1.0, 0.0, 0.0, 0.0]])
    gpu.cmd_set_viewport(cmd, 0, 0, sr["resolution"], sr["resolution"], 0.0, 1.0)
    gpu.cmd_set_scissor(cmd, 0, 0, sr["resolution"], sr["resolution"])
    gpu.cmd_bind_graphics_pipeline(cmd, sr["pipeline"])

# ============================================================================
# Draw mesh into shadow map
# ============================================================================
proc shadow_draw_mesh(sr, cmd, mesh_gpu, model_matrix):
    let light_mvp = mat4_mul(sr["light_vp"], model_matrix)
    gpu.cmd_push_constants(cmd, sr["pipe_layout"], gpu.STAGE_VERTEX, light_mvp)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed(cmd, mesh_gpu["index_count"], 1, 0, 0, 0)

# ============================================================================
# End shadow pass
# ============================================================================
proc end_shadow_pass(sr, cmd):
    gpu.cmd_end_render_pass(cmd)
    gpu.end_commands(cmd)

# ============================================================================
# Get shadow map texture handle for binding
# ============================================================================
proc get_shadow_texture(sr):
    return sr["depth_image"]

proc get_shadow_sampler(sr):
    return sr["sampler"]

proc get_light_vp(sr):
    return sr["light_vp"]
