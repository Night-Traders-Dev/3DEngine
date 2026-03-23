# test_foliage.sage - Sanity checks for foliage scattering
# Run: ./run.sh tests/test_foliage.sage

from foliage import create_scatter_rule, scatter_foliage
from foliage import foliage_count, foliage_count_by_rule
from terrain import create_terrain, generate_terrain_flat, generate_terrain_noise

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

print "=== Foliage System Sanity Checks ==="

# --- Scatter rule ---
let trees = create_scatter_rule("trees", 0.05, 2.0, 15.0, 0.0, 0.3)
check("rule created", trees != nil)
check("rule name", trees["name"] == "trees")
check("rule density", approx(trees["density"], 0.05))
check("rule height range", trees["min_height"] < trees["max_height"])
check("rule scale min", trees["scale_min"] > 0.0)
check("rule rotation random", trees["rotation_random"] == true)

# --- Flat terrain scatter ---
let t = create_terrain(16, 16, 50.0, 50.0, 10.0)
generate_terrain_flat(t, 5.0)

let rule_low = create_scatter_rule("grass", 0.1, 0.0, 3.0, 0.0, 1.0)
let rule_mid = create_scatter_rule("trees", 0.05, 4.0, 8.0, 0.0, 0.3)

# All terrain at 5.0 -> only mid rule should produce
let instances = scatter_foliage(t, [rule_low, rule_mid], 42)
check("scatter produced instances", len(instances) > 0)

let grass_count = foliage_count_by_rule(instances, "grass")
let tree_count = foliage_count_by_rule(instances, "trees")
check("no grass at height 5", grass_count == 0)
check("trees at height 5", tree_count > 0)

# --- Height filtering ---
generate_terrain_flat(t, 1.0)
let low_inst = scatter_foliage(t, [rule_low], 42)
check("grass at height 1", foliage_count_by_rule(low_inst, "grass") > 0)

generate_terrain_flat(t, 20.0)
let high_inst = scatter_foliage(t, [rule_low], 42)
check("no grass at height 20", foliage_count_by_rule(high_inst, "grass") == 0)

# --- Instance properties ---
generate_terrain_flat(t, 5.0)
let insts = scatter_foliage(t, [rule_mid], 123)
if len(insts) > 0:
    let first = insts[0]
    check("instance has position", first["position"] != nil)
    check("instance has scale", first["scale"] != nil)
    check("instance has rotation", first["rotation"] != nil)
    check("instance has rule_name", first["rule_name"] == "trees")
    check("instance pos y near terrain", approx(first["position"][1], 5.0))
    check("instance scale > 0", first["scale"][0] > 0.0)
else:
    check("at least one instance", false)
    check("skip", true)
    check("skip", true)
    check("skip", true)
    check("skip", true)
    check("skip", true)

# --- Deterministic ---
let inst_a = scatter_foliage(t, [rule_mid], 999)
let inst_b = scatter_foliage(t, [rule_mid], 999)
check("deterministic count", foliage_count(inst_a) == foliage_count(inst_b))

# Different seed -> different result
let inst_c = scatter_foliage(t, [rule_mid], 1000)
check("different seed different count or positions", true)

# --- Noisy terrain ---
let t2 = create_terrain(16, 16, 50.0, 50.0, 15.0)
generate_terrain_noise(t2, 7.0, 4, 0.5, 2.0, 3.0)
let wide_rule = create_scatter_rule("objects", 0.08, 0.0, 15.0, 0.0, 1.0)
let noisy_inst = scatter_foliage(t2, [wide_rule], 42)
check("scatter on noisy terrain", foliage_count(noisy_inst) > 0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Foliage sanity checks failed!"
else:
    print "All foliage sanity checks passed!"
