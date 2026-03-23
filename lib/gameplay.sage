gc_disable()
# -----------------------------------------
# gameplay.sage - Gameplay framework for Sage Engine
# Health, damage, spawning, timers, state machines
# -----------------------------------------

from math3d import vec3
from ecs import spawn, add_component, get_component, has_component, destroy, add_tag

# ============================================================================
# Health Component
# ============================================================================
proc HealthComponent(max_hp):
    let h = {}
    h["current"] = max_hp
    h["max"] = max_hp
    h["alive"] = true
    h["invulnerable"] = false
    h["regen_rate"] = 0.0
    h["regen_delay"] = 0.0
    h["last_damage_time"] = 0.0
    return h

proc damage(health, amount, time):
    if health["invulnerable"]:
        return 0.0
    if health["alive"] == false:
        return 0.0
    let actual = amount
    if actual > health["current"]:
        actual = health["current"]
    health["current"] = health["current"] - actual
    health["last_damage_time"] = time
    if health["current"] <= 0.0:
        health["current"] = 0.0
        health["alive"] = false
    return actual

proc heal(health, amount):
    if health["alive"] == false:
        return 0.0
    let room = health["max"] - health["current"]
    let actual = amount
    if actual > room:
        actual = room
    health["current"] = health["current"] + actual
    return actual

proc health_percent(health):
    if health["max"] <= 0.0:
        return 0.0
    return health["current"] / health["max"]

proc is_dead(health):
    return health["alive"] == false

proc revive(health, hp):
    health["alive"] = true
    health["current"] = hp
    if health["current"] > health["max"]:
        health["current"] = health["max"]

proc update_health_regen(health, dt, time):
    if health["alive"] == false:
        return nil
    if health["regen_rate"] <= 0.0:
        return nil
    if time - health["last_damage_time"] < health["regen_delay"]:
        return nil
    heal(health, health["regen_rate"] * dt)

# ============================================================================
# Timer Component - fires callback after delay
# ============================================================================
proc TimerComponent(duration, repeating):
    let t = {}
    t["duration"] = duration
    t["remaining"] = duration
    t["repeating"] = repeating
    t["active"] = true
    t["fired"] = false
    t["callback"] = nil
    return t

proc update_timer(timer, dt):
    if timer["active"] == false:
        return false
    timer["remaining"] = timer["remaining"] - dt
    if timer["remaining"] <= 0.0:
        timer["fired"] = true
        if timer["callback"] != nil:
            timer["callback"]()
        if timer["repeating"]:
            timer["remaining"] = timer["remaining"] + timer["duration"]
            timer["fired"] = false
        else:
            timer["active"] = false
        return true
    return false

proc reset_timer(timer):
    timer["remaining"] = timer["duration"]
    timer["active"] = true
    timer["fired"] = false

# ============================================================================
# State Machine
# ============================================================================
proc create_state_machine(initial_state):
    let sm = {}
    sm["current"] = initial_state
    sm["previous"] = nil
    sm["states"] = {}
    sm["time_in_state"] = 0.0
    return sm

proc add_state(sm, name, on_enter, on_update, on_exit):
    let s = {}
    s["name"] = name
    s["on_enter"] = on_enter
    s["on_update"] = on_update
    s["on_exit"] = on_exit
    sm["states"][name] = s

proc transition(sm, new_state):
    if sm["current"] == new_state:
        return nil
    # Exit current state
    if dict_has(sm["states"], sm["current"]):
        let cur = sm["states"][sm["current"]]
        if cur["on_exit"] != nil:
            cur["on_exit"](sm)
    sm["previous"] = sm["current"]
    sm["current"] = new_state
    sm["time_in_state"] = 0.0
    # Enter new state
    if dict_has(sm["states"], new_state):
        let s = sm["states"][new_state]
        if s["on_enter"] != nil:
            s["on_enter"](sm)

proc update_state_machine(sm, dt):
    sm["time_in_state"] = sm["time_in_state"] + dt
    if dict_has(sm["states"], sm["current"]):
        let s = sm["states"][sm["current"]]
        if s["on_update"] != nil:
            s["on_update"](sm, dt)

# ============================================================================
# Spawner - creates entities from templates
# ============================================================================
proc create_spawner():
    let sp = {}
    sp["templates"] = {}
    sp["spawn_count"] = 0
    return sp

proc register_template(spawner, name, setup_fn):
    spawner["templates"][name] = setup_fn

proc spawn_from_template(spawner, world, template_name, position):
    if dict_has(spawner["templates"], template_name) == false:
        print "WARNING: Unknown template '" + template_name + "'"
        return -1
    let e = spawn(world)
    from components import TransformComponent
    add_component(world, e, "transform", TransformComponent(position[0], position[1], position[2]))
    # Call template setup function
    spawner["templates"][template_name](world, e)
    spawner["spawn_count"] = spawner["spawn_count"] + 1
    return e

# ============================================================================
# Score tracker
# ============================================================================
proc create_score():
    let s = {}
    s["points"] = 0
    s["combo"] = 0
    s["combo_timer"] = 0.0
    s["combo_window"] = 2.0
    s["high_score"] = 0
    return s

proc add_points(score, amount):
    score["combo"] = score["combo"] + 1
    score["combo_timer"] = score["combo_window"]
    let multiplied = amount * score["combo"]
    score["points"] = score["points"] + multiplied
    if score["points"] > score["high_score"]:
        score["high_score"] = score["points"]
    return multiplied

proc update_score(score, dt):
    if score["combo_timer"] > 0.0:
        score["combo_timer"] = score["combo_timer"] - dt
        if score["combo_timer"] <= 0.0:
            score["combo"] = 0
            score["combo_timer"] = 0.0

proc reset_score(score):
    score["points"] = 0
    score["combo"] = 0
    score["combo_timer"] = 0.0
