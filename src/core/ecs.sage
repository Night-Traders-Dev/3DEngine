gc_disable()
# -----------------------------------------
# ecs.sage - Entity Component System for Sage Engine
#
# Archetype-free, dict-based ECS optimized for readability.
# Entities are integer IDs. Components are dicts stored per-type.
# Systems are procs that run each frame on matching entities.
# -----------------------------------------

# ============================================================================
# World - the ECS container
# ============================================================================
proc create_world():
    let w = {}
    w["next_id"] = 1
    w["entities"] = {}
    w["components"] = {}
    w["systems"] = []
    w["tags"] = {}
    w["dead"] = []
    return w

# ============================================================================
# Entity management
# ============================================================================
proc spawn(world):
    let id = world["next_id"]
    world["next_id"] = id + 1
    world["entities"][str(id)] = true
    return id

proc destroy(world, entity):
    let sid = str(entity)
    if dict_has(world["entities"], sid) == false:
        return nil
    world["entities"][sid] = false
    push(world["dead"], entity)

proc is_alive(world, entity):
    let sid = str(entity)
    if dict_has(world["entities"], sid) == false:
        return false
    return world["entities"][sid]

proc entity_count(world):
    let count = 0
    let keys = dict_keys(world["entities"])
    let i = 0
    while i < len(keys):
        if world["entities"][keys[i]] == true:
            count = count + 1
        i = i + 1
    return count

# ============================================================================
# Component management
# ============================================================================
proc add_component(world, entity, comp_type, data):
    if dict_has(world["components"], comp_type) == false:
        world["components"][comp_type] = {}
    world["components"][comp_type][str(entity)] = data

proc get_component(world, entity, comp_type):
    if dict_has(world["components"], comp_type) == false:
        return nil
    let store = world["components"][comp_type]
    let sid = str(entity)
    if dict_has(store, sid) == false:
        return nil
    return store[sid]

proc has_component(world, entity, comp_type):
    if dict_has(world["components"], comp_type) == false:
        return false
    return dict_has(world["components"][comp_type], str(entity))

proc remove_component(world, entity, comp_type):
    if dict_has(world["components"], comp_type) == false:
        return nil
    let store = world["components"][comp_type]
    let sid = str(entity)
    if dict_has(store, sid):
        dict_delete(store, sid)

# ============================================================================
# Tags (lightweight markers with no data)
# ============================================================================
proc add_tag(world, entity, tag):
    if dict_has(world["tags"], tag) == false:
        world["tags"][tag] = {}
    world["tags"][tag][str(entity)] = true

proc has_tag(world, entity, tag):
    if dict_has(world["tags"], tag) == false:
        return false
    return dict_has(world["tags"][tag], str(entity))

proc remove_tag(world, entity, tag):
    if dict_has(world["tags"], tag) == false:
        return nil
    let store = world["tags"][tag]
    let sid = str(entity)
    if dict_has(store, sid):
        dict_delete(store, sid)

# ============================================================================
# Queries - find entities with specific components
# ============================================================================
proc query(world, comp_types):
    if len(comp_types) == 0:
        return []
    let first_type = comp_types[0]
    if dict_has(world["components"], first_type) == false:
        return []
    let candidates = dict_keys(world["components"][first_type])
    let result = []
    let i = 0
    while i < len(candidates):
        let sid = candidates[i]
        if world["entities"][sid] == true:
            let has_all = true
            let j = 1
            while j < len(comp_types):
                let ct = comp_types[j]
                if dict_has(world["components"], ct) == false:
                    has_all = false
                    j = len(comp_types)
                else:
                    if dict_has(world["components"][ct], sid) == false:
                        has_all = false
                        j = len(comp_types)
                j = j + 1
            if has_all:
                push(result, tonumber(sid))
        i = i + 1
    return result

proc query_tag(world, tag):
    if dict_has(world["tags"], tag) == false:
        return []
    let store = world["tags"][tag]
    let keys = dict_keys(store)
    let result = []
    let i = 0
    while i < len(keys):
        let sid = keys[i]
        if dict_has(world["entities"], sid):
            if world["entities"][sid] == true:
                push(result, tonumber(sid))
        i = i + 1
    return result

# ============================================================================
# Systems - registered procs that run each tick
# ============================================================================
proc register_system(world, name, required_components, update_fn):
    let sys = {}
    sys["name"] = name
    sys["requires"] = required_components
    sys["update"] = update_fn
    sys["enabled"] = true
    push(world["systems"], sys)

proc enable_system(world, name):
    let i = 0
    while i < len(world["systems"]):
        if world["systems"][i]["name"] == name:
            world["systems"][i]["enabled"] = true
        i = i + 1

proc disable_system(world, name):
    let i = 0
    while i < len(world["systems"]):
        if world["systems"][i]["name"] == name:
            world["systems"][i]["enabled"] = false
        i = i + 1

proc tick_systems(world, dt):
    let i = 0
    while i < len(world["systems"]):
        let sys = world["systems"][i]
        if sys["enabled"]:
            let entities = query(world, sys["requires"])
            sys["update"](world, entities, dt)
        i = i + 1

# ============================================================================
# Cleanup dead entities
# ============================================================================
proc flush_dead(world):
    let i = 0
    while i < len(world["dead"]):
        let entity = world["dead"][i]
        let sid = str(entity)
        # Remove from all component stores
        let comp_types = dict_keys(world["components"])
        let j = 0
        while j < len(comp_types):
            let store = world["components"][comp_types[j]]
            if dict_has(store, sid):
                dict_delete(store, sid)
            j = j + 1
        # Remove from all tag stores
        let tag_types = dict_keys(world["tags"])
        let k = 0
        while k < len(tag_types):
            let tstore = world["tags"][tag_types[k]]
            if dict_has(tstore, sid):
                dict_delete(tstore, sid)
            k = k + 1
        # Remove entity entry
        if dict_has(world["entities"], sid):
            dict_delete(world["entities"], sid)
        i = i + 1
    world["dead"] = []
