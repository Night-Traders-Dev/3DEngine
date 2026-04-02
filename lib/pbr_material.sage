gc_disable()
# -----------------------------------------
# pbr_material.sage - PBR Material system for Sage Engine
# Cook-Torrance BRDF with texture maps (albedo, normal, metallic/roughness)
# -----------------------------------------

import gpu
from mesh import mesh_vertex_binding, mesh_vertex_attribs, build_skin_palette_uniform_data
from mesh import MAX_SKIN_JOINTS
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
    m["use_albedo_texture"] = false
    m["use_normal_texture"] = false
    m["use_metallic_roughness_texture"] = false
    m["desc_set"] = -1
    return m

proc create_pbr_fallback_textures():
    let textures = {}
    let flags = gpu.IMAGE_SAMPLED | gpu.IMAGE_TRANSFER_DST
    textures["albedo"] = gpu.create_image(1, 1, 1, gpu.FORMAT_RGBA8, flags)
    textures["normal"] = gpu.create_image(1, 1, 1, gpu.FORMAT_RGBA8, flags)
    textures["mr"] = gpu.create_image(1, 1, 1, gpu.FORMAT_RGBA8, flags)
    return textures

proc create_pbr_material_from_imported(mat_info, fallback_textures):
    let m = create_pbr_material_data()
    if mat_info == nil:
        return m
    if dict_has(mat_info, "albedo_color"):
        m["albedo_color"] = mat_info["albedo_color"]
    if dict_has(mat_info, "metallic"):
        m["metallic"] = mat_info["metallic"]
    if dict_has(mat_info, "roughness"):
        m["roughness"] = mat_info["roughness"]

    if dict_has(mat_info, "albedo_tex") and mat_info["albedo_tex"] >= 0:
        m["albedo_texture"] = mat_info["albedo_tex"]
        m["use_albedo_texture"] = true
    else:
        if fallback_textures != nil and dict_has(fallback_textures, "albedo"):
            m["albedo_texture"] = fallback_textures["albedo"]

    if dict_has(mat_info, "normal_tex") and mat_info["normal_tex"] >= 0:
        m["normal_texture"] = mat_info["normal_tex"]
        m["use_normal_texture"] = true
    else:
        if fallback_textures != nil and dict_has(fallback_textures, "normal"):
            m["normal_texture"] = fallback_textures["normal"]

    if dict_has(mat_info, "mr_tex") and mat_info["mr_tex"] >= 0:
        m["metallic_roughness_texture"] = mat_info["mr_tex"]
        m["use_metallic_roughness_texture"] = true
    else:
        if fallback_textures != nil and dict_has(fallback_textures, "mr"):
            m["metallic_roughness_texture"] = fallback_textures["mr"]
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

    let skin_binding = _create_skin_binding()
    let shadow_binding = _create_shadow_binding()
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    let pipe_layout = gpu.create_pipeline_layout([scene_desc_layout, mat_layout, skin_binding["layout"], shadow_binding["layout"]], 176, stage_flags)

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
    pbr["skin_layout"] = skin_binding["layout"]
    pbr["skin_pool"] = skin_binding["pool"]
    pbr["skin_desc_set"] = skin_binding["desc_set"]
    pbr["skin_ubo"] = skin_binding["ubo"]
    pbr["shadow_layout"] = shadow_binding["layout"]
    pbr["shadow_pool"] = shadow_binding["pool"]
    pbr["shadow_desc_set"] = shadow_binding["desc_set"]
    pbr["shadow_ubo"] = shadow_binding["ubo"]
    pbr["shadow_dummy_image"] = shadow_binding["dummy_image"]
    pbr["shadow_dummy_sampler"] = shadow_binding["dummy_sampler"]
    pbr["shadow_source"] = nil
    pbr["vert"] = vert
    pbr["frag"] = frag
    _update_shadow_binding(pbr)
    print "PBR renderer initialized"
    return pbr

proc set_pbr_shadow_source(pbr_renderer, shadow_renderer):
    pbr_renderer["shadow_source"] = shadow_renderer
    _update_shadow_binding(pbr_renderer)
    return shadow_renderer

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

proc build_pbr_push_data(mvp, model, mat_data):
    let push_data = []
    let i = 0
    while i < 16:
        push(push_data, mvp[i])
        i = i + 1
    i = 0
    while i < 16:
        push(push_data, model[i])
        i = i + 1
    push(push_data, mat_data["albedo_color"][0])
    push(push_data, mat_data["albedo_color"][1])
    push(push_data, mat_data["albedo_color"][2])
    push(push_data, mat_data["albedo_color"][3])
    push(push_data, mat_data["metallic"])
    push(push_data, mat_data["roughness"])
    push(push_data, 0.0)
    push(push_data, 0.0)
    if mat_data["use_albedo_texture"]:
        push(push_data, 1.0)
    else:
        push(push_data, 0.0)
    if mat_data["use_normal_texture"]:
        push(push_data, 1.0)
    else:
        push(push_data, 0.0)
    if mat_data["use_metallic_roughness_texture"]:
        push(push_data, 1.0)
    else:
        push(push_data, 0.0)
    push(push_data, 0.0)
    return push_data

# ============================================================================
# Draw mesh with PBR material
# ============================================================================
proc draw_pbr(cmd, pbr_renderer, mesh_gpu, mvp, model, scene_desc_set, mat_data):
    draw_pbr_skinned(cmd, pbr_renderer, mesh_gpu, mvp, model, scene_desc_set, mat_data, nil)

proc draw_pbr_skinned(cmd, pbr_renderer, mesh_gpu, mvp, model, scene_desc_set, mat_data, skin_draw):
    gpu.cmd_bind_graphics_pipeline(cmd, pbr_renderer["pipeline"])
    let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
    let joint_palette = nil
    if skin_draw != nil and dict_has(skin_draw, "joint_palette"):
        joint_palette = skin_draw["joint_palette"]
    _update_skin_binding(pbr_renderer, joint_palette)
    _update_shadow_binding(pbr_renderer)
    gpu.cmd_bind_descriptor_set(cmd, pbr_renderer["pipe_layout"], 0, scene_desc_set)
    if mat_data["desc_set"] >= 0:
        gpu.cmd_bind_descriptor_set(cmd, pbr_renderer["pipe_layout"], 1, mat_data["desc_set"])
    gpu.cmd_bind_descriptor_set(cmd, pbr_renderer["pipe_layout"], 2, pbr_renderer["skin_desc_set"])
    gpu.cmd_bind_descriptor_set(cmd, pbr_renderer["pipe_layout"], 3, pbr_renderer["shadow_desc_set"])
    let push_data = build_pbr_push_data(mvp, model, mat_data)
    gpu.cmd_push_constants(cmd, pbr_renderer["pipe_layout"], stage_flags, push_data)
    gpu.cmd_bind_vertex_buffer(cmd, mesh_gpu["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh_gpu["ibuf"])
    gpu.cmd_draw_indexed(cmd, mesh_gpu["index_count"], 1, 0, 0, 0)
