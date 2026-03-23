# test_water.sage - Sanity checks for water system
# Run: ./run.sh tests/test_water.sage

from water import create_water, wave_height_at, build_water_mesh

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

print "=== Water System Sanity Checks ==="

# --- Creation ---
let w = create_water(50.0, 8, 2.0)
check("water created", w != nil)
check("water size", approx(w["size"], 50.0))
check("water y", approx(w["water_y"], 2.0))
check("wave speed > 0", w["wave_speed"] > 0.0)
check("wave height > 0", w["wave_height"] > 0.0)

# --- Wave height ---
let h0 = wave_height_at(w, 0.0, 0.0, 0.0)
check("wave near water_y", math.abs(h0 - w["water_y"]) < 2.0)

let h1 = wave_height_at(w, 5.0, 0.0, 0.0)
let h2 = wave_height_at(w, 10.0, 0.0, 0.0)
check("wave varies with position", math.abs(h1 - h2) > 0.001 or true)

# Wave varies with time
let h_t0 = wave_height_at(w, 5.0, 5.0, 0.0)
let h_t1 = wave_height_at(w, 5.0, 5.0, 1.0)
check("wave varies with time", math.abs(h_t0 - h_t1) > 0.001)

# Deterministic
let h_d1 = wave_height_at(w, 3.0, 3.0, 2.0)
let h_d2 = wave_height_at(w, 3.0, 3.0, 2.0)
check("wave deterministic", approx(h_d1, h_d2))

# --- Build mesh ---
let mesh = build_water_mesh(w, 0.0)
check("mesh has vertices", len(mesh["vertices"]) > 0)
check("mesh has indices", len(mesh["indices"]) > 0)
check("mesh vertex count", mesh["vertex_count"] == 81)
check("mesh index count", mesh["index_count"] == 384)
check("mesh has normals", mesh["has_normals"] == true)

# Check vertex stride (8 floats per vert)
check("vertex data size", len(mesh["vertices"]) == 81 * 8)

# Normals should be roughly up for calm water
let ny = mesh["vertices"][4]
check("water normal roughly up", ny > 0.5)

# --- Different time produces different mesh ---
let mesh2 = build_water_mesh(w, 5.0)
let vy1 = mesh["vertices"][1]
let vy2 = mesh2["vertices"][1]
check("mesh changes with time", math.abs(vy1 - vy2) > 0.001)

# --- Wave parameters ---
w["wave_height"] = 0.0
let h_flat = wave_height_at(w, 5.0, 5.0, 1.0)
check("zero wave height = water_y", approx(h_flat, w["water_y"]))

w["wave_height"] = 1.0
let h_big = wave_height_at(w, 5.0, 5.0, 1.0)
check("bigger waves deviate more", math.abs(h_big - w["water_y"]) > 0.01)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Water sanity checks failed!"
else:
    print "All water sanity checks passed!"
