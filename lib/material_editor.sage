gc_disable()
# material_editor.sage — Runtime Material Editor
# Create and modify PBR materials with live preview.
# Supports: albedo, metallic, roughness, normal, emissive, alpha,
# texture slots, shader presets, material library.

# ============================================================================
# Material Definition
# ============================================================================

proc create_material_def(name):
    return {
        "name": name,
        "albedo": [1.0, 1.0, 1.0],
        "metallic": 0.0,
        "roughness": 0.5,
        "emissive": [0.0, 0.0, 0.0],
        "emissive_strength": 0.0,
        "alpha": 1.0,
        "double_sided": false,
        "blend_mode": "opaque",       # opaque, alpha_blend, additive
        "albedo_texture": nil,
        "normal_texture": nil,
        "metallic_texture": nil,
        "roughness_texture": nil,
        "emissive_texture": nil,
        "ao_texture": nil,
        "tiling": [1.0, 1.0],
        "offset": [0.0, 0.0],
        "shader": "lit",              # lit, unlit, transparent, emissive
        "dirty": true
    }

# ============================================================================
# Presets
# ============================================================================

proc material_preset_metal(name):
    let m = create_material_def(name)
    m["metallic"] = 0.95
    m["roughness"] = 0.15
    m["albedo"] = [0.8, 0.8, 0.85]
    return m

proc material_preset_wood(name):
    let m = create_material_def(name)
    m["metallic"] = 0.0
    m["roughness"] = 0.7
    m["albedo"] = [0.55, 0.35, 0.15]
    return m

proc material_preset_glass(name):
    let m = create_material_def(name)
    m["metallic"] = 0.0
    m["roughness"] = 0.05
    m["albedo"] = [0.9, 0.95, 1.0]
    m["alpha"] = 0.3
    m["blend_mode"] = "alpha_blend"
    return m

proc material_preset_emissive(name, color, strength):
    let m = create_material_def(name)
    m["emissive"] = color
    m["emissive_strength"] = strength
    m["albedo"] = [0.1, 0.1, 0.1]
    return m

proc material_preset_plastic(name, color):
    let m = create_material_def(name)
    m["metallic"] = 0.0
    m["roughness"] = 0.4
    m["albedo"] = color
    return m

proc material_preset_stone(name):
    let m = create_material_def(name)
    m["metallic"] = 0.0
    m["roughness"] = 0.85
    m["albedo"] = [0.5, 0.48, 0.45]
    return m

proc material_preset_fabric(name, color):
    let m = create_material_def(name)
    m["metallic"] = 0.0
    m["roughness"] = 0.95
    m["albedo"] = color
    return m

# ============================================================================
# Material Library — manage collections of materials
# ============================================================================

proc create_material_library():
    return {"materials": {}, "categories": {}}

proc add_to_library(lib, material):
    lib["materials"][material["name"]] = material

proc get_from_library(lib, name):
    if dict_has(lib["materials"], name):
        return lib["materials"][name]
    return nil

proc list_materials(lib):
    return dict_keys(lib["materials"])

proc categorize_material(lib, name, category):
    if not dict_has(lib["categories"], category):
        lib["categories"][category] = []
    push(lib["categories"][category], name)

proc materials_in_category(lib, category):
    if dict_has(lib["categories"], category):
        return lib["categories"][category]
    return []

# ============================================================================
# Material to Surface Conversion (for render_system)
# ============================================================================

proc material_to_surface(mat):
    return {
        "albedo": mat["albedo"],
        "metallic": mat["metallic"],
        "roughness": mat["roughness"],
        "emissive": mat["emissive"],
        "alpha": mat["alpha"]
    }

# ============================================================================
# Material Editing Operations
# ============================================================================

proc set_albedo(mat, r, g, b):
    mat["albedo"] = [r, g, b]
    mat["dirty"] = true

proc set_metallic(mat, value):
    mat["metallic"] = value
    mat["dirty"] = true

proc set_roughness(mat, value):
    mat["roughness"] = value
    mat["dirty"] = true

proc set_emissive(mat, r, g, b, strength):
    mat["emissive"] = [r, g, b]
    mat["emissive_strength"] = strength
    mat["dirty"] = true

proc set_alpha(mat, value):
    mat["alpha"] = value
    if value < 1.0:
        mat["blend_mode"] = "alpha_blend"
    else:
        mat["blend_mode"] = "opaque"
    mat["dirty"] = true

proc set_tiling(mat, u, v):
    mat["tiling"] = [u, v]
    mat["dirty"] = true
