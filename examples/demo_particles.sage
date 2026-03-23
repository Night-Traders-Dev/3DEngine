# demo_particles.sage - Sage Engine Phase 8 Demo
# Particles, VFX presets, post-processing effects
#
# Run: ./run.sh examples/demo_particles.sage
# Controls:
#   WASD=Move  Mouse=Look  ESC=Capture  SPACE=Jump  SHIFT=Sprint
#   1=Fire 2=Smoke 3=Explosion 4=Rain 5=Magic
#   R=Sparks  E=Shoot  F=Fog  Q=Quit

import gpu
import math
import sys
from renderer import create_renderer, begin_frame, end_frame
from renderer import shutdown_renderer, check_resize, update_title_fps
from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, query, tick_systems, flush_dead
from ecs import entity_count, destroy, add_tag, query_tag
from components import TransformComponent, NameComponent
from input import create_input, update_input, bind_action
from input import action_just_pressed, default_fps_bindings
from engine_math import transform_to_matrix
from math3d import vec3, v3_add, v3_scale, mat4_mul, radians
from mesh import cube_mesh, plane_mesh, sphere_mesh, upload_mesh
from lighting import create_light_scene, directional_light, point_light
from lighting import add_light, set_ambient, set_view_position, set_fog
from lighting import init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit
from sky import create_sky, init_sky_gpu, draw_sky, sky_preset_day
from player_controller import create_player_controller, update_player
from player_controller import player_view_matrix, player_eye_position
from player_controller import player_projection, player_forward
from ui_renderer import create_ui_renderer, draw_ui
from particles import create_particle_system, add_emitter_to_system
from particles import update_particle_system, total_alive_particles
from particles import seed_particles, get_emitter, reset_emitter
from particle_renderer import create_particle_renderer, render_particles
from vfx_presets import vfx_fire, vfx_smoke, vfx_sparks, vfx_explosion
from vfx_presets import vfx_rain, vfx_dust, vfx_magic
from post_fx import create_postfx, pfx_cinematic, pfx_default
from post_fx import build_fade_quad, build_vignette_quads
from hud import create_game_hud, update_game_hud
from gameplay import create_score, add_points, update_score
from game_loop import create_time_state, update_time
from math3d import mat4_identity

print "=== Sage Engine - Phase 8: Particles & VFX Demo ==="

seed_particles(sys.clock() * 1000.0)

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(1280, 720, "Sage Engine - Particles & VFX")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

# ============================================================================
# Lighting & Sky
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.3, -0.7, 0.5, 1.0, 0.95, 0.85, 1.0))
add_light(ls, point_light(5.0, 3.0, 0.0, 1.0, 0.5, 0.2, 3.0, 15.0))
add_light(ls, point_light(-5.0, 3.0, 0.0, 0.2, 0.5, 1.0, 3.0, 15.0))
set_ambient(ls, 0.15, 0.15, 0.2, 0.3)
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])

let sky = create_sky()
sky_preset_day(sky)
init_sky_gpu(sky, r["render_pass"])

# ============================================================================
# UI & Particles
# ============================================================================
let ui_r = create_ui_renderer(r["render_pass"])
let part_r = create_particle_renderer(ui_r)
let hud = create_game_hud()
let postfx = create_postfx()
pfx_cinematic(postfx)

# ============================================================================
# Meshes & World
# ============================================================================
let cube_gpu = upload_mesh(cube_mesh())
let ground_gpu = upload_mesh(plane_mesh(40.0))
let sphere_gpu = upload_mesh(sphere_mesh(16, 16))

let world = create_world()
let ge = spawn(world)
add_component(world, ge, "transform", TransformComponent(0.0, 0.0, 0.0))
add_component(world, ge, "mesh_id", {"mesh": ground_gpu})

# Pillars as fire pedestals
let pi_idx = 0
while pi_idx < 6:
    let pa = (pi_idx / 6) * 6.2831853
    let pe = spawn(world)
    let pt = TransformComponent(math.cos(pa) * 8.0, 0.75, math.sin(pa) * 8.0)
    pt["scale"] = vec3(0.5, 1.5, 0.5)
    add_component(world, pe, "transform", pt)
    add_component(world, pe, "mesh_id", {"mesh": cube_gpu})
    pi_idx = pi_idx + 1

# ============================================================================
# Particle system with all presets
# ============================================================================
let ps = create_particle_system()

# Persistent fire torches
let fi = 0
while fi < 6:
    let fa = (fi / 6) * 6.2831853
    let fp = vec3(math.cos(fa) * 8.0, 1.8, math.sin(fa) * 8.0)
    let fire = vfx_fire(fp, 0.5)
    add_emitter_to_system(ps, "fire_" + str(fi), fire)
    fi = fi + 1

# Center magic
let magic_em = vfx_magic(vec3(0.0, 1.0, 0.0), 0.4, 0.6, 1.0)
add_emitter_to_system(ps, "magic", magic_em)

# Dust
let dust_em = vfx_dust(vec3(3.0, 0.2, 3.0))
add_emitter_to_system(ps, "dust", dust_em)

print "Active emitters: " + str(len(dict_keys(ps["emitters"])))

# ============================================================================
# Input
# ============================================================================
let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "quit", [gpu.KEY_Q])
bind_action(inp, "toggle_capture", [gpu.KEY_ESCAPE])
bind_action(inp, "sprint", [gpu.KEY_SHIFT])
bind_action(inp, "toggle_fog", [gpu.KEY_F])
bind_action(inp, "spawn_fire", [gpu.KEY_1])
bind_action(inp, "spawn_smoke", [gpu.KEY_2])
bind_action(inp, "spawn_explosion", [gpu.KEY_3])
bind_action(inp, "spawn_rain", [gpu.KEY_4])
bind_action(inp, "spawn_magic", [gpu.KEY_5])
bind_action(inp, "spawn_sparks", [gpu.KEY_R])
bind_action(inp, "shoot", [gpu.KEY_E])

let player = create_player_controller()
player["position"] = vec3(0.0, 0.0, 14.0)
player["speed"] = 8.0
let score = create_score()

# ============================================================================
# Main Loop
# ============================================================================
let ts = create_time_state()
let running = true
let fog_on = false
let spawn_counter = 0

print ""
print "Controls: WASD=Move  Mouse=Look  ESC=Capture  SHIFT=Sprint"
print "  1=Fire 2=Smoke 3=Explosion 4=Rain 5=Magic R=Sparks"
print "  E=Shoot  F=Fog  Q=Quit"

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
        set_fog(ls, fog_on, 15.0, 50.0, 0.5, 0.55, 0.6)

    update_player(player, inp, dt)

    # Spawn VFX at look position
    let spawn_pos = v3_add(player_eye_position(player), v3_scale(player_forward(player), 5.0))
    spawn_pos[1] = 0.5

    if action_just_pressed(inp, "spawn_fire"):
        let em = vfx_fire(spawn_pos, 1.0)
        add_emitter_to_system(ps, "fx_" + str(spawn_counter), em)
        spawn_counter = spawn_counter + 1
    if action_just_pressed(inp, "spawn_smoke"):
        let em = vfx_smoke(spawn_pos, 1.0)
        add_emitter_to_system(ps, "fx_" + str(spawn_counter), em)
        spawn_counter = spawn_counter + 1
    if action_just_pressed(inp, "spawn_explosion"):
        let em = vfx_explosion(spawn_pos, 1.5)
        add_emitter_to_system(ps, "fx_" + str(spawn_counter), em)
        spawn_counter = spawn_counter + 1
        add_points(score, 100)
    if action_just_pressed(inp, "spawn_rain"):
        let em = vfx_rain(30.0, 1.0)
        add_emitter_to_system(ps, "fx_" + str(spawn_counter), em)
        spawn_counter = spawn_counter + 1
    if action_just_pressed(inp, "spawn_magic"):
        let em = vfx_magic(spawn_pos, 0.8, 0.2, 1.0)
        add_emitter_to_system(ps, "fx_" + str(spawn_counter), em)
        spawn_counter = spawn_counter + 1
    if action_just_pressed(inp, "spawn_sparks"):
        let em = vfx_sparks(spawn_pos, 50)
        add_emitter_to_system(ps, "fx_" + str(spawn_counter), em)
        spawn_counter = spawn_counter + 1
        add_points(score, 25)

    # Update particles
    update_particle_system(ps, dt)
    update_score(score, dt)

    # Lighting
    set_view_position(ls, player_eye_position(player))
    update_light_ubo(ls)

    # Update HUD
    update_game_hud(hud, 1.0, score["points"], score["combo"], ts["fps"], total_alive_particles(ps))

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

    # 3D meshes
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

    # Render all particle emitters
    let sw = r["width"] + 0.0
    let sh = r["height"] + 0.0
    let em_names = dict_keys(ps["emitters"])
    let ei = 0
    while ei < len(em_names):
        render_particles(part_r, cmd, ps["emitters"][em_names[ei]], vp, sw, sh)
        ei = ei + 1

    # Post-FX overlays (vignette) - rendered via HUD overlay
    # Vignette quads drawn as part of HUD to avoid buffer conflicts

    # HUD
    draw_ui(ui_r, cmd, hud["root"], sw, sh)

    end_frame(r, frame)

    let tp = total_alive_particles(ps)
    let title = "Sage Engine | Particles:" + str(tp)
    title = title + " Score:" + str(score["points"])
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
