gc_disable()
# -----------------------------------------
# player_controller.sage - FPS Player Controller for Sage Engine
# Handles movement, gravity, jumping, mouse look, ground detection
# -----------------------------------------

import gpu
import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_cross, v3_dot, v3_length
from math3d import mat4_look_at, mat4_perspective, radians
from engine_math import clamp

# ============================================================================
# Player Controller
# ============================================================================
proc create_player_controller():
    let pc = {}
    # Position and orientation
    pc["position"] = vec3(0.0, 2.0, 0.0)
    pc["yaw"] = -1.5708
    pc["pitch"] = 0.0
    # Movement
    pc["speed"] = 6.0
    pc["sprint_speed"] = 12.0
    pc["air_speed"] = 2.0
    pc["jump_force"] = 6.0
    # Look
    pc["sensitivity"] = 0.003
    pc["captured"] = false
    # Physics state
    pc["velocity"] = vec3(0.0, 0.0, 0.0)
    pc["grounded"] = false
    pc["gravity"] = -15.0
    pc["ground_y"] = 0.0
    pc["height"] = 1.8
    pc["radius"] = 0.3
    # Camera
    pc["fov"] = 70.0
    pc["near"] = 0.1
    pc["far"] = 500.0
    pc["eye_offset"] = 1.6
    # State
    pc["noclip"] = false
    pc["head_bob_time"] = 0.0
    pc["head_bob_amount"] = 0.03
    return pc

# ============================================================================
# Compute forward/right vectors from yaw/pitch
# ============================================================================
proc player_forward(pc):
    let cy = math.cos(pc["yaw"])
    let sy = math.sin(pc["yaw"])
    let cp = math.cos(pc["pitch"])
    let sp = math.sin(pc["pitch"])
    return vec3(cy * cp, sp, sy * cp)

proc player_right(pc):
    let front = player_forward(pc)
    return v3_normalize(v3_cross(front, vec3(0.0, 1.0, 0.0)))

proc player_flat_forward(pc):
    let cy = math.cos(pc["yaw"])
    let sy = math.sin(pc["yaw"])
    return v3_normalize(vec3(cy, 0.0, sy))

# ============================================================================
# Update player controller
# ============================================================================
proc update_player(pc, inp, dt):
    from input import action_held, action_just_pressed, mouse_delta, scroll_value

    # Toggle mouse capture
    if action_just_pressed(inp, "toggle_capture"):
        if pc["captured"]:
            pc["captured"] = false
            gpu.set_cursor_mode(gpu.CURSOR_NORMAL)
        else:
            pc["captured"] = true
            gpu.set_cursor_mode(gpu.CURSOR_DISABLED)

    # Toggle noclip
    if action_just_pressed(inp, "noclip"):
        pc["noclip"] = pc["noclip"] == false

    # Mouse look
    if pc["captured"]:
        let md = mouse_delta(inp)
        pc["yaw"] = pc["yaw"] + md[0] * pc["sensitivity"]
        pc["pitch"] = pc["pitch"] - md[1] * pc["sensitivity"]
        pc["pitch"] = clamp(pc["pitch"], -1.48, 1.48)

    # Scroll to adjust speed
    let sv = scroll_value(inp)
    if sv[1] != 0.0:
        pc["speed"] = clamp(pc["speed"] + sv[1] * 0.5, 1.0, 50.0)

    # Movement vectors
    let fwd = player_flat_forward(pc)
    let right = player_right(pc)

    if pc["noclip"]:
        # Noclip: fly freely
        let fly_fwd = player_forward(pc)
        let move_speed = pc["speed"] * dt
        if action_held(inp, "sprint"):
            move_speed = pc["sprint_speed"] * dt
        if action_held(inp, "move_forward"):
            pc["position"] = v3_add(pc["position"], v3_scale(fly_fwd, move_speed))
        if action_held(inp, "move_back"):
            pc["position"] = v3_add(pc["position"], v3_scale(fly_fwd, 0.0 - move_speed))
        if action_held(inp, "move_left"):
            pc["position"] = v3_add(pc["position"], v3_scale(right, 0.0 - move_speed))
        if action_held(inp, "move_right"):
            pc["position"] = v3_add(pc["position"], v3_scale(right, move_speed))
        if action_held(inp, "jump"):
            pc["position"][1] = pc["position"][1] + move_speed
        if action_held(inp, "crouch"):
            pc["position"][1] = pc["position"][1] - move_speed
        pc["velocity"] = vec3(0.0, 0.0, 0.0)
        pc["grounded"] = true
        return nil

    # Ground movement
    let move_speed = pc["speed"]
    if action_held(inp, "sprint"):
        move_speed = pc["sprint_speed"]
    if pc["grounded"] == false:
        move_speed = pc["air_speed"]

    let wish_dir = vec3(0.0, 0.0, 0.0)
    if action_held(inp, "move_forward"):
        wish_dir = v3_add(wish_dir, fwd)
    if action_held(inp, "move_back"):
        wish_dir = v3_sub(wish_dir, fwd)
    if action_held(inp, "move_left"):
        wish_dir = v3_sub(wish_dir, right)
    if action_held(inp, "move_right"):
        wish_dir = v3_add(wish_dir, right)

    let wish_len = v3_length(wish_dir)
    if wish_len > 0.001:
        wish_dir = v3_normalize(wish_dir)

    # Apply horizontal movement
    pc["velocity"][0] = wish_dir[0] * move_speed
    pc["velocity"][2] = wish_dir[2] * move_speed

    # Jump
    if action_just_pressed(inp, "jump") and pc["grounded"]:
        pc["velocity"][1] = pc["jump_force"]
        pc["grounded"] = false

    # Gravity
    if pc["grounded"] == false:
        pc["velocity"][1] = pc["velocity"][1] + pc["gravity"] * dt

    # Integrate position
    pc["position"] = v3_add(pc["position"], v3_scale(pc["velocity"], dt))

    # Ground collision
    let feet_y = pc["position"][1]
    if feet_y <= pc["ground_y"]:
        pc["position"][1] = pc["ground_y"]
        if pc["velocity"][1] < 0.0:
            pc["velocity"][1] = 0.0
        pc["grounded"] = true
    else:
        if pc["velocity"][1] < -0.1:
            pc["grounded"] = false

    # Head bob
    if pc["grounded"] and wish_len > 0.001:
        pc["head_bob_time"] = pc["head_bob_time"] + dt * move_speed * 0.8
    else:
        pc["head_bob_time"] = pc["head_bob_time"] * 0.9

# ============================================================================
# Get view matrix from player controller
# ============================================================================
proc player_view_matrix(pc):
    let eye_y = pc["position"][1] + pc["eye_offset"]
    # Head bob
    let bob = math.sin(pc["head_bob_time"]) * pc["head_bob_amount"]
    eye_y = eye_y + bob
    let eye = vec3(pc["position"][0], eye_y, pc["position"][2])
    let front = player_forward(pc)
    let target = v3_add(eye, front)
    return mat4_look_at(eye, target, vec3(0.0, 1.0, 0.0))

proc player_eye_position(pc):
    let eye_y = pc["position"][1] + pc["eye_offset"]
    return vec3(pc["position"][0], eye_y, pc["position"][2])

proc player_projection(pc, aspect):
    return mat4_perspective(radians(pc["fov"]), aspect, pc["near"], pc["far"])
