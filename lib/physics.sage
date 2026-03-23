gc_disable()
# -----------------------------------------
# physics.sage - Rigid body physics for Sage Engine
# Gravity, velocity integration, collision response
# -----------------------------------------

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_dot, v3_length, v3_normalize
from collision import aabb_vs_aabb, sphere_vs_sphere, sphere_vs_aabb

let GRAVITY = vec3(0.0, -9.81, 0.0)

# ============================================================================
# Rigidbody component
# ============================================================================
proc RigidbodyComponent(mass):
    let rb = {}
    rb["mass"] = mass
    rb["inv_mass"] = 0.0
    if mass > 0.0001:
        rb["inv_mass"] = 1.0 / mass
    rb["velocity"] = vec3(0.0, 0.0, 0.0)
    rb["acceleration"] = vec3(0.0, 0.0, 0.0)
    rb["forces"] = vec3(0.0, 0.0, 0.0)
    rb["use_gravity"] = true
    rb["is_kinematic"] = false
    rb["restitution"] = 0.3
    rb["friction"] = 0.5
    rb["linear_damping"] = 0.01
    rb["grounded"] = false
    rb["ground_normal"] = vec3(0.0, 1.0, 0.0)
    return rb

# Static body (infinite mass, doesn't move)
proc StaticBodyComponent():
    let rb = RigidbodyComponent(0.0)
    rb["is_kinematic"] = true
    rb["use_gravity"] = false
    return rb

# ============================================================================
# Collider component
# ============================================================================
proc BoxColliderComponent(half_x, half_y, half_z):
    let c = {}
    c["type"] = "aabb"
    c["half"] = vec3(half_x, half_y, half_z)
    c["offset"] = vec3(0.0, 0.0, 0.0)
    c["is_trigger"] = false
    return c

proc SphereColliderComponent(radius):
    let c = {}
    c["type"] = "sphere"
    c["radius"] = radius
    c["offset"] = vec3(0.0, 0.0, 0.0)
    c["is_trigger"] = false
    return c

# ============================================================================
# Apply force / impulse
# ============================================================================
proc apply_force(rb, force):
    rb["forces"] = v3_add(rb["forces"], force)

proc apply_impulse(rb, impulse):
    if rb["inv_mass"] > 0.0:
        rb["velocity"] = v3_add(rb["velocity"], v3_scale(impulse, rb["inv_mass"]))

# ============================================================================
# Physics world
# ============================================================================
proc create_physics_world():
    let pw = {}
    pw["gravity"] = vec3(0.0, -9.81, 0.0)
    pw["ground_y"] = 0.0
    pw["ground_enabled"] = true
    pw["collision_pairs"] = []
    pw["trigger_events"] = []
    return pw

# ============================================================================
# Integration step - updates velocity and position
# ============================================================================
proc integrate_body(rb, transform, gravity, dt):
    if rb["is_kinematic"]:
        return nil
    # Accumulate gravity
    if rb["use_gravity"]:
        rb["forces"] = v3_add(rb["forces"], v3_scale(gravity, rb["mass"]))
    # Acceleration from forces
    rb["acceleration"] = v3_scale(rb["forces"], rb["inv_mass"])
    # Semi-implicit Euler
    rb["velocity"] = v3_add(rb["velocity"], v3_scale(rb["acceleration"], dt))
    # Linear damping
    let damp = 1.0 - rb["linear_damping"]
    rb["velocity"] = v3_scale(rb["velocity"], damp)
    # Update position
    transform["position"] = v3_add(transform["position"], v3_scale(rb["velocity"], dt))
    transform["dirty"] = true
    # Clear forces for next frame
    rb["forces"] = vec3(0.0, 0.0, 0.0)

# ============================================================================
# Ground collision (simple infinite plane)
# ============================================================================
proc resolve_ground(rb, transform, collider, ground_y):
    let pos = transform["position"]
    let bottom = pos[1]
    if collider["type"] == "aabb":
        bottom = pos[1] - collider["half"][1] + collider["offset"][1]
    if collider["type"] == "sphere":
        bottom = pos[1] - collider["radius"] + collider["offset"][1]
    if bottom < ground_y:
        let penetration = ground_y - bottom
        transform["position"][1] = transform["position"][1] + penetration
        transform["dirty"] = true
        # Bounce or stop
        if rb["velocity"][1] < 0.0:
            rb["velocity"][1] = 0.0 - rb["velocity"][1] * rb["restitution"]
            if math.abs(rb["velocity"][1]) < 0.5:
                rb["velocity"][1] = 0.0
        rb["grounded"] = true
        rb["ground_normal"] = vec3(0.0, 1.0, 0.0)
        # Ground friction
        let friction = rb["friction"]
        rb["velocity"][0] = rb["velocity"][0] * (1.0 - friction * 0.1)
        rb["velocity"][2] = rb["velocity"][2] * (1.0 - friction * 0.1)
    else:
        rb["grounded"] = false

# ============================================================================
# AABB vs AABB collision response (push apart)
# ============================================================================
proc resolve_aabb_pair(rb_a, t_a, col_a, rb_b, t_b, col_b):
    let pos_a = v3_add(t_a["position"], col_a["offset"])
    let pos_b = v3_add(t_b["position"], col_b["offset"])
    let hit = aabb_vs_aabb(pos_a, col_a["half"], pos_b, col_b["half"])
    if hit == nil:
        return nil
    let normal = hit["normal"]
    let depth = hit["depth"]
    # Separate based on mass ratio
    let total_inv = rb_a["inv_mass"] + rb_b["inv_mass"]
    if total_inv < 0.0001:
        return hit
    let ratio_a = rb_a["inv_mass"] / total_inv
    let ratio_b = rb_b["inv_mass"] / total_inv
    t_a["position"] = v3_add(t_a["position"], v3_scale(normal, depth * ratio_a))
    t_b["position"] = v3_sub(t_b["position"], v3_scale(normal, depth * ratio_b))
    t_a["dirty"] = true
    t_b["dirty"] = true
    # Velocity response (simple elastic)
    let rel_vel = v3_sub(rb_a["velocity"], rb_b["velocity"])
    let vel_along = v3_dot(rel_vel, normal)
    if vel_along > 0.0:
        return hit
    let e = (rb_a["restitution"] + rb_b["restitution"]) * 0.5
    let j = (0.0 - (1.0 + e) * vel_along) / total_inv
    let impulse = v3_scale(normal, j)
    if rb_a["inv_mass"] > 0.0:
        rb_a["velocity"] = v3_add(rb_a["velocity"], v3_scale(impulse, rb_a["inv_mass"]))
    if rb_b["inv_mass"] > 0.0:
        rb_b["velocity"] = v3_sub(rb_b["velocity"], v3_scale(impulse, rb_b["inv_mass"]))
    return hit

# ============================================================================
# Physics system (register with ECS)
# ============================================================================
proc create_physics_system(physics_world):
    let pw = physics_world
    proc physics_update(world, entities, dt):
        from ecs import get_component, has_component
        # Integration
        let i = 0
        while i < len(entities):
            let e = entities[i]
            let rb = get_component(world, e, "rigidbody")
            let t = get_component(world, e, "transform")
            integrate_body(rb, t, pw["gravity"], dt)
            # Ground collision
            if pw["ground_enabled"] and has_component(world, e, "collider"):
                let col = get_component(world, e, "collider")
                resolve_ground(rb, t, col, pw["ground_y"])
            i = i + 1
    return physics_update
