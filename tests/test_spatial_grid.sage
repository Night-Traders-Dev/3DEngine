# test_spatial_grid.sage - Sanity checks for spatial grid broadphase
from spatial_grid import create_spatial_grid, insert_entity, remove_entity
from spatial_grid import update_entity, clear_grid, get_collision_pairs
from spatial_grid import query_radius, query_cell, grid_stats
from math3d import vec3

import math

let p = 0
let f = 0
proc check(n, c):
    if c:
        p = p + 1
    else:
        print "  FAIL: " + n
        f = f + 1

print "=== Spatial Grid Sanity Checks ==="

let sg = create_spatial_grid(2.0)
check("grid created", sg != nil)
check("cell size", math.abs(sg["cell_size"] - 2.0) < 0.01)
let s = grid_stats(sg)
check("empty grid 0 cells", s["cells"] == 0)
check("empty grid 0 entities", s["entities"] == 0)

# Insert entities
insert_entity(sg, 1, [0.0, 0.0, 0.0], [0.5, 0.5, 0.5])
insert_entity(sg, 2, [1.0, 0.0, 0.0], [0.5, 0.5, 0.5])
insert_entity(sg, 3, [10.0, 0.0, 0.0], [0.5, 0.5, 0.5])
let s2 = grid_stats(sg)
check("3 entities inserted", s2["entities"] == 3)
check("cells > 0", s2["cells"] > 0)

# Collision pairs (1 and 2 are close, 3 is far)
let pairs = get_collision_pairs(sg)
check("at least 1 pair", len(pairs) >= 1)
# Check that 1,2 are a pair
let found_12 = false
let pi = 0
while pi < len(pairs):
    let pair = pairs[pi]
    if (pair[0] == 1 and pair[1] == 2) or (pair[0] == 2 and pair[1] == 1):
        found_12 = true
    pi = pi + 1
check("entities 1,2 form a pair", found_12)

# Entity 3 should not pair with 1 or 2
let found_13 = false
pi = 0
while pi < len(pairs):
    let pair = pairs[pi]
    if (pair[0] == 1 and pair[1] == 3) or (pair[0] == 3 and pair[1] == 1):
        found_13 = true
    pi = pi + 1
check("entities 1,3 not paired", found_13 == false)

# Radius query
let near = query_radius(sg, [0.0, 0.0, 0.0], 3.0)
check("radius query finds nearby", len(near) >= 2)
let far = query_radius(sg, [50.0, 50.0, 50.0], 1.0)
check("radius query finds none far away", len(far) == 0)

# Remove entity
remove_entity(sg, 2)
let s3 = grid_stats(sg)
check("2 entities after remove", s3["entities"] == 2)
let pairs2 = get_collision_pairs(sg)
let found_after = false
pi = 0
while pi < len(pairs2):
    if pairs2[pi][0] == 2 or pairs2[pi][1] == 2:
        found_after = true
    pi = pi + 1
check("removed entity not in pairs", found_after == false)

# Update entity position
update_entity(sg, 3, [0.5, 0.0, 0.0], [0.5, 0.5, 0.5])
let pairs3 = get_collision_pairs(sg)
check("moved entity creates pair", len(pairs3) >= 1)

# Clear
clear_grid(sg)
let s4 = grid_stats(sg)
check("cleared 0 entities", s4["entities"] == 0)
check("cleared 0 cells", s4["cells"] == 0)

# Large entity spanning multiple cells
let sg2 = create_spatial_grid(1.0)
insert_entity(sg2, 10, [0.0, 0.0, 0.0], [3.0, 3.0, 3.0])
let s5 = grid_stats(sg2)
check("large entity in many cells", s5["cells"] > 1)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Spatial grid sanity checks failed!"
else:
    print "All spatial grid sanity checks passed!"
