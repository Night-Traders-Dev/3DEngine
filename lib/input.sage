gc_disable()
# -----------------------------------------
# input.sage - Input system with action mapping for Sage Engine
# Maps physical keys/buttons to logical game actions
# Supports keyboard, mouse, and gamepad (via gpu input)
# -----------------------------------------

import gpu

# ============================================================================
# Input Manager
# ============================================================================
proc create_input():
    let inp = {}
    inp["actions"] = {}
    inp["axes"] = {}
    inp["action_state"] = {}
    inp["action_prev"] = {}
    inp["axis_values"] = {}
    inp["mouse_dx"] = 0.0
    inp["mouse_dy"] = 0.0
    inp["mouse_x"] = 0.0
    inp["mouse_y"] = 0.0
    inp["last_mx"] = 0.0
    inp["last_my"] = 0.0
    inp["first_frame"] = true
    inp["scroll_x"] = 0.0
    inp["scroll_y"] = 0.0
    return inp

# ============================================================================
# Action mapping - bind keys to named actions
# ============================================================================
proc bind_action(inp, action_name, keys):
    inp["actions"][action_name] = keys
    inp["action_state"][action_name] = false
    inp["action_prev"][action_name] = false

proc bind_axis(inp, axis_name, positive_keys, negative_keys):
    let ax = {}
    ax["positive"] = positive_keys
    ax["negative"] = negative_keys
    inp["axes"][axis_name] = ax
    inp["axis_values"][axis_name] = 0.0

# ============================================================================
# Query actions
# ============================================================================
proc action_held(inp, action_name):
    if dict_has(inp["action_state"], action_name) == false:
        return false
    return inp["action_state"][action_name]

proc action_just_pressed(inp, action_name):
    if dict_has(inp["action_state"], action_name) == false:
        return false
    return inp["action_state"][action_name] and (inp["action_prev"][action_name] == false)

proc action_just_released(inp, action_name):
    if dict_has(inp["action_state"], action_name) == false:
        return false
    return (inp["action_state"][action_name] == false) and inp["action_prev"][action_name]

proc axis_value(inp, axis_name):
    if dict_has(inp["axis_values"], axis_name) == false:
        return 0.0
    return inp["axis_values"][axis_name]

proc mouse_delta(inp):
    return [inp["mouse_dx"], inp["mouse_dy"]]

proc mouse_position(inp):
    return [inp["mouse_x"], inp["mouse_y"]]

proc scroll_value(inp):
    return [inp["scroll_x"], inp["scroll_y"]]

# ============================================================================
# Update - call once per frame before game logic
# ============================================================================
proc update_input(inp):
    # Save previous state
    let action_names = dict_keys(inp["actions"])
    let i = 0
    while i < len(action_names):
        let name = action_names[i]
        inp["action_prev"][name] = inp["action_state"][name]
        i = i + 1

    # Poll action states
    i = 0
    while i < len(action_names):
        let name = action_names[i]
        let keys = inp["actions"][name]
        let pressed = false
        let k = 0
        while k < len(keys):
            if gpu.key_pressed(keys[k]):
                pressed = true
                k = len(keys)
            k = k + 1
        inp["action_state"][name] = pressed
        i = i + 1

    # Poll axis values
    let axis_names = dict_keys(inp["axes"])
    i = 0
    while i < len(axis_names):
        let name = axis_names[i]
        let ax = inp["axes"][name]
        let val = 0.0
        let pk = 0
        while pk < len(ax["positive"]):
            if gpu.key_pressed(ax["positive"][pk]):
                val = val + 1.0
                pk = len(ax["positive"])
            pk = pk + 1
        let nk = 0
        while nk < len(ax["negative"]):
            if gpu.key_pressed(ax["negative"][nk]):
                val = val - 1.0
                nk = len(ax["negative"])
            nk = nk + 1
        inp["axis_values"][name] = val
        i = i + 1

    # Mouse delta
    let mp = gpu.mouse_pos()
    if mp != nil:
        let mx = mp["x"]
        let my = mp["y"]
        if inp["first_frame"]:
            inp["last_mx"] = mx
            inp["last_my"] = my
            inp["first_frame"] = false
        inp["mouse_dx"] = mx - inp["last_mx"]
        inp["mouse_dy"] = my - inp["last_my"]
        inp["mouse_x"] = mx
        inp["mouse_y"] = my
        inp["last_mx"] = mx
        inp["last_my"] = my
    else:
        inp["mouse_dx"] = 0.0
        inp["mouse_dy"] = 0.0

    # Scroll
    let sc = gpu.scroll_delta()
    if sc != nil:
        inp["scroll_x"] = sc["x"]
        inp["scroll_y"] = sc["y"]
    else:
        inp["scroll_x"] = 0.0
        inp["scroll_y"] = 0.0

# ============================================================================
# Default bindings preset - FPS style
# ============================================================================
proc default_fps_bindings(inp):
    bind_action(inp, "move_forward", [gpu.KEY_W])
    bind_action(inp, "move_back", [gpu.KEY_S])
    bind_action(inp, "move_left", [gpu.KEY_A])
    bind_action(inp, "move_right", [gpu.KEY_D])
    bind_action(inp, "jump", [gpu.KEY_SPACE])
    bind_action(inp, "crouch", [gpu.KEY_SHIFT])
    bind_action(inp, "interact", [gpu.KEY_E])
    bind_action(inp, "pause", [gpu.KEY_ESCAPE])

    bind_axis(inp, "move_x", [gpu.KEY_D], [gpu.KEY_A])
    bind_axis(inp, "move_z", [gpu.KEY_W], [gpu.KEY_S])
    bind_axis(inp, "move_y", [gpu.KEY_SPACE], [gpu.KEY_SHIFT])
