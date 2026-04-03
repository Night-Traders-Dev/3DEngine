# test_scene_serial.sage - Sanity checks for scene serialization
# Run: ./run.sh tests/test_scene_serial.sage

from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, add_tag, has_tag, entity_count
from components import TransformComponent, VelocityComponent, NameComponent, CameraComponent
from components import PointLightComponent, MeshRendererComponent
from gameplay import HealthComponent
from forge_version import engine_name, engine_version, scene_format_version
from scene_serial import serialize_scene, load_scene_string, snapshot_scene, load_scene_snapshot
from scene_serial import vec3_to_json, json_to_vec3
from json import cJSON_GetArraySize, cJSON_GetArrayItem, cJSON_GetNumberValue
from math3d import vec3
from voxel_world import create_voxel_world, set_voxel, get_voxel

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
add_component(w, e2, "imported_asset", {"source": "assets/Box.gltf", "name": "Box.gltf", "gpu_meshes": [{"gpu_mesh": 1}], "materials": [{"name": "Default"}]})
add_component(w, e2, "animation_state", {"clip": "Idle", "playing": true, "time": 2.0, "speed": 0.5, "looping": false})
add_component(w, e2, "asset_ref", {"kind": "texture", "path": "assets/text_test.png"})
let voxel_comp = create_voxel_world(12, 8, 12)
set_voxel(voxel_comp, 6, 1, 6, 4)
add_component(w, e2, "voxel_world", voxel_comp)
add_tag(w, e2, "enemy")
add_tag(w, e2, "shootable")

let e3 = spawn(w)
add_component(w, e3, "transform", TransformComponent(-2.0, 3.0, 1.0))
add_component(w, e3, "name", NameComponent("Lamp"))
add_component(w, e3, "light", PointLightComponent(1.0, 0.8, 0.6, 3.5, 18.0))
let mr = MeshRendererComponent(nil, "metallic")
mr["visible"] = false
mr["cast_shadows"] = false
mr["receive_shadows"] = true
add_component(w, e3, "mesh_renderer", mr)
add_tag(w, e3, "light_source")

# --- Serialize ---
let json_str = serialize_scene(w, "TestScene")
check("serialized not nil", json_str != nil)
check("serialized has content", len(json_str) > 50)
check("contains scene name", contains(json_str, "TestScene"))
check("contains Player", contains(json_str, "Player"))
check("contains Box", contains(json_str, "Box"))
check("contains Lamp", contains(json_str, "Lamp"))
check("contains player tag", contains(json_str, "player"))
check("contains enemy tag", contains(json_str, "enemy"))
check("contains engine name", contains(json_str, engine_name()))
check("contains engine version", contains(json_str, engine_version()))

# --- Deserialize ---
let result = load_scene_string(json_str)
check("loaded result not nil", result != nil)
check("scene name", result["name"] == "TestScene")
check("scene engine name", result["engine"] == engine_name())
check("scene engine version", result["engine_version"] == engine_version())
check("scene format version", result["scene_version"] == scene_format_version())
check("entity count", result["entity_count"] == 3)

let w2 = result["world"]
check("world created", w2 != nil)
check("world has entities", entity_count(w2) >= 3)

# Find entities by checking for name component
let found_player = false
let found_box = false
let found_lamp = false
let all_eids = [1, 2, 3]
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
            check("box has imported asset", has_component(w2, eid, "imported_asset"))
            if has_component(w2, eid, "imported_asset"):
                let bia = get_component(w2, eid, "imported_asset")
                check("box imported source", bia["source"] == "assets/Box.gltf")
                check("box imported name", bia["name"] == "Box.gltf")
            check("box has animation state", has_component(w2, eid, "animation_state"))
            if has_component(w2, eid, "animation_state"):
                let bas = get_component(w2, eid, "animation_state")
                check("box animation clip", bas["clip"] == "Idle")
                check("box animation time", approx(bas["time"], 2.0))
                check("box animation speed", approx(bas["speed"], 0.5))
                check("box animation looping", bas["looping"] == false)
            check("box has asset ref", has_component(w2, eid, "asset_ref"))
            if has_component(w2, eid, "asset_ref"):
                let bar = get_component(w2, eid, "asset_ref")
                check("box asset ref path", bar["path"] == "assets/text_test.png")
            check("box has voxel world", has_component(w2, eid, "voxel_world"))
            if has_component(w2, eid, "voxel_world"):
                let bvw = get_component(w2, eid, "voxel_world")
                check("box voxel world preserves block", get_voxel(bvw, 6, 1, 6) == 4)
            # Tags
            check("box enemy tag", has_tag(w2, eid, "enemy"))
            check("box shootable tag", has_tag(w2, eid, "shootable"))
        if n["name"] == "Lamp":
            found_lamp = true
            check("lamp has light", has_component(w2, eid, "light"))
            if has_component(w2, eid, "light"):
                let ll = get_component(w2, eid, "light")
                check("lamp type point", ll["type"] == "point")
                check("lamp intensity", approx(ll["intensity"], 3.5))
                check("lamp radius", approx(ll["radius"], 18.0))
            check("lamp has mesh renderer", has_component(w2, eid, "mesh_renderer"))
            if has_component(w2, eid, "mesh_renderer"):
                let lm = get_component(w2, eid, "mesh_renderer")
                check("mesh renderer material", lm["material"] == "metallic")
                check("mesh renderer visible false", lm["visible"] == false)
                check("mesh renderer cast_shadows false", lm["cast_shadows"] == false)
                check("mesh renderer receive_shadows true", lm["receive_shadows"] == true)
            check("lamp tag", has_tag(w2, eid, "light_source"))
    i = i + 1

check("found player entity", found_player)
check("found box entity", found_box)
check("found lamp entity", found_lamp)

let snapshot = snapshot_scene(w, "PIE")
check("snapshot scene built", snapshot != nil and snapshot["name"] == "PIE")
let snap_result = load_scene_snapshot(snapshot)
check("snapshot scene loads", snap_result != nil)
if snap_result != nil:
    check("snapshot entity count", snap_result["entity_count"] == 3)
    let snap_world = snap_result["world"]
    let snap_box = -1
    let snap_ids = [1, 2, 3]
    let si = 0
    while si < len(snap_ids):
        let snap_eid = snap_ids[si]
        if has_component(snap_world, snap_eid, "name"):
            let snap_name = get_component(snap_world, snap_eid, "name")
            if snap_name["name"] == "Box":
                snap_box = snap_eid
        si = si + 1
    check("snapshot preserves box entity", snap_box > 0)
    if snap_box > 0:
        check("snapshot preserves voxel block", has_component(snap_world, snap_box, "voxel_world") and get_voxel(get_component(snap_world, snap_box, "voxel_world"), 6, 1, 6) == 4)
        check("snapshot preserves imported asset marker", has_component(snap_world, snap_box, "imported_asset"))

# --- File round-trip ---
import io
from scene_serial import save_scene, load_scene
save_scene(w, "FileTest", "/tmp/sage_test_scene.json")
check("save file exists", io.exists("/tmp/sage_test_scene.json"))

let loaded = load_scene("/tmp/sage_test_scene.json")
check("load from file works", loaded != nil)
check("loaded name", loaded["name"] == "FileTest")
check("loaded engine version", loaded["engine_version"] == engine_version())
check("loaded entity count", loaded["entity_count"] == 3)
io.remove("/tmp/sage_test_scene.json")

# --- Edge case: empty world ---
let empty_w = create_world()
let empty_json = serialize_scene(empty_w, "Empty")
check("empty scene serializes", empty_json != nil)
let empty_result = load_scene_string(empty_json)
check("empty scene loads", empty_result != nil)
check("empty scene engine version", empty_result["engine_version"] == engine_version())
check("empty scene 0 entities", empty_result["entity_count"] == 0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Scene serialization sanity checks failed!"
else:
    print "All scene serialization sanity checks passed!"
