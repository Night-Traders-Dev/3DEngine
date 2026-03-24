gc_disable()
# -----------------------------------------
# material.sage - Feature 13: Material System
# Shader + texture + descriptor binding management
# -----------------------------------------

import gpu

# ============================================================================
# Create a material from shaders and descriptor config
# ============================================================================
proc create_material(vert_path, frag_path, desc_bindings, push_size):
    let mat = {}
    mat["vert_shader"] = gpu.load_shader(vert_path, gpu.STAGE_VERTEX)
    mat["frag_shader"] = gpu.load_shader(frag_path, gpu.STAGE_FRAGMENT)
    mat["push_size"] = push_size

    if len(desc_bindings) > 0:
        mat["desc_layout"] = gpu.create_descriptor_layout(desc_bindings)
        mat["pipe_layout"] = gpu.create_pipeline_layout([mat["desc_layout"]], push_size, gpu.STAGE_ALL)
    else:
        mat["desc_layout"] = -1
        mat["pipe_layout"] = gpu.create_pipeline_layout([], push_size, gpu.STAGE_ALL)

    mat["pipeline"] = -1
    mat["textures"] = []
    mat["uniforms"] = []
    return mat

# Build graphics pipeline for a material
proc build_pipeline(mat, render_pass, vertex_bindings, vertex_attribs, config):
    let cfg = {}
    cfg["layout"] = mat["pipe_layout"]
    cfg["render_pass"] = render_pass
    cfg["vertex_shader"] = mat["vert_shader"]
    cfg["fragment_shader"] = mat["frag_shader"]
    cfg["vertex_bindings"] = vertex_bindings
    cfg["vertex_attribs"] = vertex_attribs

    # Apply config overrides
    if dict_has(config, "topology"):
        cfg["topology"] = config["topology"]
    else:
        cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
    if dict_has(config, "cull_mode"):
        cfg["cull_mode"] = config["cull_mode"]
    else:
        cfg["cull_mode"] = gpu.CULL_BACK
    if dict_has(config, "depth_test"):
        cfg["depth_test"] = config["depth_test"]
    else:
        cfg["depth_test"] = true
    if dict_has(config, "depth_write"):
        cfg["depth_write"] = config["depth_write"]
    else:
        cfg["depth_write"] = true
    if dict_has(config, "blend"):
        cfg["blend"] = config["blend"]
    if dict_has(config, "front_face"):
        cfg["front_face"] = config["front_face"]
    else:
        cfg["front_face"] = gpu.FRONT_CCW

    mat["pipeline"] = gpu.create_graphics_pipeline(cfg)
    return mat["pipeline"]

# Bind material for drawing
proc bind_material(cmd, mat):
    gpu.cmd_bind_graphics_pipeline(cmd, mat["pipeline"])

# ============================================================================
# Preset materials
# ============================================================================
proc unlit_material(vert_path, frag_path, push_size):
    return create_material(vert_path, frag_path, [], push_size)

proc textured_material(vert_path, frag_path, push_size):
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_COMBINED_SAMPLER
    b0["stage"] = gpu.STAGE_FRAGMENT
    b0["count"] = 1
    return create_material(vert_path, frag_path, [b0], push_size)

proc pbr_material(vert_path, frag_path, push_size):
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_UNIFORM_BUFFER
    b0["stage"] = gpu.STAGE_FRAGMENT
    b0["count"] = 1
    return create_material(vert_path, frag_path, [b0], push_size)

# ============================================================================
# Material presets library
# ============================================================================
proc mat_preset_metal():
    from components import MaterialComponent
    let m = MaterialComponent(0.8, 0.8, 0.85)
    m["metallic"] = 0.95
    m["roughness"] = 0.15
    return m

proc mat_preset_wood():
    from components import MaterialComponent
    let m = MaterialComponent(0.55, 0.35, 0.18)
    m["metallic"] = 0.0
    m["roughness"] = 0.7
    return m

proc mat_preset_concrete():
    from components import MaterialComponent
    let m = MaterialComponent(0.6, 0.58, 0.55)
    m["metallic"] = 0.0
    m["roughness"] = 0.9
    return m

proc mat_preset_glass():
    from components import MaterialComponent
    let m = MaterialComponent(0.95, 0.95, 0.98)
    m["metallic"] = 0.0
    m["roughness"] = 0.05
    m["alpha"] = 0.3
    return m

proc mat_preset_plastic():
    from components import MaterialComponent
    let m = MaterialComponent(0.8, 0.2, 0.2)
    m["metallic"] = 0.0
    m["roughness"] = 0.4
    return m

proc mat_preset_gold():
    from components import MaterialComponent
    let m = MaterialComponent(1.0, 0.84, 0.0)
    m["metallic"] = 1.0
    m["roughness"] = 0.2
    return m

proc mat_preset_rubber():
    from components import MaterialComponent
    let m = MaterialComponent(0.15, 0.15, 0.15)
    m["metallic"] = 0.0
    m["roughness"] = 0.95
    return m

proc mat_preset_emissive(r, g, b, strength):
    from components import MaterialComponent
    let m = MaterialComponent(r, g, b)
    m["metallic"] = 0.0
    m["roughness"] = 0.5
    m["emission"] = [r, g, b]
    m["emission_strength"] = strength
    return m

proc get_material_presets():
    return ["Metal", "Wood", "Concrete", "Glass", "Plastic", "Gold", "Rubber", "Emissive"]

proc create_material_preset(name):
    if name == "Metal":
        return mat_preset_metal()
    if name == "Wood":
        return mat_preset_wood()
    if name == "Concrete":
        return mat_preset_concrete()
    if name == "Glass":
        return mat_preset_glass()
    if name == "Plastic":
        return mat_preset_plastic()
    if name == "Gold":
        return mat_preset_gold()
    if name == "Rubber":
        return mat_preset_rubber()
    if name == "Emissive":
        return mat_preset_emissive(1.0, 0.5, 0.0, 2.0)
    return nil
