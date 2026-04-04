# voxel_mobai.sage - Advanced mob AI with pathfinding and behavior
# Intelligent mob behavior, targeting, and tactical movement

import math
from math3d import vec3, v3_add, v3_sub, v3_normalize, v3_length, v3_scale

# =====================================================
# Behavior Tree Nodes
# =====================================================

proc create_behavior_state(mob_type):
    let state = {}
    state["current_behavior"] = "idle"
    state["behavior_time"] = 0.0
    state["path"] = []
    state["path_index"] = 0
    state["last_player_seen"] = -999.0
    state["player_last_pos"] = vec3(0.0, 0.0, 0.0)
    state["search_radius"] = 32.0
    state["attack_range"] = 2.0
    state["patrol_center"] = vec3(0.0, 0.0, 0.0)
    state["alert_level"] = 0.0  # 0-1
    state["flee_cooldown"] = 0.0
    state["special_ability_cooldown"] = 0.0
    return state

# =====================================================
# Mob AI Behaviors
# =====================================================

proc mob_idle_behavior(mob, behavior, dt):
    # Random wandering
    behavior["behavior_time"] = behavior["behavior_time"] - dt
    
    if behavior["behavior_time"] <= 0.0:
        # Pick random direction
        let angle = math.random() * 6.28
        mob["direction"] = vec3(math.cos(angle), 0.0, math.sin(angle))
        mob["velocity"] = v3_scale(mob["direction"], 1.5)
        behavior["behavior_time"] = 3.0 + math.random() * 7.0
    
    # Check for player
    return "idle"

proc mob_patrol_behavior(mob, behavior, player_pos, dt):
    # Patrol around spawn point with awareness
    let to_center = v3_sub(behavior["patrol_center"], mob["position"])
    let dist_to_center = v3_length(to_center)
    
    if dist_to_center > 20.0:
        # Return to patrol center
        mob["direction"] = v3_normalize(to_center)
    else:
        # Random patrol
        let angle = math.sin(behavior["behavior_time"]) * 0.5
        mob["direction"] = vec3(math.cos(angle), 0.0, math.sin(angle))
    
    mob["velocity"] = v3_scale(mob["direction"], 2.0)
    
    # Check for player
    let player_dist = v3_length(v3_sub(player_pos, mob["position"]))
    if player_dist < behavior["search_radius"]:
        if behavior["alert_level"] < 0.5:
            behavior["alert_level"] = behavior["alert_level"] + dt * 0.5
        return "investigate"
    
    behavior["alert_level"] = math.max(0.0, behavior["alert_level"] - dt * 0.2)
    return "patrol"

proc mob_investigate_behavior(mob, behavior, player_pos, dt):
    # Head toward last known player position
    let to_player = v3_sub(behavior["player_last_pos"], mob["position"])
    let dist = v3_length(to_player)
    
    if dist < 1.0:
        behavior["behavior_time"] = behavior["behavior_time"] - dt
        if behavior["behavior_time"] <= 0.0:
            behavior["alert_level"] = math.max(0.0, behavior["alert_level"] - dt * 0.3)
            if behavior["alert_level"] < 0.3:
                return "patrol"
    else:
        mob["direction"] = v3_normalize(to_player)
        mob["velocity"] = v3_scale(mob["direction"], 4.0)
    
    # Update player position if close
    let player_dist = v3_length(v3_sub(player_pos, mob["position"]))
    if player_dist < behavior["search_radius"]:
        behavior["player_last_pos"] = player_pos
        behavior["last_player_seen"] = 0.0
        return "chase"
    
    return "investigate"

proc mob_chase_behavior(mob, behavior, player_pos, dt):
    # Pursue player aggressively
    behavior["alert_level"] = 1.0
    
    let to_player = v3_sub(player_pos, mob["position"])
    let dist = v3_length(to_player)
    
    # Get mob speed
    let speed = dict_has(mob, "speed") and mob["speed"] or 4.5
    
    if dist > behavior["attack_range"]:
        mob["direction"] = v3_normalize(to_player)
        mob["velocity"] = v3_scale(mob["direction"], speed * 1.2)
    else:
        # In attack range
        if dist > 0.1:
            mob["direction"] = v3_normalize(to_player)
        mob["velocity"] = vec3(0.0, mob["velocity"][1], 0.0)
        
        # Attempt attack
        behavior["behavior_time"] = behavior["behavior_time"] - dt
        if behavior["behavior_time"] <= 0.0:
            mob["attacking"] = true
            behavior["behavior_time"] = 1.0
    
    behavior["player_last_pos"] = player_pos
    behavior["last_player_seen"] = 0.0
    
    if dist > behavior["search_radius"]:
        return "investigate"
    
    return "chase"

proc mob_flee_behavior(mob, behavior, player_pos, dt):
    # Run away from player
    let to_player = v3_sub(player_pos, mob["position"])
    mob["direction"] = v3_normalize(v3_scale(to_player, -1.0))
    
    let speed = dict_has(mob, "speed") and mob["speed"] or 4.5
    mob["velocity"] = v3_scale(mob["direction"], speed * 1.5)
    
    behavior["flee_cooldown"] = behavior["flee_cooldown"] - dt
    if behavior["flee_cooldown"] <= 0.0:
        return "patrol"
    
    return "flee"

proc mob_special_behavior(mob, behavior, player_pos, dt, mob_type):
    # Type-specific behaviors
    if mob_type == "creeper":
        return _creeper_behavior(mob, behavior, player_pos, dt)
    elif mob_type == "skeleton":
        return _skeleton_behavior(mob, behavior, player_pos, dt)
    elif mob_type == "spider":
        return _spider_behavior(mob, behavior, player_pos, dt)
    
    return "idle"

proc _creeper_behavior(mob, behavior, player_pos, dt):
    # Creepers charge toward player
    let to_player = v3_sub(player_pos, mob["position"])
    let dist = v3_length(to_player)
    
    if dist < 16.0:
        mob["direction"] = v3_normalize(to_player)
        mob["velocity"] = v3_scale(mob["direction"], 5.5)
        
        if dist < 2.5:
            mob["fuse_time"] = mob["fuse_time"] + dt
            if mob["fuse_time"] > 1.5:
                mob["is_exploding"] = true
                mob["health"] = 0.0
                return "explosion"
    
    return "idle"

proc _skeleton_behavior(mob, behavior, player_pos, dt):
    # Skeletons keep distance and shoot
    let to_player = v3_sub(player_pos, mob["position"])
    let dist = v3_length(to_player)
    
    if dist < behavior["search_radius"]:
        if dist > 8.0:
            # Move closer
            mob["direction"] = v3_normalize(to_player)
            mob["velocity"] = v3_scale(mob["direction"], 3.0)
        else:
            # Strafe while shooting
            let angle = math.sin(behavior["behavior_time"]) * 0.5
            mob["direction"] = vec3(math.cos(angle), 0.0, math.sin(angle))
            mob["velocity"] = v3_scale(mob["direction"], 2.0)
            
            behavior["special_ability_cooldown"] = behavior["special_ability_cooldown"] - dt
            if behavior["special_ability_cooldown"] <= 0.0:
                mob["shooting"] = true
                behavior["special_ability_cooldown"] = 1.5
    
    return "idle"

proc _spider_behavior(mob, behavior, player_pos, dt):
    # Spiders circle prey
    let to_player = v3_sub(player_pos, mob["position"])
    let dist = v3_length(to_player)
    
    if dist < 16.0:
        # Circle around player at mid-range
        let circumference = dist * 6.28
        let orbital_angle = behavior["behavior_time"] * (2.0 / circumference)
        let angle = math.atan2(to_player[2], to_player[0]) + orbital_angle
        
        mob["direction"] = vec3(math.cos(angle), 0.0, math.sin(angle))
        mob["velocity"] = v3_scale(mob["direction"], 6.0)
        
        if dist < 3.0:
            mob["attacking"] = true
    
    return "idle"

# =====================================================
# AI Update Loop
# =====================================================

proc update_mob_ai(mob, behavior, player_pos, dt):
    behavior["behavior_time"] = behavior["behavior_time"] + dt
    
    let player_dist = v3_length(v3_sub(player_pos, mob["position"]))
    
    # Decide behavior based on current state
    let new_behavior = behavior["current_behavior"]
    
    if player_dist < 2.0 and behavior["current_behavior"] != "fleeing":
        new_behavior = "chase"
    elif behavior["alert_level"] > 0.5 and behavior["current_behavior"] != "chasing":
        new_behavior = "investigate"
    
    # Execute behavior
    if new_behavior == "idle":
        new_behavior = mob_idle_behavior(mob, behavior, dt)
    elif new_behavior == "patrol":
        new_behavior = mob_patrol_behavior(mob, behavior, player_pos, dt)
    elif new_behavior == "investigate":
        new_behavior = mob_investigate_behavior(mob, behavior, player_pos, dt)
    elif new_behavior == "chase":
        new_behavior = mob_chase_behavior(mob, behavior, player_pos, dt)
    elif new_behavior == "flee":
        new_behavior = mob_flee_behavior(mob, behavior, player_pos, dt)
    
    behavior["current_behavior"] = new_behavior

# =====================================================
# Pathfinding
# =====================================================

proc simple_pathfind(start, goal, max_steps):
    # Simplified A* style pathfinding
    let path = [start]
    let current = start
    let step = 0
    
    while step < max_steps:
        if v3_length(v3_sub(current, goal)) < 1.0:
            return path
        
        let direction = v3_normalize(v3_sub(goal, current))
        current = v3_add(current, v3_scale(direction, 1.0))
        push(path, current)
        step = step + 1
    
    return path
