# test_undo_redo.sage - Sanity checks for undo/redo system
# Run: ./run.sh tests/test_undo_redo.sage

from undo_redo import create_command_history, execute_command, undo, redo
from undo_redo import can_undo, can_redo, undo_count, redo_count
from undo_redo import clear_history, is_dirty, mark_clean
from undo_redo import cmd_set_property, cmd_set_vec3

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

print "=== Undo/Redo Sanity Checks ==="

# --- History creation ---
let h = create_command_history(50)
check("history created", h != nil)
check("no undo", can_undo(h) == false)
check("no redo", can_redo(h) == false)
check("not dirty", is_dirty(h) == false)

# --- Simple property command ---
let obj = {}
obj["x"] = 10.0
let cmd = cmd_set_property(obj, "x", 20.0)
execute_command(h, cmd)
check("property set to 20", approx(obj["x"], 20.0))
check("can undo", can_undo(h))
check("undo count 1", undo_count(h) == 1)
check("is dirty", is_dirty(h))

# --- Undo ---
let undone = undo(h)
check("undo succeeded", undone == true)
check("property back to 10", approx(obj["x"], 10.0))
check("can redo", can_redo(h))
check("undo count 0", undo_count(h) == 0)

# --- Redo ---
let redone = redo(h)
check("redo succeeded", redone == true)
check("property back to 20", approx(obj["x"], 20.0))
check("redo count 0", redo_count(h) == 0)

# --- Multiple commands ---
execute_command(h, cmd_set_property(obj, "x", 30.0))
execute_command(h, cmd_set_property(obj, "x", 40.0))
execute_command(h, cmd_set_property(obj, "x", 50.0))
check("3 commands -> x=50", approx(obj["x"], 50.0))
check("undo count 4", undo_count(h) == 4)

undo(h)
check("undo to 40", approx(obj["x"], 40.0))
undo(h)
check("undo to 30", approx(obj["x"], 30.0))

# New command clears redo
execute_command(h, cmd_set_property(obj, "x", 99.0))
check("new cmd clears redo", can_redo(h) == false)
check("x is 99", approx(obj["x"], 99.0))

# --- Vec3 command ---
let vec_obj = {}
vec_obj["pos"] = [1.0, 2.0, 3.0]
let v_cmd = cmd_set_vec3(vec_obj, "pos", 1, 10.0)
execute_command(h, v_cmd)
check("vec3 y set to 10", approx(vec_obj["pos"][1], 10.0))
undo(h)
check("vec3 y undone to 2", approx(vec_obj["pos"][1], 2.0))

# --- Undo/redo on empty ---
let h2 = create_command_history(10)
check("undo empty returns false", undo(h2) == false)
check("redo empty returns false", redo(h2) == false)

# --- Max size trim ---
let h3 = create_command_history(3)
let counter = {}
counter["v"] = 0
execute_command(h3, cmd_set_property(counter, "v", 1))
execute_command(h3, cmd_set_property(counter, "v", 2))
execute_command(h3, cmd_set_property(counter, "v", 3))
execute_command(h3, cmd_set_property(counter, "v", 4))
check("capped at max size", undo_count(h3) <= 3)

# --- Clear ---
clear_history(h)
check("cleared no undo", can_undo(h) == false)
check("cleared no redo", can_redo(h) == false)
check("cleared not dirty", is_dirty(h) == false)

# --- Mark clean ---
execute_command(h, cmd_set_property(obj, "x", 1.0))
check("dirty after cmd", is_dirty(h))
mark_clean(h)
check("clean after mark", is_dirty(h) == false)
execute_command(h, cmd_set_property(obj, "x", 2.0))
check("dirty again after new cmd", is_dirty(h))

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Undo/redo sanity checks failed!"
else:
    print "All undo/redo sanity checks passed!"
