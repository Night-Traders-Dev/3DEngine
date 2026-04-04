gc_disable()
# -----------------------------------------
# scene.sage - Feature 12: Scene Graph
# Dict-based node hierarchy with transforms
# -----------------------------------------

from math3d import mat4_identity, mat4_mul

# Create a scene node
proc create_node(name):
    let n = {}
    n["name"] = name
    n["transform"] = mat4_identity()
    n["children"] = []
    n["parent"] = nil
    n["mesh"] = nil
    n["material"] = nil
    n["visible"] = true
    n["user_data"] = nil
    return n

# Add child to parent
proc add_child(parent, child):
    push(parent["children"], child)
    child["parent"] = parent

# Remove child by name
proc remove_child(parent, child):
    let child_name = child["name"]
    let new_children = []
    let i = 0
    while i < len(parent["children"]):
        let c = parent["children"][i]
        if c["name"] != child_name:
            push(new_children, c)
        i = i + 1
    parent["children"] = new_children
    child["parent"] = nil

# Compute world transform (walk up parent chain)
proc world_transform(node):
    let result = node["transform"]
    let current = node["parent"]
    while current != nil:
        result = mat4_mul(current["transform"], result)
        current = current["parent"]
    return result

# Visit all nodes (depth-first)
proc traverse(node, visitor):
    if node["visible"] == false:
        return nil
    visitor(node)
    let i = 0
    while i < len(node["children"]):
        traverse(node["children"][i], visitor)
        i = i + 1

# Count nodes in subtree
proc node_count(node):
    let count = 1
    let i = 0
    while i < len(node["children"]):
        count = count + node_count(node["children"][i])
        i = i + 1
    return count

# Find node by name (DFS)
proc find_node(root, name):
    if root["name"] == name:
        return root
    let i = 0
    while i < len(root["children"]):
        let found = find_node(root["children"][i], name)
        if found != nil:
            return found
        i = i + 1
    return nil

# ============================================================================
# Level streaming — load/unload sub-scenes
# ============================================================================
proc create_level_manager():
    let lm = {}
    lm["loaded_levels"] = {}
    lm["loading_queue"] = []
    lm["unload_queue"] = []
    return lm

proc request_level_load(lm, level_name, filepath):
    push(lm["loading_queue"], {"name": level_name, "path": filepath})

proc request_level_unload(lm, level_name):
    push(lm["unload_queue"], level_name)

proc is_level_loaded(lm, level_name):
    return dict_has(lm["loaded_levels"], level_name)

proc process_level_queue(lm, world):
    from scene_serial import load_scene
    # Process loads
    let li = 0
    while li < len(lm["loading_queue"]):
        let req = lm["loading_queue"][li]
        if dict_has(lm["loaded_levels"], req["name"]) == false:
            let result = load_scene(req["path"])
            if result != nil:
                lm["loaded_levels"][req["name"]] = {"path": req["path"]}
                print "Level loaded: " + req["name"]
        li = li + 1
    lm["loading_queue"] = []
    # Process unloads
    let ui = 0
    while ui < len(lm["unload_queue"]):
        let name = lm["unload_queue"][ui]
        if dict_has(lm["loaded_levels"], name):
            dict_delete(lm["loaded_levels"], name)
            print "Level unloaded: " + name
        ui = ui + 1
    lm["unload_queue"] = []

proc get_loaded_levels(lm):
    return dict_keys(lm["loaded_levels"])
