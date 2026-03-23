# test_vfx_presets.sage - Sanity checks for VFX presets
# Run: ./run.sh tests/test_vfx_presets.sage

from vfx_presets import vfx_fire, vfx_smoke, vfx_sparks, vfx_explosion
from vfx_presets import vfx_rain, vfx_dust, vfx_magic
from particles import update_emitter, collect_particles, seed_particles
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

print "=== VFX Presets Sanity Checks ==="

seed_particles(99.0)
let pos = vec3(0.0, 0.0, 0.0)

# --- Fire ---
let fire = vfx_fire(pos, 1.0)
check("fire created", fire != nil)
check("fire rate > 0", fire["rate"] > 0.0)
check("fire upward", fire["direction"][1] > 0.0)
check("fire warm color", fire["color_start"][0] > 0.5)
update_emitter(fire, 0.5)
check("fire spawns particles", fire["alive_count"] > 0)

# --- Smoke ---
let smoke = vfx_smoke(pos, 1.0)
check("smoke created", smoke != nil)
check("smoke grows", smoke["size_end"] > smoke["size_start"])
check("smoke semi-transparent", smoke["color_start"][3] < 1.0)
update_emitter(smoke, 0.5)
check("smoke spawns", smoke["alive_count"] > 0)

# --- Sparks ---
let sparks = vfx_sparks(pos, 30)
check("sparks one_shot", sparks["one_shot"] == true)
check("sparks burst count", sparks["burst"] == 30)
check("sparks fast", sparks["speed_max"] > 5.0)
check("sparks gravity down", sparks["gravity"][1] < 0.0)
update_emitter(sparks, 0.016)
check("sparks burst spawned", sparks["alive_count"] == 30)

# --- Explosion ---
let boom = vfx_explosion(pos, 1.0)
check("explosion created", boom != nil)
check("explosion one_shot", boom["one_shot"] == true)
check("explosion burst large", boom["burst"] >= 100)
check("explosion fast", boom["speed_max"] > 8.0)
update_emitter(boom, 0.016)
check("explosion spawns many", boom["alive_count"] > 50)

# --- Rain ---
let rain = vfx_rain(20.0, 1.0)
check("rain created", rain != nil)
check("rain falls down", rain["direction"][1] < 0.0)
check("rain small particles", rain["size_start"] < 0.1)
check("rain spawns high", rain["position"][1] > 10.0)
update_emitter(rain, 0.5)
check("rain has particles", rain["alive_count"] > 0)

# --- Dust ---
let dust = vfx_dust(pos)
check("dust created", dust != nil)
check("dust slow", dust["speed_max"] < 2.0)
check("dust semi-transparent", dust["color_start"][3] < 0.5)
update_emitter(dust, 1.0)
check("dust has particles", dust["alive_count"] > 0)

# --- Magic ---
let magic = vfx_magic(pos, 0.5, 0.8, 1.0)
check("magic created", magic != nil)
check("magic color matches", magic["color_start"][2] > 0.9)
check("magic floats up", magic["gravity"][1] > 0.0)
update_emitter(magic, 0.5)
check("magic has particles", magic["alive_count"] > 0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "VFX presets sanity checks failed!"
else:
    print "All VFX presets sanity checks passed!"
