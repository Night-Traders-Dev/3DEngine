# test_scene_editor.sage - Sanity checks for scene editor
# Run: ./run.sh tests/test_scene_editor.sage

from scene_editor import create_scene_editor, select_entity, deselect
from scene_editor import place_entity, delete_selected, duplicate_selected
from scene_editor import apply_gizmo_delta, editor_stats
from scene_editor import toggle_entity_selection, select_all_entities, selected_entities
from ecs import create_world, spawn, add_component, has_component, entity_count, get_component
from components import TransformComponent, NameComponent, CameraComponent, MaterialComponent
from collision import ray_vs_aabb
from math3d import vec3
from gizmo import GIZMO_TRANSLATE, GIZMO_ROTATE, GIZMO_SCALE

import math

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

proc approx(a, b):
    return math.abs(a - b) < 0.1

print "=== Scene Editor Sanity Checks ==="

# --- Creation ---
let w = create_world()
let ed = create_scene_editor(w)
check("editor created", ed != nil)
check("no selection", ed["selected"] == -1)
check("gizmo exists", ed["gizmo"] != nil)
check("inspector exists", ed["inspector"] != nil)
check("history exists", ed["history"] != nil)
check("active", ed["active"] == true)

# --- Place entity ---
let eid = place_entity(ed, vec3(5.0, 0.0, 3.0), "TestCube", nil)
check("placed entity", eid > 0)
check("entity has transform", has_component(w, eid, "transform"))
check("entity has name", has_component(w, eid, "name"))
check("auto-selected", ed["selected"] == eid)

# Check position
let t = get_component(w, eid, "transform")
check("placed at correct pos", approx(t["position"][0], 5.0))

let cam_comp = CameraComponent(80.0, 0.1, 250.0)
cam_comp["active"] = true
add_component(w, eid, "camera", cam_comp)
let mat_comp = MaterialComponent(0.4, 0.5, 0.9)
mat_comp["metallic"] = 0.7
add_component(w, eid, "material", mat_comp)
add_component(w, eid, "imported_asset", {"name": "MockImport", "materials": [{"name": "Blue"}], "gpu_meshes": [{"gpu_mesh": 7, "material_index": 0}]})

# --- Select/deselect ---
deselect(ed)
check("deselected", ed["selected"] == -1)
select_entity(ed, eid)
check("reselected", ed["selected"] == eid)

# --- Gizmo translate ---
ed["gizmo"]["mode"] = GIZMO_TRANSLATE
apply_gizmo_delta(ed, vec3(2.0, 0.0, 0.0))
let t2 = get_component(w, eid, "transform")
check("translated x", approx(t2["position"][0], 7.0))
check("gizmo follows", approx(ed["gizmo"]["position"][0], 7.0))

# --- Gizmo rotate ---
ed["gizmo"]["mode"] = GIZMO_ROTATE
apply_gizmo_delta(ed, vec3(0.0, 1.5, 0.0))
let t3 = get_component(w, eid, "transform")
check("rotated y", approx(t3["rotation"][1], 1.5))

# --- Gizmo scale ---
ed["gizmo"]["mode"] = GIZMO_SCALE
apply_gizmo_delta(ed, vec3(1.0, 0.0, 0.0))
let t4 = get_component(w, eid, "transform")
check("scaled x", approx(t4["scale"][0], 2.0))

# --- Snap ---
ed["snap_enabled"] = true
ed["snap_size"] = 1.0
ed["gizmo"]["mode"] = GIZMO_TRANSLATE
apply_gizmo_delta(ed, vec3(0.3, 0.0, 0.0))
let t5 = get_component(w, eid, "transform")
# Should snap to nearest 1.0 grid
let snapped_x = t5["position"][0]
let remainder = snapped_x - math.floor(snapped_x)
check("snap aligns to grid", approx(remainder, 0.0))
ed["snap_enabled"] = false

# --- Duplicate ---
let eid2 = duplicate_selected(ed)
check("duplicate created", eid2 > 0)
check("duplicate selected", ed["selected"] == eid2)
check("duplicate has transform", has_component(w, eid2, "transform"))
check("duplicate has name", has_component(w, eid2, "name"))
check("duplicate has camera", has_component(w, eid2, "camera"))
check("duplicate has material", has_component(w, eid2, "material"))
check("duplicate has imported asset", has_component(w, eid2, "imported_asset"))
let t6 = get_component(w, eid2, "transform")
let t_orig = get_component(w, eid, "transform")
check("duplicate offset x", t6["position"][0] > t_orig["position"][0])
let dup_cam = get_component(w, eid2, "camera")
check("duplicate camera active", dup_cam["active"] == true)
let dup_mat = get_component(w, eid2, "material")
check("duplicate material metallic", approx(dup_mat["metallic"], 0.7))
let dup_asset = get_component(w, eid2, "imported_asset")
check("duplicate imported asset name", dup_asset["name"] == "MockImport")

# --- Delete ---
let before_count = entity_count(w)
delete_selected(ed)
check("deleted selected", ed["selected"] == -1)
from ecs import flush_dead
flush_dead(w)

# --- Multiple entities ---
place_entity(ed, vec3(0.0, 0.0, 0.0), "A", nil)
let e_multi_b = place_entity(ed, vec3(1.0, 0.0, 0.0), "B", nil)
let e_multi_c = place_entity(ed, vec3(2.0, 0.0, 0.0), "C", nil)

# --- Multi-select ---
select_entity(ed, e_multi_b)
toggle_entity_selection(ed, e_multi_c)
check("multi-select includes B/C", len(selected_entities(ed)) >= 2)
let sel_all_count = select_all_entities(ed)
check("select_all returns count", sel_all_count > 0)
check("select_all matches selection len", len(selected_entities(ed)) == sel_all_count)

# --- Editor stats ---
let stats = editor_stats(ed)
check("stats has selected", dict_has(stats, "selected"))
check("stats has selected_count", dict_has(stats, "selected_count"))
check("stats has mode", dict_has(stats, "mode"))
check("stats has entities", stats["entities"] > 0)
check("stats has snap", dict_has(stats, "snap"))

# --- Apply gizmo with no selection ---
deselect(ed)
apply_gizmo_delta(ed, vec3(1.0, 0.0, 0.0))
check("no crash with no selection", true)

# --- Delete with no selection ---
let del_empty = delete_selected(ed)
check("delete empty returns false", del_empty == false)

# --- Duplicate with no selection ---
let dup_empty = duplicate_selected(ed)
check("duplicate empty returns -1", dup_empty == -1)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Scene editor sanity checks failed!"
else:
    print "All scene editor sanity checks passed!"
