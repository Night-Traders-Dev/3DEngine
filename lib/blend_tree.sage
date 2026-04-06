gc_disable()
# blend_tree.sage — Animation Blend Tree System
# Node-based animation blending with state machines, 1D/2D blend spaces,
# additive layers, root motion extraction, and transition rules.
#
# Usage:
#   let tree = create_blend_tree()
#   let idle = add_clip_node(tree, "idle", idle_clip)
#   let walk = add_clip_node(tree, "walk", walk_clip)
#   let run = add_clip_node(tree, "run", run_clip)
#   let blend = add_blend_1d(tree, "locomotion", [idle, walk, run], [0.0, 0.5, 1.0])
#   set_blend_param(tree, "locomotion", "speed", 0.7)
#   let pose = evaluate_blend_tree(tree, dt)

import math

# ============================================================================
# Node Types
# ============================================================================

let NODE_CLIP = "clip"
let NODE_BLEND_1D = "blend_1d"
let NODE_BLEND_2D = "blend_2d"
let NODE_ADDITIVE = "additive"
let NODE_STATE_MACHINE = "state_machine"

# ============================================================================
# Blend Tree
# ============================================================================

proc create_blend_tree():
    return {
        "nodes": {},
        "root": nil,
        "parameters": {},
        "time": 0.0
    }

# ============================================================================
# Clip Node — plays a single animation clip
# ============================================================================

proc add_clip_node(tree, name, clip):
    let node = {
        "type": NODE_CLIP,
        "name": name,
        "clip": clip,
        "time": 0.0,
        "speed": 1.0,
        "loop": true,
        "weight": 1.0
    }
    tree["nodes"][name] = node
    if tree["root"] == nil:
        tree["root"] = name
    return name

# ============================================================================
# 1D Blend Space — blend between clips based on one parameter
# ============================================================================

proc add_blend_1d(tree, name, child_names, thresholds):
    let node = {
        "type": NODE_BLEND_1D,
        "name": name,
        "children": child_names,
        "thresholds": thresholds,
        "param": "speed",
        "value": 0.0
    }
    tree["nodes"][name] = node
    return name

# ============================================================================
# 2D Blend Space — blend based on two parameters (x, y)
# ============================================================================

proc add_blend_2d(tree, name, child_names, positions):
    # positions: array of [x, y] for each child
    let node = {
        "type": NODE_BLEND_2D,
        "name": name,
        "children": child_names,
        "positions": positions,
        "param_x": "move_x",
        "param_y": "move_y",
        "value_x": 0.0,
        "value_y": 0.0
    }
    tree["nodes"][name] = node
    return name

# ============================================================================
# Additive Layer — add one animation on top of another
# ============================================================================

proc add_additive_node(tree, name, base_name, additive_name, weight):
    let node = {
        "type": NODE_ADDITIVE,
        "name": name,
        "base": base_name,
        "additive": additive_name,
        "weight": weight
    }
    tree["nodes"][name] = node
    return name

# ============================================================================
# State Machine — transitions between states with conditions
# ============================================================================

proc add_state_machine(tree, name, states, default_state):
    # states: {"idle": node_name, "walk": node_name, ...}
    let node = {
        "type": NODE_STATE_MACHINE,
        "name": name,
        "states": states,
        "current": default_state,
        "previous": nil,
        "transitions": [],
        "transition_time": 0.0,
        "transition_duration": 0.2,
        "transitioning": false
    }
    tree["nodes"][name] = node
    return name

proc add_transition(tree, sm_name, from_state, to_state, condition_param, condition_value, duration):
    let sm = tree["nodes"][sm_name]
    push(sm["transitions"], {
        "from": from_state,
        "to": to_state,
        "param": condition_param,
        "value": condition_value,
        "duration": duration
    })

# ============================================================================
# Parameters
# ============================================================================

proc set_blend_param(tree, param_name, value):
    tree["parameters"][param_name] = value

proc get_blend_param(tree, param_name):
    if dict_has(tree["parameters"], param_name):
        return tree["parameters"][param_name]
    return 0.0

# ============================================================================
# Evaluation — compute final blended pose
# ============================================================================

proc evaluate_blend_tree(tree, dt):
    tree["time"] = tree["time"] + dt
    if tree["root"] == nil:
        return nil
    return _evaluate_node(tree, tree["root"], dt)

proc _evaluate_node(tree, node_name, dt):
    if not dict_has(tree["nodes"], node_name):
        return nil
    let node = tree["nodes"][node_name]

    if node["type"] == NODE_CLIP:
        return _evaluate_clip(node, dt)

    if node["type"] == NODE_BLEND_1D:
        return _evaluate_blend_1d(tree, node, dt)

    if node["type"] == NODE_BLEND_2D:
        return _evaluate_blend_2d(tree, node, dt)

    if node["type"] == NODE_ADDITIVE:
        return _evaluate_additive(tree, node, dt)

    if node["type"] == NODE_STATE_MACHINE:
        return _evaluate_state_machine(tree, node, dt)

    return nil

proc _evaluate_clip(node, dt):
    node["time"] = node["time"] + dt * node["speed"]
    let clip = node["clip"]
    if clip == nil:
        return {"time": node["time"], "clip": nil, "weight": node["weight"]}
    let duration = 1.0
    if dict_has(clip, "duration"):
        duration = clip["duration"]
    if node["loop"] and duration > 0:
        while node["time"] > duration:
            node["time"] = node["time"] - duration
    return {"time": node["time"], "clip": clip, "weight": node["weight"], "node": node["name"]}

proc _evaluate_blend_1d(tree, node, dt):
    let param_val = get_blend_param(tree, node["param"])
    node["value"] = param_val
    let children = node["children"]
    let thresholds = node["thresholds"]
    let n = len(children)
    if n == 0:
        return nil
    if n == 1:
        return _evaluate_node(tree, children[0], dt)

    # Find the two surrounding thresholds
    let lo = 0
    let hi = n - 1
    let i = 0
    while i < n - 1:
        if param_val >= thresholds[i] and param_val <= thresholds[i + 1]:
            lo = i
            hi = i + 1
            break
        i = i + 1

    let range = thresholds[hi] - thresholds[lo]
    let blend = 0.0
    if range > 0.0001:
        blend = (param_val - thresholds[lo]) / range

    let pose_a = _evaluate_node(tree, children[lo], dt)
    let pose_b = _evaluate_node(tree, children[hi], dt)
    return {"blend": blend, "pose_a": pose_a, "pose_b": pose_b, "type": "blend_1d"}

proc _evaluate_blend_2d(tree, node, dt):
    let px = get_blend_param(tree, node["param_x"])
    let py = get_blend_param(tree, node["param_y"])
    # Simplified: find nearest child
    let children = node["children"]
    let positions = node["positions"]
    let best = 0
    let best_dist = 999999.0
    let i = 0
    while i < len(children):
        let dx = px - positions[i][0]
        let dy = py - positions[i][1]
        let dist = math.sqrt(dx * dx + dy * dy)
        if dist < best_dist:
            best_dist = dist
            best = i
        i = i + 1
    return _evaluate_node(tree, children[best], dt)

proc _evaluate_additive(tree, node, dt):
    let base = _evaluate_node(tree, node["base"], dt)
    let additive = _evaluate_node(tree, node["additive"], dt)
    return {"type": "additive", "base": base, "additive": additive, "weight": node["weight"]}

proc _evaluate_state_machine(tree, node, dt):
    # Check transitions
    let ti = 0
    while ti < len(node["transitions"]):
        let tr = node["transitions"][ti]
        if tr["from"] == node["current"] or tr["from"] == "*":
            let param_val = get_blend_param(tree, tr["param"])
            if param_val == tr["value"]:
                if not node["transitioning"] or node["current"] != tr["to"]:
                    node["previous"] = node["current"]
                    node["current"] = tr["to"]
                    node["transitioning"] = true
                    node["transition_time"] = 0.0
                    node["transition_duration"] = tr["duration"]
        ti = ti + 1

    # Update transition
    if node["transitioning"]:
        node["transition_time"] = node["transition_time"] + dt
        if node["transition_time"] >= node["transition_duration"]:
            node["transitioning"] = false

    # Evaluate current state
    let current_node = node["states"][node["current"]]
    let current_pose = _evaluate_node(tree, current_node, dt)

    if node["transitioning"] and node["previous"] != nil:
        let prev_node = node["states"][node["previous"]]
        let prev_pose = _evaluate_node(tree, prev_node, dt)
        let blend = node["transition_time"] / node["transition_duration"]
        return {"type": "transition", "from": prev_pose, "to": current_pose, "blend": blend}

    return current_pose

# ============================================================================
# Root Motion — extract displacement from animation
# ============================================================================

proc extract_root_motion(pose, dt):
    if pose == nil:
        return vec3(0.0, 0.0, 0.0)
    if dict_has(pose, "clip") and pose["clip"] != nil:
        if dict_has(pose["clip"], "root_motion"):
            let rm = pose["clip"]["root_motion"]
            return vec3(rm[0] * dt, rm[1] * dt, rm[2] * dt)
    return vec3(0.0, 0.0, 0.0)
