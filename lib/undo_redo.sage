gc_disable()
# -----------------------------------------
# undo_redo.sage - Command-based undo/redo for Sage Engine Editor
# Records actions as command objects with do/undo functions
# -----------------------------------------

# ============================================================================
# Command History
# ============================================================================
proc create_command_history(max_size):
    let ch = {}
    ch["undo_stack"] = []
    ch["redo_stack"] = []
    ch["max_size"] = max_size
    ch["dirty"] = false
    return ch

# ============================================================================
# Execute a command and push to undo stack
# ============================================================================
proc execute_command(history, command):
    # Execute the command
    command["execute"](command)
    # Push to undo stack
    push(history["undo_stack"], command)
    # Trim if over max
    while len(history["undo_stack"]) > history["max_size"]:
        let new_stack = []
        let i = 1
        while i < len(history["undo_stack"]):
            push(new_stack, history["undo_stack"][i])
            i = i + 1
        history["undo_stack"] = new_stack
    # Clear redo stack (new action invalidates redo)
    history["redo_stack"] = []
    history["dirty"] = true

# ============================================================================
# Undo last command
# ============================================================================
proc undo(history):
    if len(history["undo_stack"]) == 0:
        return false
    let idx = len(history["undo_stack"]) - 1
    let cmd = history["undo_stack"][idx]
    # Pop from undo
    let new_undo = []
    let i = 0
    while i < idx:
        push(new_undo, history["undo_stack"][i])
        i = i + 1
    history["undo_stack"] = new_undo
    # Undo the command
    cmd["undo"](cmd)
    # Push to redo
    push(history["redo_stack"], cmd)
    history["dirty"] = true
    return true

# ============================================================================
# Redo last undone command
# ============================================================================
proc redo(history):
    if len(history["redo_stack"]) == 0:
        return false
    let idx = len(history["redo_stack"]) - 1
    let cmd = history["redo_stack"][idx]
    # Pop from redo
    let new_redo = []
    let i = 0
    while i < idx:
        push(new_redo, history["redo_stack"][i])
        i = i + 1
    history["redo_stack"] = new_redo
    # Re-execute
    cmd["execute"](cmd)
    push(history["undo_stack"], cmd)
    history["dirty"] = true
    return true

# ============================================================================
# Query state
# ============================================================================
proc can_undo(history):
    return len(history["undo_stack"]) > 0

proc can_redo(history):
    return len(history["redo_stack"]) > 0

proc undo_count(history):
    return len(history["undo_stack"])

proc redo_count(history):
    return len(history["redo_stack"])

proc clear_history(history):
    history["undo_stack"] = []
    history["redo_stack"] = []
    history["dirty"] = false

proc mark_clean(history):
    history["dirty"] = false

proc is_dirty(history):
    return history["dirty"]

# ============================================================================
# Common command builders
# ============================================================================
proc cmd_set_property(target, key, new_value):
    let old_value = target[key]
    let cmd = {}
    cmd["name"] = "set_" + key
    cmd["target"] = target
    cmd["key"] = key
    cmd["old_value"] = old_value
    cmd["new_value"] = new_value
    proc do_it(c):
        c["target"][c["key"]] = c["new_value"]
    proc undo_it(c):
        c["target"][c["key"]] = c["old_value"]
    cmd["execute"] = do_it
    cmd["undo"] = undo_it
    return cmd

proc cmd_set_vec3(target, key, index, new_value):
    let old_value = target[key][index]
    let cmd = {}
    cmd["name"] = "set_" + key + "_" + str(index)
    cmd["target"] = target
    cmd["key"] = key
    cmd["index"] = index
    cmd["old_value"] = old_value
    cmd["new_value"] = new_value
    proc do_it(c):
        c["target"][c["key"]][c["index"]] = c["new_value"]
    proc undo_it(c):
        c["target"][c["key"]][c["index"]] = c["old_value"]
    cmd["execute"] = do_it
    cmd["undo"] = undo_it
    return cmd

proc cmd_spawn_entity(world, setup_fn):
    let cmd = {}
    cmd["name"] = "spawn_entity"
    cmd["world"] = world
    cmd["entity_id"] = -1
    cmd["setup_fn"] = setup_fn
    proc do_it(c):
        from ecs import spawn
        let eid = spawn(c["world"])
        c["entity_id"] = eid
        c["setup_fn"](c["world"], eid)
    proc undo_it(c):
        from ecs import destroy
        if c["entity_id"] >= 0:
            destroy(c["world"], c["entity_id"])
    cmd["execute"] = do_it
    cmd["undo"] = undo_it
    return cmd

proc cmd_destroy_entity(world, entity_id, snapshot):
    let cmd = {}
    cmd["name"] = "destroy_entity"
    cmd["world"] = world
    cmd["entity_id"] = entity_id
    cmd["snapshot"] = snapshot
    proc do_it(c):
        from ecs import destroy
        destroy(c["world"], c["entity_id"])
    proc undo_it(c):
        from ecs import spawn, add_component
        let eid = spawn(c["world"])
        let snap = c["snapshot"]
        let keys = dict_keys(snap)
        let i = 0
        while i < len(keys):
            add_component(c["world"], eid, keys[i], snap[keys[i]])
            i = i + 1
        c["entity_id"] = eid
    cmd["execute"] = do_it
    cmd["undo"] = undo_it
    return cmd
