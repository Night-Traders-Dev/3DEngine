# test_frustum.sage - Sanity checks for frustum culling
from frustum import extract_frustum_planes, point_in_frustum, sphere_in_frustum, aabb_in_frustum
from frustum import create_draw_batch, add_to_batch, sort_batch, clear_batch, batch_count
from math3d import mat4_perspective, mat4_look_at, mat4_mul, mat4_identity, radians, vec3

import math

let p = 0
let f = 0
proc check(n, c):
    if c:
        p = p + 1
    else:
        print "  FAIL: " + n
        f = f + 1

print "=== Frustum Culling Sanity Checks ==="

# Build a VP matrix looking down -Z
let view = mat4_look_at(vec3(0.0, 0.0, 5.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0))
let proj = mat4_perspective(radians(60.0), 1.78, 0.1, 100.0)
let vp = mat4_mul(proj, view)
let planes = extract_frustum_planes(vp)
check("6 planes extracted", len(planes) == 6)
check("plane has 4 components", len(planes[0]) == 4)

# Point in front of camera
check("point in front visible", point_in_frustum(planes, 0.0, 0.0, 0.0))
# Point behind camera
check("point behind not visible", point_in_frustum(planes, 0.0, 0.0, 10.0) == false)
# Point far to the side
check("point far right not visible", point_in_frustum(planes, 100.0, 0.0, 0.0) == false)
# Point far above
check("point far above not visible", point_in_frustum(planes, 0.0, 100.0, 0.0) == false)

# Sphere tests
check("sphere in front", sphere_in_frustum(planes, 0.0, 0.0, 0.0, 1.0))
check("sphere behind", sphere_in_frustum(planes, 0.0, 0.0, 20.0, 1.0) == false)
check("large sphere partially visible", sphere_in_frustum(planes, 5.0, 0.0, 0.0, 10.0))

# AABB tests
let half = vec3(1.0, 1.0, 1.0)
check("aabb in front", aabb_in_frustum(planes, vec3(0.0, 0.0, 0.0), half))
check("aabb behind", aabb_in_frustum(planes, vec3(0.0, 0.0, 20.0), half) == false)
check("aabb far side", aabb_in_frustum(planes, vec3(50.0, 0.0, 0.0), half) == false)
# Large AABB should be visible even if center is off
check("large aabb visible", aabb_in_frustum(planes, vec3(3.0, 0.0, 0.0), vec3(5.0, 5.0, 5.0)))

# Draw batch
let batch = create_draw_batch()
check("batch empty", batch_count(batch) == 0)
add_to_batch(batch, "cube", "lit", 1, nil)
add_to_batch(batch, "cube", "lit", 2, nil)
add_to_batch(batch, "sphere", "pbr", 3, nil)
check("batch has 3", batch_count(batch) == 3)
sort_batch(batch)
check("batch sorted", batch["sorted"] == true)
clear_batch(batch)
check("batch cleared", batch_count(batch) == 0)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Frustum sanity checks failed!"
else:
    print "All frustum sanity checks passed!"
