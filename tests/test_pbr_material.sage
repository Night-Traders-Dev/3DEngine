# test_pbr_material.sage - Sanity checks for PBR material (non-GPU parts)
from pbr_material import create_pbr_material_data, create_pbr_material_from_imported

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
check("default albedo texture flag false", m["use_albedo_texture"] == false)
check("default normal texture flag false", m["use_normal_texture"] == false)
check("default mr texture flag false", m["use_metallic_roughness_texture"] == false)
check("no desc set", m["desc_set"] == -1)

# Set properties
m["metallic"] = 0.8
m["roughness"] = 0.2
m["albedo_color"] = [0.5, 0.3, 0.1, 1.0]
check("metallic set", approx(m["metallic"], 0.8))
check("roughness set", approx(m["roughness"], 0.2))
check("albedo color set", approx(m["albedo_color"][0], 0.5))

let imported = {
    "albedo_color": [0.2, 0.4, 0.6, 0.9],
    "metallic": 0.3,
    "roughness": 0.7,
    "albedo_tex": 11,
    "normal_tex": -1,
    "mr_tex": 33
}
let fallback = {"albedo": 101, "normal": 202, "mr": 303}
let pm = create_pbr_material_from_imported(imported, fallback)
check("imported albedo copied", approx(pm["albedo_color"][2], 0.6))
check("imported metallic copied", approx(pm["metallic"], 0.3))
check("imported roughness copied", approx(pm["roughness"], 0.7))
check("imported albedo texture used", pm["albedo_texture"] == 11)
check("imported albedo texture flag true", pm["use_albedo_texture"] == true)
check("missing normal uses fallback", pm["normal_texture"] == 202)
check("missing normal flag false", pm["use_normal_texture"] == false)
check("imported mr texture used", pm["metallic_roughness_texture"] == 33)
check("imported mr flag true", pm["use_metallic_roughness_texture"] == true)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "PBR material sanity checks failed!"
else:
    print "All PBR material sanity checks passed!"
