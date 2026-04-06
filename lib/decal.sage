gc_disable()
# decal.sage — Projected Decal System
# Supports: impact marks, blood splatter, bullet holes, scorch marks,
# footprints, tire tracks, spray paint. Decals are projected onto
# surfaces and fade over time.
#
# Usage:
#   let dm = create_decal_manager(256)
#   spawn_decal(dm, "bullet_hole", hit_pos, hit_normal, 0.2)
#   update_decals(dm, dt)
#   draw_decals(dm, cmd, mat, view_proj)

from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_cross, v3_dot

# ============================================================================
# Decal Types
# ============================================================================

let _decal_types = {}

proc register_decal_type(id, properties):
    _decal_types[id] = properties

proc default_decal_types():
    register_decal_type("bullet_hole", {
        "size": 0.05,
        "color": [0.1, 0.1, 0.1, 0.9],
        "lifetime": 30.0,
        "fade_time": 5.0
    })
    register_decal_type("blood_splatter", {
        "size": 0.3,
        "color": [0.6, 0.05, 0.02, 0.85],
        "lifetime": 60.0,
        "fade_time": 10.0
    })
    register_decal_type("scorch_mark", {
        "size": 0.8,
        "color": [0.15, 0.12, 0.1, 0.7],
        "lifetime": 120.0,
        "fade_time": 20.0
    })
    register_decal_type("footprint", {
        "size": 0.12,
        "color": [0.3, 0.25, 0.2, 0.4],
        "lifetime": 15.0,
        "fade_time": 5.0
    })
    register_decal_type("tire_track", {
        "size": 0.15,
        "color": [0.15, 0.15, 0.15, 0.5],
        "lifetime": 20.0,
        "fade_time": 8.0
    })
    register_decal_type("crack", {
        "size": 0.4,
        "color": [0.2, 0.2, 0.2, 0.8],
        "lifetime": 999.0,
        "fade_time": 0.0
    })
    register_decal_type("spray_paint", {
        "size": 0.5,
        "color": [0.9, 0.2, 0.1, 0.95],
        "lifetime": 999.0,
        "fade_time": 0.0
    })

# ============================================================================
# Decal Manager
# ============================================================================

proc create_decal_manager(max_decals):
    return {
        "decals": [],
        "max_decals": max_decals,
        "total_spawned": 0
    }

proc spawn_decal(dm, type_id, position, normal, size_override):
    let props = nil
    if dict_has(_decal_types, type_id):
        props = _decal_types[type_id]
    if props == nil:
        props = {"size": 0.2, "color": [1.0, 1.0, 1.0, 1.0], "lifetime": 30.0, "fade_time": 5.0}

    let size = props["size"]
    if size_override > 0:
        size = size_override

    # Build tangent frame from normal
    let up = vec3(0.0, 1.0, 0.0)
    if v3_dot(normal, up) > 0.99:
        up = vec3(1.0, 0.0, 0.0)
    let tangent = v3_normalize(v3_cross(up, normal))
    let bitangent = v3_cross(normal, tangent)

    let decal = {
        "type": type_id,
        "position": position,
        "normal": normal,
        "tangent": tangent,
        "bitangent": bitangent,
        "size": size,
        "color": [props["color"][0], props["color"][1], props["color"][2], props["color"][3]],
        "lifetime": props["lifetime"],
        "fade_time": props["fade_time"],
        "age": 0.0,
        "alpha": props["color"][3]
    }

    # Evict oldest if at capacity
    if len(dm["decals"]) >= dm["max_decals"]:
        # Remove first (oldest)
        let new_list = []
        let i = 1
        while i < len(dm["decals"]):
            push(new_list, dm["decals"][i])
            i = i + 1
        dm["decals"] = new_list

    push(dm["decals"], decal)
    dm["total_spawned"] = dm["total_spawned"] + 1
    return decal

proc update_decals(dm, dt):
    let alive = []
    let i = 0
    while i < len(dm["decals"]):
        let d = dm["decals"][i]
        d["age"] = d["age"] + dt

        if d["age"] < d["lifetime"]:
            # Fade near end of lifetime
            if d["fade_time"] > 0 and d["age"] > d["lifetime"] - d["fade_time"]:
                let fade_progress = (d["age"] - (d["lifetime"] - d["fade_time"])) / d["fade_time"]
                d["color"][3] = d["alpha"] * (1.0 - fade_progress)
            push(alive, d)
        i = i + 1
    dm["decals"] = alive

proc decal_count(dm):
    return len(dm["decals"])

proc clear_decals(dm):
    dm["decals"] = []
