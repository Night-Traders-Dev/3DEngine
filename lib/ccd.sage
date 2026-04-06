gc_disable()
# ccd.sage — Continuous Collision Detection
# Prevents fast-moving objects from tunneling through thin geometry.
# Uses swept sphere/AABB tests and binary search for exact contact time.

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot

proc create_ccd_settings():
    return {
        "enabled": true,
        "velocity_threshold": 5.0,   # Only CCD for objects faster than this
        "max_iterations": 8,          # Binary search iterations
        "skin_width": 0.01            # Small padding to prevent exact-surface sticking
    }

proc swept_sphere_vs_plane(center, radius, velocity, plane_normal, plane_dist, dt):
    let speed = v3_dot(velocity, plane_normal)
    if speed >= 0:
        return nil  # Moving away from plane
    let dist_to_plane = v3_dot(center, plane_normal) - plane_dist - radius
    if dist_to_plane < 0:
        return {"time": 0.0, "point": center, "normal": plane_normal}  # Already penetrating
    if speed == 0:
        return nil
    let t = dist_to_plane / (0.0 - speed)
    if t >= 0 and t <= dt:
        let contact = v3_add(center, v3_scale(velocity, t))
        return {"time": t, "point": contact, "normal": plane_normal}
    return nil

proc swept_sphere_vs_sphere(c1, r1, v1, c2, r2, v2, dt):
    let rel_vel = v3_sub(v1, v2)
    let rel_pos = v3_sub(c1, c2)
    let combined_r = r1 + r2
    # Solve quadratic: |rel_pos + t * rel_vel|² = combined_r²
    let a = v3_dot(rel_vel, rel_vel)
    let b = 2.0 * v3_dot(rel_pos, rel_vel)
    let c = v3_dot(rel_pos, rel_pos) - combined_r * combined_r
    if c < 0:
        return {"time": 0.0, "normal": v3_normalize(rel_pos)}  # Already overlapping
    let disc = b * b - 4.0 * a * c
    if disc < 0 or a < 0.00001:
        return nil
    let sqrt_disc = math.sqrt(disc)
    let t = (0.0 - b - sqrt_disc) / (2.0 * a)
    if t >= 0 and t <= dt:
        let contact_pos = v3_add(c1, v3_scale(v1, t))
        let other_pos = v3_add(c2, v3_scale(v2, t))
        let normal = v3_normalize(v3_sub(contact_pos, other_pos))
        return {"time": t, "normal": normal}
    return nil

proc swept_aabb_vs_aabb(min1, max1, vel1, min2, max2, vel2, dt):
    let rel_vel = v3_sub(vel1, vel2)
    # Separating axis test on each axis
    let t_enter = 0.0
    let t_exit = dt
    let normal = vec3(0.0, 0.0, 0.0)
    let axes = [0, 1, 2]
    let ai = 0
    while ai < 3:
        let axis = axes[ai]
        let a_min = min1[axis]
        let a_max = max1[axis]
        let b_min = min2[axis]
        let b_max = max2[axis]
        let v = rel_vel[axis]
        if v == 0:
            if a_max < b_min or a_min > b_max:
                return nil  # No overlap and no relative movement
        else:
            let t1 = (b_min - a_max) / v
            let t2 = (b_max - a_min) / v
            if t1 > t2:
                let tmp = t1
                t1 = t2
                t2 = tmp
            if t1 > t_enter:
                t_enter = t1
                normal = vec3(0.0, 0.0, 0.0)
                if axis == 0:
                    normal = vec3(0.0 - v / (v + 0.001), 0.0, 0.0)
                elif axis == 1:
                    normal = vec3(0.0, 0.0 - v / (v + 0.001), 0.0)
                else:
                    normal = vec3(0.0, 0.0, 0.0 - v / (v + 0.001))
            if t2 < t_exit:
                t_exit = t2
            if t_enter > t_exit:
                return nil
        ai = ai + 1
    if t_enter >= 0 and t_enter <= dt:
        return {"time": t_enter, "normal": v3_normalize(normal)}
    return nil

proc ccd_check(settings, position, velocity, radius, obstacles, dt):
    if not settings["enabled"]:
        return nil
    let speed = v3_length(velocity)
    if speed < settings["velocity_threshold"]:
        return nil
    let earliest = nil
    let i = 0
    while i < len(obstacles):
        let obs = obstacles[i]
        let hit = nil
        if obs["type"] == "sphere":
            hit = swept_sphere_vs_sphere(position, radius, velocity, obs["center"], obs["radius"], vec3(0,0,0), dt)
        elif obs["type"] == "plane":
            hit = swept_sphere_vs_plane(position, radius, velocity, obs["normal"], obs["distance"], dt)
        if hit != nil:
            if earliest == nil or hit["time"] < earliest["time"]:
                earliest = hit
        i = i + 1
    return earliest

proc ccd_resolve(position, velocity, hit, skin_width):
    # Move to contact point minus skin width
    let safe_pos = v3_add(position, v3_scale(velocity, hit["time"]))
    safe_pos = v3_add(safe_pos, v3_scale(hit["normal"], skin_width))
    # Reflect velocity along normal
    let vn = v3_dot(velocity, hit["normal"])
    let reflected = v3_sub(velocity, v3_scale(hit["normal"], 2.0 * vn))
    return {"position": safe_pos, "velocity": v3_scale(reflected, 0.5)}
