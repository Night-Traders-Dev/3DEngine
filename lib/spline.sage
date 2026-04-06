gc_disable()
# spline.sage — Spline System for Roads, Rivers, Rails, Paths
# Catmull-Rom splines with uniform sampling, mesh generation,
# and runtime evaluation.

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length

proc create_spline():
    return {"points": [], "closed": false, "tension": 0.5, "samples_per_segment": 16}

proc add_spline_point(spline, position):
    push(spline["points"], position)

proc set_spline_closed(spline, closed):
    spline["closed"] = closed

proc spline_point_count(spline):
    return len(spline["points"])

proc evaluate_spline(spline, t):
    let n = len(spline["points"])
    if n < 2:
        if n == 1:
            return spline["points"][0]
        return vec3(0.0, 0.0, 0.0)
    let segment = t * (n - 1)
    let idx = int(segment)
    let local_t = segment - idx
    if idx >= n - 1:
        idx = n - 2
        local_t = 1.0
    let p0 = spline["points"][idx - 1]
    if idx == 0:
        p0 = spline["points"][0]
    let p1 = spline["points"][idx]
    let p2 = spline["points"][idx + 1]
    let p3 = spline["points"][idx + 2]
    if idx + 2 >= n:
        p3 = spline["points"][n - 1]
    return _catmull_rom(p0, p1, p2, p3, local_t, spline["tension"])

proc _catmull_rom(p0, p1, p2, p3, t, tension):
    let t2 = t * t
    let t3 = t2 * t
    let s = (1.0 - tension) * 0.5
    let x = s * (2.0 * p1[0] + (0.0 - p0[0] + p2[0]) * t + (2.0 * p0[0] - 5.0 * p1[0] + 4.0 * p2[0] - p3[0]) * t2 + (0.0 - p0[0] + 3.0 * p1[0] - 3.0 * p2[0] + p3[0]) * t3)
    let y = s * (2.0 * p1[1] + (0.0 - p0[1] + p2[1]) * t + (2.0 * p0[1] - 5.0 * p1[1] + 4.0 * p2[1] - p3[1]) * t2 + (0.0 - p0[1] + 3.0 * p1[1] - 3.0 * p2[1] + p3[1]) * t3)
    let z = s * (2.0 * p1[2] + (0.0 - p0[2] + p2[2]) * t + (2.0 * p0[2] - 5.0 * p1[2] + 4.0 * p2[2] - p3[2]) * t2 + (0.0 - p0[2] + 3.0 * p1[2] - 3.0 * p2[2] + p3[2]) * t3)
    return vec3(x, y, z)

proc spline_tangent(spline, t):
    let delta = 0.001
    let a = evaluate_spline(spline, t - delta)
    let b = evaluate_spline(spline, t + delta)
    return v3_normalize(v3_sub(b, a))

proc spline_length(spline):
    let total = 0.0
    let steps = len(spline["points"]) * spline["samples_per_segment"]
    let prev = evaluate_spline(spline, 0.0)
    let i = 1
    while i <= steps:
        let t = i / steps
        let curr = evaluate_spline(spline, t)
        total = total + v3_length(v3_sub(curr, prev))
        prev = curr
        i = i + 1
    return total

proc sample_spline_uniform(spline, count):
    let points = []
    let i = 0
    while i < count:
        let t = i / (count - 1)
        push(points, evaluate_spline(spline, t))
        i = i + 1
    return points

proc generate_spline_mesh(spline, width, segments):
    let vertices = []
    let indices = []
    let i = 0
    while i <= segments:
        let t = i / segments
        let center = evaluate_spline(spline, t)
        let tangent = spline_tangent(spline, t)
        let right = v3_normalize(vec3(0.0 - tangent[2], 0.0, tangent[0]))
        let left = v3_add(center, v3_scale(right, 0.0 - width * 0.5))
        let right_pt = v3_add(center, v3_scale(right, width * 0.5))
        push(vertices, left)
        push(vertices, right_pt)
        if i > 0:
            let base = (i - 1) * 2
            push(indices, base)
            push(indices, base + 1)
            push(indices, base + 2)
            push(indices, base + 1)
            push(indices, base + 3)
            push(indices, base + 2)
        i = i + 1
    return {"vertices": vertices, "indices": indices}
