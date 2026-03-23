gc_disable()
# -----------------------------------------
# pbr_material.sage - PBR Material system for Sage Engine
# Cook-Torrance BRDF with texture maps (albedo, normal, metallic/roughness)
# -----------------------------------------

import gpu
from mesh import mesh_vertex_binding, mesh_vertex_attribs

# ============================================================================
# PBR Material
# ============================================================================
proc create_pbr_material_data():
    let m = {}
    m["albedo_texture"] = -1
    m["normal_texture"] = -1
    m["metallic_roughness_texture"] = -1
    m["sampler"] = -1
    m["albedo_color"] = [1.0, 1.0, 1.0, 1.0]
    m["metallic"] = 0.0
    m["roughness"] = 0.5
    m["desc_set"] = -1
    return m

# ============================================================================
# PBR Renderer Setup
# ============================================================================
proc create_pbr_renderer(render_pass, scene_desc_layout):
    let pbr = {}

    let vert = gpu.load_shader("shaders/engine_pbr.vert.spv", gpu.STAGE_VERTEX)
    let frag = gpu.load_shader("shaders/engine_pbr.frag.spv", gpu.STAGE_FRAGMENT)
    if vert < 0 or frag < 0:
        print "PBR ERROR: Failed to load PBR shaders"
        return nil

    # Material descriptor layout (set 1): albedo, normal, metallic/roughness
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
    let mat_layout = gpu.create_descriptor_layout([b0, b1, b2])

    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    let pipe_layout = gpu.create_pipeline_layout([scene_desc_layout, mat_layout], 128, stage_flags)

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
        print "PBR ERROR: Failed to create pipeline"
        return nil

    # Descriptor pool for materials (max 32 materials)
    let ps0 = {}
    ps0["type"] = gpu.DESC_COMBINED_SAMPLER
    ps0["count"] = 96
    let pool = gpu.create_descriptor_pool(32, [ps0])

    pbr["pipeline"] = pipeline
    pbr["pipe_layout"] = pipe_layout
    pbr["mat_layout"] = mat_layout
    pbr["pool"] = pool
    pbr["vert"] = vert
    pbr["frag"] = frag
    print "PBR renderer initialized"
    return pbr

# ============================================================================
# Allocate a PBR material descriptor set and bind textures
# ============================================================================
proc bind_pbr_material(pbr_renderer, mat_data, sampler):
    let ds = gpu.allocate_descriptor_set(pbr_renderer["pool"], pbr_renderer["mat_layout"])
    if mat_data["albedo_texture"] >= 0:
        gpu.update_descriptor_image(ds, 0, mat_data["albedo_texture"], sampler)
    if mat_data["normal_texture"] >= 0:
        gpu.update_descriptor_image(ds, 1, mat_data["normal_texture"], sampler)
    if mat_data["metallic_roughness_texture"] >= 0:
        gpu.update_descriptor_image(ds, 2, mat_data["metallic_roughness_texture"], sampler)
    mat_data["desc_set"] = ds
    mat_data["sampler"] = sampler
    return ds

# ============================================================================
# Draw mesh with PBR material
# ============================================================================
proc draw_pbr(cmd, pbr_renderer, mesh_gpu, mvp, model, scene_desc_set, mat_data):
    gpu.cmd_bind_graphics_pipeline(cmd, pbr_renderer["pipeline"])
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    gpu.cmd_bind_descriptor_set(cmd, pbr_renderer["pipe_layout"], 0, scene_desc_set)
    if mat_data["desc_set"] >= 0:
        gpu.cmd_bind_descriptor_set(cmd, pbr_renderer["pipe_layout"], 1, mat_data["desc_set"])
    let push_data = []
    let i = 0
    while i < 16:
        push(push_data, mvp[i])
        i = i + 1
    i = 0
    while i < 16:
        push(push_data, model[i])
        i = i + 1
    gpu.cmd_push_constants(cmd, pbr_renderer["pipe_layout"], stage_flags, push_data)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed(cmd, mesh_gpu["index_count"], 1, 0, 0, 0)
