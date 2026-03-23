gc_disable()
# -----------------------------------------
# navigation.sage - AI Navigation for Sage Engine
# Grid-based pathfinding (A*), steering behaviors
# -----------------------------------------

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot

# ============================================================================
# Navigation Grid
# ============================================================================
proc create_nav_grid(width, height, cell_size):
    let grid = {}
    grid["width"] = width
    grid["height"] = height
    grid["cell_size"] = cell_size
    grid["origin_x"] = 0.0 - (width * cell_size) / 2.0
    grid["origin_z"] = 0.0 - (height * cell_size) / 2.0
    # Walkability: 1 = walkable, 0 = blocked
    let cells = []
    let i = 0
    while i < width * height:
        push(cells, 1)
        i = i + 1
    grid["cells"] = cells
    return grid

proc set_blocked(grid, gx, gz):
    if gx < 0 or gx >= grid["width"]:
        return nil
    if gz < 0 or gz >= grid["height"]:
        return nil
    grid["cells"][gz * grid["width"] + gx] = 0

proc set_walkable(grid, gx, gz):
    if gx < 0 or gx >= grid["width"]:
        return nil
    if gz < 0 or gz >= grid["height"]:
        return nil
    grid["cells"][gz * grid["width"] + gx] = 1

proc is_walkable(grid, gx, gz):
    if gx < 0 or gx >= grid["width"]:
        return false
    if gz < 0 or gz >= grid["height"]:
        return false
    return grid["cells"][gz * grid["width"] + gx] == 1

# World position to grid coords
proc world_to_grid(grid, wx, wz):
    let gx = math.floor((wx - grid["origin_x"]) / grid["cell_size"])
    let gz = math.floor((wz - grid["origin_z"]) / grid["cell_size"])
    return [gx, gz]

# Grid coords to world center
proc grid_to_world(grid, gx, gz):
    let wx = grid["origin_x"] + (gx + 0.5) * grid["cell_size"]
    let wz = grid["origin_z"] + (gz + 0.5) * grid["cell_size"]
    return vec3(wx, 0.0, wz)

# ============================================================================
# A* Pathfinding
# ============================================================================
proc _heuristic(ax, az, bx, bz):
    let dx = ax - bx
    let dz = az - bz
    if dx < 0:
        dx = 0 - dx
    if dz < 0:
        dz = 0 - dz
    return dx + dz

proc _key(x, z):
    return str(x) + "," + str(z)

proc find_path(grid, start_x, start_z, goal_x, goal_z):
    if is_walkable(grid, goal_x, goal_z) == false:
        return []
    if is_walkable(grid, start_x, start_z) == false:
        return []
    if start_x == goal_x and start_z == goal_z:
        return [grid_to_world(grid, start_x, start_z)]

    let open_list = []
    let g_scores = {}
    let f_scores = {}
    let came_from = {}
    let closed = {}

    let sk = _key(start_x, start_z)
    g_scores[sk] = 0
    f_scores[sk] = _heuristic(start_x, start_z, goal_x, goal_z)
    push(open_list, [start_x, start_z])

    let max_iters = grid["width"] * grid["height"]
    let iters = 0

    while len(open_list) > 0 and iters < max_iters:
        iters = iters + 1
        # Find node with lowest f score
        let best_idx = 0
        let best_f = 999999.0
        let oi = 0
        while oi < len(open_list):
            let nk = _key(open_list[oi][0], open_list[oi][1])
            if dict_has(f_scores, nk):
                if f_scores[nk] < best_f:
                    best_f = f_scores[nk]
                    best_idx = oi
            oi = oi + 1

        let current = open_list[best_idx]
        let cx = current[0]
        let cz = current[1]
        let ck = _key(cx, cz)

        # Goal reached?
        if cx == goal_x and cz == goal_z:
            # Reconstruct path
            let path = []
            let pk = ck
            while dict_has(came_from, pk):
                let parts = split(pk, ",")
                let px = tonumber(parts[0])
                let pz = tonumber(parts[1])
                push(path, grid_to_world(grid, px, pz))
                pk = came_from[pk]
            # Reverse path
            let rev = []
            let ri = len(path) - 1
            while ri >= 0:
                push(rev, path[ri])
                ri = ri - 1
            push(rev, grid_to_world(grid, goal_x, goal_z))
            return rev

        # Remove from open, add to closed
        let new_open = []
        let ni = 0
        while ni < len(open_list):
            if ni != best_idx:
                push(new_open, open_list[ni])
            ni = ni + 1
        open_list = new_open
        closed[ck] = true

        # Check 4 neighbors (no diagonals for simplicity)
        let dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]]
        let di = 0
        while di < 4:
            let nx = cx + dirs[di][0]
            let nz = cz + dirs[di][1]
            let nk = _key(nx, nz)
            if is_walkable(grid, nx, nz) and dict_has(closed, nk) == false:
                let tentative_g = g_scores[ck] + 1
                let better = false
                if dict_has(g_scores, nk) == false:
                    better = true
                else:
                    if tentative_g < g_scores[nk]:
                        better = true
                if better:
                    came_from[nk] = ck
                    g_scores[nk] = tentative_g
                    f_scores[nk] = tentative_g + _heuristic(nx, nz, goal_x, goal_z)
                    # Add to open if not already there
                    let in_open = false
                    let check_i = 0
                    while check_i < len(open_list):
                        let ok = _key(open_list[check_i][0], open_list[check_i][1])
                        if ok == nk:
                            in_open = true
                            check_i = len(open_list)
                        check_i = check_i + 1
                    if in_open == false:
                        push(open_list, [nx, nz])
            di = di + 1
    return []

# ============================================================================
# Steering Behaviors
# ============================================================================
proc steer_seek(position, target, max_speed):
    let desired = v3_sub(target, position)
    let dist = v3_length(desired)
    if dist < 0.001:
        return vec3(0.0, 0.0, 0.0)
    return v3_scale(v3_normalize(desired), max_speed)

proc steer_flee(position, threat, max_speed):
    let away = v3_sub(position, threat)
    let dist = v3_length(away)
    if dist < 0.001:
        return vec3(0.0, 0.0, 0.0)
    return v3_scale(v3_normalize(away), max_speed)

proc steer_arrive(position, target, max_speed, slow_radius):
    let to_target = v3_sub(target, position)
    let dist = v3_length(to_target)
    if dist < 0.01:
        return vec3(0.0, 0.0, 0.0)
    let speed = max_speed
    if dist < slow_radius:
        speed = max_speed * (dist / slow_radius)
    return v3_scale(v3_normalize(to_target), speed)

proc steer_wander(position, forward, wander_radius, wander_offset, angle):
    let circle_center = v3_add(position, v3_scale(forward, wander_offset))
    let wx = math.cos(angle) * wander_radius
    let wz = math.sin(angle) * wander_radius
    return vec3(circle_center[0] + wx, 0.0, circle_center[2] + wz)

proc steer_avoid(position, velocity, obstacles, avoid_radius):
    let ahead = v3_add(position, v3_scale(v3_normalize(velocity), avoid_radius))
    let closest_obs = nil
    let closest_dist = 999999.0
    let i = 0
    while i < len(obstacles):
        let obs = obstacles[i]
        let dist = v3_length(v3_sub(ahead, obs["position"]))
        if dist < obs["radius"] + avoid_radius * 0.5:
            if dist < closest_dist:
                closest_dist = dist
                closest_obs = obs
        i = i + 1
    if closest_obs == nil:
        return vec3(0.0, 0.0, 0.0)
    let away = v3_sub(ahead, closest_obs["position"])
    return v3_normalize(away)

# ============================================================================
# Path follower
# ============================================================================
proc create_path_follower(path, speed):
    let pf = {}
    pf["path"] = path
    pf["speed"] = speed
    pf["current_index"] = 0
    pf["arrival_threshold"] = 0.5
    pf["finished"] = false
    return pf

proc update_path_follower(pf, position):
    if pf["finished"]:
        return vec3(0.0, 0.0, 0.0)
    if pf["current_index"] >= len(pf["path"]):
        pf["finished"] = true
        return vec3(0.0, 0.0, 0.0)
    let target = pf["path"][pf["current_index"]]
    let to_target = v3_sub(target, position)
    let dist = v3_length(to_target)
    if dist < pf["arrival_threshold"]:
        pf["current_index"] = pf["current_index"] + 1
        if pf["current_index"] >= len(pf["path"]):
            pf["finished"] = true
            return vec3(0.0, 0.0, 0.0)
        target = pf["path"][pf["current_index"]]
        to_target = v3_sub(target, position)
    return steer_arrive(position, target, pf["speed"], 2.0)

# ============================================================================
# Nav Agent Component (for ECS)
# ============================================================================
proc NavAgentComponent(speed):
    let c = {}
    c["speed"] = speed
    c["path"] = []
    c["path_index"] = 0
    c["target"] = nil
    c["steering"] = vec3(0.0, 0.0, 0.0)
    c["arrival_threshold"] = 0.5
    c["state"] = "idle"
    return c
