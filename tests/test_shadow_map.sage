# test_shadow_map.sage - Sanity checks for shadow map helpers (non-GPU parts)

import math
from shadow_map import build_shadow_uniform_data, compute_light_vp, compute_light_vp_stable, primary_shadow_light
from shadow_map import shadow_texel_world_size, snap_shadow_view_center
from lighting import create_light_scene, point_light, directional_light, add_light
from math3d import vec3, mat4_identity, mat4_mul_vec4

let p = 0
let f = 0

proc check(name, cond):
    if cond:
        p = p + 1
    else:
        print "  FAIL: " + name
        f = f + 1

print "=== Shadow Map Sanity Checks ==="

let empty_ls = create_light_scene()
let fallback = primary_shadow_light(empty_ls)
check("fallback light index disabled", fallback["index"] == -1)
check("fallback light direction set", fallback["direction"][1] < 0.0)

add_light(empty_ls, point_light(1.0, 2.0, 3.0, 1.0, 0.8, 0.6, 2.0, 10.0))
add_light(empty_ls, directional_light(-0.4, -0.9, -0.1, 1.0, 0.95, 0.9, 1.2))
let primary = primary_shadow_light(empty_ls)
check("primary light index finds directional", primary["index"] == 1)
check("primary light keeps directional vector", primary["direction"][0] < 0.0 and primary["direction"][1] < 0.0)
empty_ls["lights"][1]["cast_shadows"] = false
let disabled_primary = primary_shadow_light(empty_ls)
check("shadow selector skips disabled directional light", disabled_primary["index"] == -1)

let light_vp = compute_light_vp(vec3(-0.3, -0.8, -0.5), vec3(2.0, 1.0, -3.0), 40.0)
check("light vp has 16 floats", len(light_vp) == 16)
let stable_light_vp = compute_light_vp_stable(vec3(-0.3, -0.8, -0.5), vec3(2.0, 1.0, -3.0), 40.0, 1024.0)
check("stable light vp has 16 floats", len(stable_light_vp) == 16)

let texel = shadow_texel_world_size(16.0, 1024.0)
check("shadow texel size tracks scene span", texel > 0.031 and texel < 0.032)
let snap_center = vec3(10.018, 5.018, 2.0)
let snapped_view = snap_shadow_view_center(mat4_identity(), snap_center, 16.0, 1024.0)
let snapped_center = mat4_mul_vec4(snapped_view, [snap_center[0], snap_center[1], snap_center[2], 1.0])
let snapped_x_steps = math.floor(snapped_center[0] / texel + 0.5)
let snapped_y_steps = math.floor(snapped_center[1] / texel + 0.5)
check("snapped center x lands on texel grid", math.abs(snapped_center[0] - snapped_x_steps * texel) < 0.000001)
check("snapped center y lands on texel grid", math.abs(snapped_center[1] - snapped_y_steps * texel) < 0.000001)
let nearby_center_pos = vec3(snap_center[0] + texel * 0.25, snap_center[1] + texel * 0.25, snap_center[2])
let nearby_view = snap_shadow_view_center(mat4_identity(), nearby_center_pos, 16.0, 1024.0)
let nearby_center = mat4_mul_vec4(nearby_view, [nearby_center_pos[0], nearby_center_pos[1], nearby_center_pos[2], 1.0])
check("sub-texel motion keeps snapped x stable", math.abs(snapped_center[0] - nearby_center[0]) < 0.000001)
check("sub-texel motion keeps snapped y stable", math.abs(snapped_center[1] - nearby_center[1]) < 0.000001)

let shadow_uniform = build_shadow_uniform_data(light_vp, true, 2048.0, 3)
check("shadow uniform has 20 floats", len(shadow_uniform) == 20)
check("shadow uniform stores matrix first", shadow_uniform[0] == light_vp[0] and shadow_uniform[15] == light_vp[15])
check("shadow uniform stores enabled flag", shadow_uniform[16] == 1.0)
check("shadow uniform stores texel size", shadow_uniform[17] > 0.0 and shadow_uniform[17] < 0.001)
check("shadow uniform stores light index", shadow_uniform[19] == 3.0)

let disabled_uniform = build_shadow_uniform_data(nil, false, 0.0, -1)
check("disabled uniform flag cleared", disabled_uniform[16] == 0.0)
check("disabled uniform uses identity matrix", disabled_uniform[0] == 1.0 and disabled_uniform[5] == 1.0 and disabled_uniform[10] == 1.0 and disabled_uniform[15] == 1.0)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Shadow map sanity checks failed!"
else:
    print "All shadow map sanity checks passed!"
