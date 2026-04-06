gc_disable()
# -----------------------------------------
# render_system.sage - Render system for Sage Engine
# Manages pipelines, materials, and draw calls
# -----------------------------------------

import gpu
from mesh import mesh_vertex_binding, mesh_vertex_attribs, build_skin_palette_uniform_data
from mesh import MAX_SKIN_JOINTS
from math3d import mat4_mul, mat4_identity
from shadow_map import build_shadow_uniform_data, get_shadow_texture, get_shadow_sampler
from shadow_map import get_light_vp, get_light_index

let SKIN_UBO_FLOATS = MAX_SKIN_JOINTS * 16
let SKIN_UBO_BYTES = SKIN_UBO_FLOATS * 4
let SHADOW_UBO_FLOATS = 20
let SHADOW_UBO_BYTES = SHADOW_UBO_FLOATS * 4

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

proc _create_shadow_binding():
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_COMBINED_SAMPLER
    b0["stage"] = gpu.STAGE_FRAGMENT
    b0["count"] = 1
    let b1 = {}
    b1["binding"] = 1
    b1["type"] = gpu.DESC_UNIFORM_BUFFER
    b1["stage"] = gpu.STAGE_FRAGMENT
    b1["count"] = 1
    let layout = gpu.create_descriptor_layout([b0, b1])
    let ps0 = {}
    ps0["type"] = gpu.DESC_COMBINED_SAMPLER
    ps0["count"] = 1
    let ps1 = {}
    ps1["type"] = gpu.DESC_UNIFORM_BUFFER
    ps1["count"] = 1
    let pool = gpu.create_descriptor_pool(1, [ps0, ps1])
    let desc_set = gpu.allocate_descriptor_set(pool, layout)
    let ubo = gpu.create_uniform_buffer(SHADOW_UBO_BYTES)
    let dummy_image = gpu.create_image(1, 1, 1, gpu.FORMAT_DEPTH32F, gpu.IMAGE_DEPTH_ATTACH | gpu.IMAGE_SAMPLED)
    let dummy_sampler = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)
    gpu.update_descriptor_image(desc_set, 0, dummy_image, dummy_sampler)
    gpu.update_descriptor(desc_set, 1, gpu.DESC_UNIFORM_BUFFER, ubo)
    gpu.update_uniform(ubo, build_shadow_uniform_data(nil, false, 1.0, -1))
    return {"layout": layout, "pool": pool, "desc_set": desc_set, "ubo": ubo, "dummy_image": dummy_image, "dummy_sampler": dummy_sampler, "source": nil}

proc _update_shadow_binding(binding):
    if binding == nil or dict_has(binding, "ubo") == false:
        return nil
    let image = binding["dummy_image"]
    let sampler = binding["dummy_sampler"]
    let light_vp = nil
    let light_index = -1
    let resolution = 1.0
    let enabled = false
    if dict_has(binding, "source") and binding["source"] != nil:
        let source = binding["source"]
        image = get_shadow_texture(source)
        sampler = get_shadow_sampler(source)
        light_vp = get_light_vp(source)
        light_index = get_light_index(source)
        resolution = source["resolution"] + 0.0
        enabled = light_vp != nil and light_index >= 0
    gpu.update_descriptor_image(binding["desc_set"], 0, image, sampler)
    gpu.update_uniform(binding["ubo"], build_shadow_uniform_data(light_vp, enabled, resolution, light_index))
    return binding["ubo"]

# ============================================================================
# Material registry
# ============================================================================
proc create_material_registry():
    let reg = {}
    reg["materials"] = {}
    reg["next_id"] = 0
    return reg

proc register_material(reg, name, mat_data):
    reg["materials"][name] = mat_data

proc get_material(reg, name):
    if dict_has(reg["materials"], name) == false:
        return nil
    return reg["materials"][name]

# ============================================================================
# Create a lit material (uses SceneUBO for lighting)
# ============================================================================
proc _create_material_binding():
    # Set 3: MaterialUBO (baseColor + surfaceControl + waterControl) + sceneColorCopy sampler
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_UNIFORM_BUFFER
    b0["stage"] = gpu.STAGE_FRAGMENT
    b0["count"] = 1
    let b1 = {}
    b1["binding"] = 1
    b1["type"] = gpu.DESC_COMBINED_SAMPLER
    b1["stage"] = gpu.STAGE_FRAGMENT
    b1["count"] = 1
    let layout = gpu.create_descriptor_layout([b0, b1])
    let ps0 = {}
    ps0["type"] = gpu.DESC_UNIFORM_BUFFER
    ps0["count"] = 1
    let ps1 = {}
    ps1["type"] = gpu.DESC_COMBINED_SAMPLER
    ps1["count"] = 1
    let pool = gpu.create_descriptor_pool(1, [ps0, ps1])
    let desc_set = gpu.allocate_descriptor_set(pool, layout)
    # MaterialUBO: baseColor(vec4) + surfaceControl(vec4) + waterControl(vec4) = 48 bytes
    let ubo = gpu.create_uniform_buffer(48)
    # Default: white color, receive shadows, no water
    let mat_data = [1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    gpu.update_uniform(ubo, mat_data)
    gpu.update_descriptor(desc_set, 0, gpu.DESC_UNIFORM_BUFFER, ubo)
    # Dummy 1x1 image for sceneColorCopy
    let dummy_img = gpu.create_image(1, 1, 1, gpu.FORMAT_RGBA8, gpu.IMAGE_SAMPLED)
    let dummy_sampler = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)
    gpu.update_descriptor_image(desc_set, 1, dummy_img, dummy_sampler)
    return {"layout": layout, "pool": pool, "desc_set": desc_set, "ubo": ubo}

proc create_lit_material(render_pass, desc_layout, desc_set):
    let vert = gpu.load_shader("shaders/engine_lit.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_lit.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "ERROR: Failed to load lit shaders"
        return nil

    # Pipeline layout: 4 descriptor sets + 160 byte push constants
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    let skin_binding = _create_skin_binding()
    let shadow_binding = _create_shadow_binding()
    let material_binding = _create_material_binding()
    let pipe_layout = gpu.create_pipeline_layout([desc_layout, skin_binding["layout"], shadow_binding["layout"], material_binding["layout"]], 160, stage_flags)

    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = render_pass
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_BACK
    cfg["front_face"] = gpu.FRONT_CCW
    cfg["depth_test"] = true
    cfg["depth_write"] = true
    cfg["vertex_bindings"] = [mesh_vertex_binding()]
    cfg["vertex_attribs"] = mesh_vertex_attribs()
    let pipeline = gpu.create_graphics_pipeline(cfg)
    if pipeline < 0:
        print "ERROR: Failed to create lit pipeline"
        return nil

    let mat = {}
    mat["name"] = "lit"
    mat["pipeline"] = pipeline
    mat["pipe_layout"] = pipe_layout
    mat["desc_set"] = desc_set
    mat["skin_layout"] = skin_binding["layout"]
    mat["skin_pool"] = skin_binding["pool"]
    mat["skin_desc_set"] = skin_binding["desc_set"]
    mat["skin_ubo"] = skin_binding["ubo"]
    mat["shadow_layout"] = shadow_binding["layout"]
    mat["shadow_pool"] = shadow_binding["pool"]
    mat["shadow_desc_set"] = shadow_binding["desc_set"]
    mat["shadow_ubo"] = shadow_binding["ubo"]
    mat["shadow_dummy_image"] = shadow_binding["dummy_image"]
    mat["shadow_dummy_sampler"] = shadow_binding["dummy_sampler"]
    mat["shadow_source"] = nil
    mat["material_layout"] = material_binding["layout"]
    mat["material_pool"] = material_binding["pool"]
    mat["material_desc_set"] = material_binding["desc_set"]
    mat["material_ubo"] = material_binding["ubo"]
    mat["vert"] = vert
    mat["frag"] = frag
    _update_shadow_binding(mat)
    return mat

proc set_lit_material_shadow_source(mat, shadow_renderer):
    mat["shadow_source"] = shadow_renderer
    _update_shadow_binding(mat)
    return shadow_renderer

# ============================================================================
# Create an unlit material (flat color, no lighting)
# ============================================================================
proc create_unlit_material(render_pass):
    let vert = gpu.load_shader("shaders/engine_unlit.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_unlit.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "ERROR: Failed to load unlit shaders"
        return nil

    # Push = 80 bytes (MVP mat4 + color vec4)
    let pipe_layout = gpu.create_pipeline_layout([], 80, gpu.STAGE_VERTEX)

    let cfg = {}
    cfg["layout"] = pipe_layout
    cfg["render_pass"] = render_pass
    cfg["vertex_shader"] = vert
    cfg["fragment_shader"] = frag
    cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    cfg["cull_mode"] = gpu.CULL_BACK
    cfg["front_face"] = gpu.FRONT_CCW
    cfg["depth_test"] = true
    cfg["depth_write"] = true
    cfg["vertex_bindings"] = [mesh_vertex_binding()]
    cfg["vertex_attribs"] = mesh_vertex_attribs()
    let pipeline = gpu.create_graphics_pipeline(cfg)
    if pipeline < 0:
        print "ERROR: Failed to create unlit pipeline"
        return nil

    let mat = {}
    mat["name"] = "unlit"
    mat["pipeline"] = pipeline
    mat["pipe_layout"] = pipe_layout
    mat["vert"] = vert
    mat["frag"] = frag
    return mat

# ============================================================================
# Draw helpers
# ============================================================================
proc build_lit_push_data(mvp_data, model_data, base_color, receive_shadows):
    let color = [0.75, 0.75, 0.75, 1.0]
    if base_color != nil:
        color = base_color
    let receive_flag = 1.0
    if receive_shadows == false:
        receive_flag = 0.0
    let push_data = []
    let i = 0
    while i < 16:
        push(push_data, mvp_data[i])
        i = i + 1
    i = 0
    while i < 16:
        push(push_data, model_data[i])
        i = i + 1
    push(push_data, color[0])
    push(push_data, color[1])
    push(push_data, color[2])
    push(push_data, color[3])
    push(push_data, receive_flag)
    push(push_data, 0.0)
    push(push_data, 0.0)
    push(push_data, 0.0)
    return push_data

proc draw_mesh_lit(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set):
    draw_mesh_lit_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, true)

proc draw_mesh_lit_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, receive_shadows):
    draw_mesh_lit_skinned_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, nil, receive_shadows)

proc draw_mesh_lit_skinned(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, skin_draw):
    draw_mesh_lit_skinned_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, skin_draw, true)

proc draw_mesh_lit_skinned_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, skin_draw, receive_shadows):
    gpu.cmd_bind_graphics_pipeline(cmd, mat["pipeline"])
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    let joint_palette = nil
    if skin_draw != nil and dict_has(skin_draw, "joint_palette"):
        joint_palette = skin_draw["joint_palette"]
    _update_skin_binding(mat, joint_palette)
    _update_shadow_binding(mat)
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 0, desc_set, 0)
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 1, mat["skin_desc_set"], 0)
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 2, mat["shadow_desc_set"], 0)
    let push_data = build_lit_push_data(mvp_data, model_data, nil, receive_shadows)
    gpu.cmd_push_constants(cmd, mat["pipe_layout"], stage_flags, push_data)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed(cmd, mesh_gpu["index_count"], 1, 0, 0, 0)

proc draw_mesh_lit_surface(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface):
    draw_mesh_lit_surface_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface, true)

proc draw_mesh_lit_surface_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface, receive_shadows):
    draw_mesh_lit_surface_skinned_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface, nil, receive_shadows)

proc draw_mesh_lit_surface_skinned(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface, skin_draw):
    draw_mesh_lit_surface_skinned_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface, skin_draw, true)

proc draw_mesh_lit_surface_skinned_controlled(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface, skin_draw, receive_shadows):
    let base_color = [0.75, 0.75, 0.75, 1.0]
    if surface != nil and dict_has(surface, "albedo"):
        base_color[0] = surface["albedo"][0]
        base_color[1] = surface["albedo"][1]
        base_color[2] = surface["albedo"][2]
        if dict_has(surface, "alpha"):
            base_color[3] = surface["alpha"]
    gpu.cmd_bind_graphics_pipeline(cmd, mat["pipeline"])
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    let joint_palette = nil
    if skin_draw != nil and dict_has(skin_draw, "joint_palette"):
        joint_palette = skin_draw["joint_palette"]
    _update_skin_binding(mat, joint_palette)
    _update_shadow_binding(mat)
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 0, desc_set, 0)
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 1, mat["skin_desc_set"], 0)
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 2, mat["shadow_desc_set"], 0)
    # Bind material UBO (set 3) with current base color
    if dict_has(mat, "material_ubo"):
        let mat_data = [base_color[0], base_color[1], base_color[2], base_color[3], 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        if receive_shadows == false:
            mat_data[4] = 0.0
        gpu.update_uniform(mat["material_ubo"], mat_data)
        gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 3, mat["material_desc_set"], 0)
    let push_data = build_lit_push_data(mvp_data, model_data, base_color, receive_shadows)
    gpu.cmd_push_constants(cmd, mat["pipe_layout"], stage_flags, push_data)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed(cmd, mesh_gpu["index_count"], 1, 0, 0, 0)

proc draw_mesh_unlit(cmd, mat, mesh_gpu, mvp_data, color):
    gpu.cmd_bind_graphics_pipeline(cmd, mat["pipeline"])
    let push_data = []
    let i = 0
    while i < 16:
        push(push_data, mvp_data[i])
        i = i + 1
    push(push_data, color[0])
    push(push_data, color[1])
    push(push_data, color[2])
    push(push_data, color[3])
    gpu.cmd_push_constants(cmd, mat["pipe_layout"], gpu.STAGE_VERTEX, push_data)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed(cmd, mesh_gpu["index_count"], 1, 0, 0, 0)

# ============================================================================
# Compute shader dispatch helpers
# ============================================================================
proc create_compute_pipeline(shader_path, desc_layout, push_size):
    let shader = gpu.load_shader(shader_path, gpu.STAGE_COMPUTE)
    if shader < 0:
        print "ERROR: Failed to load compute shader: " + shader_path
        return nil
    let pipe_layout = gpu.create_pipeline_layout([desc_layout], push_size, gpu.STAGE_COMPUTE)
    let pipeline = gpu.create_compute_pipeline(shader, pipe_layout)
    if pipeline < 0:
        print "ERROR: Failed to create compute pipeline"
        return nil
    let cp = {}
    cp["pipeline"] = pipeline
    cp["pipe_layout"] = pipe_layout
    cp["shader"] = shader
    return cp

proc dispatch_compute(cmd, cp, groups_x, groups_y, groups_z, desc_set, push_data):
    gpu.cmd_bind_compute_pipeline(cmd, cp["pipeline"])
    if desc_set >= 0:
        gpu.cmd_bind_descriptor_set(cmd, cp["pipe_layout"], 0, desc_set, 1)
    if push_data != nil:
        gpu.cmd_push_constants(cmd, cp["pipe_layout"], gpu.STAGE_COMPUTE, push_data)
    gpu.cmd_dispatch(cmd, groups_x, groups_y, groups_z)

# ============================================================================
# Advanced samplers
# ============================================================================
proc create_anisotropic_sampler(max_anisotropy):
    return gpu.create_sampler_advanced(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_REPEAT, max_anisotropy)

# ============================================================================
# Indirect draw support (GPU-driven rendering)
# ============================================================================
proc create_indirect_buffer(max_commands):
    # Each indirect draw command is 5 uint32s = 20 bytes
    let size = max_commands * 20
    return gpu.create_buffer(size, gpu.BUFFER_STORAGE | gpu.BUFFER_VERTEX)

proc draw_mesh_lit_indirect(cmd, mat, indirect_buf, draw_count, stride):
    gpu.cmd_bind_graphics_pipeline(cmd, mat["pipeline"])
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 0, mat["desc_set"], 0)
    gpu.cmd_draw_indirect(cmd, indirect_buf, 0, draw_count, stride)

proc create_indexed_indirect_buffer(max_commands):
    # Each indexed indirect command is 5 uint32s = 20 bytes
    let size = max_commands * 20
    return gpu.create_buffer(size, gpu.BUFFER_STORAGE | gpu.BUFFER_INDEX)

proc draw_mesh_lit_indexed_indirect(cmd, mat, mesh_gpu, indirect_buf, draw_count, stride):
    gpu.cmd_bind_graphics_pipeline(cmd, mat["pipeline"])
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 0, mat["desc_set"], 0)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed_indirect(cmd, indirect_buf, 0, draw_count, stride)

# ============================================================================
# Pipeline barriers for compute-to-graphics synchronization
# ============================================================================
proc barrier_compute_to_graphics(cmd):
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_FRAGMENT, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_SHADER_READ)

proc barrier_transfer_to_shader(cmd):
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_TRANSFER, gpu.PIPE_FRAGMENT, gpu.ACCESS_TRANSFER_WRITE, gpu.ACCESS_SHADER_READ)

proc barrier_graphics_to_transfer(cmd):
    gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COLOR_OUTPUT, gpu.PIPE_TRANSFER, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_TRANSFER_READ)
