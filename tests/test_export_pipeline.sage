# test_export_pipeline.sage - Headless editor/export smoke test

from scene_editor import create_scene_editor, place_entity
from scene_serial import serialize_scene, load_scene_string
from codegen import generate_game_script
from asset_import import imported_asset_draws, imported_animation_clip_names
from asset_import import create_imported_animation_state, cycle_imported_animation_clip
from asset_import import advance_imported_animation_state, step_imported_animation_time
from asset_import import imported_animation_duration, imported_skin_joint_matrices
from ecs import create_world, add_component
from components import MaterialComponent, CameraComponent, PointLightComponent
from math3d import vec3, mat4_identity

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
check("imported asset hierarchy helper present", contains(code, "imported_asset_draws"))
check("imported asset pbr path present", contains(code, "draw_pbr"))
check("material-aware draw remains enabled", contains(code, "draw_mesh_lit_surface"))
check("fallback generated point light omitted", contains(code, "point_light(5.0, 4.0, 3.0, 1.0, 0.8, 0.6, 3.0, 20.0)") == false)

let synthetic_asset = {
    "gpu_meshes": [{"gpu_mesh": 11, "material_index": 0, "mesh_index": 0}],
    "nodes": [
        {"name": "Root", "mesh_index": -1, "position": vec3(1.0, 0.0, 0.0), "rotation": [1.0, 0.0, 0.0, 0.0], "scale": vec3(1.0, 1.0, 1.0), "children": [1], "parent": -1},
        {"name": "MeshNode", "mesh_index": 0, "position": vec3(0.0, 2.0, 0.0), "rotation": [1.0, 0.0, 0.0, 0.0], "scale": vec3(1.0, 1.0, 1.0), "children": [], "parent": 0}
    ]
}
let draws = imported_asset_draws(synthetic_asset, nil)
check("hierarchy draw entry built", len(draws) == 1)
check("hierarchy draw keeps gpu mesh", draws[0]["gpu_mesh"] == 11)
check("hierarchy world translation x", draws[0]["model"][12] > 0.9)
check("hierarchy world translation y", draws[0]["model"][13] > 1.9)

let animated_asset = {
    "gpu_meshes": [{"gpu_mesh": 21, "material_index": 0, "mesh_index": 0}],
    "nodes": [
        {"name": "AnimatedMesh", "mesh_index": 0, "position": vec3(0.0, 0.0, 0.0), "rotation": [1.0, 0.0, 0.0, 0.0], "scale": vec3(1.0, 1.0, 1.0), "children": [], "parent": -1}
    ],
    "animations": [
        {"name": "Bounce", "duration": 1.0, "looping": true, "channels": [
            {"node": 0, "path": "translation", "interpolation": "LINEAR", "times": [0.0, 1.0], "values": [vec3(0.0, 0.0, 0.0), vec3(0.0, 3.0, 0.0)]}
        ]},
        {"name": "Drop", "duration": 2.0, "looping": false, "channels": [
            {"node": 0, "path": "translation", "interpolation": "LINEAR", "times": [0.0, 2.0], "values": [vec3(0.0, 4.0, 0.0), vec3(0.0, 0.0, 0.0)]}
        ]}
    ]
}
let clip_names = imported_animation_clip_names(animated_asset)
check("clip names parsed", len(clip_names) == 2)
check("clip name bounce", clip_names[0] == "Bounce")
let anim_state = create_imported_animation_state(animated_asset, "Drop")
check("animation state uses requested clip", anim_state["clip"] == "Drop")
check("animation state keeps clip looping", anim_state["looping"] == false)
check("animation duration lookup", imported_animation_duration(animated_asset, "Drop") > 1.9)
let cycled = cycle_imported_animation_clip(animated_asset, anim_state, 1)
check("clip cycle succeeds", cycled == true)
check("clip cycle wraps to bounce", anim_state["clip"] == "Bounce")
advance_imported_animation_state(animated_asset, anim_state, 0.5)
check("animation advance updates time", anim_state["time"] > 0.49)
let clamped = step_imported_animation_time(animated_asset, {"clip": "Drop", "playing": false, "time": 1.8, "speed": 1.0, "looping": false}, 0.5)
check("non-looping scrub clamps to duration", clamped > 1.9 and clamped <= 2.0)
let animated_draws = imported_asset_draws(animated_asset, {"clip": "Bounce", "playing": true, "time": 0.5, "speed": 1.0})
check("animated draw entry built", len(animated_draws) == 1)
check("animated draw samples translation", animated_draws[0]["model"][13] > 1.4)

let skinned_asset = {
    "gpu_meshes": [{"gpu_mesh": 31, "material_index": 0, "mesh_index": 0}],
    "nodes": [
        {"name": "SkinnedMesh", "mesh_index": 0, "skin_index": 0, "position": vec3(5.0, 0.0, 0.0), "rotation": [1.0, 0.0, 0.0, 0.0], "scale": vec3(1.0, 1.0, 1.0), "children": [1], "parent": -1},
        {"name": "Hip", "mesh_index": -1, "position": vec3(0.0, 1.0, 0.0), "rotation": [1.0, 0.0, 0.0, 0.0], "scale": vec3(1.0, 1.0, 1.0), "children": [2], "parent": 0},
        {"name": "Hand", "mesh_index": -1, "position": vec3(0.0, 1.0, 0.0), "rotation": [1.0, 0.0, 0.0, 0.0], "scale": vec3(1.0, 1.0, 1.0), "children": [], "parent": 1}
    ],
    "skins": [
        {"name": "Rig", "skeleton": 1, "joints": [1, 2], "joint_names": ["Hip", "Hand"], "inverse_bind_matrices": [mat4_identity(), mat4_identity()], "joint_count": 2}
    ],
    "skin_count": 1,
    "animations": [
        {"name": "Wave", "duration": 1.0, "looping": true, "channels": [
            {"node": 2, "path": "translation", "interpolation": "LINEAR", "times": [0.0, 1.0], "values": [vec3(0.0, 1.0, 0.0), vec3(0.0, 4.0, 0.0)]}
        ]}
    ]
}
let skin_palette = imported_skin_joint_matrices(skinned_asset, 0, 0, nil)
check("skin palette count", len(skin_palette) == 2)
check("skin palette root relative x", math.abs(skin_palette[0][12]) < 0.01)
check("skin palette root relative y", skin_palette[0][13] > 0.9 and skin_palette[0][13] < 1.1)
let skinned_draws = imported_asset_draws(skinned_asset, {"clip": "Wave", "playing": true, "time": 0.5, "speed": 1.0})
check("skinned draw entry built", len(skinned_draws) == 1)
check("skinned draw flagged", skinned_draws[0]["skinned"] == true)
check("skinned draw keeps joint palette", len(skinned_draws[0]["joint_palette"]) == 2)
check("skinned draw animated joint relative y", skinned_draws[0]["joint_palette"][1][13] > 3.4 and skinned_draws[0]["joint_palette"][1][13] < 3.6)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Export pipeline smoke test failed!"
else:
    print "Export pipeline smoke test passed!"
