# test_engine_math.sage - Sanity checks for engine math utilities
# Run: ./run.sh tests/test_engine_math.sage

from engine_math import clamp, lerp, inverse_lerp, remap, smoothstep
from engine_math import angle_wrap, transform_identity, transform_to_matrix, make_transform
from engine_math import aabb_create, aabb_contains, aabb_intersects, aabb_center, aabb_size
from engine_math import PI, EPSILON
from math3d import vec3, v3_length

import math

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

proc approx(a, b):
    return math.abs(a - b) < 0.001

print "=== Engine Math Sanity Checks ==="

# --- Clamp ---
check("clamp low", clamp(-5.0, 0.0, 10.0) == 0.0)
check("clamp high", clamp(15.0, 0.0, 10.0) == 10.0)
check("clamp mid", clamp(5.0, 0.0, 10.0) == 5.0)

# --- Lerp ---
check("lerp 0", approx(lerp(0.0, 10.0, 0.0), 0.0))
check("lerp 1", approx(lerp(0.0, 10.0, 1.0), 10.0))
check("lerp 0.5", approx(lerp(0.0, 10.0, 0.5), 5.0))

# --- Inverse lerp ---
check("inverse_lerp", approx(inverse_lerp(0.0, 10.0, 5.0), 0.5))

# --- Remap ---
check("remap 0-10 to 0-100", approx(remap(5.0, 0.0, 10.0, 0.0, 100.0), 50.0))

# --- Smoothstep ---
check("smoothstep at 0", approx(smoothstep(0.0, 1.0, 0.0), 0.0))
check("smoothstep at 1", approx(smoothstep(0.0, 1.0, 1.0), 1.0))
check("smoothstep at 0.5", approx(smoothstep(0.0, 1.0, 0.5), 0.5))

# --- Angle wrap ---
check("angle_wrap positive", approx(angle_wrap(PI + 1.0), 0.0 - PI + 1.0))
check("angle_wrap negative", approx(angle_wrap(0.0 - PI - 1.0), PI - 1.0))
check("angle_wrap zero", approx(angle_wrap(0.0), 0.0))

# --- Transform ---
let t = transform_identity()
check("identity pos zero", t["position"][0] == 0.0 and t["position"][1] == 0.0 and t["position"][2] == 0.0)
check("identity scale one", t["scale"][0] == 1.0 and t["scale"][1] == 1.0 and t["scale"][2] == 1.0)

let t2 = make_transform(vec3(1.0, 2.0, 3.0), vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0))
let m = transform_to_matrix(t2)
# Translation should be in columns 12,13,14
check("transform matrix translation x", approx(m[12], 1.0))
check("transform matrix translation y", approx(m[13], 2.0))
check("transform matrix translation z", approx(m[14], 3.0))

# --- AABB ---
let box_a = aabb_create(vec3(-1.0, -1.0, -1.0), vec3(1.0, 1.0, 1.0))
let box_b = aabb_create(vec3(0.5, 0.5, 0.5), vec3(2.0, 2.0, 2.0))
let box_c = aabb_create(vec3(5.0, 5.0, 5.0), vec3(6.0, 6.0, 6.0))

check("aabb contains origin", aabb_contains(box_a, vec3(0.0, 0.0, 0.0)))
check("aabb does not contain far point", aabb_contains(box_a, vec3(5.0, 5.0, 5.0)) == false)
check("aabb a intersects b", aabb_intersects(box_a, box_b))
check("aabb a does not intersect c", aabb_intersects(box_a, box_c) == false)

let center = aabb_center(box_a)
check("aabb center", approx(center[0], 0.0) and approx(center[1], 0.0) and approx(center[2], 0.0))

let size = aabb_size(box_a)
check("aabb size", approx(size[0], 2.0) and approx(size[1], 2.0) and approx(size[2], 2.0))

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Engine math sanity checks failed!"
else:
    print "All engine math sanity checks passed!"
