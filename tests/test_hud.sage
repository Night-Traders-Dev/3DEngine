# test_hud.sage - Sanity checks for HUD components
# Run: ./run.sh tests/test_hud.sage

from hud import create_health_bar, update_health_bar
from hud import create_crosshair, create_score_display, update_score_display
from hud import create_info_panel, update_info_panel
from hud import create_minimap, update_minimap_dots
from hud import create_game_hud, update_game_hud
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
    return math.abs(a - b) < 0.05

print "=== HUD Sanity Checks ==="

# --- Health bar ---
let hb = create_health_bar(20.0, 20.0, 200.0, 20.0)
check("health bar created", hb != nil)
check("health bar has bg", hb["bg"] != nil)
check("health bar has fill", hb["fill"] != nil)

update_health_bar(hb, 1.0)
check("full health = green", hb["fill"]["fill_color"][1] > 0.5)

update_health_bar(hb, 0.5)
check("half health = yellow", hb["fill"]["fill_color"][0] > 0.5 and hb["fill"]["fill_color"][1] > 0.5)

update_health_bar(hb, 0.1)
check("low health = red", hb["fill"]["fill_color"][0] > 0.5 and hb["fill"]["fill_color"][1] < 0.3)

update_health_bar(hb, 0.0)
check("zero health value", approx(hb["fill"]["value"], 0.0))

# --- Crosshair ---
let ch = create_crosshair(20.0, 2.0, [1.0, 1.0, 1.0, 0.8])
check("crosshair created", ch != nil)
check("crosshair h_bar", ch["h_bar"] != nil)
check("crosshair v_bar", ch["v_bar"] != nil)
check("crosshair dot", ch["dot"] != nil)

# --- Score display ---
let sd = create_score_display()
check("score display created", sd != nil)
check("score display panel", sd["panel"] != nil)
update_score_display(sd, 1500, 3)
check("score updated", sd["points"] == 1500)
check("combo updated", sd["combo"] == 3)

# --- Info panel ---
let ip = create_info_panel()
check("info panel created", ip != nil)
update_info_panel(ip, 60.0, 42)
check("fps updated", approx(ip["fps"], 60.0))
check("entity count updated", ip["entity_count"] == 42)

# --- Minimap ---
let mm = create_minimap(120.0)
check("minimap created", mm != nil)
check("minimap size", approx(mm["size"], 120.0))
check("minimap panel", mm["panel"] != nil)

let entities = [vec3(5.0, 0.0, 5.0), vec3(-5.0, 0.0, -5.0), vec3(100.0, 0.0, 100.0)]
update_minimap_dots(mm, vec3(0.0, 0.0, 0.0), entities)
check("minimap has dots", len(mm["dots"]) > 0)
# Far entity should be filtered out, but player dot always present
check("minimap includes player dot", len(mm["dots"]) >= 1)

# --- Full game HUD ---
let hud = create_game_hud()
check("game hud created", hud != nil)
check("hud root", hud["root"] != nil)
check("hud has health bar", hud["health_bar"] != nil)
check("hud has crosshair", hud["crosshair"] != nil)
check("hud has score", hud["score"] != nil)
check("hud has info", hud["info"] != nil)
check("hud has minimap", hud["minimap"] != nil)
check("hud root has children", len(hud["root"]["children"]) > 0)

update_game_hud(hud, 0.8, 500, 2, 60.0, 30)
check("hud health updated", approx(hud["health_bar"]["fill"]["value"], 0.8))
check("hud score updated", hud["score"]["points"] == 500)
check("hud fps updated", approx(hud["info"]["fps"], 60.0))

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "HUD sanity checks failed!"
else:
    print "All HUD sanity checks passed!"
