gc_disable()
# demo_ui.sage - Forge Engine Phase 6 Demo
# Full HUD: health bar, crosshair, score, info panel, minimap, pause menu
#
# Run: ./run.sh examples/demo_ui.sage
# Controls:
#   WASD=Move  Mouse=Look  ESC=Capture/Pause  SPACE=Jump
#   E=Shoot  R=Spawn AI  F=Fog  Q=Quit

import gpu
import math
import sys
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
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_cross
from math3d import mat4_mul, radians
from mesh import cube_mesh, plane_mesh, sphere_mesh, upload_mesh
from lighting import create_light_scene, point_light, directional_light
from lighting import add_light, set_ambient, set_fog, set_view_position
from lighting import init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit
from sky import create_sky, init_sky_gpu, draw_sky, sky_preset_day
from player_controller import create_player_controller, update_player
from player_controller import player_view_matrix, player_eye_position
from player_controller import player_projection, player_forward
from collision import ray_vs_sphere
from gameplay import HealthComponent, damage, is_dead, health_percent
from gameplay import create_score, add_points, update_score
from navigation import steer_flee, steer_seek
from ui_renderer import create_ui_renderer, draw_ui
from hud import create_game_hud, update_game_hud, update_minimap_dots
from menu import create_menu_system, register_menu, show_menu, hide_menu
from menu import is_menu_visible, update_menu_system, create_pause_menu
from game_loop import create_time_state, update_time

# Simple PRNG
let _rs = [sys.clock() * 1000.0]
proc rand():
    _rs[0] = _rs[0] * 1103515245 + 12345
    _rs[0] = _rs[0] - math.floor(_rs[0] / 2147483648.0) * 2147483648.0
    return _rs[0] / 2147483648.0

print "=== Forge Engine - Phase 6: UI Framework Demo ==="

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(1280, 720, "Forge Engine - UI Demo")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

# ============================================================================
# 3D Setup (lighting, sky, meshes)
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.3, -0.7, 0.5, 1.0, 0.95, 0.85, 1.0))
add_light(ls, point_light(6.0, 3.0, 0.0, 1.0, 0.4, 0.2, 4.0, 20.0))
add_light(ls, point_light(-6.0, 3.0, 0.0, 0.2, 0.4, 1.0, 4.0, 20.0))
set_ambient(ls, 0.15, 0.15, 0.2, 0.3)
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])

let sky = create_sky()
sky_preset_day(sky)
init_sky_gpu(sky, r["render_pass"])

let cube_gpu = upload_mesh(cube_mesh())
let ground_gpu = upload_mesh(plane_mesh(50.0))
let sphere_gpu = upload_mesh(sphere_mesh(16, 16))

# ============================================================================
# UI Setup
# ============================================================================
let ui_renderer = create_ui_renderer(r["render_pass"])
let hud = create_game_hud()

# Player health
let player_health = HealthComponent(100.0)

# Pause menu
let paused = [false]
let quit_flag = [false]

proc on_resume():
    paused[0] = false
    hide_menu(menus)
    gpu.set_cursor_mode(gpu.CURSOR_DISABLED)
    player["captured"] = true

proc on_quit():
    quit_flag[0] = true

let menus = create_menu_system()
let pause_menu = create_pause_menu(on_resume, on_quit)
register_menu(menus, "pause", pause_menu)

# ============================================================================
# World
# ============================================================================
let world = create_world()

let ge = spawn(world)
add_component(world, ge, "transform", TransformComponent(0.0, 0.0, 0.0))
add_component(world, ge, "mesh_id", {"mesh": ground_gpu})

# Pillars
let pi_idx = 0
while pi_idx < 8:
    let pa = (pi_idx / 8) * 6.2831853
    let pe = spawn(world)
    let pt = TransformComponent(math.cos(pa) * 12.0, 1.5, math.sin(pa) * 12.0)
    pt["scale"] = vec3(0.6, 3.0, 0.6)
    add_component(world, pe, "transform", pt)
    add_component(world, pe, "mesh_id", {"mesh": cube_gpu})
    pi_idx = pi_idx + 1

# AI spawner
proc spawn_ai(pos):
    let e = spawn(world)
    add_component(world, e, "transform", TransformComponent(pos[0], 0.5, pos[2]))
    add_component(world, e, "mesh_id", {"mesh": sphere_gpu})
    add_component(world, e, "collider", {"type": "sphere", "radius": 0.5})
    add_component(world, e, "health", HealthComponent(30.0))
    add_tag(world, e, "ai")
    add_tag(world, e, "shootable")
    let ai = {}
    ai["angle"] = rand() * 6.28
    ai["speed"] = 2.0 + rand() * 2.0
    ai["state"] = "wander"
    ai["flee_timer"] = 0.0
    ai["bob"] = rand() * 6.28
    add_component(world, e, "ai_data", ai)
    return e

let si = 0
while si < 6:
    let a = (si / 6) * 6.2831853
    spawn_ai(vec3(math.cos(a) * 8.0, 0.5, math.sin(a) * 8.0))
    si = si + 1

# AI system
proc ai_system(w, entities, dt):
    let i = 0
    while i < len(entities):
        let e = entities[i]
        let t = get_component(w, e, "transform")
        let ai = get_component(w, e, "ai_data")
        ai["bob"] = ai["bob"] + dt * 4.0
        t["position"][1] = 0.5 + math.sin(ai["bob"]) * 0.12
        if ai["state"] == "flee":
            ai["flee_timer"] = ai["flee_timer"] - dt
            if ai["flee_timer"] <= 0.0:
                ai["state"] = "wander"
            else:
                let fv = steer_flee(t["position"], player_eye_position(player), ai["speed"] * 1.5)
                t["position"][0] = t["position"][0] + fv[0] * dt
                t["position"][2] = t["position"][2] + fv[2] * dt
        else:
            ai["angle"] = ai["angle"] + (rand() - 0.5) * 2.0 * dt
            t["position"][0] = t["position"][0] + math.cos(ai["angle"]) * ai["speed"] * dt
            t["position"][2] = t["position"][2] + math.sin(ai["angle"]) * ai["speed"] * dt
            if t["position"][0] > 20.0 or t["position"][0] < -20.0:
                ai["angle"] = ai["angle"] + 3.14
            if t["position"][2] > 20.0 or t["position"][2] < -20.0:
                ai["angle"] = ai["angle"] + 3.14
        t["rotation"][1] = ai["angle"]
        t["dirty"] = true
        i = i + 1

register_system(world, "ai", ["transform", "ai_data"], ai_system)

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
player["position"] = vec3(0.0, 0.0, 16.0)
player["speed"] = 8.0
let score = create_score()

# Shoot
proc shoot_ray():
    let eye = player_eye_position(player)
    let dir = player_forward(player)
    let shootables = query_tag(world, "shootable")
    let closest_t = 999999.0
    let closest_ent = -1
    let i = 0
    while i < len(shootables):
        let eid = shootables[i]
        if has_component(world, eid, "transform") and has_component(world, eid, "collider"):
            let t = get_component(world, eid, "transform")
            let col = get_component(world, eid, "collider")
            let hit = ray_vs_sphere(eye, dir, t["position"], col["radius"])
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
print "Controls: WASD=Move  Mouse=Look  ESC=Pause"
print "  E=Shoot  R=Spawn AI  F=Fog  Q=Quit"
print ""

while running:
    update_time(ts)
    let dt = ts["dt"]
    check_resize(r)
    update_input(inp)

    if quit_flag[0]:
        running = false
        continue
    if action_just_pressed(inp, "quit"):
        running = false
        continue

    # Pause toggle
    if action_just_pressed(inp, "toggle_capture"):
        if paused[0]:
            on_resume()
        else:
            if player["captured"]:
                paused[0] = true
                show_menu(menus, "pause")
                gpu.set_cursor_mode(gpu.CURSOR_NORMAL)
                player["captured"] = false
            else:
                player["captured"] = true
                gpu.set_cursor_mode(gpu.CURSOR_DISABLED)

    update_menu_system(menus, dt)

    if paused[0] == false:
        if action_just_pressed(inp, "toggle_fog"):
            fog_on = fog_on == false
            set_fog(ls, fog_on, 15.0, 60.0, 0.5, 0.55, 0.6)

        update_player(player, inp, dt)

        if action_just_pressed(inp, "spawn_ai"):
            let sp = v3_add(player_eye_position(player), v3_scale(player_forward(player), 5.0))
            spawn_ai(sp)

        if action_just_pressed(inp, "shoot"):
            let hit_ent = shoot_ray()
            if hit_ent >= 0 and has_component(world, hit_ent, "health"):
                let hp = get_component(world, hit_ent, "health")
                damage(hp, 15.0, ts["total"])
                add_points(score, 10)
                if has_component(world, hit_ent, "ai_data"):
                    let ai = get_component(world, hit_ent, "ai_data")
                    ai["state"] = "flee"
                    ai["flee_timer"] = 3.0
                if is_dead(hp):
                    add_points(score, 50)
                    destroy(world, hit_ent)

        tick_systems(world, dt)
        flush_dead(world)
        update_score(score, dt)

    # Update HUD
    let hp_pct = health_percent(player_health)
    let ai_list = query_tag(world, "ai")
    let ai_positions = []
    let ai_i = 0
    while ai_i < len(ai_list):
        if has_component(world, ai_list[ai_i], "transform"):
            let at = get_component(world, ai_list[ai_i], "transform")
            push(ai_positions, at["position"])
        ai_i = ai_i + 1
    update_game_hud(hud, hp_pct, score["points"], score["combo"], ts["fps"], entity_count(world))
    update_minimap_dots(hud["minimap"], player["position"], ai_positions)

    # Lighting
    set_view_position(ls, player_eye_position(player))
    update_light_ubo(ls)

    # --- Render ---
    if gpu.window_should_close():
        running = false
        continue
    let frame = begin_frame(r)
    if frame == nil:
        # Transient resize/minimize/swapchain blip - skip this frame
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

    # Draw UI on top
    let sw = r["width"] + 0.0
    let sh = r["height"] + 0.0
    draw_ui(ui_renderer, cmd, hud["root"], sw, sh)

    # Draw pause menu overlay if visible
    if is_menu_visible(menus) and menus["active_menu"] != nil:
        let active = menus["menus"][menus["active_menu"]]
        draw_ui(ui_renderer, cmd, menus["overlay"], sw, sh)
        draw_ui(ui_renderer, cmd, active, sw, sh)

    end_frame(r, frame)
    update_title_fps(r, "Forge Engine | Score:" + str(score["points"]))

gpu.device_wait_idle()
shutdown_renderer(r)
print ""
print "Final Score: " + str(score["points"])
print "Demo complete!"
