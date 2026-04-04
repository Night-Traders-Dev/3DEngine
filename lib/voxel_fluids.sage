# voxel_fluids.sage - Water and lava flowing physics
# Implements realistic fluid dynamics with spreading and settling

import math
from math3d import vec3, v3_add, v3_scale

# =====================================================
# Fluid Physics Constants
# =====================================================

proc create_fluid_system():
    let fs = {}
    fs["water_queues"] = {}
    fs["lava_queues"] = {}
    fs["spreading_blocks"] = {}
    fs["update_interval"] = 0.2  # Update fluids every 0.2 seconds
    fs["next_update"] = 0.0
    return fs

# =====================================================
# Water Flowing
# =====================================================

proc _can_fluid_flow(vw, gx, gy, gz, block_id):
    if not voxel_in_bounds(vw, gx, gy, gz):
        return false
    let target = get_voxel(vw, gx, gy, gz)
    if target == 0:  # Air - can flow
        return true
    if target == block_id:  # Same fluid level
        return true
    if target == 14 or target == 15:  # Other fluid
        return true
    return false

proc _spread_water(vw, gx, gy, gz, is_source):
    let spread_positions = []
    
    # Always try to flow down
    if gy > 0 and _can_fluid_flow(vw, gx, gy - 1, gz, 14):
        push(spread_positions, [gx, gy - 1, gz])
    
    # If not flowing down, spread horizontally
    if gy == 0 or get_voxel(vw, gx, gy - 1, gz) != 0:
        # Horizontal spreading (limited range)
        let max_range = is_source and 7 or 5
        let i = 0
        while i < max_range:
            let offset = i + 1
            # 4 directions
            if _can_fluid_flow(vw, gx + offset, gy, gz, 14):
                push(spread_positions, [gx + offset, gy, gz])
            if _can_fluid_flow(vw, gx - offset, gy, gz, 14):
                push(spread_positions, [gx - offset, gy, gz])
            if _can_fluid_flow(vw, gx, gy, gz + offset, 14):
                push(spread_positions, [gx, gy, gz + offset])
            if _can_fluid_flow(vw, gx, gy, gz - offset, 14):
                push(spread_positions, [gx, gy, gz - offset])
            i = i + 1
    
    return spread_positions

proc _spread_lava(vw, gx, gy, gz, is_source):
    let spread_positions = []
    
    # Always try to flow down
    if gy > 0 and _can_fluid_flow(vw, gx, gy - 1, gz, 15):
        push(spread_positions, [gx, gy - 1, gz])
    
    # If not flowing down, spread horizontally
    if gy == 0 or get_voxel(vw, gx, gy - 1, gz) != 0:
        # Lava spreads less far than water
        let max_range = is_source and 3 or 2
        let i = 0
        while i < max_range:
            let offset = i + 1
            if _can_fluid_flow(vw, gx + offset, gy, gz, 15):
                push(spread_positions, [gx + offset, gy, gz])
            if _can_fluid_flow(vw, gx - offset, gy, gz, 15):
                push(spread_positions, [gx - offset, gy, gz])
            if _can_fluid_flow(vw, gx, gy, gz + offset, 15):
                push(spread_positions, [gx, gy, gz + offset])
            if _can_fluid_flow(vw, gx, gy, gz - offset, 15):
                push(spread_positions, [gx, gy, gz - offset])
            i = i + 1
    
    return spread_positions

# =====================================================
# Fluid System Update
# =====================================================

proc update_fluid_system(vw, fs, dt):
    fs["next_update"] = fs["next_update"] - dt
    if fs["next_update"] > 0.0:
        return
    
    fs["next_update"] = fs["update_interval"]
    
    # Find all water sources and spread them
    let x = 0
    while x < vw["size_x"]:
        let y = 0
        while y < vw["size_y"]:
            let z = 0
            while z < vw["size_z"]:
                let block = get_voxel(vw, x, y, z)
                
                if block == 14:  # Water
                    let spread = _spread_water(vw, x, y, z, false)
                    let i = 0
                    while i < len(spread):
                        let pos = spread[i]
                        set_voxel(vw, pos[0], pos[1], pos[2], 14)
                        i = i + 1
                
                elif block == 15:  # Lava
                    let spread = _spread_lava(vw, x, y, z, false)
                    let i = 0
                    while i < len(spread):
                        let pos = spread[i]
                        set_voxel(vw, pos[0], pos[1], pos[2], 15)
                        i = i + 1
                
                z = z + 1
            y = y + 1
        x = x + 1

# =====================================================
# Fluid Interaction
# =====================================================

proc is_fluid_block(block_id):
    return block_id == 14 or block_id == 15  # Water or Lava

proc is_water(block_id):
    return block_id == 14

proc is_lava(block_id):
    return block_id == 15

proc can_walk_on_fluid(block_id):
    return is_water(block_id)  # Can walk on water with special items

proc apply_fluid_damage(entity_state, fluid_type, dt):
    if entity_state == nil:
        return
    if fluid_type == 15:  # Lava
        if dict_has(entity_state, "health"):
            entity_state["health"] = entity_state["health"] - 2.0 * dt
    # Water absorbs fall damage and applies slowness
    return entity_state
