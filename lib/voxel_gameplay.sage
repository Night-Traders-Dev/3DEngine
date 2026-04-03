gc_disable()
# -----------------------------------------
# voxel_gameplay.sage - Shared gameplay helpers for the Forge voxel template
# Block pickups, simple hostile mobs, targeting, and save/load state.
# -----------------------------------------

import math
from math3d import vec3
from gameplay import HealthComponent, damage
from voxel_world import sample_voxel_ground_radius, voxel_collides_player, resolve_player_voxel_collision

proc _copy_vec3(v):
    return vec3(v[0], v[1], v[2])

proc _distance_sq(a, b):
    let dx = a[0] - b[0]
    let dy = a[1] - b[1]
    let dz = a[2] - b[2]
    return dx * dx + dy * dy + dz * dz

proc _distance(a, b):
    return math.sqrt(_distance_sq(a, b))

proc _distance_xz(a, b):
    let dx = a[0] - b[0]
    let dz = a[2] - b[2]
    return math.sqrt(dx * dx + dz * dz)

proc _normalize_xz(from_pos, to_pos):
    let dx = to_pos[0] - from_pos[0]
    let dz = to_pos[2] - from_pos[2]
    let dist = math.sqrt(dx * dx + dz * dz)
    if dist <= 0.0001:
        return [0.0, 0.0]
    return [dx / dist, dz / dist]

proc _create_pickup(id, block_id, count, position):
    let pickup = {}
    pickup["id"] = id
    pickup["block_id"] = block_id
    pickup["count"] = count
    pickup["position"] = _copy_vec3(position)
    pickup["age"] = 0.0
    pickup["bob_phase"] = id * 0.37
    pickup["pickup_radius"] = 1.2
    pickup["magnet_radius"] = 5.0
    pickup["max_age"] = 20.0
    return pickup

proc _slime_surface():
    let surface = {}
    surface["albedo"] = vec3(0.34, 0.88, 0.42)
    surface["alpha"] = 1.0
    return surface

proc _create_mob(id, position, mob_type):
    let mob = {}
    mob["id"] = id
    mob["type"] = mob_type
    mob["name"] = "Slime"
    mob["position"] = _copy_vec3(position)
    mob["radius"] = 0.42
    mob["height"] = 1.15
    mob["speed"] = 2.4
    mob["aggro_range"] = 18.0
    mob["attack_range"] = 1.3
    mob["attack_damage"] = 8.0
    mob["attack_cooldown"] = 1.0
    mob["last_attack_time"] = -99.0
    mob["despawn_range"] = 40.0
    mob["age"] = 0.0
    mob["surface"] = _slime_surface()
    mob["health"] = HealthComponent(20.0)
    mob["drop_block"] = 4
    mob["drop_count"] = 1
    mob["drop_spawned"] = false
    return mob

proc _copy_health_data(health):
    let out = HealthComponent(health["max"])
    out["current"] = health["current"]
    out["alive"] = health["alive"]
    out["invulnerable"] = health["invulnerable"]
    out["regen_rate"] = health["regen_rate"]
    out["regen_delay"] = health["regen_delay"]
    out["last_damage_time"] = health["last_damage_time"]
    return out

proc create_tool(name, tool_tier, durability):
    let tool = {}
    tool["name"] = name
    tool["tier"] = tool_tier
    tool["durability"] = durability
    tool["max_durability"] = durability
    return tool

proc create_voxel_gameplay_state():
    let state = {}
    state["pickups"] = []
    state["mobs"] = []
    state["tools"] = []
    state["active_tool"] = 0
    state["next_pickup_id"] = 1
    state["next_mob_id"] = 1
    state["spawn_cursor"] = 0
    return state

proc voxel_add_tool(state, tool):
    if state == nil or tool == nil:
        return false
    if dict_has(state, "tools") == false:
        state["tools"] = []
    push(state["tools"], tool)
    return true

proc voxel_select_tool(state, index):
    if state == nil or dict_has(state, "tools") == false:
        return nil
    if index < 0 or index >= len(state["tools"]):
        return nil
    state["active_tool"] = index
    return state["tools"][index]

proc voxel_active_tool(state):
    if state == nil or dict_has(state, "tools") == false:
        return nil
    if len(state["tools"]) == 0:
        return nil
    let index = state["active_tool"]
    if index < 0 or index >= len(state["tools"]):
        state["active_tool"] = 0
        index = 0
    return state["tools"][index]

proc voxel_durability_use(tool):
    if tool == nil or tool["durability"] < 0:
        return true
    tool["durability"] = tool["durability"] - 1
    if tool["durability"] <= 0:
        return false
    return true

proc voxel_has_tools(state):
    return state != nil and dict_has(state, "tools") and len(state["tools"]) > 0

proc voxel_pickup_count(state):
    return len(state["pickups"])

proc voxel_alive_mob_count(state):
    let count = 0
    let i = 0
    while i < len(state["mobs"]):
        if state["mobs"][i]["health"]["alive"]:
            count = count + 1
        i = i + 1
    return count

proc spawn_voxel_pickup(state, block_id, count, position):
    if state == nil or block_id <= 0 or count <= 0 or position == nil:
        return nil
    let pickup = _create_pickup(state["next_pickup_id"], block_id, count, position)
    state["next_pickup_id"] = state["next_pickup_id"] + 1
    push(state["pickups"], pickup)
    return pickup

proc update_voxel_pickups(state, inventory, player_pos, dt):
    let collected = []
    let remaining = []
    let i = 0
    while i < len(state["pickups"]):
        let pickup = state["pickups"][i]
        pickup["age"] = pickup["age"] + dt
        let keep_pickup = true
        if pickup["age"] > pickup["max_age"]:
            keep_pickup = false
        else:
            let dist_sq = _distance_sq(player_pos, pickup["position"])
            if dist_sq <= pickup["magnet_radius"] * pickup["magnet_radius"] and dist_sq > 0.0001:
                let dist = math.sqrt(dist_sq)
                let pull = dt * 6.0
                if pull > 0.35:
                    pull = 0.35
                let nx = (player_pos[0] - pickup["position"][0]) / dist
                let ny = (player_pos[1] + 0.6 - pickup["position"][1]) / dist
                let nz = (player_pos[2] - pickup["position"][2]) / dist
                pickup["position"] = vec3(
                    pickup["position"][0] + nx * pull * dist,
                    pickup["position"][1] + ny * pull * dist,
                    pickup["position"][2] + nz * pull * dist
                )
                dist_sq = _distance_sq(player_pos, pickup["position"])
            if dist_sq <= pickup["pickup_radius"] * pickup["pickup_radius"]:
                if inventory != nil:
                    from voxel_world import voxel_inventory_add
                    voxel_inventory_add(inventory, pickup["block_id"], pickup["count"])
                push(collected, {"block_id": pickup["block_id"], "count": pickup["count"]})
                keep_pickup = false
        if keep_pickup:
            push(remaining, pickup)
        i = i + 1
    state["pickups"] = remaining
    return collected

proc pickup_draw_position(pickup, total_time):
    let bob = 0.18 + math.sin((pickup["age"] + total_time + pickup["bob_phase"]) * 4.0) * 0.08
    return vec3(pickup["position"][0], pickup["position"][1] + bob, pickup["position"][2])

proc spawn_voxel_mob(state, position, mob_type):
    if state == nil or position == nil:
        return nil
    let mob = _create_mob(state["next_mob_id"], position, mob_type)
    state["next_mob_id"] = state["next_mob_id"] + 1
    push(state["mobs"], mob)
    return mob

proc _prune_far_mobs(state, player_pos):
    let kept = []
    let removed = 0
    let i = 0
    while i < len(state["mobs"]):
        let mob = state["mobs"][i]
        if mob["health"]["alive"] == false or _distance_xz(mob["position"], player_pos) <= mob["despawn_range"]:
            push(kept, mob)
        else:
            removed = removed + 1
        i = i + 1
    state["mobs"] = kept
    return removed

proc ensure_voxel_mob_population(state, voxel, player_pos, desired_count, world_seed):
    if state == nil or voxel == nil or player_pos == nil:
        return 0
    _prune_far_mobs(state, player_pos)
    let alive = voxel_alive_mob_count(state)
    let spawned = 0
    let attempts = 0
    while alive < desired_count and attempts < desired_count * 12:
        let cursor = state["spawn_cursor"]
        state["spawn_cursor"] = state["spawn_cursor"] + 1
        attempts = attempts + 1
        let angle = cursor * 2.39996323 + world_seed * 0.19
        let radius = 10.0 + cursor * 1.35
        let sx = player_pos[0] + math.cos(angle) * radius
        let sz = player_pos[2] + math.sin(angle) * radius
        let sy = sample_voxel_ground_radius(voxel, sx, sz, 0.42)
        let spawn_pos = vec3(sx, sy, sz)
        if _distance_xz(spawn_pos, player_pos) > 7.0 and voxel_collides_player(voxel, spawn_pos, 0.42, 1.15) == false:
            spawn_voxel_mob(state, spawn_pos, "slime")
            alive = alive + 1
            spawned = spawned + 1
    return spawned

proc update_voxel_mobs(state, voxel, player_pos, player_health, dt, total_time):
    let events = []
    let i = 0
    while i < len(state["mobs"]):
        let mob = state["mobs"][i]
        if mob["health"]["alive"]:
            mob["age"] = mob["age"] + dt
            let dist_xz = _distance_xz(mob["position"], player_pos)
            if dist_xz <= mob["aggro_range"]:
                let dir = _normalize_xz(mob["position"], player_pos)
                if dist_xz > mob["attack_range"] * 0.9:
                    let move_step = mob["speed"] * dt
                    let next_pos = vec3(
                        mob["position"][0] + dir[0] * move_step,
                        mob["position"][1],
                        mob["position"][2] + dir[1] * move_step
                    )
                    let next_ground = sample_voxel_ground_radius(voxel, next_pos[0], next_pos[2], mob["radius"])
                    if math.abs(next_ground - mob["position"][1]) <= 1.25:
                        next_pos[1] = next_ground
                        let resolved = resolve_player_voxel_collision(voxel, mob["position"], next_pos, mob["radius"], mob["height"])
                        let resolved_ground = sample_voxel_ground_radius(voxel, resolved[0], resolved[2], mob["radius"])
                        mob["position"] = vec3(resolved[0], resolved_ground, resolved[2])
                if player_health != nil and dist_xz <= mob["attack_range"] and total_time - mob["last_attack_time"] >= mob["attack_cooldown"]:
                    let dealt = damage(player_health, mob["attack_damage"], total_time)
                    if dealt > 0.0:
                        mob["last_attack_time"] = total_time
                        push(events, {"type": "player_hit", "mob_id": mob["id"], "damage": dealt, "mob_name": mob["name"]})
        i = i + 1
    return events

proc mob_draw_position(mob, total_time):
    let hop = math.sin(total_time * 3.5 + mob["id"] * 0.8) * 0.05
    return vec3(mob["position"][0], mob["position"][1] + 0.55 + hop, mob["position"][2])

proc find_target_voxel_mob(state, origin, direction, max_dist):
    let best = nil
    let i = 0
    while i < len(state["mobs"]):
        let mob = state["mobs"][i]
        if mob["health"]["alive"]:
            let center = vec3(mob["position"][0], mob["position"][1] + mob["height"] * 0.55, mob["position"][2])
            let to_x = center[0] - origin[0]
            let to_y = center[1] - origin[1]
            let to_z = center[2] - origin[2]
            let along = to_x * direction[0] + to_y * direction[1] + to_z * direction[2]
            if along >= 0.0 and along <= max_dist:
                let closest = vec3(
                    origin[0] + direction[0] * along,
                    origin[1] + direction[1] * along,
                    origin[2] + direction[2] * along
                )
                let off_dist = _distance(center, closest)
                if off_dist <= mob["radius"] + 0.45:
                    if best == nil or along < best["distance"]:
                        best = {"index": i, "mob": mob, "distance": along}
        i = i + 1
    return best

proc collect_dead_voxel_mobs(state):
    let dead = []
    let kept = []
    let i = 0
    while i < len(state["mobs"]):
        let mob = state["mobs"][i]
        if mob["health"]["alive"]:
            push(kept, mob)
        else:
            push(dead, mob)
        i = i + 1
    state["mobs"] = kept
    return dead

proc voxel_gameplay_to_sage(state):
    let data = {}
    data["next_pickup_id"] = state["next_pickup_id"]
    data["next_mob_id"] = state["next_mob_id"]
    data["spawn_cursor"] = state["spawn_cursor"]
    data["pickups"] = []
    data["mobs"] = []

    let pi = 0
    while pi < len(state["pickups"]):
        let pickup = state["pickups"][pi]
        let pd = {}
        pd["id"] = pickup["id"]
        pd["block_id"] = pickup["block_id"]
        pd["count"] = pickup["count"]
        pd["position"] = _copy_vec3(pickup["position"])
        pd["age"] = pickup["age"]
        pd["bob_phase"] = pickup["bob_phase"]
        pd["pickup_radius"] = pickup["pickup_radius"]
        pd["magnet_radius"] = pickup["magnet_radius"]
        pd["max_age"] = pickup["max_age"]
        push(data["pickups"], pd)
        pi = pi + 1
    let mi = 0
    while mi < len(state["mobs"]):
        let mob = state["mobs"][mi]
        let md = {}
        md["id"] = mob["id"]
        md["type"] = mob["type"]
        md["position"] = _copy_vec3(mob["position"])
        md["age"] = mob["age"]
        md["last_attack_time"] = mob["last_attack_time"]
        md["drop_spawned"] = mob["drop_spawned"]
        md["health"] = _copy_health_data(mob["health"])
        push(data["mobs"], md)
        mi = mi + 1
    return data

proc voxel_gameplay_from_sage(data):
    let state = create_voxel_gameplay_state()
    if data == nil:
        return state
    if dict_has(data, "next_pickup_id"):
        state["next_pickup_id"] = data["next_pickup_id"]
    if dict_has(data, "next_mob_id"):
        state["next_mob_id"] = data["next_mob_id"]
    if dict_has(data, "spawn_cursor"):
        state["spawn_cursor"] = data["spawn_cursor"]
    if dict_has(data, "pickups"):
        let pi = 0
        while pi < len(data["pickups"]):
            let pd = data["pickups"][pi]
            let pickup = _create_pickup(pd["id"], pd["block_id"], pd["count"], pd["position"])
            if dict_has(pd, "age"):
                pickup["age"] = pd["age"]
            if dict_has(pd, "bob_phase"):
                pickup["bob_phase"] = pd["bob_phase"]
            if dict_has(pd, "pickup_radius"):
                pickup["pickup_radius"] = pd["pickup_radius"]
            if dict_has(pd, "magnet_radius"):
                pickup["magnet_radius"] = pd["magnet_radius"]
            if dict_has(pd, "max_age"):
                pickup["max_age"] = pd["max_age"]
            push(state["pickups"], pickup)
            pi = pi + 1
    if dict_has(data, "mobs"):
        let mi = 0
        while mi < len(data["mobs"]):
            let md = data["mobs"][mi]
            let mob = _create_mob(md["id"], md["position"], "slime")
            if dict_has(md, "type"):
                mob["type"] = md["type"]
            if dict_has(md, "age"):
                mob["age"] = md["age"]
            if dict_has(md, "last_attack_time"):
                mob["last_attack_time"] = md["last_attack_time"]
            if dict_has(md, "drop_spawned"):
                mob["drop_spawned"] = md["drop_spawned"]
            if dict_has(md, "health") and md["health"] != nil:
                mob["health"] = _copy_health_data(md["health"])
            push(state["mobs"], mob)
            mi = mi + 1
    return state
