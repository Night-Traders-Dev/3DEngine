# test_gameplay.sage - Sanity checks for gameplay framework
# Run: ./run.sh tests/test_gameplay.sage

from gameplay import HealthComponent, damage, heal, health_percent, is_dead, revive
from gameplay import update_health_regen
from gameplay import TimerComponent, update_timer, reset_timer
from gameplay import create_state_machine, add_state, transition, update_state_machine
from gameplay import create_spawner, register_template, spawn_from_template
from gameplay import create_score, add_points, update_score, reset_score

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

print "=== Gameplay Framework Sanity Checks ==="

# --- Health ---
let h = HealthComponent(100.0)
check("health starts at max", approx(h["current"], 100.0))
check("health max", approx(h["max"], 100.0))
check("health alive", h["alive"] == true)
check("health percent = 1", approx(health_percent(h), 1.0))

# Damage
let dmg = damage(h, 30.0, 0.0)
check("damage returns actual", approx(dmg, 30.0))
check("health reduced", approx(h["current"], 70.0))
check("still alive", h["alive"] == true)
check("health percent after damage", approx(health_percent(h), 0.7))

# Overkill damage
let kill_dmg = damage(h, 200.0, 1.0)
check("overkill clamped to remaining", approx(kill_dmg, 70.0))
check("health at 0", approx(h["current"], 0.0))
check("is dead", is_dead(h))
check("dead check", h["alive"] == false)

# Damage to dead entity
let dead_dmg = damage(h, 50.0, 2.0)
check("dead takes no damage", approx(dead_dmg, 0.0))

# Heal dead entity does nothing
let dead_heal = heal(h, 50.0)
check("dead cannot heal", approx(dead_heal, 0.0))

# Revive
revive(h, 50.0)
check("revived", h["alive"] == true)
check("revived hp", approx(h["current"], 50.0))

# Heal
let healed = heal(h, 30.0)
check("healed amount", approx(healed, 30.0))
check("health after heal", approx(h["current"], 80.0))

# Overheal capped
let overheal = heal(h, 50.0)
check("overheal capped", approx(overheal, 20.0))
check("health at max after overheal", approx(h["current"], 100.0))

# Invulnerability
h["invulnerable"] = true
let inv_dmg = damage(h, 50.0, 3.0)
check("invulnerable takes no damage", approx(inv_dmg, 0.0))
check("health unchanged", approx(h["current"], 100.0))
h["invulnerable"] = false

# Regen
let h2 = HealthComponent(100.0)
h2["regen_rate"] = 10.0
h2["regen_delay"] = 1.0
damage(h2, 50.0, 0.0)
# Too soon after damage (time=0.5 < delay=1.0)
update_health_regen(h2, 1.0, 0.5)
check("regen delayed", approx(h2["current"], 50.0))
# After delay
update_health_regen(h2, 1.0, 2.0)
check("regen applies after delay", approx(h2["current"], 60.0))

# --- Timer ---
let timer = TimerComponent(2.0, false)
check("timer created", timer != nil)
check("timer active", timer["active"] == true)
check("timer not fired", timer["fired"] == false)

let fired1 = update_timer(timer, 1.0)
check("timer not fired at 1s", fired1 == false)
check("timer remaining ~1", approx(timer["remaining"], 1.0))

let fired2 = update_timer(timer, 1.5)
check("timer fired at 2.5s", fired2 == true)
check("timer marked fired", timer["fired"] == true)
check("timer inactive after one-shot", timer["active"] == false)

# Repeating timer
let rtimer = TimerComponent(1.0, true)
update_timer(rtimer, 1.5)
check("repeating timer still active", rtimer["active"] == true)
check("repeating timer reset remaining", rtimer["remaining"] > 0.0)

# Reset
reset_timer(timer)
check("reset timer active", timer["active"] == true)
check("reset timer remaining", approx(timer["remaining"], 2.0))

# Timer callback
let cb_called = [false]
proc test_cb():
    cb_called[0] = true
let cb_timer = TimerComponent(0.5, false)
cb_timer["callback"] = test_cb
update_timer(cb_timer, 1.0)
check("timer callback called", cb_called[0] == true)

# --- State Machine ---
let enter_log = []
let update_log = []
let exit_log = []

proc idle_enter(sm):
    push(enter_log, "idle")
proc idle_update(sm, dt):
    push(update_log, "idle")
proc idle_exit(sm):
    push(exit_log, "idle")
proc attack_enter(sm):
    push(enter_log, "attack")
proc attack_update(sm, dt):
    push(update_log, "attack")
proc attack_exit(sm):
    push(exit_log, "attack")

let sm = create_state_machine("idle")
add_state(sm, "idle", idle_enter, idle_update, idle_exit)
add_state(sm, "attack", attack_enter, attack_update, attack_exit)
check("sm starts in idle", sm["current"] == "idle")

update_state_machine(sm, 1.0)
check("idle update called", len(update_log) == 1)

transition(sm, "attack")
check("transitioned to attack", sm["current"] == "attack")
check("previous was idle", sm["previous"] == "idle")
check("idle exit called", len(exit_log) == 1)
check("attack enter called", len(enter_log) == 1)
check("time reset on transition", approx(sm["time_in_state"], 0.0))

# Same state transition (no-op)
transition(sm, "attack")
check("same state no-op", len(enter_log) == 1)

update_state_machine(sm, 0.5)
check("attack update called", update_log[1] == "attack")

# --- Spawner ---
let spawner = create_spawner()
check("spawner created", spawner != nil)
check("spawn count 0", spawner["spawn_count"] == 0)

let template_called = [false]
proc test_template(world, entity):
    template_called[0] = true

register_template(spawner, "test_obj", test_template)
check("template registered", dict_has(spawner["templates"], "test_obj"))

from ecs import create_world
from math3d import vec3
let test_world = create_world()
let eid = spawn_from_template(spawner, test_world, "test_obj", vec3(1.0, 2.0, 3.0))
check("spawned entity > 0", eid > 0)
check("template called", template_called[0] == true)
check("spawn count incremented", spawner["spawn_count"] == 1)

# Unknown template
let bad = spawn_from_template(spawner, test_world, "nonexistent", vec3(0.0, 0.0, 0.0))
check("unknown template returns -1", bad == -1)

# --- Score ---
let score = create_score()
check("score starts at 0", score["points"] == 0)
check("combo starts at 0", score["combo"] == 0)

let p1 = add_points(score, 100)
check("first add: 100 * combo=1", p1 == 100)
check("score is 100", score["points"] == 100)
check("combo is 1", score["combo"] == 1)

let p2 = add_points(score, 50)
check("second add: 50 * combo=2", p2 == 100)
check("score is 200", score["points"] == 200)

# Combo decay
update_score(score, 3.0)
check("combo reset after timeout", score["combo"] == 0)

# High score
check("high score tracked", score["high_score"] == 200)
reset_score(score)
check("reset points", score["points"] == 0)
check("high score preserved", score["high_score"] == 200)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Gameplay sanity checks failed!"
else:
    print "All gameplay sanity checks passed!"
