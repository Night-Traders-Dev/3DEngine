gc_disable()
# -----------------------------------------
# particles.sage - CPU Particle system for Sage Engine
# Emitters, lifetime, velocity, forces, color/size over life
# -----------------------------------------

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_length, v3_normalize

# ============================================================================
# Single particle
# ============================================================================
proc _create_particle():
    let p = {}
    p["alive"] = false
    p["position"] = vec3(0.0, 0.0, 0.0)
    p["velocity"] = vec3(0.0, 0.0, 0.0)
    p["life"] = 0.0
    p["max_life"] = 1.0
    p["size"] = 1.0
    p["size_start"] = 1.0
    p["size_end"] = 0.0
    p["color"] = [1.0, 1.0, 1.0, 1.0]
    p["color_start"] = [1.0, 1.0, 1.0, 1.0]
    p["color_end"] = [1.0, 1.0, 1.0, 0.0]
    p["rotation"] = 0.0
    p["angular_vel"] = 0.0
    return p

# ============================================================================
# Deterministic hash-based random for particles
# ============================================================================
let _pseed = [12345.6789]

proc _prand():
    _pseed[0] = _pseed[0] * 1103515245.0 + 12345.0
    _pseed[0] = _pseed[0] - math.floor(_pseed[0] / 2147483648.0) * 2147483648.0
    return _pseed[0] / 2147483648.0

proc _prand_range(lo, hi):
    return lo + _prand() * (hi - lo)

proc seed_particles(s):
    _pseed[0] = s

# ============================================================================
# Emitter shape
# ============================================================================
proc emitter_point():
    let s = {}
    s["type"] = "point"
    return s

proc emitter_sphere(radius):
    let s = {}
    s["type"] = "sphere"
    s["radius"] = radius
    return s

proc emitter_box(half_x, half_y, half_z):
    let s = {}
    s["type"] = "box"
    s["half"] = vec3(half_x, half_y, half_z)
    return s

proc emitter_cone(radius, angle):
    let s = {}
    s["type"] = "cone"
    s["radius"] = radius
    s["angle"] = angle
    return s

proc _sample_shape(shape):
    let stype = shape["type"]
    if stype == "point":
        return vec3(0.0, 0.0, 0.0)
    if stype == "sphere":
        let r = shape["radius"] * _prand()
        let theta = _prand() * 6.2831853
        let phi = _prand() * 3.1415926 - 1.5707963
        let cp = math.cos(phi)
        return vec3(math.cos(theta) * cp * r, math.sin(phi) * r, math.sin(theta) * cp * r)
    if stype == "box":
        let h = shape["half"]
        return vec3(_prand_range(0.0 - h[0], h[0]), _prand_range(0.0 - h[1], h[1]), _prand_range(0.0 - h[2], h[2]))
    if stype == "cone":
        let a = _prand() * shape["angle"]
        let theta = _prand() * 6.2831853
        let r = shape["radius"] * _prand()
        return vec3(math.cos(theta) * math.sin(a) * r, math.cos(a) * r, math.sin(theta) * math.sin(a) * r)
    return vec3(0.0, 0.0, 0.0)

# ============================================================================
# Particle Emitter
# ============================================================================
proc create_emitter(max_particles):
    let e = {}
    e["position"] = vec3(0.0, 0.0, 0.0)
    e["shape"] = emitter_point()
    e["max_particles"] = max_particles
    # Pool
    let pool = []
    let i = 0
    while i < max_particles:
        push(pool, _create_particle())
        i = i + 1
    e["particles"] = pool
    e["alive_count"] = 0
    # Emission
    e["rate"] = 10.0
    e["burst"] = 0
    e["emit_accum"] = 0.0
    e["active"] = true
    e["one_shot"] = false
    e["has_emitted"] = false
    # Particle properties
    e["life_min"] = 0.8
    e["life_max"] = 1.5
    e["speed_min"] = 1.0
    e["speed_max"] = 3.0
    e["direction"] = vec3(0.0, 1.0, 0.0)
    e["spread"] = 0.5
    e["gravity"] = vec3(0.0, -2.0, 0.0)
    e["drag"] = 0.01
    # Appearance
    e["size_start"] = 0.3
    e["size_end"] = 0.0
    e["color_start"] = [1.0, 1.0, 1.0, 1.0]
    e["color_end"] = [1.0, 1.0, 1.0, 0.0]
    e["angular_vel_min"] = 0.0
    e["angular_vel_max"] = 0.0
    return e

# ============================================================================
# Emit a single particle
# ============================================================================
proc _emit_one(emitter):
    let pool = emitter["particles"]
    # Find dead particle
    let i = 0
    while i < len(pool):
        if pool[i]["alive"] == false:
            let p = pool[i]
            p["alive"] = true
            p["position"] = v3_add(emitter["position"], _sample_shape(emitter["shape"]))
            # Direction with spread
            let dir = emitter["direction"]
            let sx = dir[0] + (_prand() - 0.5) * emitter["spread"] * 2.0
            let sy = dir[1] + (_prand() - 0.5) * emitter["spread"] * 2.0
            let sz = dir[2] + (_prand() - 0.5) * emitter["spread"] * 2.0
            let spd = _prand_range(emitter["speed_min"], emitter["speed_max"])
            let vdir = v3_normalize(vec3(sx, sy, sz))
            p["velocity"] = v3_scale(vdir, spd)
            p["life"] = 0.0
            p["max_life"] = _prand_range(emitter["life_min"], emitter["life_max"])
            p["size_start"] = emitter["size_start"]
            p["size_end"] = emitter["size_end"]
            p["size"] = emitter["size_start"]
            p["color_start"] = emitter["color_start"]
            p["color_end"] = emitter["color_end"]
            p["color"] = [emitter["color_start"][0], emitter["color_start"][1], emitter["color_start"][2], emitter["color_start"][3]]
            p["angular_vel"] = _prand_range(emitter["angular_vel_min"], emitter["angular_vel_max"])
            p["rotation"] = _prand() * 6.28
            emitter["alive_count"] = emitter["alive_count"] + 1
            return true
        i = i + 1
    return false

# ============================================================================
# Update emitter
# ============================================================================
proc update_emitter(emitter, dt):
    if emitter["active"] == false:
        _update_particles(emitter, dt)
        return nil
    # Emission
    if emitter["one_shot"]:
        if emitter["has_emitted"] == false:
            let b = 0
            while b < emitter["burst"]:
                _emit_one(emitter)
                b = b + 1
            emitter["has_emitted"] = true
            emitter["active"] = false
    else:
        emitter["emit_accum"] = emitter["emit_accum"] + emitter["rate"] * dt
        while emitter["emit_accum"] >= 1.0:
            _emit_one(emitter)
            emitter["emit_accum"] = emitter["emit_accum"] - 1.0
    _update_particles(emitter, dt)

proc _update_particles(emitter, dt):
    let pool = emitter["particles"]
    let grav = emitter["gravity"]
    let drag = emitter["drag"]
    let alive = 0
    let i = 0
    while i < len(pool):
        let p = pool[i]
        if p["alive"]:
            p["life"] = p["life"] + dt
            if p["life"] >= p["max_life"]:
                p["alive"] = false
                i = i + 1
                continue
            let t = p["life"] / p["max_life"]
            # Physics
            p["velocity"] = v3_add(p["velocity"], v3_scale(grav, dt))
            p["velocity"] = v3_scale(p["velocity"], 1.0 - drag)
            p["position"] = v3_add(p["position"], v3_scale(p["velocity"], dt))
            p["rotation"] = p["rotation"] + p["angular_vel"] * dt
            # Interpolate size
            p["size"] = p["size_start"] + (p["size_end"] - p["size_start"]) * t
            # Interpolate color
            let cs = p["color_start"]
            let ce = p["color_end"]
            p["color"][0] = cs[0] + (ce[0] - cs[0]) * t
            p["color"][1] = cs[1] + (ce[1] - cs[1]) * t
            p["color"][2] = cs[2] + (ce[2] - cs[2]) * t
            p["color"][3] = cs[3] + (ce[3] - cs[3]) * t
            alive = alive + 1
        i = i + 1
    emitter["alive_count"] = alive

# ============================================================================
# Collect alive particles (for rendering)
# ============================================================================
proc collect_particles(emitter):
    let result = []
    let pool = emitter["particles"]
    let i = 0
    while i < len(pool):
        if pool[i]["alive"]:
            push(result, pool[i])
        i = i + 1
    return result

# ============================================================================
# Reset emitter
# ============================================================================
proc reset_emitter(emitter):
    let pool = emitter["particles"]
    let i = 0
    while i < len(pool):
        pool[i]["alive"] = false
        i = i + 1
    emitter["alive_count"] = 0
    emitter["emit_accum"] = 0.0
    emitter["has_emitted"] = false
    emitter["active"] = true

# ============================================================================
# Particle System Manager
# ============================================================================
proc create_particle_system():
    let ps = {}
    ps["emitters"] = {}
    return ps

proc add_emitter_to_system(ps, name, emitter):
    ps["emitters"][name] = emitter

proc get_emitter(ps, name):
    if dict_has(ps["emitters"], name) == false:
        return nil
    return ps["emitters"][name]

proc update_particle_system(ps, dt):
    let names = dict_keys(ps["emitters"])
    let i = 0
    while i < len(names):
        update_emitter(ps["emitters"][names[i]], dt)
        i = i + 1

proc total_alive_particles(ps):
    let total = 0
    let names = dict_keys(ps["emitters"])
    let i = 0
    while i < len(names):
        total = total + ps["emitters"][names[i]]["alive_count"]
        i = i + 1
    return total
