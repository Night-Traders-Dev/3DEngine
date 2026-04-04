gc_disable()
# -----------------------------------------
# textures.sage - Texture loading and management for Sage Engine
# Uses gpu.load_texture (stb_image) for PNG/JPG/HDR
# -----------------------------------------

import gpu

# ============================================================================
# Texture cache
# ============================================================================
proc create_texture_cache():
    let tc = {}
    tc["textures"] = {}
    tc["samplers"] = {}
    tc["default_sampler"] = -1
    tc["nearest_sampler"] = -1
    return tc

proc init_texture_cache(tc):
    tc["default_sampler"] = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_REPEAT)
    tc["nearest_sampler"] = gpu.create_sampler(gpu.FILTER_NEAREST, gpu.FILTER_NEAREST, gpu.ADDRESS_REPEAT)
    # Create 1x1 white fallback texture
    let white_img = gpu.create_image(1, 1, 1, gpu.FORMAT_RGBA8, gpu.IMAGE_SAMPLED | gpu.IMAGE_TRANSFER_DST)
    tc["textures"]["_white"] = white_img
    tc["textures"]["_black"] = white_img
    return tc

# ============================================================================
# Load texture from file (cached)
# ============================================================================
proc load_texture(tc, name, path):
    if dict_has(tc["textures"], name):
        return tc["textures"][name]
    let handle = gpu.load_texture(path)
    if handle < 0:
        print "TEXTURE ERROR: Failed to load '" + path + "'"
        return tc["textures"]["_white"]
    tc["textures"][name] = handle
    return handle

proc get_texture(tc, name):
    if dict_has(tc["textures"], name) == false:
        return tc["textures"]["_white"]
    return tc["textures"][name]

proc has_texture(tc, name):
    return dict_has(tc["textures"], name)

proc texture_count(tc):
    return len(dict_keys(tc["textures"]))

# ============================================================================
# Get texture dimensions
# ============================================================================
proc texture_size(tc, name):
    if dict_has(tc["textures"], name) == false:
        return [1, 1]
    let handle = tc["textures"][name]
    let dims = gpu.texture_dims(handle)
    if dims == nil:
        return [1, 1]
    return [dims["width"], dims["height"]]

# ============================================================================
# Sampler management
# ============================================================================
proc get_linear_sampler(tc):
    return tc["default_sampler"]

proc get_nearest_sampler(tc):
    return tc["nearest_sampler"]

proc create_custom_sampler(tc, name, mag, min_f, addr):
    let s = gpu.create_sampler(mag, min_f, addr)
    tc["samplers"][name] = s
    return s
