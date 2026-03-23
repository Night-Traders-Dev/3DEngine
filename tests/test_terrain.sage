# test_terrain.sage - Sanity checks for terrain system
# Run: ./run.sh tests/test_terrain.sage

from terrain import create_terrain, set_height, get_height_grid, sample_height
from terrain import terrain_normal, generate_terrain_noise, generate_terrain_flat
from terrain import build_terrain_mesh, value_noise, fbm_noise
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
    return math.abs(a - b) < 0.1

print "=== Terrain System Sanity Checks ==="

# --- Noise ---
let n1 = value_noise(0.0, 0.0)
check("noise in 0..1", n1 >= 0.0 and n1 <= 1.0)
let n2 = value_noise(1.5, 2.5)
check("noise at different pos", n2 >= 0.0 and n2 <= 1.0)
let n3 = value_noise(0.0, 0.0)
check("noise deterministic", approx(n1, n3))

let fbm = fbm_noise(1.0, 2.0, 4, 0.5, 2.0)
check("fbm in 0..1", fbm >= 0.0 and fbm <= 1.0)

# --- Terrain creation ---
let t = create_terrain(8, 8, 100.0, 100.0, 20.0)
check("terrain created", t != nil)
check("terrain res_x", t["res_x"] == 8)
check("terrain size_x", approx(t["size_x"], 100.0))
check("terrain max_height", approx(t["max_height"], 20.0))
check("heights array size", len(t["heights"]) == 81)

# --- Set/get heights ---
set_height(t, 4, 4, 10.0)
check("set/get height", approx(get_height_grid(t, 4, 4), 10.0))
set_height(t, 0, 0, 5.0)
check("corner height", approx(get_height_grid(t, 0, 0), 5.0))

# Out of bounds clamped
check("oob clamps", get_height_grid(t, -1, -1) == get_height_grid(t, 0, 0))

# --- Flat generation ---
generate_terrain_flat(t, 3.0)
check("flat terrain center", approx(get_height_grid(t, 4, 4), 3.0))
check("flat terrain corner", approx(get_height_grid(t, 0, 0), 3.0))

# --- Noise generation ---
let t2 = create_terrain(16, 16, 100.0, 100.0, 15.0)
generate_terrain_noise(t2, 42.0, 4, 0.5, 2.0, 3.0)
let min_h = 9999.0
let max_h = -9999.0
let gi = 0
while gi < len(t2["heights"]):
    let h = t2["heights"][gi]
    if h < min_h:
        min_h = h
    if h > max_h:
        max_h = h
    gi = gi + 1
check("noise terrain has variation", max_h - min_h > 1.0)
check("noise terrain within max_height", max_h <= 15.0)
check("noise terrain positive", min_h >= 0.0)

# --- Sample height (bilinear) ---
generate_terrain_flat(t, 7.0)
let sh = sample_height(t, 0.0, 0.0)
check("sample flat terrain = 7", approx(sh, 7.0))

set_height(t, 4, 4, 10.0)
set_height(t, 5, 4, 10.0)
set_height(t, 4, 5, 10.0)
set_height(t, 5, 5, 10.0)
let sh2 = sample_height(t, 0.0, 0.0)
check("sample interpolates", sh2 >= 6.0)

# --- Normal computation ---
generate_terrain_flat(t, 5.0)
let n_flat = terrain_normal(t, 4, 4)
check("flat normal points up", n_flat[1] > 0.99)
check("flat normal length ~1", approx(v3_length(n_flat), 1.0))

# Slope test: make one side higher
set_height(t, 3, 4, 5.0)
set_height(t, 5, 4, 10.0)
let n_slope = terrain_normal(t, 4, 4)
check("slope normal tilted", n_slope[0] < -0.01)
check("slope normal still unit", approx(v3_length(n_slope), 1.0))

# --- Build mesh ---
let t3 = create_terrain(4, 4, 10.0, 10.0, 5.0)
generate_terrain_flat(t3, 2.0)
let mesh = build_terrain_mesh(t3)
check("mesh has vertices", len(mesh["vertices"]) > 0)
check("mesh has indices", len(mesh["indices"]) > 0)
check("mesh vertex count", mesh["vertex_count"] == 25)
check("mesh index count", mesh["index_count"] == 96)
check("mesh has normals", mesh["has_normals"] == true)
check("mesh has uvs", mesh["has_uvs"] == true)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Terrain sanity checks failed!"
else:
    print "All terrain sanity checks passed!"
