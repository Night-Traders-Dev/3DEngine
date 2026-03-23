# test_input.sage - Sanity checks for the input system (non-GPU parts)
# Run: ./run.sh tests/test_input.sage
# Tests the data structures and action mapping logic (without actual GPU input)

from input import create_input, bind_action, bind_axis
from input import action_held, action_just_pressed, action_just_released, axis_value
from input import mouse_delta, mouse_position, scroll_value

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Input System Sanity Checks ==="

# --- Creation ---
let inp = create_input()
check("input created", inp != nil)
check("mouse delta starts zero", mouse_delta(inp)[0] == 0.0 and mouse_delta(inp)[1] == 0.0)
check("scroll starts zero", scroll_value(inp)[0] == 0.0 and scroll_value(inp)[1] == 0.0)

# --- Action binding ---
bind_action(inp, "jump", [32])
check("action registered", dict_has(inp["actions"], "jump"))
check("action state initialized false", action_held(inp, "jump") == false)
check("no just_pressed without update", action_just_pressed(inp, "jump") == false)
check("no just_released without update", action_just_released(inp, "jump") == false)

# --- Axis binding ---
bind_axis(inp, "move_x", [68], [65])
check("axis registered", dict_has(inp["axes"], "move_x"))
check("axis value starts zero", axis_value(inp, "move_x") == 0.0)

# --- Non-existent queries ---
check("unknown action returns false", action_held(inp, "nonexistent") == false)
check("unknown axis returns 0", axis_value(inp, "nonexistent") == 0.0)

# --- Simulate state transitions manually ---
# Simulate: action was not pressed, now pressed
inp["action_prev"]["jump"] = false
inp["action_state"]["jump"] = true
check("just_pressed when prev=false curr=true", action_just_pressed(inp, "jump"))
check("not just_released when prev=false curr=true", action_just_released(inp, "jump") == false)
check("held when curr=true", action_held(inp, "jump"))

# Simulate: action was pressed, still pressed
inp["action_prev"]["jump"] = true
inp["action_state"]["jump"] = true
check("not just_pressed when both true", action_just_pressed(inp, "jump") == false)
check("still held", action_held(inp, "jump"))

# Simulate: action was pressed, now released
inp["action_prev"]["jump"] = true
inp["action_state"]["jump"] = false
check("just_released when prev=true curr=false", action_just_released(inp, "jump"))
check("not held when curr=false", action_held(inp, "jump") == false)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Input system sanity checks failed!"
else:
    print "All input system sanity checks passed!"
