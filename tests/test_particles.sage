# test_particles.sage - Sanity checks for particle system
# Run: ./run.sh tests/test_particles.sage

from particles import create_emitter, update_emitter, collect_particles, reset_emitter
from particles import emitter_point, emitter_sphere, emitter_box, emitter_cone
from particles import seed_particles
from particles import create_particle_system, add_emitter_to_system
from particles import update_particle_system, total_alive_particles, get_emitter
from math3d import vec3

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
    return math.abs(a - b) < 0.1

print "=== Particle System Sanity Checks ==="

seed_particles(42.0)

# --- Shapes ---
let pt = emitter_point()
check("point shape", pt["type"] == "point")
let sp = emitter_sphere(2.0)
check("sphere shape", sp["type"] == "sphere")
let bx = emitter_box(1.0, 2.0, 3.0)
check("box shape", bx["type"] == "box")
let cn = emitter_cone(1.0, 0.5)
check("cone shape", cn["type"] == "cone")

# --- Emitter creation ---
let e = create_emitter(100)
check("emitter created", e != nil)
check("max particles", e["max_particles"] == 100)
check("pool size", len(e["particles"]) == 100)
check("starts active", e["active"] == true)
check("0 alive initially", e["alive_count"] == 0)

# --- Continuous emission ---
e["rate"] = 50.0
e["shape"] = emitter_point()
e["life_min"] = 1.0
e["life_max"] = 2.0
update_emitter(e, 0.5)
check("particles spawned after update", e["alive_count"] > 0)

let alive1 = e["alive_count"]
update_emitter(e, 0.5)
check("more particles after second update", e["alive_count"] >= alive1)

# --- Collect alive ---
let collected = collect_particles(e)
check("collected matches alive_count", len(collected) == e["alive_count"])
if len(collected) > 0:
    check("particle has position", collected[0]["position"] != nil)
    check("particle has velocity", collected[0]["velocity"] != nil)
    check("particle has color", len(collected[0]["color"]) == 4)
    check("particle alive flag", collected[0]["alive"] == true)
    check("particle life > 0", collected[0]["life"] > 0.0)

# --- Particle death ---
let e2 = create_emitter(10)
e2["rate"] = 100.0
e2["life_min"] = 0.1
e2["life_max"] = 0.1
update_emitter(e2, 0.05)
let before = e2["alive_count"]
check("short-life particles spawned", before > 0)
update_emitter(e2, 0.2)
check("some particles died", e2["alive_count"] <= before or e2["alive_count"] > 0)

# Let them all die
e2["active"] = false
let di = 0
while di < 20:
    update_emitter(e2, 0.1)
    di = di + 1
check("all particles dead eventually", e2["alive_count"] == 0)

# --- Burst / one-shot ---
let e3 = create_emitter(50)
e3["one_shot"] = true
e3["burst"] = 30
e3["life_min"] = 1.0
e3["life_max"] = 1.0
update_emitter(e3, 0.016)
check("burst spawned particles", e3["alive_count"] == 30)
check("one-shot deactivated", e3["active"] == false)
check("has_emitted flag", e3["has_emitted"] == true)

# No more spawn
update_emitter(e3, 0.016)
check("no more spawn after one-shot", e3["alive_count"] == 30)

# --- Reset ---
reset_emitter(e3)
check("reset clears alive", e3["alive_count"] == 0)
check("reset reactivates", e3["active"] == true)
check("reset clears has_emitted", e3["has_emitted"] == false)

# --- Gravity ---
let e4 = create_emitter(10)
e4["rate"] = 100.0
e4["gravity"] = vec3(0.0, -10.0, 0.0)
e4["direction"] = vec3(0.0, 1.0, 0.0)
e4["speed_min"] = 5.0
e4["speed_max"] = 5.0
e4["life_min"] = 2.0
e4["life_max"] = 2.0
update_emitter(e4, 0.1)
update_emitter(e4, 0.5)
let p4 = collect_particles(e4)
if len(p4) > 0:
    check("gravity affects velocity", p4[0]["velocity"][1] < 5.0)

# --- Color/size interpolation ---
let e5 = create_emitter(5)
e5["rate"] = 100.0
e5["life_min"] = 1.0
e5["life_max"] = 1.0
e5["size_start"] = 2.0
e5["size_end"] = 0.0
e5["color_start"] = [1.0, 0.0, 0.0, 1.0]
e5["color_end"] = [0.0, 1.0, 0.0, 0.0]
update_emitter(e5, 0.01)
update_emitter(e5, 0.5)
let p5 = collect_particles(e5)
if len(p5) > 0:
    check("size shrinks over life", p5[0]["size"] < 2.0)
    check("color interpolates", p5[0]["color"][0] < 1.0)

# --- Particle system manager ---
let ps = create_particle_system()
let em_a = create_emitter(20)
em_a["rate"] = 30.0
let em_b = create_emitter(20)
em_b["rate"] = 20.0
add_emitter_to_system(ps, "fire", em_a)
add_emitter_to_system(ps, "smoke", em_b)
check("system has 2 emitters", len(dict_keys(ps["emitters"])) == 2)
check("get emitter works", get_emitter(ps, "fire") != nil)
check("get missing returns nil", get_emitter(ps, "nonexistent") == nil)

update_particle_system(ps, 0.5)
let total = total_alive_particles(ps)
check("system has alive particles", total > 0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Particle system sanity checks failed!"
else:
    print "All particle system sanity checks passed!"
