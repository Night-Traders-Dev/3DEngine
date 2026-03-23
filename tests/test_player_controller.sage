# test_player_controller.sage - Sanity checks for player controller (non-GPU)
# Run: ./run.sh tests/test_player_controller.sage

from player_controller import create_player_controller
from player_controller import player_forward, player_right, player_flat_forward
from player_controller import player_eye_position
from math3d import vec3, v3_length, v3_dot

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
    return math.abs(a - b) < 0.01

print "=== Player Controller Sanity Checks ==="

# --- Creation ---
let pc = create_player_controller()
check("controller created", pc != nil)
check("position exists", pc["position"] != nil)
check("starts at height 2", approx(pc["position"][1], 2.0))
check("speed > 0", pc["speed"] > 0.0)
check("sprint speed > normal", pc["sprint_speed"] > pc["speed"])
check("jump force > 0", pc["jump_force"] > 0.0)
check("sensitivity > 0", pc["sensitivity"] > 0.0)
check("not captured initially", pc["captured"] == false)
check("gravity is negative", pc["gravity"] < 0.0)
check("height > 0", pc["height"] > 0.0)
check("fov reasonable", pc["fov"] > 30.0 and pc["fov"] < 120.0)
check("not noclip", pc["noclip"] == false)

# --- Forward vector ---
# Default yaw = -pi/2, pitch = 0 => looking along -Z
let fwd = player_forward(pc)
check("forward is unit length", approx(v3_length(fwd), 1.0))
# At yaw=-pi/2: cos(-pi/2)~=0, sin(-pi/2)~=-1 => forward ~= (0, 0, -1)
check("forward z component < 0", fwd[2] < -0.9)

# --- Right vector ---
let rgt = player_right(pc)
check("right is unit length", approx(v3_length(rgt), 1.0))
# Forward cross up = right
check("right is perpendicular to forward", approx(v3_dot(fwd, rgt), 0.0))

# --- Flat forward (no pitch) ---
let flat = player_flat_forward(pc)
check("flat forward is unit", approx(v3_length(flat), 1.0))
check("flat forward y = 0", approx(flat[1], 0.0))

# --- Eye position ---
let eye = player_eye_position(pc)
check("eye above position", eye[1] > pc["position"][1])
check("eye at expected height", approx(eye[1], pc["position"][1] + pc["eye_offset"]))

# --- Yaw/pitch changes ---
pc["yaw"] = 0.0
let fwd2 = player_forward(pc)
check("yaw=0 forward along +X", fwd2[0] > 0.9)

pc["pitch"] = 1.0
let fwd3 = player_forward(pc)
check("pitch up tilts forward up", fwd3[1] > 0.5)

# --- Velocity and grounded ---
check("velocity starts zero", approx(pc["velocity"][0], 0.0))
check("not grounded initially", pc["grounded"] == false)

# --- Noclip toggle ---
pc["noclip"] = true
check("noclip toggled", pc["noclip"] == true)
pc["noclip"] = false

# --- Ground collision simulation ---
pc["position"] = vec3(0.0, -0.5, 0.0)
pc["velocity"] = vec3(0.0, -5.0, 0.0)
# Simulate ground check
let feet_y = pc["position"][1]
if feet_y <= pc["ground_y"]:
    pc["position"][1] = pc["ground_y"]
    if pc["velocity"][1] < 0.0:
        pc["velocity"][1] = 0.0
    pc["grounded"] = true
check("simulated ground collision", pc["grounded"] == true)
check("position at ground", approx(pc["position"][1], 0.0))
check("velocity stopped", approx(pc["velocity"][1], 0.0))

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Player controller sanity checks failed!"
else:
    print "All player controller sanity checks passed!"
