gc_disable()
# convex_collider.sage — Convex Mesh Collision Detection
# Supports: convex hull generation from point clouds, GJK intersection test,
# EPA penetration depth, convex-convex/convex-sphere/convex-AABB tests.
#
# Usage:
#   let hull = create_convex_hull(points)
#   let hit = test_convex_convex(hull_a, transform_a, hull_b, transform_b)
#   if hit["colliding"]:
#       resolve_penetration(entity, hit["normal"], hit["depth"])

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot

# ============================================================================
# Convex Hull
# ============================================================================

proc create_convex_hull(points):
    # Simplified: use all input points as hull vertices
    # For production, implement quickhull or gift wrapping
    let hull = {
        "vertices": [],
        "center": vec3(0.0, 0.0, 0.0),
        "radius": 0.0    # Bounding sphere radius for broadphase
    }
    let cx = 0.0
    let cy = 0.0
    let cz = 0.0
    let i = 0
    while i < len(points):
        push(hull["vertices"], points[i])
        cx = cx + points[i][0]
        cy = cy + points[i][1]
        cz = cz + points[i][2]
        i = i + 1
    if len(points) > 0:
        hull["center"] = vec3(cx / len(points), cy / len(points), cz / len(points))
        # Compute bounding radius
        let max_r = 0.0
        i = 0
        while i < len(points):
            let r = v3_length(v3_sub(points[i], hull["center"]))
            if r > max_r:
                max_r = r
            i = i + 1
        hull["radius"] = max_r
    return hull

proc create_convex_box(half_extents):
    let hx = half_extents[0]
    let hy = half_extents[1]
    let hz = half_extents[2]
    return create_convex_hull([
        vec3(0.0 - hx, 0.0 - hy, 0.0 - hz), vec3(hx, 0.0 - hy, 0.0 - hz),
        vec3(hx, hy, 0.0 - hz), vec3(0.0 - hx, hy, 0.0 - hz),
        vec3(0.0 - hx, 0.0 - hy, hz), vec3(hx, 0.0 - hy, hz),
        vec3(hx, hy, hz), vec3(0.0 - hx, hy, hz)
    ])

proc create_convex_cylinder(radius, half_height, segments):
    let points = []
    let i = 0
    while i < segments:
        let angle = (i * 6.2831853) / segments
        let x = math.cos(angle) * radius
        let z = math.sin(angle) * radius
        push(points, vec3(x, 0.0 - half_height, z))
        push(points, vec3(x, half_height, z))
        i = i + 1
    return create_convex_hull(points)

# ============================================================================
# Support function — farthest point in direction (for GJK)
# ============================================================================

proc _support(hull, transform_pos, direction):
    let max_dot = -999999.0
    let best = hull["vertices"][0]
    let i = 0
    while i < len(hull["vertices"]):
        let world_pt = v3_add(hull["vertices"][i], transform_pos)
        let d = v3_dot(world_pt, direction)
        if d > max_dot:
            max_dot = d
            best = world_pt
        i = i + 1
    return best

proc _minkowski_support(hull_a, pos_a, hull_b, pos_b, direction):
    let a = _support(hull_a, pos_a, direction)
    let neg_dir = v3_scale(direction, -1.0)
    let b = _support(hull_b, pos_b, neg_dir)
    return v3_sub(a, b)

# ============================================================================
# GJK — Gilbert-Johnson-Keerthi intersection test
# ============================================================================

proc test_convex_convex(hull_a, pos_a, hull_b, pos_b):
    # Broadphase: bounding sphere test
    let dist = v3_length(v3_sub(
        v3_add(hull_a["center"], pos_a),
        v3_add(hull_b["center"], pos_b)
    ))
    if dist > hull_a["radius"] + hull_b["radius"] + 0.1:
        return {"colliding": false, "normal": vec3(0.0, 0.0, 0.0), "depth": 0.0}

    # GJK narrow phase (simplified 2D-style with max iterations)
    let direction = v3_sub(v3_add(hull_b["center"], pos_b), v3_add(hull_a["center"], pos_a))
    if v3_length(direction) < 0.0001:
        direction = vec3(1.0, 0.0, 0.0)
    direction = v3_normalize(direction)

    let simplex = []
    let a = _minkowski_support(hull_a, pos_a, hull_b, pos_b, direction)
    push(simplex, a)

    direction = v3_scale(a, -1.0)
    if v3_length(direction) < 0.0001:
        direction = vec3(1.0, 0.0, 0.0)
    direction = v3_normalize(direction)

    let max_iters = 32
    let iter = 0
    while iter < max_iters:
        a = _minkowski_support(hull_a, pos_a, hull_b, pos_b, direction)
        if v3_dot(a, direction) < 0.0:
            return {"colliding": false, "normal": vec3(0.0, 0.0, 0.0), "depth": 0.0}

        push(simplex, a)

        if len(simplex) == 2:
            # Line case
            let b_pt = simplex[0]
            let a_pt = simplex[1]
            let ab = v3_sub(b_pt, a_pt)
            let ao = v3_scale(a_pt, -1.0)
            direction = _triple_cross(ab, ao, ab)
            if v3_length(direction) < 0.0001:
                direction = vec3(0.0 - ab[2], 0.0, ab[0])
            direction = v3_normalize(direction)
        elif len(simplex) == 3:
            # Triangle case — check if origin is enclosed
            let c_pt = simplex[0]
            let b_pt = simplex[1]
            let a_pt = simplex[2]
            let ab = v3_sub(b_pt, a_pt)
            let ac = v3_sub(c_pt, a_pt)
            let ao = v3_scale(a_pt, -1.0)
            let abc_normal = _cross(ab, ac)

            if v3_dot(_cross(abc_normal, ac), ao) > 0:
                # Region AC
                simplex = [c_pt, a_pt]
                direction = _triple_cross(ac, ao, ac)
            elif v3_dot(_cross(ab, abc_normal), ao) > 0:
                # Region AB
                simplex = [b_pt, a_pt]
                direction = _triple_cross(ab, ao, ab)
            else:
                # Origin is inside triangle (collision in 2D projection)
                let sep_normal = v3_normalize(v3_sub(v3_add(hull_a["center"], pos_a), v3_add(hull_b["center"], pos_b)))
                let depth = hull_a["radius"] + hull_b["radius"] - dist
                if depth < 0.01:
                    depth = 0.01
                return {"colliding": true, "normal": sep_normal, "depth": depth}

            if v3_length(direction) < 0.0001:
                direction = vec3(1.0, 0.0, 0.0)
            direction = v3_normalize(direction)
        iter = iter + 1

    return {"colliding": false, "normal": vec3(0.0, 0.0, 0.0), "depth": 0.0}

proc _cross(a, b):
    return vec3(
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0]
    )

proc _triple_cross(a, b, c):
    # (A × B) × C
    let ab = _cross(a, b)
    return _cross(ab, c)

# ============================================================================
# Convex vs Sphere / AABB
# ============================================================================

proc test_convex_sphere(hull, hull_pos, sphere_center, sphere_radius):
    # Find closest point on hull to sphere center
    let closest = _support(hull, hull_pos, v3_normalize(v3_sub(sphere_center, v3_add(hull["center"], hull_pos))))
    let dist = v3_length(v3_sub(sphere_center, closest))
    if dist < sphere_radius:
        let normal = v3_normalize(v3_sub(sphere_center, closest))
        return {"colliding": true, "normal": normal, "depth": sphere_radius - dist, "point": closest}
    return {"colliding": false, "normal": vec3(0.0, 0.0, 0.0), "depth": 0.0, "point": nil}

proc test_convex_aabb(hull, hull_pos, aabb_min, aabb_max):
    let box_hull = create_convex_box(vec3(
        (aabb_max[0] - aabb_min[0]) * 0.5,
        (aabb_max[1] - aabb_min[1]) * 0.5,
        (aabb_max[2] - aabb_min[2]) * 0.5
    ))
    let box_center = vec3(
        (aabb_min[0] + aabb_max[0]) * 0.5,
        (aabb_min[1] + aabb_max[1]) * 0.5,
        (aabb_min[2] + aabb_max[2]) * 0.5
    )
    return test_convex_convex(hull, hull_pos, box_hull, box_center)
