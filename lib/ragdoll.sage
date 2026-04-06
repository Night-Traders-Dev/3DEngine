gc_disable()
# ragdoll.sage — Ragdoll Physics System
# Converts animated skeletons into physics-driven ragdolls on death/impact.
# Supports: bone→rigidbody mapping, joint constraints, activation/deactivation,
# blending between animation and ragdoll, impulse application.
#
# Usage:
#   let rd = create_ragdoll(skeleton_def)
#   activate_ragdoll(rd, current_bone_positions, impact_impulse)
#   update_ragdoll(rd, dt, gravity)
#   let bone_transforms = ragdoll_bone_transforms(rd)

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot

# ============================================================================
# Bone Definition for Ragdoll
# ============================================================================

proc ragdoll_bone(name, parent_idx, length, radius, mass):
    return {
        "name": name,
        "parent": parent_idx,
        "length": length,
        "radius": radius,
        "mass": mass,
        # Physics state
        "position": vec3(0.0, 0.0, 0.0),
        "velocity": vec3(0.0, 0.0, 0.0),
        "rotation": 0.0,
        "angular_vel": 0.0,
        "grounded": false
    }

# ============================================================================
# Ragdoll Creation
# ============================================================================

proc create_ragdoll(bone_defs):
    return {
        "bones": bone_defs,
        "active": false,
        "blend_factor": 0.0,   # 0 = animation, 1 = ragdoll
        "blend_speed": 5.0,
        "damping": 0.95,
        "angular_damping": 0.9,
        "ground_y": 0.0,
        "bounce": 0.3,
        "friction": 0.8,
        "settled": false,       # True when all bones stopped moving
        "settle_threshold": 0.1
    }

proc create_humanoid_ragdoll():
    let bones = []
    # Torso (root)
    push(bones, ragdoll_bone("pelvis", -1, 0.25, 0.15, 8.0))
    push(bones, ragdoll_bone("spine", 0, 0.3, 0.12, 6.0))
    push(bones, ragdoll_bone("chest", 1, 0.3, 0.14, 7.0))
    push(bones, ragdoll_bone("head", 2, 0.2, 0.1, 4.0))
    # Left arm
    push(bones, ragdoll_bone("l_upper_arm", 2, 0.28, 0.05, 2.0))
    push(bones, ragdoll_bone("l_forearm", 4, 0.25, 0.04, 1.5))
    push(bones, ragdoll_bone("l_hand", 5, 0.1, 0.03, 0.5))
    # Right arm
    push(bones, ragdoll_bone("r_upper_arm", 2, 0.28, 0.05, 2.0))
    push(bones, ragdoll_bone("r_forearm", 7, 0.25, 0.04, 1.5))
    push(bones, ragdoll_bone("r_hand", 8, 0.1, 0.03, 0.5))
    # Left leg
    push(bones, ragdoll_bone("l_thigh", 0, 0.4, 0.07, 4.0))
    push(bones, ragdoll_bone("l_shin", 10, 0.38, 0.05, 3.0))
    push(bones, ragdoll_bone("l_foot", 11, 0.15, 0.04, 1.0))
    # Right leg
    push(bones, ragdoll_bone("r_thigh", 0, 0.4, 0.07, 4.0))
    push(bones, ragdoll_bone("r_shin", 13, 0.38, 0.05, 3.0))
    push(bones, ragdoll_bone("r_foot", 14, 0.15, 0.04, 1.0))
    return create_ragdoll(bones)

# ============================================================================
# Activation — transition from animation to ragdoll
# ============================================================================

proc activate_ragdoll(rd, bone_positions, impulse):
    rd["active"] = true
    rd["blend_factor"] = 0.0
    rd["settled"] = false

    let i = 0
    while i < len(rd["bones"]):
        let bone = rd["bones"][i]
        if i < len(bone_positions):
            bone["position"] = bone_positions[i]
        bone["velocity"] = vec3(0.0, 0.0, 0.0)
        bone["grounded"] = false
        i = i + 1

    # Apply impact impulse to nearest bone
    if impulse != nil and dict_has(impulse, "bone_index"):
        let bi = impulse["bone_index"]
        if bi >= 0 and bi < len(rd["bones"]):
            let force = impulse["force"]
            let bone = rd["bones"][bi]
            bone["velocity"] = v3_scale(force, 1.0 / bone["mass"])
            # Propagate to neighbors
            _propagate_impulse(rd, bi, force, 0.5)

proc deactivate_ragdoll(rd):
    rd["active"] = false
    rd["blend_factor"] = 0.0

proc _propagate_impulse(rd, bone_idx, force, falloff):
    let i = 0
    while i < len(rd["bones"]):
        if i != bone_idx:
            let bone = rd["bones"][i]
            # Check if connected (parent or child)
            let connected = false
            if bone["parent"] == bone_idx:
                connected = true
            if rd["bones"][bone_idx]["parent"] == i:
                connected = true
            if connected:
                bone["velocity"] = v3_add(bone["velocity"], v3_scale(force, falloff / bone["mass"]))
        i = i + 1

# ============================================================================
# Physics Update
# ============================================================================

proc update_ragdoll(rd, dt, gravity):
    if not rd["active"]:
        return

    # Blend factor (smooth transition from animation to ragdoll)
    if rd["blend_factor"] < 1.0:
        rd["blend_factor"] = rd["blend_factor"] + rd["blend_speed"] * dt
        if rd["blend_factor"] > 1.0:
            rd["blend_factor"] = 1.0

    let all_settled = true
    let i = 0
    while i < len(rd["bones"]):
        let bone = rd["bones"][i]

        if not bone["grounded"]:
            # Gravity
            bone["velocity"] = v3_add(bone["velocity"], v3_scale(vec3(0.0, gravity, 0.0), dt))

            # Damping
            bone["velocity"] = v3_scale(bone["velocity"], rd["damping"])
            bone["angular_vel"] = bone["angular_vel"] * rd["angular_damping"]

            # Update position
            bone["position"] = v3_add(bone["position"], v3_scale(bone["velocity"], dt))
            bone["rotation"] = bone["rotation"] + bone["angular_vel"] * dt

            # Ground collision
            if bone["position"][1] < rd["ground_y"] + bone["radius"]:
                bone["position"][1] = rd["ground_y"] + bone["radius"]
                bone["velocity"][1] = 0.0 - bone["velocity"][1] * rd["bounce"]
                # Friction
                bone["velocity"][0] = bone["velocity"][0] * rd["friction"]
                bone["velocity"][2] = bone["velocity"][2] * rd["friction"]
                bone["angular_vel"] = bone["angular_vel"] * 0.5
                if v3_length(bone["velocity"]) < rd["settle_threshold"]:
                    bone["grounded"] = true
                    bone["velocity"] = vec3(0.0, 0.0, 0.0)

        # Joint constraint: keep bones connected to parents
        if bone["parent"] >= 0 and bone["parent"] < len(rd["bones"]):
            let parent = rd["bones"][bone["parent"]]
            let to_parent = v3_sub(parent["position"], bone["position"])
            let dist = v3_length(to_parent)
            let max_dist = bone["length"] * 1.2
            if dist > max_dist:
                let correction = v3_scale(v3_normalize(to_parent), (dist - max_dist) * 0.5)
                bone["position"] = v3_add(bone["position"], correction)
                parent["position"] = v3_sub(parent["position"], correction)

        if not bone["grounded"]:
            all_settled = false
        i = i + 1

    rd["settled"] = all_settled

# ============================================================================
# Query
# ============================================================================

proc ragdoll_bone_transforms(rd):
    let transforms = []
    let i = 0
    while i < len(rd["bones"]):
        push(transforms, rd["bones"][i]["position"])
        i = i + 1
    return transforms

proc is_ragdoll_active(rd):
    return rd["active"]

proc is_ragdoll_settled(rd):
    return rd["settled"]

proc ragdoll_center_of_mass(rd):
    let total_mass = 0.0
    let cx = 0.0
    let cy = 0.0
    let cz = 0.0
    let i = 0
    while i < len(rd["bones"]):
        let b = rd["bones"][i]
        cx = cx + b["position"][0] * b["mass"]
        cy = cy + b["position"][1] * b["mass"]
        cz = cz + b["position"][2] * b["mass"]
        total_mass = total_mass + b["mass"]
        i = i + 1
    if total_mass > 0:
        return vec3(cx / total_mass, cy / total_mass, cz / total_mass)
    return vec3(0.0, 0.0, 0.0)
