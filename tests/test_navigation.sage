# test_navigation.sage - Sanity checks for navigation system
# Run: ./run.sh tests/test_navigation.sage

from navigation import create_nav_grid, set_blocked, set_walkable, is_walkable
from navigation import world_to_grid, grid_to_world, find_path
from navigation import steer_seek, steer_flee, steer_arrive, steer_wander
from navigation import create_path_follower, update_path_follower
from navigation import NavAgentComponent
from math3d import vec3, v3_length, v3_dot, v3_sub

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

print "=== Navigation System Sanity Checks ==="

# --- Grid creation ---
let grid = create_nav_grid(10, 10, 1.0)
check("grid created", grid != nil)
check("grid width", grid["width"] == 10)
check("grid height", grid["height"] == 10)
check("cell size", approx(grid["cell_size"], 1.0))
check("all cells walkable", is_walkable(grid, 0, 0))
check("all cells walkable 2", is_walkable(grid, 9, 9))

# --- Block/unblock ---
set_blocked(grid, 5, 5)
check("blocked cell not walkable", is_walkable(grid, 5, 5) == false)
set_walkable(grid, 5, 5)
check("unblocked cell walkable", is_walkable(grid, 5, 5) == true)

# Out of bounds
check("oob not walkable", is_walkable(grid, -1, 0) == false)
check("oob not walkable 2", is_walkable(grid, 10, 0) == false)

# --- World <-> Grid conversion ---
let gc = world_to_grid(grid, 0.0, 0.0)
check("world origin maps to center", gc[0] == 5 and gc[1] == 5)

let wc = grid_to_world(grid, 5, 5)
check("center cell maps near origin", approx(wc[0], 0.5) and approx(wc[2], 0.5))

# --- A* Pathfinding ---
# Clear path
let path = find_path(grid, 0, 0, 9, 9)
check("path found", len(path) > 0)
check("path reaches goal", len(path) >= 2)

# Same start and goal
let same = find_path(grid, 5, 5, 5, 5)
check("same start/goal gives 1 node", len(same) == 1)

# Blocked goal
set_blocked(grid, 9, 9)
let blocked_path = find_path(grid, 0, 0, 9, 9)
check("blocked goal gives empty path", len(blocked_path) == 0)
set_walkable(grid, 9, 9)

# Path around obstacle wall
let wi = 0
while wi < 8:
    set_blocked(grid, 5, wi)
    wi = wi + 1
let around_path = find_path(grid, 3, 3, 7, 3)
check("path around wall found", len(around_path) > 0)
check("path around wall longer", len(around_path) > 4)
# Restore
wi = 0
while wi < 8:
    set_walkable(grid, 5, wi)
    wi = wi + 1

# --- Steering: Seek ---
let seek = steer_seek(vec3(0.0, 0.0, 0.0), vec3(10.0, 0.0, 0.0), 5.0)
check("seek points toward target", seek[0] > 0.0)
check("seek speed capped", approx(v3_length(seek), 5.0))

# --- Steering: Flee ---
let flee = steer_flee(vec3(0.0, 0.0, 0.0), vec3(10.0, 0.0, 0.0), 5.0)
check("flee points away", flee[0] < 0.0)

# --- Steering: Arrive ---
let arrive_far = steer_arrive(vec3(0.0, 0.0, 0.0), vec3(10.0, 0.0, 0.0), 5.0, 3.0)
check("arrive far = full speed", approx(v3_length(arrive_far), 5.0))

let arrive_near = steer_arrive(vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), 5.0, 3.0)
check("arrive near = reduced speed", v3_length(arrive_near) < 5.0)

let arrive_at = steer_arrive(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), 5.0, 3.0)
check("arrive at target = zero", approx(v3_length(arrive_at), 0.0))

# --- Steering: Wander ---
let wander = steer_wander(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), 2.0, 3.0, 0.5)
check("wander returns position", wander != nil)

# --- Path follower ---
let test_path = [vec3(0.0, 0.0, 0.0), vec3(5.0, 0.0, 0.0), vec3(5.0, 0.0, 5.0)]
let pf = create_path_follower(test_path, 3.0)
check("follower created", pf != nil)
check("follower not finished", pf["finished"] == false)

let vel = update_path_follower(pf, vec3(0.0, 0.0, 0.0))
check("follower returns velocity", v3_length(vel) > 0.0)
check("follower moves toward first wp", vel[0] > 0.0 or vel[2] > 0.0)

# Simulate reaching first waypoint
pf["current_index"] = 2
let vel2 = update_path_follower(pf, vec3(5.0, 0.0, 5.0))
check("follower finishes at last wp", pf["finished"] == true)

# --- Nav Agent Component ---
let agent = NavAgentComponent(4.0)
check("agent created", agent != nil)
check("agent speed", approx(agent["speed"], 4.0))
check("agent idle", agent["state"] == "idle")

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Navigation sanity checks failed!"
else:
    print "All navigation sanity checks passed!"
