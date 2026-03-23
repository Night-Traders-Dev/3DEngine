# demo_assets.sage - Forge Engine Phase 4 Demo
# Asset manager, scene save/load, audio system
#
# Run: ./run.sh examples/demo_assets.sage
# Controls:
#   WASD=Move  Mouse=Look  ESC=Capture  SPACE=Jump  SHIFT=Sprint
#   R=Spawn cube  E=Shoot  5=Save scene  F=Fog  Q=Quit
#   1=Day 2=Sunset 3=Night 4=Overcast

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame
from renderer import shutdown_renderer, check_resize, update_title_fps
from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, query, register_system, tick_systems
from ecs import flush_dead, destroy, add_tag, query_tag, entity_count
from components import TransformComponent, VelocityComponent, NameComponent
from input import create_input, update_input, bind_action
from input import action_held, action_just_pressed
from input import mouse_delta, default_fps_bindings
from engine_math import transform_to_matrix, clamp
from math3d import vec3, v3_add, v3_scale, v3_normalize, v3_cross
from math3d import mat4_perspective, mat4_look_at, mat4_mul, radians
from math3d import pack_mvp
from lighting import create_light_scene, point_light, directional_light
from lighting import add_light, set_ambient, set_fog, set_view_position
from lighting import init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit
from sky import create_sky, init_sky_gpu, draw_sky
from sky import sky_preset_day, sky_preset_sunset
from sky import sky_preset_night, sky_preset_overcast
from player_controller import create_player_controller, update_player
from player_controller import player_view_matrix, player_eye_position
from player_controller import player_projection, player_forward
from physics import RigidbodyComponent, StaticBodyComponent
from physics import BoxColliderComponent, SphereColliderComponent
from physics import create_physics_world, create_physics_system
from physics import apply_impulse
from collision import ray_vs_aabb, ray_vs_sphere
from gameplay import HealthComponent, damage, is_dead
from gameplay import create_score, add_points, update_score
from asset_manager import create_asset_manager, load_mesh, get_mesh
from asset_manager import print_asset_stats
from scene_serial import save_scene
from audio import create_audio_manager, update_listener
from audio import set_channel_volume, shutdown_audio
from game_loop import create_time_state, update_time

print "=== Forge Engine - Phase 4: Content Pipeline Demo ==="

# ============================================================================
# Asset Manager - load all meshes through it
# ============================================================================
let assets = create_asset_manager()
print "Asset manager created"

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(1280, 720, "Forge Engine - Content Pipeline")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

# ============================================================================
# Load meshes via asset manager
# ============================================================================
let cube_gpu = load_mesh(assets, "cube", "primitive:cube")
let ground_gpu = load_mesh(assets, "ground", "primitive:plane_large")
let sphere_gpu = load_mesh(assets, "sphere", "primitive:sphere")
let pillar_gpu = load_mesh(assets, "pillar", "primitive:cube")

# Cache hit test
let cube_again = load_mesh(assets, "cube", "primitive:cube")
print_asset_stats(assets)

# ============================================================================
# Audio (graceful if unavailable)
# ============================================================================
let audio = create_audio_manager()

# ============================================================================
# Lighting
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.4, -0.7, 0.3, 1.0, 0.95, 0.85, 1.0))
add_light(ls, point_light(6.0, 3.0, 2.0, 1.0, 0.5, 0.2, 4.0, 20.0))
add_light(ls, point_light(-6.0, 3.0, -2.0, 0.2, 0.5, 1.0, 4.0, 20.0))
add_light(ls, point_light(0.0, 4.0, 0.0, 0.9, 0.9, 0.8, 2.0, 15.0))
set_ambient(ls, 0.12, 0.12, 0.18, 0.3)

let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])

# ============================================================================
# Sky
# ============================================================================
let sky = create_sky()
sky_preset_day(sky)
init_sky_gpu(sky, r["render_pass"])

# ============================================================================
# Physics
# ============================================================================
let pw = create_physics_world()
let physics_fn = create_physics_system(pw)

# ============================================================================
# Build scene
# ============================================================================
let world = create_world()
register_system(world, "physics", ["rigidbody", "transform"], physics_fn)

# Ground
let ge = spawn(world)
add_component(world, ge, "transform", TransformComponent(0.0, 0.0, 0.0))
add_component(world, ge, "name", NameComponent("Ground"))
add_component(world, ge, "mesh_id", {"mesh": ground_gpu, "name": "ground"})
add_component(world, ge, "rigidbody", StaticBodyComponent())
add_component(world, ge, "collider", BoxColliderComponent(20.0, 0.1, 20.0))

# Pillars in a ring
let pi_count = 8
let pi_idx = 0
while pi_idx < pi_count:
    let pa = (pi_idx / pi_count) * 6.2831853
    let ppx = math.cos(pa) * 10.0
    let ppz = math.sin(pa) * 10.0
    let pe = spawn(world)
    let pt = TransformComponent(ppx, 1.5, ppz)
    pt["scale"] = vec3(0.6, 3.0, 0.6)
    add_component(world, pe, "transform", pt)
    add_component(world, pe, "name", NameComponent("Pillar_" + str(pi_idx)))
    add_component(world, pe, "mesh_id", {"mesh": pillar_gpu, "name": "pillar"})
    add_component(world, pe, "rigidbody", StaticBodyComponent())
    add_component(world, pe, "collider", BoxColliderComponent(0.3, 1.5, 0.3))
    add_tag(world, pe, "shootable")
    add_component(world, pe, "health", HealthComponent(80.0))
    pi_idx = pi_idx + 1

# Physics cubes
let ci = 0
while ci < 10:
    let ca = (ci / 10) * 6.2831853
    let ccx = math.cos(ca) * 5.0
    let ccz = math.sin(ca) * 5.0
    let ce = spawn(world)
    add_component(world, ce, "transform", TransformComponent(ccx, 4.0 + ci * 0.5, ccz))
    let crb = RigidbodyComponent(1.0)
    crb["restitution"] = 0.4
    add_component(world, ce, "rigidbody", crb)
    add_component(world, ce, "collider", BoxColliderComponent(0.5, 0.5, 0.5))
    add_component(world, ce, "name", NameComponent("Crate_" + str(ci)))
    add_component(world, ce, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
    add_tag(world, ce, "shootable")
    add_component(world, ce, "health", HealthComponent(25.0))
    ci = ci + 1

# Spheres
let si = 0
while si < 5:
    let sa = (si / 5) * 6.2831853
    let ssx = math.cos(sa) * 7.0
    let ssz = math.sin(sa) * 7.0
    let se = spawn(world)
    add_component(world, se, "transform", TransformComponent(ssx, 6.0, ssz))
    let srb = RigidbodyComponent(1.5)
    srb["restitution"] = 0.6
    add_component(world, se, "rigidbody", srb)
    add_component(world, se, "collider", SphereColliderComponent(0.5))
    add_component(world, se, "name", NameComponent("Ball_" + str(si)))
    add_component(world, se, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})
    add_tag(world, se, "shootable")
    add_component(world, se, "health", HealthComponent(15.0))
    si = si + 1

print "Scene: " + str(entity_count(world)) + " entities"

# ============================================================================
# Input
# ============================================================================
let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "quit", [gpu.KEY_Q])
bind_action(inp, "toggle_capture", [gpu.KEY_ESCAPE])
bind_action(inp, "spawn_cube", [gpu.KEY_R])
bind_action(inp, "shoot", [gpu.KEY_E])
bind_action(inp, "sprint", [gpu.KEY_SHIFT])
bind_action(inp, "save_scene", [gpu.KEY_5])
bind_action(inp, "preset_day", [gpu.KEY_1])
bind_action(inp, "preset_sunset", [gpu.KEY_2])
bind_action(inp, "preset_night", [gpu.KEY_3])
bind_action(inp, "preset_overcast", [gpu.KEY_4])
bind_action(inp, "toggle_fog", [gpu.KEY_F])

# ============================================================================
# Player & Score
# ============================================================================
let player = create_player_controller()
player["position"] = vec3(0.0, 0.0, 15.0)
player["speed"] = 8.0
let score = create_score()

# ============================================================================
# Helpers
# ============================================================================
proc spawn_physics_cube(pos):
    let e = spawn(world)
    add_component(world, e, "transform", TransformComponent(pos[0], pos[1], pos[2]))
    let rb = RigidbodyComponent(1.5)
    rb["restitution"] = 0.4
    add_component(world, e, "rigidbody", rb)
    add_component(world, e, "collider", BoxColliderComponent(0.5, 0.5, 0.5))
    add_component(world, e, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
    add_tag(world, e, "shootable")
    add_component(world, e, "health", HealthComponent(20.0))

proc shoot_ray(origin, direction):
    let shootables = query_tag(world, "shootable")
    let closest_t = 999999.0
    let closest_ent = -1
    let i = 0
    while i < len(shootables):
        let eid = shootables[i]
        if has_component(world, eid, "transform") == false:
            i = i + 1
            continue
        let t = get_component(world, eid, "transform")
        let pos = t["position"]
        let hit = nil
        if has_component(world, eid, "collider"):
            let col = get_component(world, eid, "collider")
            if col["type"] == "aabb":
                hit = ray_vs_aabb(origin, direction, pos, col["half"])
            if col["type"] == "sphere":
                hit = ray_vs_sphere(origin, direction, pos, col["radius"])
        if hit != nil:
            if hit["t"] < closest_t and hit["t"] > 0.0:
                closest_t = hit["t"]
                closest_ent = eid
        i = i + 1
    return closest_ent

# ============================================================================
# Main Loop
# ============================================================================
let ts = create_time_state()
let running = true
let fog_on = false

print ""
print "Controls:"
print "  WASD=Move  Mouse=Look  ESC=Capture  SPACE=Jump"
print "  E=Shoot  R=Spawn cube  5=Save scene"
print "  1-4=Sky  F=Fog  Q=Quit"
print ""

while running:
    update_time(ts)
    let dt = ts["dt"]
    check_resize(r)
    update_input(inp)

    if action_just_pressed(inp, "quit"):
        running = false
        continue

    # Sky presets
    if action_just_pressed(inp, "preset_day"):
        sky_preset_day(sky)
        set_ambient(ls, 0.12, 0.12, 0.18, 0.3)
    if action_just_pressed(inp, "preset_sunset"):
        sky_preset_sunset(sky)
        set_ambient(ls, 0.2, 0.12, 0.08, 0.2)
    if action_just_pressed(inp, "preset_night"):
        sky_preset_night(sky)
        set_ambient(ls, 0.02, 0.02, 0.05, 0.1)
    if action_just_pressed(inp, "preset_overcast"):
        sky_preset_overcast(sky)
        set_ambient(ls, 0.25, 0.25, 0.28, 0.4)
    if action_just_pressed(inp, "toggle_fog"):
        fog_on = fog_on == false
        set_fog(ls, fog_on, 20.0, 80.0, 0.6, 0.65, 0.7)

    # Player
    update_player(player, inp, dt)

    # Spawn
    if action_just_pressed(inp, "spawn_cube"):
        let sp = v3_add(player_eye_position(player), v3_scale(player_forward(player), 3.0))
        sp[1] = sp[1] + 2.0
        spawn_physics_cube(sp)

    # Shoot
    if action_just_pressed(inp, "shoot"):
        let eye = player_eye_position(player)
        let dir = player_forward(player)
        let hit_ent = shoot_ray(eye, dir)
        if hit_ent >= 0 and has_component(world, hit_ent, "health"):
            let hp = get_component(world, hit_ent, "health")
            damage(hp, 15.0, ts["total"])
            add_points(score, 10)
            if has_component(world, hit_ent, "rigidbody"):
                apply_impulse(get_component(world, hit_ent, "rigidbody"), v3_scale(dir, 8.0))
            if is_dead(hp):
                destroy(world, hit_ent)

    # Save scene
    if action_just_pressed(inp, "save_scene"):
        save_scene(world, "DemoScene", "assets/saved_scene.json")
        print_asset_stats(assets)

    # Physics & ECS
    tick_systems(world, dt)
    flush_dead(world)
    update_score(score, dt)

    # Audio listener
    let eye_pos = player_eye_position(player)
    update_listener(audio, eye_pos, player_forward(player), vec3(0.0, 1.0, 0.0))

    # Lighting
    set_view_position(ls, eye_pos)
    # Animate a light
    let al = ls["lights"][1]
    al["position"][0] = math.cos(ts["total"] * 0.5) * 7.0
    al["position"][2] = math.sin(ts["total"] * 0.5) * 7.0
    ls["dirty"] = true
    update_light_ubo(ls)

    # --- Render ---
    let frame = begin_frame(r)
    if frame == nil:
        running = false
        continue
    let cmd = frame["cmd"]

    let view = player_view_matrix(player)
    let aspect = r["width"] / r["height"]
    let proj = player_projection(player, aspect)
    let vp = mat4_mul(proj, view)

    draw_sky(sky, cmd, view, aspect, radians(player["fov"]), ts["total"])

    let renderers = query(world, ["transform", "mesh_id"])
    let ri = 0
    while ri < len(renderers):
        let eid = renderers[ri]
        let t = get_component(world, eid, "transform")
        let mi = get_component(world, eid, "mesh_id")
        let model = transform_to_matrix(t)
        let mvp = mat4_mul(vp, model)
        draw_mesh_lit(cmd, lit_mat, mi["mesh"], mvp, model, ls["desc_set"])
        ri = ri + 1

    end_frame(r, frame)

    let title = "Forge Engine | Score:" + str(score["points"])
    title = title + " Entities:" + str(entity_count(world))
    update_title_fps(r, title)

# Shutdown
shutdown_audio(audio)
gpu.device_wait_idle()
shutdown_renderer(r)
print ""
print "Final Score: " + str(score["points"])
print_asset_stats(assets)
let tf = ts["frame_count"]
let te = ts["total"]
if te > 0:
    print "Frames: " + str(tf) + " (" + str(tf / te) + " FPS)"
print "Demo complete!"
