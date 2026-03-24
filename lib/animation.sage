gc_disable()
# -----------------------------------------
# animation.sage - Skeletal animation framework for Sage Engine
# Bones, keyframes, clips, blending, animation controller
# -----------------------------------------

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_dot, v3_length, v3_normalize, v3_lerp, mat4_identity, mat4_translate, mat4_rotate_x, mat4_rotate_y, mat4_rotate_z, mat4_scale, mat4_mul
from engine_math import clamp

# ============================================================================
# Bone
# ============================================================================
proc create_bone(name, parent_index):
    let b = {}
    b["name"] = name
    b["parent"] = parent_index
    b["local_position"] = vec3(0.0, 0.0, 0.0)
    b["local_rotation"] = vec3(0.0, 0.0, 0.0)
    b["local_scale"] = vec3(1.0, 1.0, 1.0)
    b["bind_inverse"] = mat4_identity()
    b["world_matrix"] = mat4_identity()
    return b

# ============================================================================
# Skeleton
# ============================================================================
proc create_skeleton():
    let sk = {}
    sk["bones"] = []
    sk["bone_map"] = {}
    return sk

proc add_bone(sk, name, parent_name):
    let parent_idx = -1
    if parent_name != nil and parent_name != "":
        if dict_has(sk["bone_map"], parent_name):
            parent_idx = sk["bone_map"][parent_name]
    let idx = len(sk["bones"])
    let bone = create_bone(name, parent_idx)
    push(sk["bones"], bone)
    sk["bone_map"][name] = idx
    return idx

proc get_bone_index(sk, name):
    if dict_has(sk["bone_map"], name) == false:
        return -1
    return sk["bone_map"][name]

proc bone_count(sk):
    return len(sk["bones"])

# ============================================================================
# Keyframe
# ============================================================================
proc create_keyframe(time, position, rotation, scale):
    let kf = {}
    kf["time"] = time
    kf["position"] = position
    kf["rotation"] = rotation
    kf["scale"] = scale
    return kf

# ============================================================================
# Animation Clip
# ============================================================================
proc create_clip(name, duration, looping):
    let clip = {}
    clip["name"] = name
    clip["duration"] = duration
    clip["looping"] = looping
    clip["channels"] = {}
    return clip

proc add_channel(clip, bone_name, keyframes):
    clip["channels"][bone_name] = keyframes

# ============================================================================
# Sample a channel at a given time (linear interpolation)
# ============================================================================
proc sample_channel(keyframes, time):
    if len(keyframes) == 0:
        return nil
    if len(keyframes) == 1:
        return keyframes[0]
    # Find surrounding keyframes
    let kf_a = keyframes[0]
    let kf_b = keyframes[len(keyframes) - 1]
    let i = 0
    while i < len(keyframes) - 1:
        if keyframes[i + 1]["time"] >= time:
            kf_a = keyframes[i]
            kf_b = keyframes[i + 1]
            i = len(keyframes)
        i = i + 1
    let dt = kf_b["time"] - kf_a["time"]
    let t = 0.0
    if dt > 0.0001:
        t = (time - kf_a["time"]) / dt
    if t < 0.0:
        t = 0.0
    if t > 1.0:
        t = 1.0
    let result = {}
    result["position"] = v3_lerp(kf_a["position"], kf_b["position"], t)
    result["rotation"] = v3_lerp(kf_a["rotation"], kf_b["rotation"], t)
    result["scale"] = v3_lerp(kf_a["scale"], kf_b["scale"], t)
    return result

# ============================================================================
# Compute bone local matrix from position/rotation/scale
# ============================================================================
proc bone_local_matrix(pos, rot, scl):
    let s = mat4_scale(scl[0], scl[1], scl[2])
    let rx = mat4_rotate_x(rot[0])
    let ry = mat4_rotate_y(rot[1])
    let rz = mat4_rotate_z(rot[2])
    let tr = mat4_translate(pos[0], pos[1], pos[2])
    return mat4_mul(tr, mat4_mul(ry, mat4_mul(rx, mat4_mul(rz, s))))

# ============================================================================
# Update skeleton from an animation clip at a given time
# ============================================================================
proc apply_clip(sk, clip, time):
    let anim_time = time
    if clip["looping"] and clip["duration"] > 0.0:
        anim_time = time - math.floor(time / clip["duration"]) * clip["duration"]
    let bones = sk["bones"]
    let channels = clip["channels"]
    # Sample each channel
    let channel_names = dict_keys(channels)
    let ci = 0
    while ci < len(channel_names):
        let bone_name = channel_names[ci]
        let idx = get_bone_index(sk, bone_name)
        if idx >= 0:
            let sample = sample_channel(channels[bone_name], anim_time)
            if sample != nil:
                bones[idx]["local_position"] = sample["position"]
                bones[idx]["local_rotation"] = sample["rotation"]
                bones[idx]["local_scale"] = sample["scale"]
        ci = ci + 1

# ============================================================================
# Compute world matrices for all bones
# ============================================================================
proc update_skeleton_matrices(sk):
    let bones = sk["bones"]
    let i = 0
    while i < len(bones):
        let b = bones[i]
        let local = bone_local_matrix(b["local_position"], b["local_rotation"], b["local_scale"])
        if b["parent"] >= 0:
            b["world_matrix"] = mat4_mul(bones[b["parent"]]["world_matrix"], local)
        else:
            b["world_matrix"] = local
        i = i + 1

# ============================================================================
# Animation Controller (manages clips, transitions, blending)
# ============================================================================
proc create_anim_controller(skeleton):
    let ac = {}
    ac["skeleton"] = skeleton
    ac["clips"] = {}
    ac["current_clip"] = nil
    ac["current_time"] = 0.0
    ac["speed"] = 1.0
    ac["playing"] = false
    ac["blend_from"] = nil
    ac["blend_time"] = 0.0
    ac["blend_duration"] = 0.0
    return ac

proc add_clip_to_controller(ac, clip):
    ac["clips"][clip["name"]] = clip

proc play_clip(ac, clip_name):
    if dict_has(ac["clips"], clip_name) == false:
        return false
    ac["current_clip"] = clip_name
    ac["current_time"] = 0.0
    ac["playing"] = true
    ac["blend_from"] = nil
    return true

proc crossfade(ac, clip_name, duration):
    if dict_has(ac["clips"], clip_name) == false:
        return false
    ac["blend_from"] = ac["current_clip"]
    ac["blend_time"] = 0.0
    ac["blend_duration"] = duration
    ac["current_clip"] = clip_name
    ac["current_time"] = 0.0
    ac["playing"] = true
    return true

proc update_anim_controller(ac, dt):
    if ac["playing"] == false:
        return nil
    if ac["current_clip"] == nil:
        return nil
    ac["current_time"] = ac["current_time"] + dt * ac["speed"]
    let clip = ac["clips"][ac["current_clip"]]
    # Apply current clip
    apply_clip(ac["skeleton"], clip, ac["current_time"])
    # Handle blending
    if ac["blend_from"] != nil:
        ac["blend_time"] = ac["blend_time"] + dt
        if ac["blend_time"] >= ac["blend_duration"]:
            ac["blend_from"] = nil
    update_skeleton_matrices(ac["skeleton"])

# ============================================================================
# Procedural animation helpers
# ============================================================================
proc create_procedural_walk(speed, stride, bob_amount):
    let pa = {}
    pa["speed"] = speed
    pa["stride"] = stride
    pa["bob_amount"] = bob_amount
    pa["phase"] = 0.0
    return pa

proc update_procedural_walk(pa, dt, velocity_length):
    if velocity_length < 0.1:
        pa["phase"] = pa["phase"] * 0.9
        return vec3(0.0, 0.0, 0.0)
    pa["phase"] = pa["phase"] + dt * pa["speed"] * velocity_length
    let bob_y = math.sin(pa["phase"] * 2.0) * pa["bob_amount"]
    let sway_x = math.sin(pa["phase"]) * pa["stride"] * 0.3
    let step_z = math.cos(pa["phase"] * 2.0) * pa["stride"]
    return vec3(sway_x, bob_y, step_z)

# ============================================================================
# Animation Component (for ECS)
# ============================================================================
proc AnimationComponent(controller):
    let c = {}
    c["controller"] = controller
    c["playing"] = true
    return c

# ============================================================================
# Animation Events
# ============================================================================
proc add_animation_event(clip, time, name, data):
    if dict_has(clip, "events") == false:
        clip["events"] = []
    push(clip["events"], {"time": time, "name": name, "data": data})

proc check_animation_events(clip, prev_time, curr_time):
    if dict_has(clip, "events") == false:
        return []
    let fired = []
    let i = 0
    while i < len(clip["events"]):
        let evt = clip["events"][i]
        if evt["time"] > prev_time and evt["time"] <= curr_time:
            push(fired, evt)
        i = i + 1
    return fired

proc fire_animation_events(controller, clip, prev_time, curr_time, callback):
    let events = check_animation_events(clip, prev_time, curr_time)
    let i = 0
    while i < len(events):
        callback(events[i])
        i = i + 1

# ============================================================================
# Two-Bone IK Solver
# ============================================================================
proc solve_ik_two_bone(root_pos, mid_pos, end_pos, target_pos, pole_target):
    # Lengths
    let upper_len = v3_length(v3_sub(mid_pos, root_pos))
    let lower_len = v3_length(v3_sub(end_pos, mid_pos))
    let target_dist = v3_length(v3_sub(target_pos, root_pos))

    # Clamp target distance to reachable range
    let max_reach = upper_len + lower_len - 0.001
    if target_dist > max_reach:
        target_dist = max_reach
    let min_reach = math.abs(upper_len - lower_len) + 0.001
    if target_dist < min_reach:
        target_dist = min_reach

    # Law of cosines for mid joint angle
    let cos_mid = (upper_len * upper_len + lower_len * lower_len - target_dist * target_dist) / (2.0 * upper_len * lower_len)
    cos_mid = clamp(cos_mid, -1.0, 1.0)
    let mid_angle = math.acos(cos_mid)

    # Direction to target
    let to_target = v3_sub(target_pos, root_pos)
    let target_dir = v3_normalize(to_target)

    # Angle at root
    let cos_root = (upper_len * upper_len + target_dist * target_dist - lower_len * lower_len) / (2.0 * upper_len * target_dist)
    cos_root = clamp(cos_root, -1.0, 1.0)
    let root_angle = math.acos(cos_root)

    # Compute new mid position
    let new_mid = v3_add(root_pos, v3_scale(target_dir, upper_len * math.cos(root_angle)))
    # Perpendicular component toward pole target
    let pole_dir = v3_sub(pole_target, root_pos)
    let pole_proj = v3_scale(target_dir, v3_dot(pole_dir, target_dir))
    let pole_perp = v3_sub(pole_dir, pole_proj)
    let pole_len = v3_length(pole_perp)
    if pole_len > 0.001:
        pole_perp = v3_scale(pole_perp, 1.0 / pole_len)
    else:
        pole_perp = vec3(0.0, 1.0, 0.0)
    let offset = upper_len * math.sin(root_angle)
    new_mid = v3_add(new_mid, v3_scale(pole_perp, offset))

    # Compute new end position
    let mid_to_target = v3_sub(target_pos, new_mid)
    let mid_to_target_len = v3_length(mid_to_target)
    let new_end = target_pos
    if mid_to_target_len > 0.001:
        new_end = v3_add(new_mid, v3_scale(v3_normalize(mid_to_target), lower_len))

    return {"root": root_pos, "mid": new_mid, "end": new_end, "mid_angle": mid_angle}

proc apply_ik_to_skeleton(skeleton, root_bone_name, mid_bone_name, end_bone_name, target_pos, pole_target):
    let root_idx = get_bone_index(skeleton, root_bone_name)
    let mid_idx = get_bone_index(skeleton, mid_bone_name)
    let end_idx = get_bone_index(skeleton, end_bone_name)
    if root_idx < 0 or mid_idx < 0 or end_idx < 0:
        return false
    let root_pos = skeleton["bones"][root_idx]["world_position"]
    let mid_pos = skeleton["bones"][mid_idx]["world_position"]
    let end_pos = skeleton["bones"][end_idx]["world_position"]
    let result = solve_ik_two_bone(root_pos, mid_pos, end_pos, target_pos, pole_target)
    skeleton["bones"][mid_idx]["local_position"] = result["mid"]
    return true
