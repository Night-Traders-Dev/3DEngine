gc_disable()
# -----------------------------------------
# engine_math.sage - Extended math utilities for Sage Engine
# Builds on sagelang's math3d with engine-specific helpers
# -----------------------------------------

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_dot, v3_cross, v3_length, v3_lerp, v3_distance
from math3d import mat4_identity, mat4_mul, mat4_translate, mat4_scale, mat4_rotate_x, mat4_rotate_y, mat4_rotate_z
from math3d import mat4_perspective, mat4_look_at, radians, degrees

let PI = 3.14159265358979323846
let TAU = 6.28318530717958647692
let DEG2RAD = PI / 180.0
let RAD2DEG = 180.0 / PI
let EPSILON = 0.000001

# ============================================================================
# Clamp and interpolation
# ============================================================================
proc clamp(val, lo, hi):
    if val < lo:
        return lo
    if val > hi:
        return hi
    return val

proc lerp(a, b, t):
    return a + (b - a) * t

proc inverse_lerp(a, b, val):
    if math.abs(b - a) < EPSILON:
        return 0.0
    return (val - a) / (b - a)

proc remap(val, in_lo, in_hi, out_lo, out_hi):
    let t = inverse_lerp(in_lo, in_hi, val)
    return lerp(out_lo, out_hi, t)

proc smoothstep(edge0, edge1, x):
    let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

# ============================================================================
# Angle utilities
# ============================================================================
proc angle_wrap(angle):
    while angle > PI:
        angle = angle - TAU
    while angle < 0.0 - PI:
        angle = angle + TAU
    return angle

proc angle_lerp(a, b, t):
    let diff = angle_wrap(b - a)
    return a + diff * t

# ============================================================================
# Transform helpers
# ============================================================================
proc make_transform(pos, rot, scl):
    let t = {}
    t["position"] = pos
    t["rotation"] = rot
    t["scale"] = scl
    return t

proc transform_identity():
    return make_transform(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0))

proc transform_to_matrix(t):
    let s = mat4_scale(t["scale"][0], t["scale"][1], t["scale"][2])
    let rx = mat4_rotate_x(t["rotation"][0])
    let ry = mat4_rotate_y(t["rotation"][1])
    let rz = mat4_rotate_z(t["rotation"][2])
    let tr = mat4_translate(t["position"][0], t["position"][1], t["position"][2])
    # T * Ry * Rx * Rz * S (standard TRS order)
    return mat4_mul(tr, mat4_mul(ry, mat4_mul(rx, mat4_mul(rz, s))))

# ============================================================================
# AABB (Axis-Aligned Bounding Box)
# ============================================================================
proc aabb_create(min_pt, max_pt):
    let b = {}
    b["min"] = min_pt
    b["max"] = max_pt
    return b

proc aabb_contains(box, point):
    if point[0] < box["min"][0]:
        return false
    if point[1] < box["min"][1]:
        return false
    if point[2] < box["min"][2]:
        return false
    if point[0] > box["max"][0]:
        return false
    if point[1] > box["max"][1]:
        return false
    if point[2] > box["max"][2]:
        return false
    return true

proc aabb_intersects(a, b):
    if a["max"][0] < b["min"][0]:
        return false
    if a["min"][0] > b["max"][0]:
        return false
    if a["max"][1] < b["min"][1]:
        return false
    if a["min"][1] > b["max"][1]:
        return false
    if a["max"][2] < b["min"][2]:
        return false
    if a["min"][2] > b["max"][2]:
        return false
    return true

proc aabb_center(box):
    let cx = (box["min"][0] + box["max"][0]) / 2.0
    let cy = (box["min"][1] + box["max"][1]) / 2.0
    let cz = (box["min"][2] + box["max"][2]) / 2.0
    return vec3(cx, cy, cz)

proc aabb_size(box):
    return v3_sub(box["max"], box["min"])
