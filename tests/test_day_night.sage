# test_day_night.sage - Sanity checks for day/night cycle
# Run: ./run.sh tests/test_day_night.sage

from day_night import create_day_cycle, set_time_of_day, get_time_of_day
from day_night import get_hour, update_day_cycle
from math3d import v3_length

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

print "=== Day/Night Cycle Sanity Checks ==="

# --- Creation ---
let dc = create_day_cycle(120.0)
check("cycle created", dc != nil)
check("day length", approx(dc["day_length"], 120.0))
check("starts at 0.25 (sunrise)", approx(dc["time_of_day"], 0.25))

# --- Time of day ---
set_time_of_day(dc, 0.5)
check("set to noon", approx(get_time_of_day(dc), 0.5))
check("noon = hour 12", approx(get_hour(dc), 12.0))

set_time_of_day(dc, 0.0)
check("midnight = hour 0", approx(get_hour(dc), 0.0))

set_time_of_day(dc, 0.75)
check("sunset = hour 18", approx(get_hour(dc), 18.0))

# Wrapping
set_time_of_day(dc, 1.5)
check("wraps past 1.0", get_time_of_day(dc) < 1.0)

# --- Update ---
set_time_of_day(dc, 0.5)
dc["speed"] = 1.0
update_day_cycle(dc, 1.0)
check("time advances", get_time_of_day(dc) > 0.5)

# Paused
dc["paused"] = true
let before = get_time_of_day(dc)
update_day_cycle(dc, 10.0)
check("paused doesn't advance", approx(get_time_of_day(dc), before))
dc["paused"] = false

# --- Noon properties ---
set_time_of_day(dc, 0.5)
update_day_cycle(dc, 0.001)
check("noon sun high", dc["sun_dir"][1] > 0.5)
check("noon sun intense", dc["sun_intensity"] > 0.8)
check("noon sky blue", dc["sky_top"][2] > dc["sky_top"][0])
check("noon ambient bright", dc["ambient_intensity"] > 0.2)

# --- Midnight properties ---
set_time_of_day(dc, 0.0)
update_day_cycle(dc, 0.001)
check("midnight sun below", dc["sun_dir"][1] < 0.0)
check("midnight sun dim", dc["sun_intensity"] < 0.3)
check("midnight sky dark", dc["sky_top"][0] < 0.1 and dc["sky_top"][1] < 0.1)
check("midnight ambient dim", dc["ambient_intensity"] < 0.2)

# --- Dawn properties ---
set_time_of_day(dc, 0.25)
update_day_cycle(dc, 0.001)
check("dawn sun near horizon", math.abs(dc["sun_dir"][1]) < 0.5)
check("dawn warm horizon", dc["sky_horizon"][0] > dc["sky_horizon"][2])

# --- Sunset properties ---
set_time_of_day(dc, 0.75)
update_day_cycle(dc, 0.001)
check("sunset sun near horizon", math.abs(dc["sun_dir"][1]) < 0.5)

# --- Sun direction is normalized ---
set_time_of_day(dc, 0.3)
update_day_cycle(dc, 0.001)
check("sun dir unit at 0.3", approx(v3_length(dc["sun_dir"]), 1.0))

set_time_of_day(dc, 0.6)
update_day_cycle(dc, 0.001)
check("sun dir unit at 0.6", approx(v3_length(dc["sun_dir"]), 1.0))

# --- Full cycle ---
set_time_of_day(dc, 0.0)
dc["speed"] = 1.0
let i = 0
let max_intensity = 0.0
let min_intensity = 999.0
while i < 120:
    update_day_cycle(dc, 1.0)
    if dc["sun_intensity"] > max_intensity:
        max_intensity = dc["sun_intensity"]
    if dc["sun_intensity"] < min_intensity:
        min_intensity = dc["sun_intensity"]
    i = i + 1
check("full cycle max intensity > 0.5", max_intensity > 0.5)
check("full cycle min intensity < 0.3", min_intensity < 0.3)
check("full cycle wraps back", get_time_of_day(dc) < 0.1 or get_time_of_day(dc) > 0.9)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Day/night cycle sanity checks failed!"
else:
    print "All day/night cycle sanity checks passed!"
