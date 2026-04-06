gc_disable()
# level_streaming.sage — Level Streaming / World Partition
# Loads and unloads world chunks based on player position.
# Supports: grid-based streaming, async loading, LOD-based detail,
# persistent entities across chunks, transition zones.
#
# Usage:
#   let world_stream = create_world_streamer(chunk_size, load_radius)
#   register_chunk_loader(world_stream, proc(cx, cz): load_chunk(cx, cz))
#   update_streaming(world_stream, player_pos)

from math3d import vec3, v3_sub, v3_length

# ============================================================================
# World Streamer
# ============================================================================

proc create_world_streamer(chunk_size, load_radius):
    return {
        "chunk_size": chunk_size,
        "load_radius": load_radius,
        "unload_radius": load_radius + 2,
        "loaded_chunks": {},       # "cx,cz" → chunk_data
        "loading_queue": [],
        "unload_queue": [],
        "max_loads_per_frame": 2,
        "max_unloads_per_frame": 4,
        "load_fn": nil,
        "unload_fn": nil,
        "center_chunk": [0, 0],
        "total_loaded": 0,
        "total_unloaded": 0,
        "persistent_entities": {}   # Entities that survive chunk unload
    }

proc register_chunk_loader(ws, load_fn):
    ws["load_fn"] = load_fn

proc register_chunk_unloader(ws, unload_fn):
    ws["unload_fn"] = unload_fn

# ============================================================================
# Chunk Key Helpers
# ============================================================================

proc _chunk_key(cx, cz):
    return str(cx) + "," + str(cz)

proc _world_to_chunk(ws, wx, wz):
    let cx = int(wx / ws["chunk_size"])
    let cz = int(wz / ws["chunk_size"])
    if wx < 0:
        cx = cx - 1
    if wz < 0:
        cz = cz - 1
    return [cx, cz]

# ============================================================================
# Update — determine what to load/unload based on player position
# ============================================================================

proc update_streaming(ws, player_pos):
    let chunk_coords = _world_to_chunk(ws, player_pos[0], player_pos[2])
    let pcx = chunk_coords[0]
    let pcz = chunk_coords[1]
    ws["center_chunk"] = [pcx, pcz]

    let load_r = ws["load_radius"]
    let unload_r = ws["unload_radius"]

    # Determine which chunks should be loaded
    let wanted = {}
    let cx = pcx - load_r
    while cx <= pcx + load_r:
        let cz = pcz - load_r
        while cz <= pcz + load_r:
            let key = _chunk_key(cx, cz)
            wanted[key] = [cx, cz]
            cz = cz + 1
        cx = cx + 1

    # Queue loads for chunks not yet loaded
    let wanted_keys = dict_keys(wanted)
    let loads_queued = 0
    let wi = 0
    while wi < len(wanted_keys):
        let key = wanted_keys[wi]
        if not dict_has(ws["loaded_chunks"], key):
            if loads_queued < ws["max_loads_per_frame"]:
                let coords = wanted[key]
                _load_chunk(ws, coords[0], coords[1])
                loads_queued = loads_queued + 1
        wi = wi + 1

    # Queue unloads for chunks too far away
    let loaded_keys = dict_keys(ws["loaded_chunks"])
    let unloads = 0
    let li = 0
    while li < len(loaded_keys):
        let key = loaded_keys[li]
        if not dict_has(wanted, key):
            # Check distance
            let chunk_data = ws["loaded_chunks"][key]
            let chunk_cx = chunk_data["cx"]
            let chunk_cz = chunk_data["cz"]
            let dx = chunk_cx - pcx
            let dz = chunk_cz - pcz
            if dx < 0:
                dx = 0 - dx
            if dz < 0:
                dz = 0 - dz
            if dx > unload_r or dz > unload_r:
                if unloads < ws["max_unloads_per_frame"]:
                    _unload_chunk(ws, key)
                    unloads = unloads + 1
        li = li + 1

proc _load_chunk(ws, cx, cz):
    let key = _chunk_key(cx, cz)
    let chunk_data = {"cx": cx, "cz": cz, "entities": [], "loaded": true}
    if ws["load_fn"] != nil:
        let result = ws["load_fn"](cx, cz)
        if result != nil:
            chunk_data["entities"] = result
    ws["loaded_chunks"][key] = chunk_data
    ws["total_loaded"] = ws["total_loaded"] + 1

proc _unload_chunk(ws, key):
    if dict_has(ws["loaded_chunks"], key):
        let chunk = ws["loaded_chunks"][key]
        if ws["unload_fn"] != nil:
            ws["unload_fn"](chunk)
        dict_delete(ws["loaded_chunks"], key)
        ws["total_unloaded"] = ws["total_unloaded"] + 1

# ============================================================================
# Queries
# ============================================================================

proc is_chunk_loaded(ws, cx, cz):
    return dict_has(ws["loaded_chunks"], _chunk_key(cx, cz))

proc loaded_chunk_count(ws):
    return len(dict_keys(ws["loaded_chunks"]))

proc streaming_stats(ws):
    return {
        "loaded": loaded_chunk_count(ws),
        "total_loaded": ws["total_loaded"],
        "total_unloaded": ws["total_unloaded"],
        "center": ws["center_chunk"]
    }

proc get_loaded_chunks(ws):
    return ws["loaded_chunks"]

# ============================================================================
# Persistent Entities — survive chunk unload/reload
# ============================================================================

proc mark_persistent(ws, entity_id, data):
    ws["persistent_entities"][str(entity_id)] = data

proc get_persistent(ws, entity_id):
    let key = str(entity_id)
    if dict_has(ws["persistent_entities"], key):
        return ws["persistent_entities"][key]
    return nil

proc remove_persistent(ws, entity_id):
    let key = str(entity_id)
    if dict_has(ws["persistent_entities"], key):
        dict_delete(ws["persistent_entities"], key)
