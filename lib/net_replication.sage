gc_disable()
# -----------------------------------------
# net_replication.sage - Entity replication for Sage Engine
# Syncs entity transforms and state over the network
# -----------------------------------------

from ecs import get_component, has_component, spawn, add_component, query
from components import TransformComponent, NameComponent
from math3d import vec3, v3_sub, v3_length, v3_lerp
from net_protocol import msg_entity_update, msg_entity_spawn, msg_entity_destroy
from net_protocol import MSG_ENTITY_UPDATE, MSG_ENTITY_SPAWN, MSG_ENTITY_DESTROY

# ============================================================================
# Replication Manager
# ============================================================================
proc create_replication_manager():
    let rm = {}
    # Map: network_id -> local_entity_id
    rm["net_to_local"] = {}
    # Map: local_entity_id -> network_id
    rm["local_to_net"] = {}
    rm["next_net_id"] = 1
    # Snapshot tracking for delta compression
    rm["last_snapshot"] = {}
    # Interpolation buffers: net_id -> [{pos, rot, time}]
    rm["interp_buffers"] = {}
    rm["interp_delay"] = 0.1
    rm["sync_rate"] = 0.05
    rm["sync_timer"] = 0.0
    return rm

# ============================================================================
# Register a local entity for replication
# ============================================================================
proc register_entity(rm, local_eid):
    let net_id = rm["next_net_id"]
    rm["next_net_id"] = net_id + 1
    rm["net_to_local"][str(net_id)] = local_eid
    rm["local_to_net"][str(local_eid)] = net_id
    return net_id

proc get_net_id(rm, local_eid):
    let key = str(local_eid)
    if dict_has(rm["local_to_net"], key) == false:
        return -1
    return rm["local_to_net"][key]

proc get_local_id(rm, net_id):
    let key = str(net_id)
    if dict_has(rm["net_to_local"], key) == false:
        return -1
    return rm["net_to_local"][key]

# ============================================================================
# Build update messages for all replicated entities
# Only sends if position changed beyond threshold
# ============================================================================
proc build_update_messages(rm, world, threshold):
    let messages = []
    let keys = dict_keys(rm["local_to_net"])
    let i = 0
    while i < len(keys):
        let local_eid = tonumber(keys[i])
        let net_id = rm["local_to_net"][keys[i]]
        if has_component(world, local_eid, "transform"):
            let t = get_component(world, local_eid, "transform")
            let pos = t["position"]
            let rot = t["rotation"]
            let snap_key = str(net_id)
            let should_send = true
            if dict_has(rm["last_snapshot"], snap_key):
                let last = rm["last_snapshot"][snap_key]
                let pos_dist = v3_length(v3_sub(pos, last["pos"]))
                let rot_dist = v3_length(v3_sub(rot, last["rot"]))
                # Send if either position or rotation changed enough
                if pos_dist < threshold and rot_dist < threshold:
                    should_send = false
            if should_send:
                let msg = msg_entity_update(net_id, [pos[0], pos[1], pos[2]], [rot[0], rot[1], rot[2]])
                push(messages, msg)
                rm["last_snapshot"][snap_key] = {"pos": vec3(pos[0], pos[1], pos[2]), "rot": vec3(rot[0], rot[1], rot[2])}
        i = i + 1
    return messages

# ============================================================================
# Apply received update to a remote entity (with interpolation buffer)
# ============================================================================
proc apply_remote_update(rm, world, net_id, position, rotation, time):
    let local_eid = get_local_id(rm, net_id)
    if local_eid < 0:
        # Unknown entity — spawn it
        local_eid = spawn(world)
        add_component(world, local_eid, "transform", TransformComponent(position[0], position[1], position[2]))
        add_component(world, local_eid, "name", NameComponent("Remote_" + str(net_id)))
        rm["net_to_local"][str(net_id)] = local_eid
        rm["local_to_net"][str(local_eid)] = net_id
    # Add to interpolation buffer
    let buf_key = str(net_id)
    if dict_has(rm["interp_buffers"], buf_key) == false:
        rm["interp_buffers"][buf_key] = []
    let buf = rm["interp_buffers"][buf_key]
    push(buf, {"pos": vec3(position[0], position[1], position[2]), "rot": vec3(rotation[0], rotation[1], rotation[2]), "time": time})
    # Keep buffer short (last 10 snapshots)
    while len(buf) > 10:
        let new_buf = []
        let bi = 1
        while bi < len(buf):
            push(new_buf, buf[bi])
            bi = bi + 1
        rm["interp_buffers"][buf_key] = new_buf
        buf = new_buf

# ============================================================================
# Interpolate remote entities toward their latest known state
# ============================================================================
proc interpolate_remotes(rm, world, dt):
    let keys = dict_keys(rm["interp_buffers"])
    let i = 0
    while i < len(keys):
        let net_id = tonumber(keys[i])
        let local_eid = get_local_id(rm, net_id)
        if local_eid < 0:
            i = i + 1
            continue
        let buf = rm["interp_buffers"][keys[i]]
        if len(buf) == 0:
            i = i + 1
            continue
        let target = buf[len(buf) - 1]
        if has_component(world, local_eid, "transform"):
            let t = get_component(world, local_eid, "transform")
            # Smooth interpolation
            let speed = 10.0
            let lerp_t = dt * speed
            if lerp_t > 1.0:
                lerp_t = 1.0
            t["position"] = v3_lerp(t["position"], target["pos"], lerp_t)
            t["rotation"] = v3_lerp(t["rotation"], target["rot"], lerp_t)
            t["dirty"] = true
        i = i + 1

# ============================================================================
# Handle network messages for replication
# ============================================================================
proc handle_replication_message(rm, world, msg, time):
    let mtype = msg["type"]
    if mtype == MSG_ENTITY_UPDATE:
        let p = msg["payload"]
        apply_remote_update(rm, world, p["eid"], p["pos"], p["rot"], time)
        return true
    if mtype == MSG_ENTITY_SPAWN:
        let p = msg["payload"]
        let existing = get_local_id(rm, p["eid"])
        if existing >= 0:
            # Idempotent spawn handling: don't duplicate entities for the same net id
            if has_component(world, existing, "transform"):
                let et = get_component(world, existing, "transform")
                et["position"] = vec3(p["pos"][0], p["pos"][1], p["pos"][2])
                et["dirty"] = true
            return true
        let local_eid = spawn(world)
        add_component(world, local_eid, "transform", TransformComponent(p["pos"][0], p["pos"][1], p["pos"][2]))
        add_component(world, local_eid, "name", NameComponent(p["type"] + "_" + str(p["eid"])))
        rm["net_to_local"][str(p["eid"])] = local_eid
        rm["local_to_net"][str(local_eid)] = p["eid"]
        return true
    if mtype == MSG_ENTITY_DESTROY:
        let p = msg["payload"]
        let local_eid = get_local_id(rm, p["eid"])
        if local_eid >= 0:
            from ecs import destroy
            destroy(world, local_eid)
            dict_delete(rm["net_to_local"], str(p["eid"]))
            dict_delete(rm["local_to_net"], str(local_eid))
            dict_delete(rm["interp_buffers"], str(p["eid"]))
            dict_delete(rm["last_snapshot"], str(p["eid"]))
        return true
    return false

# ============================================================================
# Stats
# ============================================================================
proc replication_stats(rm):
    let s = {}
    s["replicated_entities"] = len(dict_keys(rm["net_to_local"]))
    s["interp_buffers"] = len(dict_keys(rm["interp_buffers"]))
    return s
