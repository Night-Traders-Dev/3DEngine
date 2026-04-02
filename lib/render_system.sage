gc_disable()
# -----------------------------------------
# render_system.sage - Render system for Sage Engine
# Manages pipelines, materials, and draw calls
# -----------------------------------------

import gpu
from mesh import mesh_vertex_binding, mesh_vertex_attribs, build_skin_palette_uniform_data
from mesh import MAX_SKIN_JOINTS
from math3d import mat4_mul, mat4_identity

let SKIN_UBO_FLOATS = MAX_SKIN_JOINTS * 16
let SKIN_UBO_BYTES = SKIN_UBO_FLOATS * 4

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
proc create_lit_material(render_pass, desc_layout, desc_set):
    let vert = gpu.load_shader("shaders/engine_lit.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_lit.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "ERROR: Failed to load lit shaders"
        return nil

    # Pipeline layout: push = 144 bytes (MVP + Model + baseColor), 1 descriptor set (SceneUBO)
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    let skin_binding = _create_skin_binding()
    let pipe_layout = gpu.create_pipeline_layout([desc_layout, skin_binding["layout"]], 144, stage_flags)

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
    mat["vert"] = vert
    mat["frag"] = frag
    return mat

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
proc build_lit_push_data(mvp_data, model_data, base_color):
    let color = [0.75, 0.75, 0.75, 1.0]
    if base_color != nil:
        color = base_color
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
    return push_data

proc draw_mesh_lit(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set):
    draw_mesh_lit_skinned(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, nil)

proc draw_mesh_lit_skinned(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, skin_draw):
    gpu.cmd_bind_graphics_pipeline(cmd, mat["pipeline"])
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    let joint_palette = nil
    if skin_draw != nil and dict_has(skin_draw, "joint_palette"):
        joint_palette = skin_draw["joint_palette"]
    _update_skin_binding(mat, joint_palette)
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 0, desc_set, 0)
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 1, mat["skin_desc_set"], 0)
    let push_data = build_lit_push_data(mvp_data, model_data, nil)
    gpu.cmd_push_constants(cmd, mat["pipe_layout"], stage_flags, push_data)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed(cmd, mesh_gpu["index_count"], 1, 0, 0, 0)

proc draw_mesh_lit_surface(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface):
    draw_mesh_lit_surface_skinned(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface, nil)

proc draw_mesh_lit_surface_skinned(cmd, mat, mesh_gpu, mvp_data, model_data, desc_set, surface, skin_draw):
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
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 0, desc_set, 0)
    gpu.cmd_bind_descriptor_set(cmd, mat["pipe_layout"], 1, mat["skin_desc_set"], 0)
    let push_data = build_lit_push_data(mvp_data, model_data, base_color)
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
