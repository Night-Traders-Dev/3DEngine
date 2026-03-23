# test_sky.sage - Sanity checks for the sky system (non-GPU parts)
# Run: ./run.sh tests/test_sky.sage

from sky import create_sky, sky_preset_day, sky_preset_sunset, sky_preset_night, sky_preset_overcast
from sky import extract_inv_view_rotation
from math3d import mat4_identity, mat4_rotate_y, radians

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

print "=== Sky System Sanity Checks ==="

# --- Creation ---
let s = create_sky()
check("sky created", s != nil)
check("sun dir exists", s["sun_dir"] != nil)
check("sun dir has 3 components", len(s["sun_dir"]) == 3)
check("sky top color", len(s["sky_top"]) == 3)
check("sky horizon color", len(s["sky_horizon"]) == 3)
check("ground color", len(s["ground_color"]) == 3)
check("sun intensity > 0", s["sun_intensity"] > 0.0)
check("sun size > 0", s["sun_size"] > 0.0)
check("not initialized without GPU", s["initialized"] == false)

# --- Day preset ---
sky_preset_day(s)
check("day sun points up", s["sun_dir"][1] > 0.0)
check("day sky top is blue", s["sky_top"][2] > s["sky_top"][0])
check("day intensity is 1", approx(s["sun_intensity"], 1.0))

# --- Sunset preset ---
sky_preset_sunset(s)
check("sunset sun near horizon", s["sun_dir"][1] < 0.3)
check("sunset horizon is warm", s["sky_horizon"][0] > s["sky_horizon"][2])
check("sunset intensity > 1", s["sun_intensity"] > 1.0)

# --- Night preset ---
sky_preset_night(s)
check("night sun below horizon", s["sun_dir"][1] < 0.0)
check("night sky is dark", s["sky_top"][0] < 0.05)
check("night intensity is low", s["sun_intensity"] < 0.5)

# --- Overcast preset ---
sky_preset_overcast(s)
check("overcast sun dim", s["sun_intensity"] < 0.5)
check("overcast sky is gray", math.abs(s["sky_top"][0] - s["sky_top"][1]) < 0.1)

# --- Inverse view rotation extraction ---
let identity = mat4_identity()
let inv = extract_inv_view_rotation(identity)
check("identity inverse is identity [0]", approx(inv[0], 1.0))
check("identity inverse is identity [5]", approx(inv[5], 1.0))
check("identity inverse is identity [10]", approx(inv[10], 1.0))

# Rotation matrix: inverse = transpose
let rot = mat4_rotate_y(radians(90.0))
let inv_rot = extract_inv_view_rotation(rot)
# For a Y rotation: R[0]=cos, R[2]=-sin, R[8]=sin, R[10]=cos
# Transpose: inv[0]=cos, inv[8]=-sin, inv[2]=sin, inv[10]=cos
check("rotated inv transposes correctly [0]", approx(inv_rot[0], rot[0]))
check("rotated inv transposes correctly [2]", approx(inv_rot[2], rot[8]))
check("rotated inv transposes correctly [8]", approx(inv_rot[8], rot[2]))

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Sky sanity checks failed!"
else:
    print "All sky sanity checks passed!"
