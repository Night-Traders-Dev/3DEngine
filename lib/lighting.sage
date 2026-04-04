gc_disable()
# -----------------------------------------
# lighting.sage - Lighting system for Sage Engine
# Manages scene lights and packs data into a Vulkan UBO
# Supports point, directional, and spot lights (up to 16)
# -----------------------------------------

import gpu
from math3d import vec3, v3_normalize

let LIGHT_TYPE_POINT = 0
let LIGHT_TYPE_DIRECTIONAL = 1
let LIGHT_TYPE_SPOT = 2
let MAX_LIGHTS = 16

# UBO layout (must match engine_lit.frag SceneUBO):
# lights[16]:     each 48 bytes (3 * vec4)  = 768 bytes
# viewPos:        16 bytes (vec4)
# ambient:        16 bytes (vec4)
# fogParams:      16 bytes (vec4)
# fogColor:       16 bytes (vec4)
# Total: 832 bytes
let SCENE_UBO_SIZE = 832

# ============================================================================
# Light Scene - holds all lights and scene parameters
# ============================================================================
proc create_light_scene():
    let ls = {}
    ls["lights"] = []
    ls["ambient_color"] = vec3(0.15, 0.15, 0.2)
    ls["ambient_intensity"] = 0.3
    ls["fog_enabled"] = false
    ls["fog_start"] = 50.0
    ls["fog_end"] = 200.0
    ls["fog_density"] = 0.01
    ls["fog_color"] = vec3(0.6, 0.65, 0.7)
    ls["view_pos"] = vec3(0.0, 0.0, 0.0)
    ls["ubo"] = -1
    ls["desc_layout"] = -1
    ls["desc_pool"] = -1
    ls["desc_set"] = -1
    ls["dirty"] = true
    return ls

# ============================================================================
# Light constructors
# ============================================================================
proc point_light(px, py, pz, r, g, b, intensity, radius):
    let l = {}
    l["type"] = LIGHT_TYPE_POINT
    l["position"] = vec3(px, py, pz)
    l["color"] = vec3(r, g, b)
    l["intensity"] = intensity
    l["radius"] = radius
    l["inner_cone"] = 0.0
    l["outer_cone"] = 0.0
    l["cast_shadows"] = false
    l["enabled"] = true
    return l

proc directional_light(dx, dy, dz, r, g, b, intensity):
    let l = {}
    l["type"] = LIGHT_TYPE_DIRECTIONAL
    l["position"] = v3_normalize(vec3(dx, dy, dz))
    l["color"] = vec3(r, g, b)
    l["intensity"] = intensity
    l["radius"] = 0.0
    l["inner_cone"] = 0.0
    l["outer_cone"] = 0.0
    l["cast_shadows"] = true
    l["enabled"] = true
    return l

proc spot_light(px, py, pz, r, g, b, intensity, radius, inner_deg, outer_deg):
    import math
    let l = {}
    l["type"] = LIGHT_TYPE_SPOT
    l["position"] = vec3(px, py, pz)
    l["color"] = vec3(r, g, b)
    l["intensity"] = intensity
    l["radius"] = radius
    l["inner_cone"] = math.cos(inner_deg * 3.14159265 / 180.0)
    l["outer_cone"] = math.cos(outer_deg * 3.14159265 / 180.0)
    l["cast_shadows"] = false
    l["enabled"] = true
    return l

# ============================================================================
# Add/remove lights
# ============================================================================
proc add_light(ls, light):
    if len(ls["lights"]) >= MAX_LIGHTS:
        print "WARNING: Max lights (" + str(MAX_LIGHTS) + ") reached"
        return -1
    push(ls["lights"], light)
    ls["dirty"] = true
    return len(ls["lights"]) - 1

proc remove_light(ls, index):
    if index < 0 or index >= len(ls["lights"]):
        return nil
    let new_lights = []
    let i = 0
    while i < len(ls["lights"]):
        if i != index:
            push(new_lights, ls["lights"][i])
        i = i + 1
    ls["lights"] = new_lights
    ls["dirty"] = true

proc get_light(ls, index):
    if index < 0 or index >= len(ls["lights"]):
        return nil
    return ls["lights"][index]

proc light_count(ls):
    let count = 0
    let i = 0
    while i < len(ls["lights"]):
        if ls["lights"][i]["enabled"]:
            count = count + 1
        i = i + 1
    return count

# ============================================================================
# Scene parameters
# ============================================================================
proc set_ambient(ls, r, g, b, intensity):
    ls["ambient_color"] = vec3(r, g, b)
    ls["ambient_intensity"] = intensity
    ls["dirty"] = true

proc set_fog(ls, enabled, start, end_dist, color_r, color_g, color_b):
    ls["fog_enabled"] = enabled
    ls["fog_start"] = start
    ls["fog_end"] = end_dist
    ls["fog_color"] = vec3(color_r, color_g, color_b)
    ls["dirty"] = true

proc set_view_position(ls, pos):
    ls["view_pos"] = pos
    ls["dirty"] = true

# ============================================================================
# GPU setup - create UBO, descriptor layout, pool, set
# ============================================================================
proc init_light_gpu(ls):
    # Create UBO buffer (host-visible for easy updates)
    let mem_flags = gpu.MEMORY_HOST_VISIBLE | gpu.MEMORY_HOST_COHERENT
    let ubo = gpu.create_buffer(SCENE_UBO_SIZE, gpu.BUFFER_UNIFORM, mem_flags)
    ls["ubo"] = ubo

    # Descriptor layout: binding 0 = uniform buffer, all stages
    let b0 = {}
    b0["binding"] = 0
    b0["type"] = gpu.DESC_UNIFORM_BUFFER
    b0["stage"] = gpu.STAGE_ALL
    b0["count"] = 1
    ls["desc_layout"] = gpu.create_descriptor_layout([b0])

    # Descriptor pool
    let pool_size = {}
    pool_size["type"] = gpu.DESC_UNIFORM_BUFFER
    pool_size["count"] = 1
    ls["desc_pool"] = gpu.create_descriptor_pool(1, [pool_size])

    # Allocate and bind descriptor set
    ls["desc_set"] = gpu.allocate_descriptor_set(ls["desc_pool"], ls["desc_layout"])
    gpu.update_descriptor(ls["desc_set"], 0, gpu.DESC_UNIFORM_BUFFER, ubo)

    print "Lighting GPU initialized (UBO " + str(SCENE_UBO_SIZE) + " bytes)"
    return ls

# ============================================================================
# Pack lights into float array and upload to UBO
# ============================================================================
proc update_light_ubo(ls):
    let data = []

    # Pack each light: 3 vec4s = 12 floats per light
    let i = 0
    let active_count = 0
    while i < MAX_LIGHTS:
        if i < len(ls["lights"]) and ls["lights"][i]["enabled"]:
            let l = ls["lights"][i]
            # vec4 position (xyz + type)
            push(data, l["position"][0])
            push(data, l["position"][1])
            push(data, l["position"][2])
            push(data, l["type"] + 0.0)
            # vec4 color (rgb + intensity)
            push(data, l["color"][0])
            push(data, l["color"][1])
            push(data, l["color"][2])
            push(data, l["intensity"])
            # vec4 params (radius, inner_cone, outer_cone, 0)
            push(data, l["radius"])
            push(data, l["inner_cone"])
            push(data, l["outer_cone"])
            push(data, 0.0)
            active_count = active_count + 1
        else:
            # Empty light slot (12 zeros)
            let z = 0
            while z < 12:
                push(data, 0.0)
                z = z + 1
        i = i + 1

    # viewPos (xyz + light count)
    push(data, ls["view_pos"][0])
    push(data, ls["view_pos"][1])
    push(data, ls["view_pos"][2])
    push(data, active_count + 0.0)

    # ambient (rgb + intensity)
    push(data, ls["ambient_color"][0])
    push(data, ls["ambient_color"][1])
    push(data, ls["ambient_color"][2])
    push(data, ls["ambient_intensity"])

    # fogParams (start, end, density, enable)
    push(data, ls["fog_start"])
    push(data, ls["fog_end"])
    push(data, ls["fog_density"])
    if ls["fog_enabled"]:
        push(data, 1.0)
    else:
        push(data, 0.0)

    # fogColor (rgb + pad)
    push(data, ls["fog_color"][0])
    push(data, ls["fog_color"][1])
    push(data, ls["fog_color"][2])
    push(data, 0.0)

    # Upload to UBO
    gpu.buffer_upload(ls["ubo"], data)
    ls["dirty"] = false
