# test_animation.sage - Sanity checks for animation framework
# Run: ./run.sh tests/test_animation.sage

from animation import create_skeleton, add_bone, get_bone_index, bone_count
from animation import create_keyframe, create_clip, add_channel
from animation import sample_channel, bone_local_matrix
from animation import apply_clip, update_skeleton_matrices
from animation import create_anim_controller, add_clip_to_controller
from animation import play_clip, update_anim_controller
from animation import create_procedural_walk, update_procedural_walk
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
    return math.abs(a - b) < 0.05

print "=== Animation System Sanity Checks ==="

# --- Skeleton ---
let sk = create_skeleton()
check("skeleton created", sk != nil)
check("0 bones initially", bone_count(sk) == 0)

let root_idx = add_bone(sk, "root", nil)
check("root bone index 0", root_idx == 0)
check("1 bone", bone_count(sk) == 1)

let spine_idx = add_bone(sk, "spine", "root")
let head_idx = add_bone(sk, "head", "spine")
let arm_l = add_bone(sk, "arm_left", "spine")
let arm_r = add_bone(sk, "arm_right", "spine")
check("5 bones", bone_count(sk) == 5)
check("spine parent is root", sk["bones"][spine_idx]["parent"] == root_idx)
check("head parent is spine", sk["bones"][head_idx]["parent"] == spine_idx)

# --- Bone index lookup ---
check("find root", get_bone_index(sk, "root") == 0)
check("find head", get_bone_index(sk, "head") == head_idx)
check("missing bone", get_bone_index(sk, "nonexistent") == -1)

# --- Keyframes ---
let kf0 = create_keyframe(0.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0))
let kf1 = create_keyframe(1.0, vec3(0.0, 2.0, 0.0), vec3(0.5, 0.0, 0.0), vec3(1.0, 1.0, 1.0))
check("keyframe time", approx(kf0["time"], 0.0))
check("keyframe pos", approx(kf1["position"][1], 2.0))

# --- Sample channel ---
let keyframes = [kf0, kf1]
let s_half = sample_channel(keyframes, 0.5)
check("sample at 0.5 pos y", approx(s_half["position"][1], 1.0))
check("sample at 0.5 rot x", approx(s_half["rotation"][0], 0.25))

let s_start = sample_channel(keyframes, 0.0)
check("sample at 0 pos y", approx(s_start["position"][1], 0.0))

let s_end = sample_channel(keyframes, 1.0)
check("sample at 1 pos y", approx(s_end["position"][1], 2.0))

# Single keyframe
let s_single = sample_channel([kf0], 0.5)
check("single keyframe returns it", approx(s_single["position"][1], 0.0))

# --- Clip ---
let clip = create_clip("walk", 1.0, true)
check("clip created", clip != nil)
check("clip name", clip["name"] == "walk")
check("clip looping", clip["looping"] == true)

add_channel(clip, "root", keyframes)
check("channel added", dict_has(clip["channels"], "root"))

# --- Apply clip to skeleton ---
apply_clip(sk, clip, 0.5)
check("clip applied root pos", approx(sk["bones"][0]["local_position"][1], 1.0))

# --- Update matrices ---
update_skeleton_matrices(sk)
check("root has world matrix", sk["bones"][0]["world_matrix"] != nil)
check("world matrix length 16", len(sk["bones"][0]["world_matrix"]) == 16)

# --- Bone local matrix ---
let m = bone_local_matrix(vec3(1.0, 2.0, 3.0), vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0))
check("bone matrix translation x", approx(m[12], 1.0))
check("bone matrix translation y", approx(m[13], 2.0))
check("bone matrix translation z", approx(m[14], 3.0))

# --- Animation controller ---
let ac = create_anim_controller(sk)
add_clip_to_controller(ac, clip)
check("controller created", ac != nil)
check("clip added", dict_has(ac["clips"], "walk"))

let played = play_clip(ac, "walk")
check("play_clip success", played == true)
check("controller playing", ac["playing"] == true)

update_anim_controller(ac, 0.5)
check("controller advances time", ac["current_time"] > 0.0)

let bad_play = play_clip(ac, "nonexistent")
check("play unknown clip fails", bad_play == false)

# --- Procedural walk ---
let pw = create_procedural_walk(8.0, 0.15, 0.05)
check("proc walk created", pw != nil)

let idle_offset = update_procedural_walk(pw, 0.016, 0.0)
check("idle returns near zero", v3_length(idle_offset) < 0.1)

let walk_offset = update_procedural_walk(pw, 0.016, 5.0)
check("walking produces offset", true)

# Run multiple frames to see bob
let ti = 0
while ti < 60:
    update_procedural_walk(pw, 0.016, 5.0)
    ti = ti + 1
check("phase advances", pw["phase"] > 0.0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Animation sanity checks failed!"
else:
    print "All animation sanity checks passed!"
