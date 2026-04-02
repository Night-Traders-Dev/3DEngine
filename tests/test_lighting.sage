# test_lighting.sage - Sanity checks for the lighting system (non-GPU parts)
# Run: ./run.sh tests/test_lighting.sage

from lighting import create_light_scene, point_light, directional_light, spot_light
from lighting import add_light, remove_light, get_light, light_count
from lighting import set_ambient, set_fog, set_view_position
from lighting import LIGHT_TYPE_POINT, LIGHT_TYPE_DIRECTIONAL, LIGHT_TYPE_SPOT, MAX_LIGHTS

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

print "=== Lighting System Sanity Checks ==="

# --- Scene creation ---
let ls = create_light_scene()
check("scene created", ls != nil)
check("starts with 0 lights", len(ls["lights"]) == 0)
check("default ambient exists", ls["ambient_color"] != nil)
check("fog disabled by default", ls["fog_enabled"] == false)
check("starts dirty", ls["dirty"] == true)

# --- Point light ---
let pl = point_light(1.0, 2.0, 3.0, 1.0, 0.8, 0.6, 5.0, 20.0)
check("point light type", pl["type"] == LIGHT_TYPE_POINT)
check("point light pos x", approx(pl["position"][0], 1.0))
check("point light pos y", approx(pl["position"][1], 2.0))
check("point light color r", approx(pl["color"][0], 1.0))
check("point light intensity", approx(pl["intensity"], 5.0))
check("point light radius", approx(pl["radius"], 20.0))
check("point light shadows disabled by default", pl["cast_shadows"] == false)
check("point light enabled", pl["enabled"] == true)

# --- Directional light ---
let dl = directional_light(0.0, -1.0, 0.0, 1.0, 1.0, 0.9, 1.5)
check("dir light type", dl["type"] == LIGHT_TYPE_DIRECTIONAL)
check("dir light direction normalized", approx(dl["position"][1], -1.0))
check("dir light intensity", approx(dl["intensity"], 1.5))
check("dir light shadows enabled by default", dl["cast_shadows"] == true)

# --- Spot light ---
let sl = spot_light(0.0, 5.0, 0.0, 1.0, 1.0, 1.0, 3.0, 15.0, 15.0, 30.0)
check("spot light type", sl["type"] == LIGHT_TYPE_SPOT)
check("spot light position", approx(sl["position"][1], 5.0))
check("spot light has inner cone", sl["inner_cone"] > 0.0)
check("spot light has outer cone", sl["outer_cone"] > 0.0)
check("inner > outer (cosines)", sl["inner_cone"] > sl["outer_cone"])
check("spot light shadows disabled by default", sl["cast_shadows"] == false)

# --- Add lights ---
let idx0 = add_light(ls, pl)
let idx1 = add_light(ls, dl)
let idx2 = add_light(ls, sl)
check("first light index 0", idx0 == 0)
check("second light index 1", idx1 == 1)
check("third light index 2", idx2 == 2)
check("3 lights in scene", len(ls["lights"]) == 3)
check("active count is 3", light_count(ls) == 3)

# --- Get light ---
let got = get_light(ls, 1)
check("get light returns dir light", got["type"] == LIGHT_TYPE_DIRECTIONAL)

let missing = get_light(ls, 99)
check("out of bounds returns nil", missing == nil)

# --- Disable light ---
ls["lights"][1]["enabled"] = false
check("active count after disable", light_count(ls) == 2)

# --- Remove light ---
remove_light(ls, 1)
check("2 lights after remove", len(ls["lights"]) == 2)
check("first is still point", ls["lights"][0]["type"] == LIGHT_TYPE_POINT)
check("second is now spot", ls["lights"][1]["type"] == LIGHT_TYPE_SPOT)

# --- Max lights ---
ls["lights"] = []
let i = 0
while i < MAX_LIGHTS:
    add_light(ls, point_light(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 10.0))
    i = i + 1
check("16 lights at max", len(ls["lights"]) == MAX_LIGHTS)
let overflow = add_light(ls, point_light(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 10.0))
check("overflow returns -1", overflow == -1)
check("still 16 lights after overflow", len(ls["lights"]) == MAX_LIGHTS)

# --- Scene parameters ---
set_ambient(ls, 0.3, 0.3, 0.4, 0.5)
check("ambient color set", approx(ls["ambient_color"][0], 0.3))
check("ambient intensity set", approx(ls["ambient_intensity"], 0.5))

set_fog(ls, true, 10.0, 100.0, 0.5, 0.5, 0.6)
check("fog enabled", ls["fog_enabled"] == true)
check("fog start", approx(ls["fog_start"], 10.0))
check("fog end", approx(ls["fog_end"], 100.0))
check("fog color", approx(ls["fog_color"][0], 0.5))

from math3d import vec3
set_view_position(ls, vec3(1.0, 2.0, 3.0))
check("view pos set", approx(ls["view_pos"][0], 1.0))
check("dirty after changes", ls["dirty"] == true)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Lighting sanity checks failed!"
else:
    print "All lighting sanity checks passed!"
