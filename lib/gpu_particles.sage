gc_disable()
# gpu_particles.sage — Advanced GPU Particle System (Niagara-like)
# Modular particle system with emitter modules, events, and attribute readers.
# Supports: spawn modules, update modules, render modules, particle events,
# attribute readers, ribbons, mesh particles, GPU simulation.

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length

# ============================================================================
# Particle System
# ============================================================================

proc create_particle_system(name, max_particles):
    return {
        "name": name,
        "max": max_particles,
        "particles": [],
        "emitters": [],
        "spawn_modules": [],
        "update_modules": [],
        "render_modules": [],
        "events": {},
        "time": 0.0,
        "active": true,
        "warmup_time": 0.0
    }

# ============================================================================
# Particle Data
# ============================================================================

proc _create_particle():
    return {
        "position": vec3(0.0, 0.0, 0.0),
        "velocity": vec3(0.0, 0.0, 0.0),
        "acceleration": vec3(0.0, 0.0, 0.0),
        "color": [1.0, 1.0, 1.0, 1.0],
        "size": 1.0,
        "age": 0.0,
        "lifetime": 2.0,
        "rotation": 0.0,
        "angular_velocity": 0.0,
        "mass": 1.0,
        "alive": true,
        "custom": {}
    }

# ============================================================================
# Spawn Modules — control how particles are created
# ============================================================================

proc spawn_rate_module(rate):
    return {"type": "spawn_rate", "rate": rate, "accumulator": 0.0}

proc spawn_burst_module(count, interval):
    return {"type": "spawn_burst", "count": count, "interval": interval, "timer": 0.0}

proc spawn_shape_sphere(center, radius):
    return {"type": "shape_sphere", "center": center, "radius": radius}

proc spawn_shape_cone(origin, direction, angle, speed_min, speed_max):
    return {"type": "shape_cone", "origin": origin, "direction": direction, "angle": angle, "speed_min": speed_min, "speed_max": speed_max}

proc spawn_shape_box(min_corner, max_corner):
    return {"type": "shape_box", "min": min_corner, "max": max_corner}

# ============================================================================
# Update Modules — modify particles each frame
# ============================================================================

proc gravity_module(strength):
    return {"type": "gravity", "strength": strength}

proc drag_module(coefficient):
    return {"type": "drag", "coefficient": coefficient}

proc noise_module(frequency, amplitude):
    return {"type": "noise", "frequency": frequency, "amplitude": amplitude}

proc color_over_life_module(start_color, end_color):
    return {"type": "color_over_life", "start": start_color, "end": end_color}

proc size_over_life_module(start_size, end_size):
    return {"type": "size_over_life", "start": start_size, "end": end_size}

proc orbit_module(center, speed, radius):
    return {"type": "orbit", "center": center, "speed": speed, "radius": radius}

proc attract_module(target, strength, kill_radius):
    return {"type": "attract", "target": target, "strength": strength, "kill_radius": kill_radius}

proc collision_module(ground_y, bounce, friction):
    return {"type": "collision", "ground_y": ground_y, "bounce": bounce, "friction": friction}

proc kill_zone_module(min_bounds, max_bounds):
    return {"type": "kill_zone", "min": min_bounds, "max": max_bounds}

# ============================================================================
# Render Modules
# ============================================================================

proc sprite_renderer_module():
    return {"type": "sprite"}

proc ribbon_renderer_module(width, segments):
    return {"type": "ribbon", "width": width, "segments": segments}

proc mesh_renderer_module(mesh_gpu):
    return {"type": "mesh", "mesh": mesh_gpu}

# ============================================================================
# Events — trigger behavior on particle lifecycle
# ============================================================================

proc on_spawn_event(system, callback):
    system["events"]["on_spawn"] = callback

proc on_death_event(system, callback):
    system["events"]["on_death"] = callback

proc on_collision_event(system, callback):
    system["events"]["on_collision"] = callback

# ============================================================================
# System Update
# ============================================================================

proc add_spawn_module(system, module):
    push(system["spawn_modules"], module)

proc add_update_module(system, module):
    push(system["update_modules"], module)

proc add_render_module(system, module):
    push(system["render_modules"], module)

proc update_particle_system(system, dt):
    if not system["active"]:
        return
    system["time"] = system["time"] + dt

    # Spawn phase
    let si = 0
    while si < len(system["spawn_modules"]):
        let mod = system["spawn_modules"][si]
        if mod["type"] == "spawn_rate":
            mod["accumulator"] = mod["accumulator"] + mod["rate"] * dt
            while mod["accumulator"] >= 1.0 and len(system["particles"]) < system["max"]:
                mod["accumulator"] = mod["accumulator"] - 1.0
                let p = _create_particle()
                _apply_spawn_shape(system, p)
                push(system["particles"], p)
                if dict_has(system["events"], "on_spawn"):
                    system["events"]["on_spawn"](p)
        elif mod["type"] == "spawn_burst":
            mod["timer"] = mod["timer"] + dt
            if mod["timer"] >= mod["interval"]:
                mod["timer"] = 0.0
                let bi = 0
                while bi < mod["count"] and len(system["particles"]) < system["max"]:
                    let p = _create_particle()
                    _apply_spawn_shape(system, p)
                    push(system["particles"], p)
                    bi = bi + 1
        si = si + 1

    # Update phase
    let alive = []
    let pi = 0
    while pi < len(system["particles"]):
        let p = system["particles"][pi]
        p["age"] = p["age"] + dt
        if p["age"] >= p["lifetime"]:
            p["alive"] = false
            if dict_has(system["events"], "on_death"):
                system["events"]["on_death"](p)
            pi = pi + 1
            continue

        # Apply update modules
        let mi = 0
        while mi < len(system["update_modules"]):
            _apply_update_module(system["update_modules"][mi], p, dt, system)
            mi = mi + 1

        # Integrate
        p["velocity"] = v3_add(p["velocity"], v3_scale(p["acceleration"], dt))
        p["position"] = v3_add(p["position"], v3_scale(p["velocity"], dt))
        p["rotation"] = p["rotation"] + p["angular_velocity"] * dt
        p["acceleration"] = vec3(0.0, 0.0, 0.0)

        push(alive, p)
        pi = pi + 1
    system["particles"] = alive

proc _apply_spawn_shape(system, particle):
    let si = 0
    while si < len(system["spawn_modules"]):
        let mod = system["spawn_modules"][si]
        if mod["type"] == "shape_sphere":
            let angle1 = math.random() * 6.2831853
            let angle2 = math.random() * 3.1415926
            let r = math.random() * mod["radius"]
            particle["position"] = v3_add(mod["center"], vec3(
                math.cos(angle1) * math.sin(angle2) * r,
                math.cos(angle2) * r,
                math.sin(angle1) * math.sin(angle2) * r
            ))
        elif mod["type"] == "shape_cone":
            let spread = mod["angle"] * 0.01745329
            let angle = math.random() * 6.2831853
            let cone_r = math.random() * math.sin(spread)
            let speed = mod["speed_min"] + math.random() * (mod["speed_max"] - mod["speed_min"])
            particle["position"] = mod["origin"]
            particle["velocity"] = v3_scale(v3_add(mod["direction"], vec3(math.cos(angle) * cone_r, 0.0, math.sin(angle) * cone_r)), speed)
        elif mod["type"] == "shape_box":
            particle["position"] = vec3(
                mod["min"][0] + math.random() * (mod["max"][0] - mod["min"][0]),
                mod["min"][1] + math.random() * (mod["max"][1] - mod["min"][1]),
                mod["min"][2] + math.random() * (mod["max"][2] - mod["min"][2])
            )
        si = si + 1

proc _apply_update_module(mod, particle, dt, system):
    if mod["type"] == "gravity":
        particle["acceleration"] = v3_add(particle["acceleration"], vec3(0.0, 0.0 - mod["strength"], 0.0))
    elif mod["type"] == "drag":
        particle["velocity"] = v3_scale(particle["velocity"], 1.0 - mod["coefficient"] * dt)
    elif mod["type"] == "color_over_life":
        let t = particle["age"] / particle["lifetime"]
        particle["color"][0] = mod["start"][0] + (mod["end"][0] - mod["start"][0]) * t
        particle["color"][1] = mod["start"][1] + (mod["end"][1] - mod["start"][1]) * t
        particle["color"][2] = mod["start"][2] + (mod["end"][2] - mod["start"][2]) * t
        particle["color"][3] = mod["start"][3] + (mod["end"][3] - mod["start"][3]) * t
    elif mod["type"] == "size_over_life":
        let t = particle["age"] / particle["lifetime"]
        particle["size"] = mod["start"] + (mod["end"] - mod["start"]) * t
    elif mod["type"] == "collision":
        if particle["position"][1] < mod["ground_y"]:
            particle["position"][1] = mod["ground_y"]
            particle["velocity"][1] = 0.0 - particle["velocity"][1] * mod["bounce"]
            particle["velocity"][0] = particle["velocity"][0] * mod["friction"]
            particle["velocity"][2] = particle["velocity"][2] * mod["friction"]
            if dict_has(system["events"], "on_collision"):
                system["events"]["on_collision"](particle)
    elif mod["type"] == "attract":
        let to_target = v3_sub(mod["target"], particle["position"])
        let dist = v3_length(to_target)
        if dist > 0.01:
            particle["acceleration"] = v3_add(particle["acceleration"], v3_scale(v3_normalize(to_target), mod["strength"]))
        if dist < mod["kill_radius"]:
            particle["alive"] = false

proc particle_count(system):
    return len(system["particles"])

proc particle_positions(system):
    let positions = []
    let i = 0
    while i < len(system["particles"]):
        push(positions, system["particles"][i]["position"])
        i = i + 1
    return positions
