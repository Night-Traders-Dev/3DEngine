gc_disable()
# splatmap.sage — Terrain Multi-Texture Splatmap System
# Blends up to 4 terrain materials based on a weight map.
# Supports: height-based auto-painting, slope-based rules, manual painting,
# material layers with tiling and normal maps.
#
# Usage:
#   let splat = create_splatmap(terrain_width, terrain_depth, resolution)
#   add_terrain_layer(splat, "grass", [0.3, 0.6, 0.2], 4.0)
#   add_terrain_layer(splat, "rock", [0.5, 0.5, 0.45], 8.0)
#   auto_paint_by_height(splat, terrain)
#   auto_paint_by_slope(splat, terrain)

import math

# ============================================================================
# Splatmap Creation
# ============================================================================

proc create_splatmap(width, depth, resolution):
    let w = width * resolution
    let h = depth * resolution
    if w < 1:
        w = 1
    if h < 1:
        h = 1
    let total = w * h
    # 4 channels per pixel (RGBA — one per layer)
    let data = []
    let i = 0
    while i < total:
        push(data, [1.0, 0.0, 0.0, 0.0])  # Default: 100% layer 0
        i = i + 1
    return {
        "width": w,
        "height": h,
        "resolution": resolution,
        "terrain_width": width,
        "terrain_depth": depth,
        "data": data,
        "layers": [],
        "dirty": true
    }

# ============================================================================
# Terrain Layers
# ============================================================================

proc add_terrain_layer(splat, name, base_color, tiling):
    let layer = {
        "name": name,
        "base_color": base_color,
        "tiling": tiling,
        "roughness": 0.8,
        "metallic": 0.0,
        "normal_strength": 1.0,
        "texture": nil,
        "normal_map": nil
    }
    push(splat["layers"], layer)
    return len(splat["layers"]) - 1

proc set_layer_properties(splat, layer_idx, roughness, metallic, normal_strength):
    if layer_idx >= 0 and layer_idx < len(splat["layers"]):
        splat["layers"][layer_idx]["roughness"] = roughness
        splat["layers"][layer_idx]["metallic"] = metallic
        splat["layers"][layer_idx]["normal_strength"] = normal_strength

# ============================================================================
# Manual Painting
# ============================================================================

proc paint_splat(splat, world_x, world_z, layer_idx, radius, strength):
    let cx = world_x * splat["resolution"]
    let cz = world_z * splat["resolution"]
    let r = radius * splat["resolution"]
    let min_x = cx - r
    let max_x = cx + r
    let min_z = cz - r
    let max_z = cz + r
    if min_x < 0:
        min_x = 0
    if min_z < 0:
        min_z = 0
    if max_x >= splat["width"]:
        max_x = splat["width"] - 1
    if max_z >= splat["height"]:
        max_z = splat["height"] - 1

    let iz = min_z
    while iz <= max_z:
        let ix = min_x
        while ix <= max_x:
            let dx = ix - cx
            let dz = iz - cz
            let dist = math.sqrt(dx * dx + dz * dz)
            if dist <= r:
                let falloff = 1.0 - (dist / r)
                let weight = strength * falloff
                let pixel_idx = iz * splat["width"] + ix
                if pixel_idx >= 0 and pixel_idx < len(splat["data"]):
                    _apply_weight(splat["data"][pixel_idx], layer_idx, weight)
            ix = ix + 1
        iz = iz + 1
    splat["dirty"] = true

proc _apply_weight(pixel, layer_idx, amount):
    if layer_idx < 0 or layer_idx > 3:
        return
    # Add weight to target layer
    pixel[layer_idx] = pixel[layer_idx] + amount
    # Normalize so all channels sum to 1.0
    let total = pixel[0] + pixel[1] + pixel[2] + pixel[3]
    if total > 0.001:
        pixel[0] = pixel[0] / total
        pixel[1] = pixel[1] / total
        pixel[2] = pixel[2] / total
        pixel[3] = pixel[3] / total

# ============================================================================
# Auto-Painting by Height
# ============================================================================

proc auto_paint_by_height(splat, terrain, rules):
    # rules: [{"layer": idx, "min_height": h, "max_height": h, "blend": b}]
    let iz = 0
    while iz < splat["height"]:
        let ix = 0
        while ix < splat["width"]:
            let wx = ix / splat["resolution"]
            let wz = iz / splat["resolution"]
            let height = 0.0
            if dict_has(terrain, "height_fn") and terrain["height_fn"] != nil:
                height = terrain["height_fn"](wx, wz)
            let pixel_idx = iz * splat["width"] + ix
            if pixel_idx < len(splat["data"]):
                let pixel = [0.0, 0.0, 0.0, 0.0]
                let ri = 0
                while ri < len(rules):
                    let rule = rules[ri]
                    let li = rule["layer"]
                    if li >= 0 and li <= 3:
                        if height >= rule["min_height"] and height <= rule["max_height"]:
                            let blend = rule["blend"]
                            # Smooth blend at edges
                            let edge_lo = height - rule["min_height"]
                            let edge_hi = rule["max_height"] - height
                            let edge = edge_lo
                            if edge_hi < edge:
                                edge = edge_hi
                            let factor = 1.0
                            if edge < blend and blend > 0:
                                factor = edge / blend
                            pixel[li] = pixel[li] + factor
                    ri = ri + 1
                # Normalize
                let total = pixel[0] + pixel[1] + pixel[2] + pixel[3]
                if total > 0.001:
                    pixel[0] = pixel[0] / total
                    pixel[1] = pixel[1] / total
                    pixel[2] = pixel[2] / total
                    pixel[3] = pixel[3] / total
                else:
                    pixel[0] = 1.0
                splat["data"][pixel_idx] = pixel
            ix = ix + 1
        iz = iz + 1
    splat["dirty"] = true

# ============================================================================
# Auto-Painting by Slope
# ============================================================================

proc auto_paint_by_slope(splat, terrain, flat_layer, steep_layer, threshold):
    let iz = 1
    while iz < splat["height"] - 1:
        let ix = 1
        while ix < splat["width"] - 1:
            let wx = ix / splat["resolution"]
            let wz = iz / splat["resolution"]
            let step = 1.0 / splat["resolution"]
            let h = 0.0
            let hx = 0.0
            let hz = 0.0
            if dict_has(terrain, "height_fn") and terrain["height_fn"] != nil:
                h = terrain["height_fn"](wx, wz)
                hx = terrain["height_fn"](wx + step, wz)
                hz = terrain["height_fn"](wx, wz + step)
            let slope_x = (hx - h) / step
            let slope_z = (hz - h) / step
            let slope = math.sqrt(slope_x * slope_x + slope_z * slope_z)

            let pixel_idx = iz * splat["width"] + ix
            if pixel_idx < len(splat["data"]):
                let pixel = splat["data"][pixel_idx]
                if slope > threshold:
                    _apply_weight(pixel, steep_layer, slope * 0.5)
                else:
                    _apply_weight(pixel, flat_layer, (1.0 - slope / threshold) * 0.3)
            ix = ix + 1
        iz = iz + 1
    splat["dirty"] = true

# ============================================================================
# Sampling — get blended material at a world position
# ============================================================================

proc sample_splatmap(splat, world_x, world_z):
    let px = world_x * splat["resolution"]
    let pz = world_z * splat["resolution"]
    let ix = int(px)
    let iz = int(pz)
    if ix < 0:
        ix = 0
    if iz < 0:
        iz = 0
    if ix >= splat["width"]:
        ix = splat["width"] - 1
    if iz >= splat["height"]:
        iz = splat["height"] - 1
    let pixel_idx = iz * splat["width"] + ix
    if pixel_idx < len(splat["data"]):
        let weights = splat["data"][pixel_idx]
        # Blend colors from layers
        let r = 0.0
        let g = 0.0
        let b = 0.0
        let li = 0
        while li < len(splat["layers"]) and li < 4:
            let layer = splat["layers"][li]
            r = r + layer["base_color"][0] * weights[li]
            g = g + layer["base_color"][1] * weights[li]
            b = b + layer["base_color"][2] * weights[li]
            li = li + 1
        return {"color": [r, g, b], "weights": weights}
    return {"color": [0.5, 0.5, 0.5], "weights": [1.0, 0.0, 0.0, 0.0]}
