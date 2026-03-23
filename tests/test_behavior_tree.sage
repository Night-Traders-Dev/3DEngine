# test_behavior_tree.sage - Sanity checks for behavior trees
# Run: ./run.sh tests/test_behavior_tree.sage

from behavior_tree import BT_SUCCESS, BT_FAILURE, BT_RUNNING
from behavior_tree import bt_action, bt_condition, bt_sequence, bt_selector
from behavior_tree import bt_inverter, bt_repeater, bt_succeeder, bt_wait
from behavior_tree import bt_tick, bt_reset
from behavior_tree import BehaviorTreeComponent, update_behavior_tree

import math

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Behavior Tree Sanity Checks ==="

let ctx = {}
ctx["dt"] = 0.016

# --- Action node ---
let action_ran = [false]
proc test_action(c):
    action_ran[0] = true
    return BT_SUCCESS

let a = bt_action("test", test_action)
check("action created", a["type"] == "action")
let r = bt_tick(a, ctx)
check("action ran", action_ran[0] == true)
check("action returns success", r == BT_SUCCESS)

# --- Condition node ---
let flag = [true]
proc test_cond(c):
    return flag[0]

let cond = bt_condition("flag_check", test_cond)
check("condition true = success", bt_tick(cond, ctx) == BT_SUCCESS)
flag[0] = false
check("condition false = failure", bt_tick(cond, ctx) == BT_FAILURE)

# --- Sequence ---
let seq_log = []
proc seq_a(c):
    push(seq_log, "a")
    return BT_SUCCESS
proc seq_b(c):
    push(seq_log, "b")
    return BT_SUCCESS
proc seq_fail(c):
    push(seq_log, "fail")
    return BT_FAILURE

# All succeed
let seq = bt_sequence("test_seq", [bt_action("a", seq_a), bt_action("b", seq_b)])
let sr = bt_tick(seq, ctx)
check("sequence all success", sr == BT_SUCCESS)
check("sequence ran both", len(seq_log) == 2)

# First fails -> stops
seq_log = []
let seq2 = bt_sequence("fail_seq", [bt_action("fail", seq_fail), bt_action("b", seq_b)])
let sr2 = bt_tick(seq2, ctx)
check("sequence fails on first failure", sr2 == BT_FAILURE)
check("sequence stopped at failure", len(seq_log) == 1)

# --- Selector ---
let sel_log = []
proc sel_fail(c):
    push(sel_log, "fail")
    return BT_FAILURE
proc sel_ok(c):
    push(sel_log, "ok")
    return BT_SUCCESS

let sel = bt_selector("test_sel", [bt_action("fail", sel_fail), bt_action("ok", sel_ok)])
let selr = bt_tick(sel, ctx)
check("selector succeeds on second", selr == BT_SUCCESS)
check("selector tried both", len(sel_log) == 2)

# All fail
sel_log = []
let sel2 = bt_selector("all_fail", [bt_action("f1", sel_fail), bt_action("f2", sel_fail)])
check("selector all fail", bt_tick(sel2, ctx) == BT_FAILURE)

# --- Inverter ---
proc always_success(c):
    return BT_SUCCESS
proc always_fail(c):
    return BT_FAILURE

let inv = bt_inverter("inv", bt_action("ok", always_success))
check("inverter flips success to failure", bt_tick(inv, ctx) == BT_FAILURE)

let inv2 = bt_inverter("inv2", bt_action("fail", always_fail))
check("inverter flips failure to success", bt_tick(inv2, ctx) == BT_SUCCESS)

# --- Succeeder ---
let succ = bt_succeeder("succ", bt_action("fail", always_fail))
check("succeeder always success", bt_tick(succ, ctx) == BT_SUCCESS)

# --- Wait ---
let wait = bt_wait("wait", 1.0)
ctx["dt"] = 0.3
check("wait running at 0.3s", bt_tick(wait, ctx) == BT_RUNNING)
check("wait running at 0.6s", bt_tick(wait, ctx) == BT_RUNNING)
check("wait running at 0.9s", bt_tick(wait, ctx) == BT_RUNNING)
check("wait success at 1.2s", bt_tick(wait, ctx) == BT_SUCCESS)

# --- Repeater ---
let rep_count = [0]
proc rep_action(c):
    rep_count[0] = rep_count[0] + 1
    return BT_SUCCESS

let rep = bt_repeater("rep", bt_action("inc", rep_action), 3)
check("repeater running 1", bt_tick(rep, ctx) == BT_RUNNING)
check("repeater running 2", bt_tick(rep, ctx) == BT_RUNNING)
check("repeater done at 3", bt_tick(rep, ctx) == BT_SUCCESS)
check("repeater ran 3 times", rep_count[0] == 3)

# --- Sequence with RUNNING ---
let running_count = [0]
proc running_action(c):
    running_count[0] = running_count[0] + 1
    if running_count[0] < 3:
        return BT_RUNNING
    return BT_SUCCESS

let run_seq = bt_sequence("run_seq", [bt_action("run", running_action), bt_action("ok", always_success)])
check("running pauses sequence", bt_tick(run_seq, ctx) == BT_RUNNING)
check("running resumes", bt_tick(run_seq, ctx) == BT_RUNNING)
check("running completes", bt_tick(run_seq, ctx) == BT_SUCCESS)

# --- Reset ---
bt_reset(wait)
check("wait reset elapsed", wait["elapsed"] == 0.0)
bt_reset(rep)
check("repeater reset count", rep["current_count"] == 0)
bt_reset(run_seq)
check("sequence reset index", run_seq["running_index"] == 0)

# --- BT Component ---
let bt_comp = BehaviorTreeComponent(bt_action("noop", always_success))
check("bt component created", bt_comp != nil)
check("bt component enabled", bt_comp["enabled"] == true)

from ecs import create_world, spawn, add_component
let w = create_world()
let e = spawn(w)
update_behavior_tree(bt_comp, w, e, 0.016)
check("bt component updated", bt_comp["last_result"] == BT_SUCCESS)

# Disabled
bt_comp["enabled"] = false
bt_comp["last_result"] = BT_FAILURE
update_behavior_tree(bt_comp, w, e, 0.016)
check("disabled bt not updated", bt_comp["last_result"] == BT_FAILURE)

# --- Complex tree: patrol with health check ---
flag[0] = true
let fight_seq = bt_sequence("fight", [bt_condition("has_target", test_cond), bt_action("attack", always_success)])
let complex = bt_selector("root", [fight_seq, bt_action("patrol", always_success)])
check("complex tree: fight when flag true", bt_tick(complex, ctx) == BT_SUCCESS)
flag[0] = false
bt_reset(complex)
check("complex tree: patrol when flag false", bt_tick(complex, ctx) == BT_SUCCESS)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Behavior tree sanity checks failed!"
else:
    print "All behavior tree sanity checks passed!"
