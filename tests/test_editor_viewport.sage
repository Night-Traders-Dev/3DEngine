# test_editor_viewport.sage - Sanity checks for editor viewport
from editor_viewport import create_editor_camera, editor_camera_view, editor_camera_position
from editor_viewport import editor_camera_forward
from math3d import vec3, v3_length

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
    return math.abs(a - b) < 0.1

print "=== Editor Viewport Sanity Checks ==="

let ec = create_editor_camera()
check("camera created", ec != nil)
check("distance > 0", ec["distance"] > 0.0)
check("target exists", ec["target"] != nil)

let view = editor_camera_view(ec)
check("view matrix 16 elements", len(view) == 16)

let pos = editor_camera_position(ec)
check("position not at origin", v3_length(pos) > 1.0)
check("position 3 components", len(pos) == 3)

let fwd = editor_camera_forward(ec)
check("forward is unit", approx(v3_length(fwd), 1.0))

# Change orbit
ec["yaw"] = 0.0
ec["pitch"] = 0.0
ec["distance"] = 10.0
ec["target"] = vec3(0.0, 0.0, 0.0)
let pos2 = editor_camera_position(ec)
check("orbit at yaw=0 pitch=0", approx(v3_length(pos2), 10.0))

# Change distance
ec["distance"] = 5.0
let pos3 = editor_camera_position(ec)
check("distance changes position", approx(v3_length(pos3), 5.0))

# Pan target
ec["target"] = vec3(10.0, 0.0, 0.0)
let pos4 = editor_camera_position(ec)
check("pan moves camera", pos4[0] > 5.0)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Editor viewport sanity checks failed!"
else:
    print "All editor viewport sanity checks passed!"
