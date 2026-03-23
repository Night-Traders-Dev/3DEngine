gc_disable()
# -----------------------------------------
# tween.sage - Tweening & easing system for Sage Engine
# Property animation with easing functions
# -----------------------------------------

import math
from math3d import vec3, v3_lerp

let PI = 3.14159265358979323846

# ============================================================================
# Easing functions (t in 0..1, returns 0..1)
# ============================================================================
proc ease_linear(t):
    return t

proc ease_in_quad(t):
    return t * t

proc ease_out_quad(t):
    return t * (2.0 - t)

proc ease_in_out_quad(t):
    if t < 0.5:
        return 2.0 * t * t
    return -1.0 + (4.0 - 2.0 * t) * t

proc ease_in_cubic(t):
    return t * t * t

proc ease_out_cubic(t):
    let u = t - 1.0
    return u * u * u + 1.0

proc ease_in_out_cubic(t):
    if t < 0.5:
        return 4.0 * t * t * t
    let u = 2.0 * t - 2.0
    return (u * u * u + 2.0) / 2.0

proc ease_in_sine(t):
    return 1.0 - math.cos(t * PI / 2.0)

proc ease_out_sine(t):
    return math.sin(t * PI / 2.0)

proc ease_in_out_sine(t):
    return 0.0 - (math.cos(PI * t) - 1.0) / 2.0

proc ease_in_expo(t):
    if t <= 0.0:
        return 0.0
    return math.pow(2.0, 10.0 * (t - 1.0))

proc ease_out_expo(t):
    if t >= 1.0:
        return 1.0
    return 1.0 - math.pow(2.0, -10.0 * t)

proc ease_in_elastic(t):
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return 1.0
    let p = 0.3
    let s = p / 4.0
    let u = t - 1.0
    return 0.0 - math.pow(2.0, 10.0 * u) * math.sin((u - s) * (2.0 * PI) / p)

proc ease_out_elastic(t):
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return 1.0
    let p = 0.3
    let s = p / 4.0
    return math.pow(2.0, -10.0 * t) * math.sin((t - s) * (2.0 * PI) / p) + 1.0

proc ease_out_bounce(t):
    if t < 1.0 / 2.75:
        return 7.5625 * t * t
    if t < 2.0 / 2.75:
        let u = t - 1.5 / 2.75
        return 7.5625 * u * u + 0.75
    if t < 2.5 / 2.75:
        let u = t - 2.25 / 2.75
        return 7.5625 * u * u + 0.9375
    let u = t - 2.625 / 2.75
    return 7.5625 * u * u + 0.984375

proc ease_in_bounce(t):
    return 1.0 - ease_out_bounce(1.0 - t)

proc ease_in_back(t):
    let s = 1.70158
    return t * t * ((s + 1.0) * t - s)

proc ease_out_back(t):
    let s = 1.70158
    let u = t - 1.0
    return u * u * ((s + 1.0) * u + s) + 1.0

# ============================================================================
# Easing lookup by name
# ============================================================================
let _easings = {}
_easings["linear"] = ease_linear
_easings["in_quad"] = ease_in_quad
_easings["out_quad"] = ease_out_quad
_easings["in_out_quad"] = ease_in_out_quad
_easings["in_cubic"] = ease_in_cubic
_easings["out_cubic"] = ease_out_cubic
_easings["in_out_cubic"] = ease_in_out_cubic
_easings["in_sine"] = ease_in_sine
_easings["out_sine"] = ease_out_sine
_easings["in_out_sine"] = ease_in_out_sine
_easings["in_expo"] = ease_in_expo
_easings["out_expo"] = ease_out_expo
_easings["in_elastic"] = ease_in_elastic
_easings["out_elastic"] = ease_out_elastic
_easings["out_bounce"] = ease_out_bounce
_easings["in_bounce"] = ease_in_bounce
_easings["in_back"] = ease_in_back
_easings["out_back"] = ease_out_back

proc get_easing(name):
    if dict_has(_easings, name):
        return _easings[name]
    return ease_linear

# ============================================================================
# Tween object
# ============================================================================
proc create_tween(from_val, to_val, duration, easing_name):
    let tw = {}
    tw["from"] = from_val
    tw["to"] = to_val
    tw["duration"] = duration
    tw["elapsed"] = 0.0
    tw["easing"] = get_easing(easing_name)
    tw["easing_name"] = easing_name
    tw["active"] = true
    tw["finished"] = false
    tw["loop"] = false
    tw["ping_pong"] = false
    tw["direction"] = 1
    tw["on_complete"] = nil
    tw["delay"] = 0.0
    tw["delay_remaining"] = 0.0
    return tw

proc create_tween_vec3(from_v, to_v, duration, easing_name):
    let tw = create_tween(0.0, 1.0, duration, easing_name)
    tw["from_vec"] = from_v
    tw["to_vec"] = to_v
    tw["is_vec3"] = true
    return tw

# ============================================================================
# Update tween
# ============================================================================
proc update_tween(tw, dt):
    if tw["active"] == false:
        return nil
    # Delay
    if tw["delay_remaining"] > 0.0:
        tw["delay_remaining"] = tw["delay_remaining"] - dt
        return nil
    tw["elapsed"] = tw["elapsed"] + dt * tw["direction"]
    if tw["elapsed"] >= tw["duration"]:
        if tw["ping_pong"]:
            tw["direction"] = -1
            tw["elapsed"] = tw["duration"]
        else:
            if tw["loop"]:
                tw["elapsed"] = tw["elapsed"] - tw["duration"]
            else:
                tw["elapsed"] = tw["duration"]
                tw["finished"] = true
                tw["active"] = false
                if tw["on_complete"] != nil:
                    tw["on_complete"]()
    if tw["elapsed"] < 0.0:
        if tw["loop"]:
            tw["direction"] = 1
            tw["elapsed"] = 0.0
        else:
            tw["elapsed"] = 0.0
            tw["finished"] = true
            tw["active"] = false

proc tween_value(tw):
    let t = tw["elapsed"] / tw["duration"]
    if t < 0.0:
        t = 0.0
    if t > 1.0:
        t = 1.0
    let eased = tw["easing"](t)
    if dict_has(tw, "is_vec3"):
        return v3_lerp(tw["from_vec"], tw["to_vec"], eased)
    return tw["from"] + (tw["to"] - tw["from"]) * eased

proc tween_progress(tw):
    return tw["elapsed"] / tw["duration"]

proc reset_tween(tw):
    tw["elapsed"] = 0.0
    tw["active"] = true
    tw["finished"] = false
    tw["direction"] = 1
    tw["delay_remaining"] = tw["delay"]

# ============================================================================
# Tween Manager - manages multiple tweens
# ============================================================================
proc create_tween_manager():
    let tm = {}
    tm["tweens"] = {}
    tm["next_id"] = 1
    return tm

proc add_tween(tm, name, tw):
    tm["tweens"][name] = tw

proc get_tween(tm, name):
    if dict_has(tm["tweens"], name) == false:
        return nil
    return tm["tweens"][name]

proc update_tweens(tm, dt):
    let names = dict_keys(tm["tweens"])
    let i = 0
    while i < len(names):
        let tw = tm["tweens"][names[i]]
        update_tween(tw, dt)
        i = i + 1

proc remove_finished(tm):
    let names = dict_keys(tm["tweens"])
    let to_remove = []
    let i = 0
    while i < len(names):
        if tm["tweens"][names[i]]["finished"]:
            push(to_remove, names[i])
        i = i + 1
    i = 0
    while i < len(to_remove):
        dict_delete(tm["tweens"], to_remove[i])
        i = i + 1
    return len(to_remove)

proc active_tween_count(tm):
    let count = 0
    let names = dict_keys(tm["tweens"])
    let i = 0
    while i < len(names):
        if tm["tweens"][names[i]]["active"]:
            count = count + 1
        i = i + 1
    return count
