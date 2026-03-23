# test_scene_serial.sage - Sanity checks for scene serialization
# Run: ./run.sh tests/test_scene_serial.sage

from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, add_tag, has_tag, entity_count
from components import TransformComponent, VelocityComponent, NameComponent, CameraComponent
from gameplay import HealthComponent
from scene_serial import serialize_scene, load_scene_string
from scene_serial import vec3_to_json, json_to_vec3
from json import cJSON_GetArraySize, cJSON_GetArrayItem, cJSON_GetNumberValue
from math3d import vec3

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
    return math.abs(a - b) < 0.01

print "=== Scene Serialization Sanity Checks ==="

# --- vec3 round-trip ---
let v = vec3(1.5, 2.5, 3.5)
let j = vec3_to_json(v)
check("vec3 to json created", j != nil)
check("vec3 json has 3 elements", cJSON_GetArraySize(j) == 3)

let v2 = json_to_vec3(j)
check("vec3 round-trip x", approx(v2[0], 1.5))
check("vec3 round-trip y", approx(v2[1], 2.5))
check("vec3 round-trip z", approx(v2[2], 3.5))

# --- Build a test scene ---
let w = create_world()

let e1 = spawn(w)
add_component(w, e1, "transform", TransformComponent(1.0, 2.0, 3.0))
add_component(w, e1, "name", NameComponent("Player"))
let cam = CameraComponent(75.0, 0.1, 500.0)
cam["yaw"] = 1.23
cam["pitch"] = 0.45
add_component(w, e1, "camera", cam)
add_tag(w, e1, "player")

let e2 = spawn(w)
let t2 = TransformComponent(4.0, 5.0, 6.0)
t2["rotation"] = vec3(0.1, 0.2, 0.3)
t2["scale"] = vec3(2.0, 2.0, 2.0)
add_component(w, e2, "transform", t2)
add_component(w, e2, "name", NameComponent("Box"))
let v_comp = VelocityComponent()
v_comp["linear"] = vec3(1.0, 0.0, -1.0)
v_comp["angular"] = vec3(0.0, 0.5, 0.0)
add_component(w, e2, "velocity", v_comp)
add_component(w, e2, "health", HealthComponent(50.0))
add_tag(w, e2, "enemy")
add_tag(w, e2, "shootable")

# --- Serialize ---
let json_str = serialize_scene(w, "TestScene")
check("serialized not nil", json_str != nil)
check("serialized has content", len(json_str) > 50)
check("contains scene name", contains(json_str, "TestScene"))
check("contains Player", contains(json_str, "Player"))
check("contains Box", contains(json_str, "Box"))
check("contains player tag", contains(json_str, "player"))
check("contains enemy tag", contains(json_str, "enemy"))

# --- Deserialize ---
let result = load_scene_string(json_str)
check("loaded result not nil", result != nil)
check("scene name", result["name"] == "TestScene")
check("entity count", result["entity_count"] == 2)

let w2 = result["world"]
check("world created", w2 != nil)
check("world has entities", entity_count(w2) >= 2)

# Find entities by checking for name component
let found_player = false
let found_box = false
let all_eids = [1, 2]
let i = 0
while i < len(all_eids):
    let eid = all_eids[i]
    if has_component(w2, eid, "name"):
        let n = get_component(w2, eid, "name")
        if n["name"] == "Player":
            found_player = true
            # Check transform
            check("player has transform", has_component(w2, eid, "transform"))
            let pt = get_component(w2, eid, "transform")
            check("player pos x", approx(pt["position"][0], 1.0))
            check("player pos y", approx(pt["position"][1], 2.0))
            check("player pos z", approx(pt["position"][2], 3.0))
            # Check camera
            check("player has camera", has_component(w2, eid, "camera"))
            if has_component(w2, eid, "camera"):
                let pc = get_component(w2, eid, "camera")
                check("camera fov", approx(pc["fov"], 75.0))
                check("camera yaw", approx(pc["yaw"], 1.23))
                check("camera pitch", approx(pc["pitch"], 0.45))
            # Check tag
            check("player tag", has_tag(w2, eid, "player"))
        if n["name"] == "Box":
            found_box = true
            let bt = get_component(w2, eid, "transform")
            check("box pos x", approx(bt["position"][0], 4.0))
            check("box rotation y", approx(bt["rotation"][1], 0.2))
            check("box scale x", approx(bt["scale"][0], 2.0))
            # Velocity
            check("box has velocity", has_component(w2, eid, "velocity"))
            if has_component(w2, eid, "velocity"):
                let bv = get_component(w2, eid, "velocity")
                check("box vel linear x", approx(bv["linear"][0], 1.0))
                check("box vel angular y", approx(bv["angular"][1], 0.5))
            # Health
            check("box has health", has_component(w2, eid, "health"))
            if has_component(w2, eid, "health"):
                let bh = get_component(w2, eid, "health")
                check("box health max", approx(bh["max"], 50.0))
                check("box health current", approx(bh["current"], 50.0))
            # Tags
            check("box enemy tag", has_tag(w2, eid, "enemy"))
            check("box shootable tag", has_tag(w2, eid, "shootable"))
    i = i + 1

check("found player entity", found_player)
check("found box entity", found_box)

# --- File round-trip ---
import io
from scene_serial import save_scene, load_scene
save_scene(w, "FileTest", "/tmp/sage_test_scene.json")
check("save file exists", io.exists("/tmp/sage_test_scene.json"))

let loaded = load_scene("/tmp/sage_test_scene.json")
check("load from file works", loaded != nil)
check("loaded name", loaded["name"] == "FileTest")
check("loaded entity count", loaded["entity_count"] == 2)
io.remove("/tmp/sage_test_scene.json")

# --- Edge case: empty world ---
let empty_w = create_world()
let empty_json = serialize_scene(empty_w, "Empty")
check("empty scene serializes", empty_json != nil)
let empty_result = load_scene_string(empty_json)
check("empty scene loads", empty_result != nil)
check("empty scene 0 entities", empty_result["entity_count"] == 0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Scene serialization sanity checks failed!"
else:
    print "All scene serialization sanity checks passed!"
