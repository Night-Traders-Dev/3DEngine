gc_disable()
# navmesh.sage — Polygon-based Navigation Mesh
# Replaces grid-based A* with proper 3D navigation on arbitrary terrain.
# Supports: polygon generation from geometry, path queries, agent navigation,
# off-mesh links (jumps/ladders), dynamic obstacle avoidance.
#
# Usage:
#   let nav = create_navmesh()
#   add_navmesh_polygon(nav, [v0, v1, v2])
#   build_navmesh_adjacency(nav)
#   let path = navmesh_find_path(nav, start_pos, end_pos)
#   let next = navmesh_agent_update(agent, path, dt)

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot

# ============================================================================
# NavMesh Data Structures
# ============================================================================

proc create_navmesh():
    return {
        "polygons": [],        # Array of polygon dicts
        "adjacency": {},       # polygon_idx → [neighbor_indices]
        "off_mesh_links": [],  # Jump/climb connections
        "agent_radius": 0.3,
        "agent_height": 1.8,
        "cell_size": 0.5,
        "max_slope": 45.0,     # Max walkable slope in degrees
        "built": false
    }

proc add_navmesh_polygon(nav, vertices):
    # vertices: array of vec3 (3+ points)
    let center = vec3(0.0, 0.0, 0.0)
    let i = 0
    while i < len(vertices):
        center = v3_add(center, vertices[i])
        i = i + 1
    center = v3_scale(center, 1.0 / len(vertices))

    let poly = {
        "vertices": vertices,
        "center": center,
        "normal": _compute_polygon_normal(vertices),
        "index": len(nav["polygons"]),
        "neighbors": [],
        "cost": 1.0       # Traversal cost multiplier
    }
    push(nav["polygons"], poly)
    return poly["index"]

proc _compute_polygon_normal(verts):
    if len(verts) < 3:
        return vec3(0.0, 1.0, 0.0)
    let v0 = verts[0]
    let v1 = verts[1]
    let v2 = verts[2]
    let e1 = v3_sub(v1, v0)
    let e2 = v3_sub(v2, v0)
    # Cross product
    let nx = e1[1] * e2[2] - e1[2] * e2[1]
    let ny = e1[2] * e2[0] - e1[0] * e2[2]
    let nz = e1[0] * e2[1] - e1[1] * e2[0]
    let len_n = math.sqrt(nx * nx + ny * ny + nz * nz)
    if len_n < 0.0001:
        return vec3(0.0, 1.0, 0.0)
    return vec3(nx / len_n, ny / len_n, nz / len_n)

# ============================================================================
# Generate navmesh from heightmap terrain
# ============================================================================

proc generate_navmesh_from_terrain(nav, terrain, resolution):
    let sx = terrain["size_x"]
    let sz = terrain["size_z"]
    let step = resolution
    let max_slope_rad = nav["max_slope"] * 0.01745329

    let gz = 0.0
    while gz < sz - step:
        let gx = 0.0
        while gx < sx - step:
            # Sample 4 corners of the cell
            let h00 = _terrain_height(terrain, gx, gz)
            let h10 = _terrain_height(terrain, gx + step, gz)
            let h01 = _terrain_height(terrain, gx, gz + step)
            let h11 = _terrain_height(terrain, gx + step, gz + step)

            # Check slope — if too steep, skip
            let max_diff = h10 - h00
            if h01 - h00 > max_diff:
                max_diff = h01 - h00
            if h11 - h00 > max_diff:
                max_diff = h11 - h00
            if max_diff < 0:
                max_diff = 0 - max_diff
            let slope = max_diff / step
            if slope < math.sin(max_slope_rad) / math.cos(max_slope_rad):
                # Triangle 1
                add_navmesh_polygon(nav, [
                    vec3(gx, h00, gz),
                    vec3(gx + step, h10, gz),
                    vec3(gx, h01, gz + step)
                ])
                # Triangle 2
                add_navmesh_polygon(nav, [
                    vec3(gx + step, h10, gz),
                    vec3(gx + step, h11, gz + step),
                    vec3(gx, h01, gz + step)
                ])
            gx = gx + step
        gz = gz + step

    build_navmesh_adjacency(nav)
    return len(nav["polygons"])

proc _terrain_height(terrain, x, z):
    if dict_has(terrain, "height_fn") and terrain["height_fn"] != nil:
        return terrain["height_fn"](x, z)
    return 0.0

# ============================================================================
# Adjacency — find which polygons share edges
# ============================================================================

proc build_navmesh_adjacency(nav):
    let n = len(nav["polygons"])
    nav["adjacency"] = {}
    let i = 0
    while i < n:
        nav["adjacency"][str(i)] = []
        i = i + 1

    # O(n²) brute force — fine for moderate mesh sizes
    i = 0
    while i < n:
        let j = i + 1
        while j < n:
            if _polygons_share_edge(nav["polygons"][i], nav["polygons"][j]):
                push(nav["adjacency"][str(i)], j)
                push(nav["adjacency"][str(j)], i)
                push(nav["polygons"][i]["neighbors"], j)
                push(nav["polygons"][j]["neighbors"], i)
            j = j + 1
        i = i + 1
    nav["built"] = true

proc _polygons_share_edge(poly_a, poly_b):
    let shared = 0
    let va = poly_a["vertices"]
    let vb = poly_b["vertices"]
    let ai = 0
    while ai < len(va):
        let bi = 0
        while bi < len(vb):
            let dist = v3_length(v3_sub(va[ai], vb[bi]))
            if dist < 0.01:
                shared = shared + 1
                if shared >= 2:
                    return true
            bi = bi + 1
        ai = ai + 1
    return false

# ============================================================================
# Off-Mesh Links — jumps, ladders, teleporters
# ============================================================================

proc add_off_mesh_link(nav, start_pos, end_pos, bidirectional, cost):
    push(nav["off_mesh_links"], {
        "start": start_pos,
        "end": end_pos,
        "bidirectional": bidirectional,
        "cost": cost,
        "start_poly": _find_closest_polygon(nav, start_pos),
        "end_poly": _find_closest_polygon(nav, end_pos)
    })

proc _find_closest_polygon(nav, pos):
    let closest = -1
    let closest_dist = 999999.0
    let i = 0
    while i < len(nav["polygons"]):
        let dist = v3_length(v3_sub(nav["polygons"][i]["center"], pos))
        if dist < closest_dist:
            closest_dist = dist
            closest = i
        i = i + 1
    return closest

# ============================================================================
# Pathfinding — A* on navmesh polygons
# ============================================================================

proc navmesh_find_path(nav, start_pos, end_pos):
    if not nav["built"] or len(nav["polygons"]) == 0:
        return []

    let start_poly = _find_closest_polygon(nav, start_pos)
    let end_poly = _find_closest_polygon(nav, end_pos)
    if start_poly < 0 or end_poly < 0:
        return []
    if start_poly == end_poly:
        return [start_pos, end_pos]

    # A* search
    let open_set = [start_poly]
    let came_from = {}
    let g_score = {}
    let f_score = {}
    g_score[str(start_poly)] = 0.0
    f_score[str(start_poly)] = v3_length(v3_sub(nav["polygons"][end_poly]["center"], nav["polygons"][start_poly]["center"]))

    let max_iters = 5000
    let iters = 0
    while len(open_set) > 0 and iters < max_iters:
        iters = iters + 1
        # Find node with lowest f_score in open set
        let current = open_set[0]
        let current_f = 999999.0
        if dict_has(f_score, str(current)):
            current_f = f_score[str(current)]
        let oi = 1
        while oi < len(open_set):
            let node = open_set[oi]
            let nf = 999999.0
            if dict_has(f_score, str(node)):
                nf = f_score[str(node)]
            if nf < current_f:
                current = node
                current_f = nf
            oi = oi + 1

        if current == end_poly:
            # Reconstruct path
            return _reconstruct_navpath(nav, came_from, start_poly, end_poly, start_pos, end_pos)

        # Remove from open set
        let new_open = []
        oi = 0
        while oi < len(open_set):
            if open_set[oi] != current:
                push(new_open, open_set[oi])
            oi = oi + 1
        open_set = new_open

        # Check neighbors
        let neighbors = nav["polygons"][current]["neighbors"]
        let ni = 0
        while ni < len(neighbors):
            let neighbor = neighbors[ni]
            let edge_cost = v3_length(v3_sub(
                nav["polygons"][neighbor]["center"],
                nav["polygons"][current]["center"]
            )) * nav["polygons"][neighbor]["cost"]

            let tentative_g = 0.0
            if dict_has(g_score, str(current)):
                tentative_g = g_score[str(current)]
            tentative_g = tentative_g + edge_cost

            let neighbor_g = 999999.0
            if dict_has(g_score, str(neighbor)):
                neighbor_g = g_score[str(neighbor)]

            if tentative_g < neighbor_g:
                came_from[str(neighbor)] = current
                g_score[str(neighbor)] = tentative_g
                f_score[str(neighbor)] = tentative_g + v3_length(v3_sub(
                    nav["polygons"][end_poly]["center"],
                    nav["polygons"][neighbor]["center"]
                ))
                # Add to open set if not already there
                let in_open = false
                oi = 0
                while oi < len(open_set):
                    if open_set[oi] == neighbor:
                        in_open = true
                    oi = oi + 1
                if not in_open:
                    push(open_set, neighbor)
            ni = ni + 1

    return []  # No path found

proc _reconstruct_navpath(nav, came_from, start_poly, end_poly, start_pos, end_pos):
    let poly_path = [end_poly]
    let current = end_poly
    while dict_has(came_from, str(current)):
        current = came_from[str(current)]
        push(poly_path, current)

    # Reverse and convert to world positions (polygon centers)
    let path = [start_pos]
    let i = len(poly_path) - 2  # Skip start (we have start_pos)
    while i >= 1:  # Skip end (we have end_pos)
        push(path, nav["polygons"][poly_path[i]]["center"])
        i = i - 1
    push(path, end_pos)
    return path

# ============================================================================
# Nav Agent — follows a path with smooth steering
# ============================================================================

proc create_nav_agent(position, speed, radius):
    return {
        "position": position,
        "velocity": vec3(0.0, 0.0, 0.0),
        "speed": speed,
        "radius": radius,
        "path": [],
        "path_index": 0,
        "arrival_threshold": 0.5,
        "has_path": false
    }

proc nav_agent_set_path(agent, path):
    agent["path"] = path
    agent["path_index"] = 0
    agent["has_path"] = len(path) > 0

proc nav_agent_update(agent, dt):
    if not agent["has_path"] or agent["path_index"] >= len(agent["path"]):
        agent["has_path"] = false
        agent["velocity"] = vec3(0.0, 0.0, 0.0)
        return agent["position"]

    let target = agent["path"][agent["path_index"]]
    let to_target = v3_sub(target, agent["position"])
    let dist = v3_length(to_target)

    if dist < agent["arrival_threshold"]:
        agent["path_index"] = agent["path_index"] + 1
        if agent["path_index"] >= len(agent["path"]):
            agent["has_path"] = false
            agent["velocity"] = vec3(0.0, 0.0, 0.0)
            return agent["position"]
        return agent["position"]

    let dir = v3_normalize(to_target)
    agent["velocity"] = v3_scale(dir, agent["speed"])
    agent["position"] = v3_add(agent["position"], v3_scale(agent["velocity"], dt))
    return agent["position"]

proc nav_agent_has_arrived(agent):
    return not agent["has_path"]
