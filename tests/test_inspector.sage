# test_inspector.sage - Sanity checks for property inspector
# Run: ./run.sh tests/test_inspector.sage

from inspector import create_inspector, inspect_entity, clear_inspection, refresh_inspector
from ecs import create_world, spawn, add_component
from components import TransformComponent, NameComponent, VelocityComponent, CameraComponent
from gameplay import HealthComponent
from math3d import vec3

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Inspector Sanity Checks ==="

# --- Creation ---
let ins = create_inspector()
check("inspector created", ins != nil)
check("no selection", ins["selected_entity"] == -1)
check("panel exists", ins["panel"] != nil)
check("visible", ins["visible"] == true)
check("has component types", len(ins["component_types"]) > 0)

# --- Inspect entity ---
let w = create_world()
let e1 = spawn(w)
add_component(w, e1, "transform", TransformComponent(1.0, 2.0, 3.0))
add_component(w, e1, "name", NameComponent("TestObj"))
let vel = VelocityComponent()
vel["linear"] = vec3(5.0, 0.0, 0.0)
add_component(w, e1, "velocity", vel)
add_component(w, e1, "health", HealthComponent(80.0))
add_component(w, e1, "camera", CameraComponent(60.0, 0.1, 100.0))

inspect_entity(ins, w, e1)
check("entity selected", ins["selected_entity"] == e1)
check("world stored", ins["selected_world"] != nil)
check("entries populated", len(ins["entries"]) > 0)
check("panel has children", len(ins["panel"]["children"]) > 0)

# Check we have entries for the components
let has_pos = false
let has_name = false
let has_vel = false
let has_hp = false
let i = 0
while i < len(ins["entries"]):
    let entry = ins["entries"][i]
    if entry["label"] == "position":
        has_pos = true
    if entry["label"] == "name":
        has_name = true
    if entry["label"] == "linear":
        has_vel = true
    if entry["label"] == "current":
        has_hp = true
    i = i + 1
check("has position entry", has_pos)
check("has name entry", has_name)
check("has velocity entry", has_vel)
check("has health entry", has_hp)

# --- Clear ---
clear_inspection(ins)
check("cleared selection", ins["selected_entity"] == -1)
check("cleared entries", len(ins["entries"]) == 0)

# --- Entity with minimal components ---
let e2 = spawn(w)
add_component(w, e2, "transform", TransformComponent(0.0, 0.0, 0.0))
inspect_entity(ins, w, e2)
check("minimal entity inspected", ins["selected_entity"] == e2)
check("minimal has entries", len(ins["entries"]) > 0)

# --- Refresh ---
# Refresh should rebuild entries without errors
let pre_children = len(ins["panel"]["children"])
refresh_inspector(ins)
check("refresh rebuilds panel", len(ins["panel"]["children"]) > 0)
check("refresh produces entries", len(ins["entries"]) > 0)

# --- Panel sizing ---
check("panel height adjusts", ins["panel"]["height"] > 30.0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Inspector sanity checks failed!"
else:
    print "All inspector sanity checks passed!"
