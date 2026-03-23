# test_pbr_material.sage - Sanity checks for PBR material (non-GPU parts)
from pbr_material import create_pbr_material_data

import math

let p = 0
let f = 0
proc check(n, c):
    if c:
        p = p + 1
    else:
        print "  FAIL: " + n
        f = f + 1

proc approx(a, b):
    return math.abs(a - b) < 0.01

print "=== PBR Material Sanity Checks ==="

let m = create_pbr_material_data()
check("material created", m != nil)
check("no albedo tex", m["albedo_texture"] == -1)
check("no normal tex", m["normal_texture"] == -1)
check("no mr tex", m["metallic_roughness_texture"] == -1)
check("no sampler", m["sampler"] == -1)
check("default albedo white", approx(m["albedo_color"][0], 1.0))
check("default metallic 0", approx(m["metallic"], 0.0))
check("default roughness 0.5", approx(m["roughness"], 0.5))
check("no desc set", m["desc_set"] == -1)

# Set properties
m["metallic"] = 0.8
m["roughness"] = 0.2
m["albedo_color"] = [0.5, 0.3, 0.1, 1.0]
check("metallic set", approx(m["metallic"], 0.8))
check("roughness set", approx(m["roughness"], 0.2))
check("albedo color set", approx(m["albedo_color"][0], 0.5))

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "PBR material sanity checks failed!"
else:
    print "All PBR material sanity checks passed!"
