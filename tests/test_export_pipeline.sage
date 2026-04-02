# test_export_pipeline.sage - Headless editor/export smoke test

from scene_editor import create_scene_editor, place_entity
from scene_serial import serialize_scene, load_scene_string
from codegen import generate_game_script
from ecs import create_world, add_component
from components import MaterialComponent, CameraComponent, PointLightComponent
from math3d import vec3

import math

let p = 0
let f = 0

proc check(name, condition):
    if condition:
        p = p + 1
    else:
        print "  FAIL: " + name
        f = f + 1

print "=== Export Pipeline Smoke Test ==="

let world = create_world()
let editor = create_scene_editor(world)

let cube = place_entity(editor, vec3(1.0, 0.5, 2.0), "ExportCube", nil)
let surface = MaterialComponent(0.85, 0.3, 0.2)
surface["metallic"] = 0.4
surface["roughness"] = 0.25
add_component(world, cube, "material", surface)
add_component(world, cube, "mesh_id", {"mesh": nil, "name": "cube"})

let cam_e = place_entity(editor, vec3(6.0, 3.6, 8.0), "ExportCamera", nil)
let cam = CameraComponent(75.0, 0.15, 700.0)
cam["active"] = true
cam["yaw"] = -1.1
cam["pitch"] = -0.2
add_component(world, cam_e, "camera", cam)

let light_e = place_entity(editor, vec3(-3.0, 5.0, 1.0), "ExportLight", nil)
add_component(world, light_e, "light", PointLightComponent(1.0, 0.7, 0.5, 3.8, 14.0))

let imported_e = place_entity(editor, vec3(-1.0, 0.0, -2.0), "ExportModel", nil)
add_component(world, imported_e, "imported_asset", {"source": "assets/Box.gltf", "name": "Box.gltf", "gpu_meshes": [{"gpu_mesh": 1, "material_index": 0}], "materials": [{"name": "Default"}]})
add_component(world, imported_e, "mesh_id", {"mesh": nil, "name": "imported"})

let saved = serialize_scene(world, "SmokeScene")
check("scene serialized", saved != nil)
let loaded = load_scene_string(saved)
check("scene loaded", loaded != nil)

let code = generate_game_script(loaded["world"], "SmokeScene", {"width": 960, "height": 540})
check("generated code exists", code != nil)
check("generated code names scene", contains(code, "SmokeScene"))
check("camera position exported", contains(code, "player[\"position\"] = vec3(6, 2, 8)"))
check("camera yaw exported", contains(code, "player[\"yaw\"] = -1.1"))
check("camera fov exported", contains(code, "player[\"fov\"] = 75"))
check("point light exported", contains(code, "point_light(-3, 5, 1, 1, 0.7, 0.5, 3.8, 14)"))
check("imported asset export helper present", contains(code, "_import_runtime_asset(\"assets/Box.gltf\""))
check("imported asset runtime import present", contains(code, "from asset_import import import_gltf"))
check("imported asset pbr path present", contains(code, "draw_pbr"))
check("material-aware draw remains enabled", contains(code, "draw_mesh_lit_surface"))
check("fallback generated point light omitted", contains(code, "point_light(5.0, 4.0, 3.0, 1.0, 0.8, 0.6, 3.0, 20.0)") == false)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Export pipeline smoke test failed!"
else:
    print "Export pipeline smoke test passed!"
