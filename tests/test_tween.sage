# test_tween.sage - Sanity checks for tweening system
# Run: ./run.sh tests/test_tween.sage

from tween import ease_linear, ease_in_quad, ease_out_quad, ease_in_out_quad
from tween import ease_in_cubic, ease_out_cubic, ease_out_bounce, ease_out_elastic
from tween import ease_in_back, ease_out_back, get_easing
from tween import create_tween, create_tween_vec3, update_tween, tween_value
from tween import tween_progress, reset_tween
from tween import create_tween_manager, add_tween, update_tweens
from tween import remove_finished, active_tween_count
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

print "=== Tween System Sanity Checks ==="

# --- Easing functions ---
check("linear 0", approx(ease_linear(0.0), 0.0))
check("linear 0.5", approx(ease_linear(0.5), 0.5))
check("linear 1", approx(ease_linear(1.0), 1.0))

check("in_quad 0", approx(ease_in_quad(0.0), 0.0))
check("in_quad 1", approx(ease_in_quad(1.0), 1.0))
check("in_quad 0.5 < 0.5", ease_in_quad(0.5) < 0.5)

check("out_quad 0", approx(ease_out_quad(0.0), 0.0))
check("out_quad 1", approx(ease_out_quad(1.0), 1.0))
check("out_quad 0.5 > 0.5", ease_out_quad(0.5) > 0.5)

check("in_out_quad 0", approx(ease_in_out_quad(0.0), 0.0))
check("in_out_quad 1", approx(ease_in_out_quad(1.0), 1.0))
check("in_out_quad 0.5 ~ 0.5", approx(ease_in_out_quad(0.5), 0.5))

check("out_bounce 1", approx(ease_out_bounce(1.0), 1.0))
check("out_bounce 0", approx(ease_out_bounce(0.0), 0.0))

check("out_elastic 0", approx(ease_out_elastic(0.0), 0.0))
check("out_elastic 1", approx(ease_out_elastic(1.0), 1.0))

check("in_back overshoots", ease_in_back(0.5) < 0.0)
check("out_back 1", approx(ease_out_back(1.0), 1.0))

# --- Easing lookup ---
let e = get_easing("in_cubic")
check("lookup in_cubic", approx(e(1.0), 1.0))
let def = get_easing("nonexistent")
check("unknown defaults to linear", approx(def(0.5), 0.5))

# --- Tween creation ---
let tw = create_tween(0.0, 100.0, 2.0, "linear")
check("tween created", tw != nil)
check("tween active", tw["active"] == true)
check("tween not finished", tw["finished"] == false)
check("tween value at start", approx(tween_value(tw), 0.0))

# --- Update tween ---
update_tween(tw, 1.0)
check("tween progress 0.5", approx(tween_progress(tw), 0.5))
check("tween value at half", approx(tween_value(tw), 50.0))

update_tween(tw, 1.0)
check("tween progress 1.0", approx(tween_progress(tw), 1.0))
check("tween value at end", approx(tween_value(tw), 100.0))
check("tween finished", tw["finished"] == true)
check("tween inactive", tw["active"] == false)

# --- Reset ---
reset_tween(tw)
check("reset active", tw["active"] == true)
check("reset not finished", tw["finished"] == false)
check("reset value at 0", approx(tween_value(tw), 0.0))

# --- Vec3 tween ---
let v_tw = create_tween_vec3(vec3(0.0, 0.0, 0.0), vec3(10.0, 20.0, 30.0), 1.0, "linear")
update_tween(v_tw, 0.5)
let v = tween_value(v_tw)
check("vec3 tween x", approx(v[0], 5.0))
check("vec3 tween y", approx(v[1], 10.0))
check("vec3 tween z", approx(v[2], 15.0))

# --- Loop ---
let loop_tw = create_tween(0.0, 1.0, 1.0, "linear")
loop_tw["loop"] = true
update_tween(loop_tw, 1.5)
check("loop tween still active", loop_tw["active"] == true)
check("loop tween wraps", tween_progress(loop_tw) < 1.0)

# --- Delay ---
let delay_tw = create_tween(0.0, 10.0, 1.0, "linear")
delay_tw["delay"] = 0.5
delay_tw["delay_remaining"] = 0.5
update_tween(delay_tw, 0.3)
check("delayed tween hasn't started", approx(tween_value(delay_tw), 0.0))
update_tween(delay_tw, 0.3)
update_tween(delay_tw, 0.5)
check("delayed tween progresses after delay", tween_value(delay_tw) > 0.0)

# --- Callback ---
let cb_fired = [false]
proc on_done():
    cb_fired[0] = true
let cb_tw = create_tween(0.0, 1.0, 0.5, "linear")
cb_tw["on_complete"] = on_done
update_tween(cb_tw, 1.0)
check("callback fired", cb_fired[0] == true)

# --- Tween manager ---
let tm = create_tween_manager()
add_tween(tm, "a", create_tween(0.0, 1.0, 1.0, "linear"))
add_tween(tm, "b", create_tween(0.0, 1.0, 0.5, "linear"))
check("2 active tweens", active_tween_count(tm) == 2)

update_tweens(tm, 0.6)
check("b finished after 0.6s", tm["tweens"]["b"]["finished"] == true)
check("a still active", tm["tweens"]["a"]["active"] == true)

let removed = remove_finished(tm)
check("removed 1 finished", removed == 1)
check("1 active after remove", active_tween_count(tm) == 1)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Tween sanity checks failed!"
else:
    print "All tween sanity checks passed!"
