# test_gizmo.sage - Sanity checks for gizmo system
# Run: ./run.sh tests/test_gizmo.sage

from gizmo import create_gizmo, set_gizmo_mode, cycle_gizmo_mode
from gizmo import gizmo_hit_test, begin_gizmo_drag, end_gizmo_drag, update_gizmo_drag
from gizmo import get_gizmo_visuals
from gizmo import GIZMO_TRANSLATE, GIZMO_ROTATE, GIZMO_SCALE, GIZMO_NONE
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
    return math.abs(a - b) < 0.1

print "=== Gizmo System Sanity Checks ==="

# --- Creation ---
let g = create_gizmo()
check("gizmo created", g != nil)
check("default mode translate", g["mode"] == GIZMO_TRANSLATE)
check("no active axis", g["active_axis"] == "none")
check("visible", g["visible"] == true)
check("not dragging", g["dragging"] == false)

# --- Mode switching ---
set_gizmo_mode(g, GIZMO_ROTATE)
check("set rotate mode", g["mode"] == GIZMO_ROTATE)

set_gizmo_mode(g, GIZMO_SCALE)
check("set scale mode", g["mode"] == GIZMO_SCALE)

cycle_gizmo_mode(g)
check("cycle from scale to translate", g["mode"] == GIZMO_TRANSLATE)
cycle_gizmo_mode(g)
check("cycle to rotate", g["mode"] == GIZMO_ROTATE)
cycle_gizmo_mode(g)
check("cycle to scale", g["mode"] == GIZMO_SCALE)

# --- Hit test ---
set_gizmo_mode(g, GIZMO_TRANSLATE)
g["position"] = vec3(0.0, 0.0, 0.0)
g["scale_factor"] = 1.0
# Ray toward X handle (at axis_length=2.0 on X axis)
let hit_x = gizmo_hit_test(g, vec3(-5.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0))
check("hit x axis", hit_x == "x")

# Ray toward Y handle
let hit_y = gizmo_hit_test(g, vec3(0.0, -5.0, 0.0), vec3(0.0, 1.0, 0.0))
check("hit y axis", hit_y == "y")

# Ray toward Z handle
let hit_z = gizmo_hit_test(g, vec3(0.0, 0.0, -5.0), vec3(0.0, 0.0, 1.0))
check("hit z axis", hit_z == "z")

# Ray missing all
let miss = gizmo_hit_test(g, vec3(10.0, 10.0, 10.0), vec3(1.0, 0.0, 0.0))
check("miss returns none", miss == "none")

# --- Drag ---
begin_gizmo_drag(g, "x", vec3(0.0, 0.0, 0.0))
check("dragging active", g["dragging"] == true)
check("active axis x", g["active_axis"] == "x")

let delta = update_gizmo_drag(g, vec3(3.0, 1.0, 2.0))
check("x drag constrains to x", approx(delta[0], 3.0))
check("x drag no y", approx(delta[1], 0.0))
check("x drag no z", approx(delta[2], 0.0))

end_gizmo_drag(g)
check("drag ended", g["dragging"] == false)
check("axis cleared", g["active_axis"] == "none")

# Y axis drag
begin_gizmo_drag(g, "y", vec3(0.0, 0.0, 0.0))
let dy = update_gizmo_drag(g, vec3(1.0, 5.0, 2.0))
check("y drag constrains to y", approx(dy[1], 5.0))
check("y drag no x", approx(dy[0], 0.0))
end_gizmo_drag(g)

# No drag when not active
let no_drag = update_gizmo_drag(g, vec3(1.0, 1.0, 1.0))
check("no drag when inactive", approx(v3_length(no_drag), 0.0))

# --- Visuals ---
let vis = get_gizmo_visuals(g)
check("visuals not empty", len(vis) > 0)
check("6 visual elements (3 shafts + 3 handles)", len(vis) == 6)
check("visual has pos", vis[0]["pos"] != nil)
check("visual has half", vis[0]["half"] != nil)
check("visual has color", len(vis[0]["color"]) == 4)

# Active axis highlighting
g["active_axis"] = "x"
let vis2 = get_gizmo_visuals(g)
check("active axis uses highlight color", vis2[0]["color"][1] > 0.9)
g["active_axis"] = "none"

# Hidden gizmo
g["visible"] = false
let vis3 = get_gizmo_visuals(g)
check("hidden gizmo no visuals", len(vis3) == 0)
g["visible"] = true

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Gizmo sanity checks failed!"
else:
    print "All gizmo sanity checks passed!"
