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

# ============================================================================
# Editor State
# ============================================================================
proc create_scene_editor(world):
    let ed = {}
    ed["world"] = world
    ed["selected"] = -1
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
    select_entity(ed, best_eid)
    return best_eid

proc select_entity(ed, entity_id):
    ed["selected"] = entity_id
    if entity_id >= 0:
        let w = ed["world"]
        if has_component(w, entity_id, "transform"):
            let t = get_component(w, entity_id, "transform")
            ed["gizmo"]["position"] = t["position"]
        inspect_entity(ed["inspector"], w, entity_id)
    else:
        clear_inspection(ed["inspector"])

proc deselect(ed):
    ed["selected"] = -1
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
    if ed["selected"] < 0:
        return false
    let w = ed["world"]
    destroy(w, ed["selected"])
    ed["selected"] = -1
    clear_inspection(ed["inspector"])
    return true

# ============================================================================
# Duplicate selected entity
# ============================================================================
proc duplicate_selected(ed):
    if ed["selected"] < 0:
        return -1
    let w = ed["world"]
    let src = ed["selected"]
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
        add_component(w, eid, "mesh_id", sm)
    add_tag(w, eid, "editable")
    select_entity(ed, eid)
    return eid

# ============================================================================
# Apply gizmo transform to selected entity
# ============================================================================
proc apply_gizmo_delta(ed, delta):
    if ed["selected"] < 0:
        return nil
    let w = ed["world"]
    let t = get_component(w, ed["selected"], "transform")
    if t == nil:
        return nil
    let mode = ed["gizmo"]["mode"]
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
    ed["gizmo"]["position"] = t["position"]

# ============================================================================
# Editor stats
# ============================================================================
proc editor_stats(ed):
    let s = {}
    s["selected"] = ed["selected"]
    s["mode"] = ed["gizmo"]["mode"]
    s["entities"] = entity_count(ed["world"])
    s["can_undo"] = can_undo(ed["history"])
    s["can_redo"] = can_redo(ed["history"])
    s["snap"] = ed["snap_enabled"]
    return s
