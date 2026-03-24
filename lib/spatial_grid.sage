gc_disable()
# -----------------------------------------
# spatial_grid.sage - Spatial hash grid for Sage Engine
# Broadphase collision detection via uniform grid
# -----------------------------------------

import math
from math3d import vec3

# ============================================================================
# Spatial Grid
# ============================================================================
proc create_spatial_grid(cell_size):
    let sg = {}
    sg["cell_size"] = cell_size
    sg["inv_cell"] = 1.0 / cell_size
    sg["cells"] = {}
    sg["entity_cells"] = {}
    return sg

proc _cell_key(gx, gy, gz):
    return str(gx) + "," + str(gy) + "," + str(gz)

proc _world_to_cell(sg, x, y, z):
    let inv = sg["inv_cell"]
    return [math.floor(x * inv), math.floor(y * inv), math.floor(z * inv)]

# ============================================================================
# Insert entity into grid
# ============================================================================
proc insert_entity(sg, entity_id, position, half_extent):
    let inv = sg["inv_cell"]
    let min_x = math.floor((position[0] - half_extent[0]) * inv)
    let min_y = math.floor((position[1] - half_extent[1]) * inv)
    let min_z = math.floor((position[2] - half_extent[2]) * inv)
    let max_x = math.floor((position[0] + half_extent[0]) * inv)
    let max_y = math.floor((position[1] + half_extent[1]) * inv)
    let max_z = math.floor((position[2] + half_extent[2]) * inv)
    let eid_str = str(entity_id)
    let cell_keys = []
    let gx = min_x
    while gx <= max_x:
        let gy = min_y
        while gy <= max_y:
            let gz = min_z
            while gz <= max_z:
                let key = _cell_key(gx, gy, gz)
                if dict_has(sg["cells"], key) == false:
                    sg["cells"][key] = []
                push(sg["cells"][key], entity_id)
                push(cell_keys, key)
                gz = gz + 1
            gy = gy + 1
        gx = gx + 1
    sg["entity_cells"][eid_str] = cell_keys

# ============================================================================
# Remove entity from grid
# ============================================================================
proc remove_entity(sg, entity_id):
    let eid_str = str(entity_id)
    if dict_has(sg["entity_cells"], eid_str) == false:
        return nil
    let keys = sg["entity_cells"][eid_str]
    let i = 0
    while i < len(keys):
        let key = keys[i]
        if dict_has(sg["cells"], key):
            let cell = sg["cells"][key]
            let new_cell = []
            let j = 0
            while j < len(cell):
                if cell[j] != entity_id:
                    push(new_cell, cell[j])
                j = j + 1
            sg["cells"][key] = new_cell
        i = i + 1
    dict_delete(sg["entity_cells"], eid_str)

# ============================================================================
# Update entity position (remove + reinsert)
# ============================================================================
proc update_entity(sg, entity_id, position, half_extent):
    remove_entity(sg, entity_id)
    insert_entity(sg, entity_id, position, half_extent)

# ============================================================================
# Clear entire grid
# ============================================================================
proc clear_grid(sg):
    sg["cells"] = {}
    sg["entity_cells"] = {}

# ============================================================================
# Query: get potential collision pairs (unique)
# ============================================================================
proc get_collision_pairs(sg):
    let pairs = {}
    let cell_keys = dict_keys(sg["cells"])
    let ci = 0
    while ci < len(cell_keys):
        let cell = sg["cells"][cell_keys[ci]]
        if len(cell) > 1:
            let i = 0
            while i < len(cell):
                let j = i + 1
                while j < len(cell):
                    let a = cell[i]
                    let b = cell[j]
                    let lo = a
                    let hi = b
                    if a > b:
                        lo = b
                        hi = a
                    let pk = str(lo) + "_" + str(hi)
                    if dict_has(pairs, pk) == false:
                        pairs[pk] = [lo, hi]
                    j = j + 1
                i = i + 1
        ci = ci + 1
    # Flatten to array
    let result = []
    let pk_keys = dict_keys(pairs)
    let pi = 0
    while pi < len(pk_keys):
        push(result, pairs[pk_keys[pi]])
        pi = pi + 1
    return result

# ============================================================================
# Query: get all entities near a position
# ============================================================================
proc query_radius(sg, position, radius):
    let inv = sg["inv_cell"]
    let min_x = math.floor((position[0] - radius) * inv)
    let min_y = math.floor((position[1] - radius) * inv)
    let min_z = math.floor((position[2] - radius) * inv)
    let max_x = math.floor((position[0] + radius) * inv)
    let max_y = math.floor((position[1] + radius) * inv)
    let max_z = math.floor((position[2] + radius) * inv)
    let found = {}
    let gx = min_x
    while gx <= max_x:
        let gy = min_y
        while gy <= max_y:
            let gz = min_z
            while gz <= max_z:
                let key = _cell_key(gx, gy, gz)
                if dict_has(sg["cells"], key):
                    let cell = sg["cells"][key]
                    let i = 0
                    while i < len(cell):
                        found[str(cell[i])] = cell[i]
                        i = i + 1
                gz = gz + 1
            gy = gy + 1
        gx = gx + 1
    let result = []
    let fkeys = dict_keys(found)
    let fi = 0
    while fi < len(fkeys):
        push(result, found[fkeys[fi]])
        fi = fi + 1
    return result

# ============================================================================
# Query: get entities in a cell
# ============================================================================
proc query_cell(sg, gx, gy, gz):
    let key = _cell_key(gx, gy, gz)
    if dict_has(sg["cells"], key) == false:
        return []
    return sg["cells"][key]

proc grid_stats(sg):
    let s = {}
    s["cells"] = len(dict_keys(sg["cells"]))
    s["entities"] = len(dict_keys(sg["entity_cells"]))
    return s

# ============================================================================
# Octree integration (for large scenes)
# ============================================================================
proc create_octree(center, half_size, max_depth):
    let node = {}
    node["center"] = center
    node["half_size"] = half_size
    node["depth"] = 0
    node["max_depth"] = max_depth
    node["entities"] = []
    node["children"] = nil
    return node

proc octree_insert(node, entity_id, pos):
    if node["children"] == nil and len(node["entities"]) < 8:
        push(node["entities"], {"id": entity_id, "pos": pos})
        return true
    # Subdivide if needed
    if node["children"] == nil and node["depth"] < node["max_depth"]:
        _octree_subdivide(node)
    if node["children"] != nil:
        let idx = _octree_child_index(node, pos)
        return octree_insert(node["children"][idx], entity_id, pos)
    push(node["entities"], {"id": entity_id, "pos": pos})
    return true

proc _octree_child_index(node, pos):
    let cx = node["center"]
    let idx = 0
    if pos[0] >= cx[0]:
        idx = idx + 1
    if pos[1] >= cx[1]:
        idx = idx + 2
    if pos[2] >= cx[2]:
        idx = idx + 4
    return idx

proc _octree_subdivide(node):
    let hs = node["half_size"] * 0.5
    let cx = node["center"]
    node["children"] = []
    let i = 0
    while i < 8:
        let ox = cx[0] + hs * (((i) % 2) * 2.0 - 1.0)
        let oy = cx[1] + hs * (((math.floor(i / 2)) % 2) * 2.0 - 1.0)
        let oz = cx[2] + hs * (((math.floor(i / 4)) % 2) * 2.0 - 1.0)
        let child = create_octree([ox, oy, oz], hs, node["max_depth"])
        child["depth"] = node["depth"] + 1
        push(node["children"], child)
        i = i + 1
    # Re-insert existing entities
    let old = node["entities"]
    node["entities"] = []
    let j = 0
    while j < len(old):
        let cidx = _octree_child_index(node, old[j]["pos"])
        octree_insert(node["children"][cidx], old[j]["id"], old[j]["pos"])
        j = j + 1

proc octree_query_sphere(node, center, radius):
    let results = []
    _octree_query_sphere_impl(node, center, radius, results)
    return results

proc _octree_query_sphere_impl(node, center, radius, results):
    # Check if sphere intersects this node's AABB
    let nc = node["center"]
    let hs = node["half_size"]
    let dx = math.max(0.0, math.abs(center[0] - nc[0]) - hs)
    let dy = math.max(0.0, math.abs(center[1] - nc[1]) - hs)
    let dz = math.max(0.0, math.abs(center[2] - nc[2]) - hs)
    if dx*dx + dy*dy + dz*dz > radius*radius:
        return nil
    # Check entities in this node
    let i = 0
    while i < len(node["entities"]):
        let e = node["entities"][i]
        let ex = e["pos"][0] - center[0]
        let ey = e["pos"][1] - center[1]
        let ez = e["pos"][2] - center[2]
        if ex*ex + ey*ey + ez*ez <= radius*radius:
            push(results, e["id"])
        i = i + 1
    # Recurse into children
    if node["children"] != nil:
        let ci = 0
        while ci < 8:
            _octree_query_sphere_impl(node["children"][ci], center, radius, results)
            ci = ci + 1
