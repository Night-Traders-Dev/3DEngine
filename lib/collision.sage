gc_disable()
# -----------------------------------------
# collision.sage - Collision detection for Sage Engine
# AABB, sphere, ray intersection tests and response
# -----------------------------------------

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_dot, v3_length, v3_normalize

let EPSILON = 0.000001

# ============================================================================
# Collision shapes
# ============================================================================
proc aabb_shape(half_x, half_y, half_z):
    let s = {}
    s["type"] = "aabb"
    s["half"] = vec3(half_x, half_y, half_z)
    return s

proc sphere_shape(radius):
    let s = {}
    s["type"] = "sphere"
    s["radius"] = radius
    return s

proc capsule_shape(radius, height):
    let s = {}
    s["type"] = "capsule"
    s["radius"] = radius
    s["height"] = height
    return s

# ============================================================================
# AABB vs AABB
# ============================================================================
proc aabb_vs_aabb(pos_a, half_a, pos_b, half_b):
    let dx = math.abs(pos_a[0] - pos_b[0])
    let dy = math.abs(pos_a[1] - pos_b[1])
    let dz = math.abs(pos_a[2] - pos_b[2])
    let ox = (half_a[0] + half_b[0]) - dx
    let oy = (half_a[1] + half_b[1]) - dy
    let oz = (half_a[2] + half_b[2]) - dz
    if ox <= 0.0 or oy <= 0.0 or oz <= 0.0:
        return nil
    # Return collision with minimum penetration axis
    let hit = {}
    hit["overlap"] = true
    if ox < oy and ox < oz:
        if pos_a[0] < pos_b[0]:
            hit["normal"] = vec3(-1.0, 0.0, 0.0)
        else:
            hit["normal"] = vec3(1.0, 0.0, 0.0)
        hit["depth"] = ox
    else:
        if oy < oz:
            if pos_a[1] < pos_b[1]:
                hit["normal"] = vec3(0.0, -1.0, 0.0)
            else:
                hit["normal"] = vec3(0.0, 1.0, 0.0)
            hit["depth"] = oy
        else:
            if pos_a[2] < pos_b[2]:
                hit["normal"] = vec3(0.0, 0.0, -1.0)
            else:
                hit["normal"] = vec3(0.0, 0.0, 1.0)
            hit["depth"] = oz
    return hit

# ============================================================================
# Sphere vs Sphere
# ============================================================================
proc sphere_vs_sphere(pos_a, rad_a, pos_b, rad_b):
    let diff = v3_sub(pos_a, pos_b)
    let dist_sq = v3_dot(diff, diff)
    let min_dist = rad_a + rad_b
    if dist_sq >= min_dist * min_dist:
        return nil
    let dist = math.sqrt(dist_sq)
    let hit = {}
    hit["overlap"] = true
    if dist < EPSILON:
        hit["normal"] = vec3(0.0, 1.0, 0.0)
        hit["depth"] = min_dist
    else:
        hit["normal"] = v3_scale(diff, 1.0 / dist)
        hit["depth"] = min_dist - dist
    return hit

# ============================================================================
# Sphere vs AABB
# ============================================================================
proc sphere_vs_aabb(sphere_pos, radius, box_pos, box_half):
    # Find closest point on AABB to sphere center
    let cx = sphere_pos[0] - box_pos[0]
    let cy = sphere_pos[1] - box_pos[1]
    let cz = sphere_pos[2] - box_pos[2]
    # Clamp to box extents
    if cx < 0.0 - box_half[0]:
        cx = 0.0 - box_half[0]
    if cx > box_half[0]:
        cx = box_half[0]
    if cy < 0.0 - box_half[1]:
        cy = 0.0 - box_half[1]
    if cy > box_half[1]:
        cy = box_half[1]
    if cz < 0.0 - box_half[2]:
        cz = 0.0 - box_half[2]
    if cz > box_half[2]:
        cz = box_half[2]
    let closest = vec3(box_pos[0] + cx, box_pos[1] + cy, box_pos[2] + cz)
    let diff = v3_sub(sphere_pos, closest)
    let dist_sq = v3_dot(diff, diff)
    if dist_sq >= radius * radius:
        return nil
    let dist = math.sqrt(dist_sq)
    let hit = {}
    hit["overlap"] = true
    if dist < EPSILON:
        hit["normal"] = vec3(0.0, 1.0, 0.0)
        hit["depth"] = radius
    else:
        hit["normal"] = v3_scale(diff, 1.0 / dist)
        hit["depth"] = radius - dist
    hit["point"] = closest
    return hit

# ============================================================================
# Ray vs AABB (slab method)
# ============================================================================
proc ray_vs_aabb(ray_origin, ray_dir, box_pos, box_half):
    let box_min = v3_sub(box_pos, box_half)
    let box_max = v3_add(box_pos, box_half)
    let tmin = -999999.0
    let tmax = 999999.0
    # X slab
    if math.abs(ray_dir[0]) > EPSILON:
        let inv = 1.0 / ray_dir[0]
        let t1 = (box_min[0] - ray_origin[0]) * inv
        let t2 = (box_max[0] - ray_origin[0]) * inv
        if t1 > t2:
            let tmp = t1
            t1 = t2
            t2 = tmp
        if t1 > tmin:
            tmin = t1
        if t2 < tmax:
            tmax = t2
    else:
        if ray_origin[0] < box_min[0] or ray_origin[0] > box_max[0]:
            return nil
    # Y slab
    if math.abs(ray_dir[1]) > EPSILON:
        let inv = 1.0 / ray_dir[1]
        let t1 = (box_min[1] - ray_origin[1]) * inv
        let t2 = (box_max[1] - ray_origin[1]) * inv
        if t1 > t2:
            let tmp = t1
            t1 = t2
            t2 = tmp
        if t1 > tmin:
            tmin = t1
        if t2 < tmax:
            tmax = t2
    else:
        if ray_origin[1] < box_min[1] or ray_origin[1] > box_max[1]:
            return nil
    # Z slab
    if math.abs(ray_dir[2]) > EPSILON:
        let inv = 1.0 / ray_dir[2]
        let t1 = (box_min[2] - ray_origin[2]) * inv
        let t2 = (box_max[2] - ray_origin[2]) * inv
        if t1 > t2:
            let tmp = t1
            t1 = t2
            t2 = tmp
        if t1 > tmin:
            tmin = t1
        if t2 < tmax:
            tmax = t2
    else:
        if ray_origin[2] < box_min[2] or ray_origin[2] > box_max[2]:
            return nil
    if tmin > tmax or tmax < 0.0:
        return nil
    let t = tmin
    if t < 0.0:
        t = tmax
    let hit = {}
    hit["t"] = t
    hit["point"] = v3_add(ray_origin, v3_scale(ray_dir, t))
    return hit

# ============================================================================
# Ray vs Sphere
# ============================================================================
proc ray_vs_sphere(ray_origin, ray_dir, sphere_pos, radius):
    let oc = v3_sub(ray_origin, sphere_pos)
    let a = v3_dot(ray_dir, ray_dir)
    let b = 2.0 * v3_dot(oc, ray_dir)
    let c = v3_dot(oc, oc) - radius * radius
    let discriminant = b * b - 4.0 * a * c
    if discriminant < 0.0:
        return nil
    let sqrt_d = math.sqrt(discriminant)
    let t = (0.0 - b - sqrt_d) / (2.0 * a)
    if t < 0.0:
        t = (0.0 - b + sqrt_d) / (2.0 * a)
    if t < 0.0:
        return nil
    let point = v3_add(ray_origin, v3_scale(ray_dir, t))
    let hit = {}
    hit["t"] = t
    hit["point"] = point
    hit["normal"] = v3_normalize(v3_sub(point, sphere_pos))
    return hit

# ============================================================================
# Ray vs Plane (infinite horizontal plane at y=height)
# ============================================================================
proc ray_vs_plane(ray_origin, ray_dir, plane_y):
    if math.abs(ray_dir[1]) < EPSILON:
        return nil
    let t = (plane_y - ray_origin[1]) / ray_dir[1]
    if t < 0.0:
        return nil
    let hit = {}
    hit["t"] = t
    hit["point"] = v3_add(ray_origin, v3_scale(ray_dir, t))
    hit["normal"] = vec3(0.0, 1.0, 0.0)
    return hit

# ============================================================================
# Point in AABB
# ============================================================================
proc point_in_aabb(point, box_pos, box_half):
    let dx = math.abs(point[0] - box_pos[0])
    let dy = math.abs(point[1] - box_pos[1])
    let dz = math.abs(point[2] - box_pos[2])
    return dx <= box_half[0] and dy <= box_half[1] and dz <= box_half[2]

# ============================================================================
# Distance from point to AABB surface
# ============================================================================
proc point_aabb_distance(point, box_pos, box_half):
    let dx = math.abs(point[0] - box_pos[0]) - box_half[0]
    let dy = math.abs(point[1] - box_pos[1]) - box_half[1]
    let dz = math.abs(point[2] - box_pos[2]) - box_half[2]
    if dx < 0.0:
        dx = 0.0
    if dy < 0.0:
        dy = 0.0
    if dz < 0.0:
        dz = 0.0
    return math.sqrt(dx * dx + dy * dy + dz * dz)
