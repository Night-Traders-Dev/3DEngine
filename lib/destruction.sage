gc_disable()
# destruction.sage — Destructible Objects and Fracture System
# Supports: health-based destruction, debris spawning, fracture patterns,
# explosion force propagation, chain reactions
#
# Usage:
#   let wall = create_destructible(entity_id, 100, "stone")
#   let destroyed = apply_damage(wall, 60, hit_point, hit_dir)
#   if destroyed:
#       let debris = spawn_debris(wall, hit_point, explosion_force)

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length

# ============================================================================
# Material Properties — how different materials break
# ============================================================================

let _material_props = {}

proc register_destruction_material(name, props):
    _material_props[name] = props

proc default_destruction_materials():
    register_destruction_material("wood", {
        "strength": 50,
        "debris_count": 6,
        "debris_scale_min": 0.1,
        "debris_scale_max": 0.4,
        "debris_lifetime": 5.0,
        "debris_velocity": 3.0,
        "chunk_type": "splinter",
        "sound": "wood_break"
    })
    register_destruction_material("stone", {
        "strength": 150,
        "debris_count": 10,
        "debris_scale_min": 0.05,
        "debris_scale_max": 0.3,
        "debris_lifetime": 8.0,
        "debris_velocity": 5.0,
        "chunk_type": "chunk",
        "sound": "stone_break"
    })
    register_destruction_material("glass", {
        "strength": 20,
        "debris_count": 15,
        "debris_scale_min": 0.02,
        "debris_scale_max": 0.15,
        "debris_lifetime": 3.0,
        "debris_velocity": 2.0,
        "chunk_type": "shard",
        "sound": "glass_shatter"
    })
    register_destruction_material("metal", {
        "strength": 300,
        "debris_count": 4,
        "debris_scale_min": 0.1,
        "debris_scale_max": 0.5,
        "debris_lifetime": 10.0,
        "debris_velocity": 8.0,
        "chunk_type": "plate",
        "sound": "metal_tear"
    })
    register_destruction_material("concrete", {
        "strength": 200,
        "debris_count": 12,
        "debris_scale_min": 0.05,
        "debris_scale_max": 0.35,
        "debris_lifetime": 7.0,
        "debris_velocity": 6.0,
        "chunk_type": "rubble",
        "sound": "concrete_crumble"
    })

# ============================================================================
# Destructible Object
# ============================================================================

proc create_destructible(entity_id, health, material):
    let mat_props = nil
    if dict_has(_material_props, material):
        mat_props = _material_props[material]
    return {
        "entity_id": entity_id,
        "health": health,
        "max_health": health,
        "material": material,
        "material_props": mat_props,
        "destroyed": false,
        "damage_points": [],     # Track where damage was applied
        "cracks": [],            # Visual crack positions
        "debris": []             # Active debris particles
    }

proc apply_damage(destr, amount, hit_point, hit_direction):
    if destr["destroyed"]:
        return false
    destr["health"] = destr["health"] - amount
    push(destr["damage_points"], {"point": hit_point, "direction": hit_direction, "amount": amount})

    # Add visual crack at damage point
    let crack_severity = 1.0 - (destr["health"] / destr["max_health"])
    push(destr["cracks"], {"position": hit_point, "severity": crack_severity})

    if destr["health"] <= 0:
        destr["health"] = 0
        destr["destroyed"] = true
        return true
    return false

proc is_destroyed(destr):
    return destr["destroyed"]

proc destruction_health_percent(destr):
    return (destr["health"] / destr["max_health"]) * 100.0

# ============================================================================
# Debris System
# ============================================================================

proc spawn_debris(destr, origin, force):
    let debris = []
    let props = destr["material_props"]
    if props == nil:
        return debris

    let count = props["debris_count"]
    let i = 0
    while i < count:
        let angle = math.random() * 6.2831853
        let elevation = math.random() * 1.5 - 0.3
        let speed = props["debris_velocity"] * (0.5 + math.random() * 0.5) * force
        let vx = math.cos(angle) * speed
        let vy = elevation * speed + 2.0
        let vz = math.sin(angle) * speed
        let scale = props["debris_scale_min"] + math.random() * (props["debris_scale_max"] - props["debris_scale_min"])

        let piece = {
            "position": vec3(origin[0] + math.random() * 0.5 - 0.25,
                            origin[1] + math.random() * 0.5,
                            origin[2] + math.random() * 0.5 - 0.25),
            "velocity": vec3(vx, vy, vz),
            "rotation": math.random() * 6.283,
            "angular_velocity": (math.random() - 0.5) * 10.0,
            "scale": scale,
            "lifetime": props["debris_lifetime"] * (0.5 + math.random() * 0.5),
            "age": 0.0,
            "chunk_type": props["chunk_type"],
            "material": destr["material"],
            "grounded": false
        }
        push(debris, piece)
        i = i + 1

    destr["debris"] = debris
    return debris

proc update_debris(debris_list, dt):
    let alive = []
    let i = 0
    while i < len(debris_list):
        let d = debris_list[i]
        d["age"] = d["age"] + dt

        if d["age"] < d["lifetime"]:
            # Physics
            if not d["grounded"]:
                d["velocity"] = v3_add(d["velocity"], vec3(0.0, -9.81 * dt, 0.0))
                d["position"] = v3_add(d["position"], v3_scale(d["velocity"], dt))
                d["rotation"] = d["rotation"] + d["angular_velocity"] * dt

                # Ground collision
                if d["position"][1] < 0.0:
                    d["position"][1] = 0.0
                    d["velocity"][1] = 0.0 - d["velocity"][1] * 0.3
                    d["velocity"] = v3_scale(d["velocity"], 0.7)
                    d["angular_velocity"] = d["angular_velocity"] * 0.5
                    if d["velocity"][1] < 0.2:
                        d["grounded"] = true
                        d["velocity"] = vec3(0.0, 0.0, 0.0)

            push(alive, d)
        i = i + 1
    return alive

# ============================================================================
# Explosion — damages all destructibles in radius
# ============================================================================

proc create_explosion(origin, radius, damage, force):
    return {
        "origin": origin,
        "radius": radius,
        "damage": damage,
        "force": force,
        "age": 0.0,
        "lifetime": 0.5
    }

proc apply_explosion(explosion, destructibles):
    let results = []
    let i = 0
    while i < len(destructibles):
        let d = destructibles[i]
        if not d["destroyed"]:
            # Check distance (use entity position approximation)
            let dist = 1.0  # Would need entity position lookup
            if dist < explosion["radius"]:
                let falloff = 1.0 - (dist / explosion["radius"])
                let dmg = explosion["damage"] * falloff
                let direction = vec3(0.0, 1.0, 0.0)  # Simplified
                let destroyed = apply_damage(d, dmg, explosion["origin"], direction)
                if destroyed:
                    let debris = spawn_debris(d, explosion["origin"], explosion["force"] * falloff)
                    push(results, {"entity": d["entity_id"], "debris": debris})
        i = i + 1
    return results
