# demo_ai.sage - Sage Engine Phase 5 Demo
# AI entities with behavior trees, pathfinding, steering, tweened animations
#
# Run: ./run.sh examples/demo_ai.sage
# Controls:
#   WASD=Move  Mouse=Look  ESC=Capture  SPACE=Jump
#   E=Shoot  R=Spawn AI  1-4=Sky  F=Fog  Q=Quit

import gpu
import math
import sys

# Simple pseudo-random using time seed
let _rand_state = [sys.clock() * 1000.0]
proc rand():
    _rand_state[0] = _rand_state[0] * 1103515245 + 12345
    # Keep in range to avoid overflow
    _rand_state[0] = _rand_state[0] - math.floor(_rand_state[0] / 2147483648.0) * 2147483648.0
    return (_rand_state[0] / 2147483648.0)
from renderer import create_renderer, begin_frame, end_frame
from renderer import shutdown_renderer, check_resize, update_title_fps
from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, query, register_system, tick_systems
from ecs import flush_dead, destroy, add_tag, query_tag, entity_count
from components import TransformComponent, NameComponent
from input import create_input, update_input, bind_action
from input import action_held, action_just_pressed
from input import mouse_delta, default_fps_bindings
from engine_math import transform_to_matrix, clamp
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize
from math3d import v3_cross, v3_length, v3_dot
from math3d import mat4_perspective, mat4_look_at, mat4_mul, radians
from mesh import cube_mesh, plane_mesh, sphere_mesh, upload_mesh
from lighting import create_light_scene, point_light, directional_light
from lighting import add_light, set_ambient, set_fog, set_view_position
from lighting import init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit
from sky import create_sky, init_sky_gpu, draw_sky, sky_preset_day
from player_controller import create_player_controller, update_player
from player_controller import player_view_matrix, player_eye_position
from player_controller import player_projection, player_forward
from collision import ray_vs_aabb, ray_vs_sphere
from gameplay import HealthComponent, damage, is_dead
from gameplay import create_score, add_points, update_score
from physics import RigidbodyComponent, StaticBodyComponent
from physics import BoxColliderComponent, SphereColliderComponent
from physics import create_physics_world, create_physics_system
from physics import apply_impulse
from navigation import steer_seek, steer_flee, steer_arrive, steer_wander
from behavior_tree import BT_SUCCESS, BT_FAILURE, BT_RUNNING
from behavior_tree import bt_action, bt_condition, bt_sequence, bt_selector
from behavior_tree import bt_wait, bt_tick, bt_reset
from tween import create_tween_manager, create_tween, add_tween
from tween import update_tweens, tween_value
from game_loop import create_time_state, update_time

print "=== Sage Engine - Phase 5: Animation & AI Demo ==="

# ============================================================================
# Renderer & Lighting
# ============================================================================
let r = create_renderer(1280, 720, "Sage Engine - AI Demo")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.3, -0.7, 0.5, 1.0, 0.95, 0.85, 1.0))
add_light(ls, point_light(5.0, 3.0, 0.0, 1.0, 0.4, 0.2, 3.0, 18.0))
add_light(ls, point_light(-5.0, 3.0, 0.0, 0.2, 0.4, 1.0, 3.0, 18.0))
set_ambient(ls, 0.15, 0.15, 0.2, 0.3)

let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])
let sky = create_sky()
sky_preset_day(sky)
init_sky_gpu(sky, r["render_pass"])

# ============================================================================
# Meshes
# ============================================================================
let cube_gpu = upload_mesh(cube_mesh())
let ground_gpu = upload_mesh(plane_mesh(50.0))
let sphere_gpu = upload_mesh(sphere_mesh(16, 16))

# ============================================================================
# Physics & World
# ============================================================================
let pw = create_physics_world()
let physics_fn = create_physics_system(pw)
let world = create_world()
register_system(world, "physics", ["rigidbody", "transform"], physics_fn)

# Ground
let ge = spawn(world)
add_component(world, ge, "transform", TransformComponent(0.0, 0.0, 0.0))
add_component(world, ge, "name", NameComponent("Ground"))
add_component(world, ge, "mesh_id", {"mesh": ground_gpu})
add_component(world, ge, "rigidbody", StaticBodyComponent())

# ============================================================================
# AI entity spawner
# ============================================================================
let ai_count = 0

proc spawn_ai(pos):
    let e = spawn(world)
    add_component(world, e, "transform", TransformComponent(pos[0], pos[1], pos[2]))
    add_component(world, e, "name", NameComponent("AI_" + str(ai_count)))
    add_component(world, e, "mesh_id", {"mesh": sphere_gpu})
    add_component(world, e, "collider", SphereColliderComponent(0.5))
    add_component(world, e, "health", HealthComponent(40.0))
    add_tag(world, e, "ai")
    add_tag(world, e, "shootable")
    # AI state
    let ai_data = {}
    ai_data["wander_angle"] = rand() * 6.28
    ai_data["speed"] = 2.0 + rand() * 2.0
    ai_data["state"] = "wander"
    ai_data["flee_timer"] = 0.0
    ai_data["bob_phase"] = rand() * 6.28
    add_component(world, e, "ai_data", ai_data)
    ai_count = ai_count + 1
    return e

# Spawn initial AI
let si = 0
while si < 8:
    let angle = (si / 8) * 6.2831853
    let sx = math.cos(angle) * 8.0
    let sz = math.sin(angle) * 8.0
    spawn_ai(vec3(sx, 0.5, sz))
    si = si + 1
print "Spawned " + str(ai_count) + " AI entities"

# ============================================================================
# AI System - behavior using steering
# ============================================================================
proc ai_system(w, entities, dt):
    let i = 0
    while i < len(entities):
        let e = entities[i]
        let t = get_component(w, e, "transform")
        let ai = get_component(w, e, "ai_data")
        let pos = t["position"]

        # Bob animation
        ai["bob_phase"] = ai["bob_phase"] + dt * 4.0
        t["position"][1] = 0.5 + math.sin(ai["bob_phase"]) * 0.15

        if ai["state"] == "flee":
            # Flee from player
            ai["flee_timer"] = ai["flee_timer"] - dt
            if ai["flee_timer"] <= 0.0:
                ai["state"] = "wander"
            else:
                let flee_vel = steer_flee(pos, player_eye_position(player), ai["speed"] * 1.5)
                t["position"][0] = t["position"][0] + flee_vel[0] * dt
                t["position"][2] = t["position"][2] + flee_vel[2] * dt
        else:
            # Wander
            ai["wander_angle"] = ai["wander_angle"] + (rand() - 0.5) * 2.0 * dt
            let fwd = vec3(math.cos(ai["wander_angle"]), 0.0, math.sin(ai["wander_angle"]))
            t["position"][0] = t["position"][0] + fwd[0] * ai["speed"] * dt
            t["position"][2] = t["position"][2] + fwd[2] * ai["speed"] * dt
            # Keep in bounds
            if t["position"][0] > 20.0 or t["position"][0] < -20.0:
                ai["wander_angle"] = ai["wander_angle"] + 3.14
            if t["position"][2] > 20.0 or t["position"][2] < -20.0:
                ai["wander_angle"] = ai["wander_angle"] + 3.14

        # Face direction of movement
        t["rotation"][1] = ai["wander_angle"]
        t["dirty"] = true
        i = i + 1

register_system(world, "ai", ["transform", "ai_data"], ai_system)

# ============================================================================
# Tweened pillars (breathing animation)
# ============================================================================
let tweens = create_tween_manager()
let pi_idx = 0
while pi_idx < 6:
    let pa = (pi_idx / 6) * 6.2831853
    let ppx = math.cos(pa) * 14.0
    let ppz = math.sin(pa) * 14.0
    let pe = spawn(world)
    let pt = TransformComponent(ppx, 1.5, ppz)
    pt["scale"] = vec3(0.6, 3.0, 0.6)
    add_component(world, pe, "transform", pt)
    add_component(world, pe, "name", NameComponent("Pillar_" + str(pi_idx)))
    add_component(world, pe, "mesh_id", {"mesh": cube_gpu})
    add_component(world, pe, "rigidbody", StaticBodyComponent())
    # Tween pillar height
    let tw = create_tween(2.5, 4.0, 2.0 + pi_idx * 0.3, "in_out_sine")
    tw["loop"] = true
    tw["ping_pong"] = true
    add_tween(tweens, "pillar_" + str(pi_idx), tw)
    add_component(world, pe, "tween_tag", {"tween_name": "pillar_" + str(pi_idx), "property": "scale_y"})
    pi_idx = pi_idx + 1

# ============================================================================
# Input
# ============================================================================
let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "quit", [gpu.KEY_Q])
bind_action(inp, "toggle_capture", [gpu.KEY_ESCAPE])
bind_action(inp, "spawn_ai", [gpu.KEY_R])
bind_action(inp, "shoot", [gpu.KEY_E])
bind_action(inp, "sprint", [gpu.KEY_SHIFT])
bind_action(inp, "toggle_fog", [gpu.KEY_F])

# ============================================================================
# Player & Score
# ============================================================================
let player = create_player_controller()
player["position"] = vec3(0.0, 0.0, 18.0)
player["speed"] = 8.0
let score = create_score()

# ============================================================================
# Shoot helper
# ============================================================================
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
            if col["type"] == "sphere":
                hit = ray_vs_sphere(origin, direction, pos, col["radius"])
        if hit != nil and hit["t"] < closest_t and hit["t"] > 0.0:
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
print "Controls: WASD=Move  Mouse=Look  ESC=Capture"
print "  E=Shoot  R=Spawn AI  F=Fog  Q=Quit"
print ""

while running:
    update_time(ts)
    let dt = ts["dt"]
    check_resize(r)
    update_input(inp)

    if action_just_pressed(inp, "quit"):
        running = false
        continue

    if action_just_pressed(inp, "toggle_fog"):
        fog_on = fog_on == false
        set_fog(ls, fog_on, 15.0, 60.0, 0.5, 0.55, 0.6)

    update_player(player, inp, dt)

    # Spawn AI
    if action_just_pressed(inp, "spawn_ai"):
        let sp = v3_add(player_eye_position(player), v3_scale(player_forward(player), 5.0))
        sp[1] = 0.5
        spawn_ai(sp)

    # Shoot
    if action_just_pressed(inp, "shoot"):
        let eye = player_eye_position(player)
        let dir = player_forward(player)
        let hit_ent = shoot_ray(eye, dir)
        if hit_ent >= 0 and has_component(world, hit_ent, "health"):
            let hp = get_component(world, hit_ent, "health")
            damage(hp, 20.0, ts["total"])
            add_points(score, 15)
            # Make hit AI flee
            if has_component(world, hit_ent, "ai_data"):
                let ai = get_component(world, hit_ent, "ai_data")
                ai["state"] = "flee"
                ai["flee_timer"] = 3.0
            if is_dead(hp):
                add_points(score, 50)
                destroy(world, hit_ent)

    # Update tweens
    update_tweens(tweens, dt)
    # Apply tween values to pillars
    let tweened = query(world, ["transform", "tween_tag"])
    let ti = 0
    while ti < len(tweened):
        let eid = tweened[ti]
        let t = get_component(world, eid, "transform")
        let tt = get_component(world, eid, "tween_tag")
        let tw = tweens["tweens"][tt["tween_name"]]
        if tw != nil:
            t["scale"][1] = tween_value(tw)
            t["dirty"] = true
        ti = ti + 1

    # ECS tick
    tick_systems(world, dt)
    flush_dead(world)
    update_score(score, dt)

    # Lighting
    set_view_position(ls, player_eye_position(player))
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

    let title = "Sage Engine | Score:" + str(score["points"])
    title = title + " AI:" + str(len(query_tag(world, "ai")))
    update_title_fps(r, title)

gpu.device_wait_idle()
shutdown_renderer(r)
print ""
print "Final Score: " + str(score["points"])
let tf = ts["frame_count"]
let te = ts["total"]
if te > 0:
    print "Frames: " + str(tf) + " (" + str(tf / te) + " FPS)"
print "Demo complete!"
