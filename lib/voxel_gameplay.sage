# voxel_gameplay.sage - Voxel world gameplay systems
# Tools, mobs, pickups, crafting for Minecraft-style gameplay

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length

# =====================================================
# Tools System
# =====================================================

proc create_tool(name, block_type, durability, harvest_speed, harvest_level):
    let tool = {}
    tool["name"] = name
    tool["block_type"] = block_type  # What it best harvests
    tool["max_durability"] = durability
    tool["current_durability"] = durability
    tool["harvest_speed"] = harvest_speed  # Blocks per second
    tool["harvest_level"] = harvest_level  # What hardness it can break
    tool["enchantments"] = {}
    return tool

proc create_voxel_gameplay_state():
    let state = {}
    state["tools"] = []
    state["active_tool_index"] = -1
    state["pickups"] = []  # Items on ground
    state["mobs"] = []
    state["day_time"] = 0.0  # 0-1 cycle
    state["weather"] = "clear"  # clear, rain, thunderstorm
    state["player_hunger"] = 20.0
    state["max_hunger"] = 20.0
    state["player_saturation"] = 5.0
    return state

# =====================================================
# Tool Management
# =====================================================

proc voxel_add_tool(gstate, tool):
    push(gstate["tools"], tool)
    if gstate["active_tool_index"] < 0:
        gstate["active_tool_index"] = 0

proc voxel_select_tool(gstate, index):
    if index >= 0 and index < len(gstate["tools"]):
        gstate["active_tool_index"] = index
        return true
    return false

proc voxel_active_tool(gstate):
    if gstate["active_tool_index"] >= 0 and gstate["active_tool_index"] < len(gstate["tools"]):
        return gstate["tools"][gstate["active_tool_index"]]
    return nil

proc voxel_has_tools(gstate):
    return len(gstate["tools"]) > 0

proc voxel_durability_use(tool, amount):
    if tool == nil:
        return false
    tool["current_durability"] = tool["current_durability"] - amount
    if tool["current_durability"] <= 0.0:
        tool["current_durability"] = 0.0
        return false  # Tool broke
    return true

proc tool_can_harvest(tool, block_hardness):
    if tool == nil:
        return false
    return tool["harvest_level"] >= block_hardness

# =====================================================
# Pickup / Item System
# =====================================================

proc spawn_voxel_pickup(block_id, position, velocity):
    let pickup = {}
    pickup["block_id"] = block_id
    pickup["position"] = position
    pickup["velocity"] = velocity
    pickup["age"] = 0.0
    pickup["lifespan"] = 300.0  # 5 minutes despawn
    pickup["collected"] = false
    pickup["collection_delay"] = 0.5
    return pickup

proc pickup_draw_position(pickup, time_offset):
    let pos = pickup["position"]
    let bob = math.sin(time_offset * 2.0) * 0.1
    return vec3(pos[0], pos[1] + bob, pos[2])

proc update_voxel_pickups(gstate, dt):
    let i = len(gstate["pickups"]) - 1
    while i >= 0:
        let pickup = gstate["pickups"][i]
        pickup["age"] = pickup["age"] + dt
        pickup["velocity"] = vec3(pickup["velocity"][0] * 0.95, 
                                  pickup["velocity"][1] - 9.81 * dt, 
                                  pickup["velocity"][2] * 0.95)
        pickup["position"] = v3_add(pickup["position"], v3_scale(pickup["velocity"], dt))
        
        if pickup["age"] >= pickup["lifespan"]:
            pickup["collected"] = true
        
        if pickup["collected"]:
            let swapped = gstate["pickups"][i]
            gstate["pickups"][i] = gstate["pickups"][len(gstate["pickups"]) - 1]
            pop(gstate["pickups"])
        
        i = i - 1

proc voxel_pickup_count(gstate):
    return len(gstate["pickups"])

# =====================================================
# Mob System
# =====================================================

proc spawn_voxel_mob(mob_type, position):
    let mob = {}
    mob["type"] = mob_type  # "zombie", "skeleton", "creeper", etc
    mob["position"] = position
    mob["velocity"] = vec3(0.0, 0.0, 0.0)
    mob["direction"] = vec3(0.0, 0.0, 1.0)
    mob["health"] = 20.0
    mob["max_health"] = 20.0
    mob["age"] = 0.0
    mob["anger"] = 0.0
    mob["last_target_check"] = 0.0
    mob["target_player"] = false
    mob["animation_time"] = 0.0
    mob["dead"] = false
    
    # Mob-specific stats
    if mob_type == "zombie":
        mob["max_health"] = 20.0
        mob["damage"] = 3.0
        mob["speed"] = 4.5
    elif mob_type == "skeleton":
        mob["max_health"] = 20.0
        mob["damage"] = 1.5
        mob["speed"] = 5.0
    elif mob_type == "creeper":
        mob["max_health"] = 20.0
        mob["damage"] = 49.0
        mob["speed"] = 5.0
        mob["fuse_time"] = 0.0
        mob["is_exploding"] = false
    elif mob_type == "spider":
        mob["max_health"] = 16.0
        mob["damage"] = 2.0
        mob["speed"] = 6.0
    
    mob["health"] = mob["max_health"]
    return mob

proc ensure_voxel_mob_population(gstate, player_pos, world_size):
    let desired_population = 20
    let active_mobs = 0
    let i = 0
    while i < len(gstate["mobs"]):
        if not gstate["mobs"][i]["dead"]:
            active_mobs = active_mobs + 1
        i = i + 1
    
    while active_mobs < desired_population:
        let angle = math.random() * 2.0 * math.PI
        let distance = 15.0 + math.random() * 30.0
        let mob_x = player_pos[0] + math.cos(angle) * distance
        let mob_y = player_pos[1] - 5.0
        let mob_z = player_pos[2] + math.sin(angle) * distance
        
        let mob_types = ["zombie", "skeleton", "creeper", "spider"]
        let mob_type = mob_types[int(math.random() * len(mob_types))]
        
        let mob = spawn_voxel_mob(mob_type, vec3(mob_x, mob_y, mob_z))
        push(gstate["mobs"], mob)
        active_mobs = active_mobs + 1

proc update_voxel_mobs(gstate, player_pos, dt):
    let i = 0
    while i < len(gstate["mobs"]):
        let mob = gstate["mobs"][i]
        
        if not mob["dead"]:
            # Update animation
            mob["animation_time"] = mob["animation_time"] + dt
            
            # Target detection
            mob["last_target_check"] = mob["last_target_check"] - dt
            if mob["last_target_check"] <= 0.0:
                let dist_to_player = v3_length(v3_sub(player_pos, mob["position"]))
                if dist_to_player < 32.0:
                    mob["target_player"] = true
                    mob["anger"] = 1.0
                else:
                    mob["target_player"] = false
                    mob["anger"] = math.max(0.0, mob["anger"] - dt)
                mob["last_target_check"] = 0.5
            
            # Movement toward player if angry
            if mob["target_player"]:
                let direction = v3_normalize(v3_sub(player_pos, mob["position"]))
                let speed = dict_has(mob, "speed") and mob["speed"] or 4.5
                mob["velocity"] = v3_scale(direction, speed)
                mob["direction"] = direction
            else:
                mob["velocity"] = v3_scale(mob["velocity"], 0.9)
            
            # Gravity
            mob["velocity"] = vec3(mob["velocity"][0], mob["velocity"][1] - 9.81 * dt, mob["velocity"][2])
            
            # Update position
            mob["position"] = v3_add(mob["position"], v3_scale(mob["velocity"], dt))
            
            # Simple creeper explosion
            if mob["type"] == "creeper" and mob["target_player"]:
                let dist_to_player = v3_length(v3_sub(player_pos, mob["position"]))
                if dist_to_player < 3.0:
                    mob["fuse_time"] = mob["fuse_time"] + dt
                    if mob["fuse_time"] > 1.5:
                        mob["is_exploding"] = true
                        mob["health"] = 0.0
                        mob["dead"] = true

        i = i + 1

proc find_target_voxel_mob(gstate, position):
    let closest = nil
    let closest_dist = 999999.0
    
    let i = 0
    while i < len(gstate["mobs"]):
        let mob = gstate["mobs"][i]
        if not mob["dead"]:
            let dist = v3_length(v3_sub(mob["position"], position))
            if dist < closest_dist:
                closest_dist = dist
                closest = mob
        i = i + 1
    
    return closest

proc collect_dead_mobs(gstate):
    let collected = []
    let i = len(gstate["mobs"]) - 1
    while i >= 0:
        if gstate["mobs"][i]["dead"]:
            push(collected, gstate["mobs"][i])
            let swapped = gstate["mobs"][i]
            gstate["mobs"][i] = gstate["mobs"][len(gstate["mobs"]) - 1]
            pop(gstate["mobs"])
        i = i - 1
    
    return collected

proc mob_draw_position(mob):
    return mob["position"]

proc voxel_alive_mob_count(gstate):
    let count = 0
    let i = 0
    while i < len(gstate["mobs"]):
        if not gstate["mobs"][i]["dead"]:
            count = count + 1
        i = i + 1
    return count

# =====================================================
# Serialization
# =====================================================

proc voxel_gameplay_to_sage(gstate):
    let data = {}
    data["day_time"] = gstate["day_time"]
    data["weather"] = gstate["weather"]
    data["player_hunger"] = gstate["player_hunger"]
    data["player_saturation"] = gstate["player_saturation"]
    return data

proc voxel_gameplay_from_sage(data):
    let gstate = create_voxel_gameplay_state()
    if dict_has(data, "day_time"):
        gstate["day_time"] = data["day_time"]
    if dict_has(data, "weather"):
        gstate["weather"] = data["weather"]
    if dict_has(data, "player_hunger"):
        gstate["player_hunger"] = data["player_hunger"]
    if dict_has(data, "player_saturation"):
        gstate["player_saturation"] = data["player_saturation"]
    return gstate
