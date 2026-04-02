gc_disable()
# -----------------------------------------
# scene_editor.sage - Scene editor for Sage Engine
# Select, place, delete, transform entities in-engine
# -----------------------------------------

from ecs import spawn, destroy, add_component, get_component, has_component, query
from ecs import entity_count, add_tag, has_tag
from components import TransformComponent, NameComponent
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_length
from collision import ray_vs_aabb, ray_vs_sphere
from gizmo import create_gizmo, gizmo_hit_test, begin_gizmo_drag
from gizmo import end_gizmo_drag, update_gizmo_drag, cycle_gizmo_mode
from gizmo import GIZMO_TRANSLATE, GIZMO_ROTATE, GIZMO_SCALE
from inspector import create_inspector, inspect_entity, clear_inspection, refresh_inspector
from undo_redo import create_command_history, execute_command, undo, redo
from undo_redo import can_undo, can_redo, cmd_set_property

proc _clone_sage(value):
    from json import cJSON_FromSage, cJSON_ToSage, cJSON_Delete
    let node = cJSON_FromSage(value)
    if node == nil:
        return value
    let out = cJSON_ToSage(node)
    cJSON_Delete(node)
    return out

# ============================================================================
# Editor State
# ============================================================================
proc create_scene_editor(world):
    let ed = {}
    ed["world"] = world
    ed["selected"] = -1
    ed["selection"] = []
    ed["gizmo"] = create_gizmo()
    ed["inspector"] = create_inspector()
    ed["history"] = create_command_history(100)
    ed["mode"] = "select"
    ed["active"] = true
    ed["grid_visible"] = true
    ed["grid_size"] = 20.0
    ed["grid_spacing"] = 1.0
    ed["snap_enabled"] = false
    ed["snap_size"] = 0.5
    ed["entity_names"] = {}
    ed["clipboard"] = nil
    ed["place_mesh"] = nil
    return ed

# ============================================================================
# Entity selection via raycast
# ============================================================================
proc select_by_ray(ed, ray_origin, ray_dir):
    return select_by_ray_mode(ed, ray_origin, ray_dir, false)

proc select_by_ray_mode(ed, ray_origin, ray_dir, additive):
    let w = ed["world"]
    let best_t = 999999.0
    let best_eid = -1
    let entities = query(w, ["transform"])
    let i = 0
    while i < len(entities):
        let eid = entities[i]
        if has_tag(w, eid, "editor_hidden") == false:
            let t = get_component(w, eid, "transform")
            let pos = t["position"]
            let half = vec3(0.5, 0.5, 0.5)
            if has_component(w, eid, "collider"):
                let col = get_component(w, eid, "collider")
                if col["type"] == "aabb":
                    half = col["half"]
                if col["type"] == "sphere":
                    half = vec3(col["radius"], col["radius"], col["radius"])
            let hit = ray_vs_aabb(ray_origin, ray_dir, pos, half)
            if hit != nil and hit["t"] < best_t and hit["t"] > 0.0:
                best_t = hit["t"]
                best_eid = eid
        i = i + 1
    if additive and best_eid >= 0:
        toggle_entity_selection(ed, best_eid)
    else:
        select_entity(ed, best_eid)
    return best_eid

proc select_entity(ed, entity_id):
    ed["selection"] = []
    ed["selected"] = entity_id
    if entity_id >= 0:
        push(ed["selection"], entity_id)
        let w = ed["world"]
        if has_component(w, entity_id, "transform"):
            let t = get_component(w, entity_id, "transform")
            ed["gizmo"]["position"] = t["position"]
        inspect_entity(ed["inspector"], w, entity_id)
    else:
        clear_inspection(ed["inspector"])

proc _selection_index(ed, entity_id):
    let i = 0
    while i < len(ed["selection"]):
        if ed["selection"][i] == entity_id:
            return i
        i = i + 1
    return -1

proc toggle_entity_selection(ed, entity_id):
    if entity_id < 0:
        return 0
    let idx = _selection_index(ed, entity_id)
    if idx >= 0:
        let next_sel = []
        let i = 0
        while i < len(ed["selection"]):
            if i != idx:
                push(next_sel, ed["selection"][i])
            i = i + 1
        ed["selection"] = next_sel
        if len(ed["selection"]) > 0:
            ed["selected"] = ed["selection"][0]
            inspect_entity(ed["inspector"], ed["world"], ed["selected"])
        else:
            ed["selected"] = -1
            clear_inspection(ed["inspector"])
        return len(ed["selection"])
    push(ed["selection"], entity_id)
    ed["selected"] = entity_id
    inspect_entity(ed["inspector"], ed["world"], entity_id)
    return len(ed["selection"])

proc selected_entities(ed):
    return ed["selection"]

proc select_all_entities(ed):
    let all_e = query(ed["world"], ["transform"])
    ed["selection"] = []
    let i = 0
    while i < len(all_e):
        push(ed["selection"], all_e[i])
        i = i + 1
    if len(ed["selection"]) > 0:
        ed["selected"] = ed["selection"][0]
        inspect_entity(ed["inspector"], ed["world"], ed["selected"])
    else:
        ed["selected"] = -1
        clear_inspection(ed["inspector"])
    return len(ed["selection"])

proc deselect(ed):
    ed["selected"] = -1
    ed["selection"] = []
    clear_inspection(ed["inspector"])

# ============================================================================
# Place new entity
# ============================================================================
proc place_entity(ed, position, name, mesh_ref):
    let w = ed["world"]
    let eid = spawn(w)
    add_component(w, eid, "transform", TransformComponent(position[0], position[1], position[2]))
    add_component(w, eid, "name", NameComponent(name))
    if mesh_ref != nil:
        add_component(w, eid, "mesh_id", {"mesh": mesh_ref})
    add_tag(w, eid, "editable")
    select_entity(ed, eid)
    return eid

# ============================================================================
# Delete selected entity
# ============================================================================
proc delete_selected(ed):
    let ids = []
    if len(ed["selection"]) > 0:
        let i = 0
        while i < len(ed["selection"]):
            push(ids, ed["selection"][i])
            i = i + 1
    else:
        if ed["selected"] >= 0:
            push(ids, ed["selected"])
    if len(ids) == 0:
        return false
    let w = ed["world"]
    let i = 0
    while i < len(ids):
        destroy(w, ids[i])
        i = i + 1
    ed["selected"] = -1
    ed["selection"] = []
    clear_inspection(ed["inspector"])
    return true

# ============================================================================
# Duplicate selected entity
# ============================================================================
proc duplicate_selected(ed):
    let source_ids = []
    if len(ed["selection"]) > 0:
        let i = 0
        while i < len(ed["selection"]):
            push(source_ids, ed["selection"][i])
            i = i + 1
    else:
        if ed["selected"] >= 0:
            push(source_ids, ed["selected"])
    if len(source_ids) == 0:
        return -1
    let w = ed["world"]
    let new_ids = []
    let si = 0
    while si < len(source_ids):
        let src = source_ids[si]
        let eid = spawn(w)
        # Copy transform with offset
        if has_component(w, src, "transform"):
            let st = get_component(w, src, "transform")
            let nt = TransformComponent(st["position"][0] + 1.0, st["position"][1], st["position"][2])
            nt["rotation"] = vec3(st["rotation"][0], st["rotation"][1], st["rotation"][2])
            nt["scale"] = vec3(st["scale"][0], st["scale"][1], st["scale"][2])
            add_component(w, eid, "transform", nt)
        if has_component(w, src, "name"):
            let sn = get_component(w, src, "name")
            add_component(w, eid, "name", NameComponent(sn["name"] + "_copy"))
        if has_component(w, src, "mesh_id"):
            let sm = get_component(w, src, "mesh_id")
            add_component(w, eid, "mesh_id", _clone_sage(sm))
        if has_component(w, src, "rigidbody"):
            let rb = get_component(w, src, "rigidbody")
            add_component(w, eid, "rigidbody", _clone_sage(rb))
        if has_component(w, src, "collider"):
            let col = get_component(w, src, "collider")
            add_component(w, eid, "collider", _clone_sage(col))
        if has_component(w, src, "health"):
            let hp = get_component(w, src, "health")
            add_component(w, eid, "health", _clone_sage(hp))
        if has_component(w, src, "camera"):
            let cam = get_component(w, src, "camera")
            add_component(w, eid, "camera", _clone_sage(cam))
        if has_component(w, src, "light"):
            let lt = get_component(w, src, "light")
            add_component(w, eid, "light", _clone_sage(lt))
        if has_component(w, src, "material"):
            let mat = get_component(w, src, "material")
            add_component(w, eid, "material", _clone_sage(mat))
        if has_component(w, src, "imported_asset"):
            let asset = get_component(w, src, "imported_asset")
            add_component(w, eid, "imported_asset", _clone_sage(asset))
        if has_component(w, src, "animation_state"):
            let anim = get_component(w, src, "animation_state")
            add_component(w, eid, "animation_state", _clone_sage(anim))
        if has_component(w, src, "asset_ref"):
            let asset_ref = get_component(w, src, "asset_ref")
            add_component(w, eid, "asset_ref", _clone_sage(asset_ref))
        add_tag(w, eid, "editable")
        push(new_ids, eid)
        si = si + 1
    if len(new_ids) == 0:
        return -1
    ed["selection"] = []
    let ni = 0
    while ni < len(new_ids):
        push(ed["selection"], new_ids[ni])
        ni = ni + 1
    ed["selected"] = new_ids[0]
    inspect_entity(ed["inspector"], w, ed["selected"])
    return new_ids[0]

# ============================================================================
# Apply gizmo transform to selected entity
# ============================================================================
proc apply_gizmo_delta(ed, delta):
    let targets = []
    if len(ed["selection"]) > 0:
        let ti = 0
        while ti < len(ed["selection"]):
            push(targets, ed["selection"][ti])
            ti = ti + 1
    else:
        if ed["selected"] >= 0:
            push(targets, ed["selected"])
    if len(targets) == 0:
        return nil
    let w = ed["world"]
    let mode = ed["gizmo"]["mode"]
    let i = 0
    while i < len(targets):
        let t = get_component(w, targets[i], "transform")
        if t != nil:
            if mode == GIZMO_TRANSLATE:
                t["position"] = v3_add(t["position"], delta)
                if ed["snap_enabled"]:
                    let ss = ed["snap_size"]
                    import math
                    t["position"][0] = math.floor(t["position"][0] / ss + 0.5) * ss
                    t["position"][1] = math.floor(t["position"][1] / ss + 0.5) * ss
                    t["position"][2] = math.floor(t["position"][2] / ss + 0.5) * ss
            if mode == GIZMO_ROTATE:
                t["rotation"] = v3_add(t["rotation"], delta)
            if mode == GIZMO_SCALE:
                t["scale"] = v3_add(t["scale"], delta)
            t["dirty"] = true
        i = i + 1
    if ed["selected"] >= 0 and has_component(w, ed["selected"], "transform"):
        ed["gizmo"]["position"] = get_component(w, ed["selected"], "transform")["position"]

# ============================================================================
# Editor stats
# ============================================================================
proc editor_stats(ed):
    let s = {}
    s["selected"] = ed["selected"]
    s["selected_count"] = len(ed["selection"])
    s["mode"] = ed["gizmo"]["mode"]
    s["entities"] = entity_count(ed["world"])
    s["can_undo"] = can_undo(ed["history"])
    s["can_redo"] = can_redo(ed["history"])
    s["snap"] = ed["snap_enabled"]
    return s
