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
