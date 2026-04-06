gc_disable()
# demo_world.sage - Forge Engine Phase 7 Demo
# Terrain, water, foliage, day/night cycle
#
# Run: ./run.sh examples/demo_world.sage
# Controls:
#   WASD=Move  Mouse=Look  ESC=Capture  SPACE=Jump  SHIFT=Sprint
#   1-4=Time(Dawn/Noon/Dusk/Night)  5=Pause time  F=Fog  Q=Quit

import gpu
import math
import sys
from renderer import create_renderer, begin_frame, end_frame
from renderer import shutdown_renderer, check_resize, update_title_fps
from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, query, register_system, tick_systems
from ecs import flush_dead, entity_count
from components import TransformComponent, NameComponent
from input import create_input, update_input, bind_action
from input import action_held, action_just_pressed
from input import default_fps_bindings
from engine_math import transform_to_matrix
from math3d import vec3, v3_add, v3_scale, mat4_mul, radians
from lighting import create_light_scene, directional_light
from lighting import add_light, set_view_position
from lighting import init_light_gpu, update_light_ubo, set_fog
from render_system import create_lit_material, draw_mesh_lit
from sky import create_sky, init_sky_gpu, draw_sky
from player_controller import create_player_controller, update_player
from player_controller import player_view_matrix, player_eye_position
from player_controller import player_projection, player_forward
from terrain import create_terrain, generate_terrain_noise, upload_terrain
from terrain import sample_height
from water import create_water, upload_water
from foliage import create_scatter_rule, scatter_foliage, foliage_count
from day_night import create_day_cycle, update_day_cycle, set_time_of_day
from day_night import apply_day_cycle_to_sky, apply_day_cycle_to_lighting, get_hour
from mesh import cube_mesh, sphere_mesh, upload_mesh
from game_loop import create_time_state, update_time

print "=== Forge Engine - Phase 7: Terrain & World Demo ==="

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(1280, 720, "Forge Engine - World Demo")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

# ============================================================================
# Lighting & Sky
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
let sun_idx = add_light(ls, directional_light(0.3, -0.8, 0.5, 1.0, 0.95, 0.85, 1.0))

let sky = create_sky()
init_sky_gpu(sky, r["render_pass"])
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])

# ============================================================================
# Day/Night Cycle
# ============================================================================
let day_cycle = create_day_cycle(60.0)
set_time_of_day(day_cycle, 0.35)

# ============================================================================
# Terrain
# ============================================================================
print "Generating terrain..."
let terrain = create_terrain(32, 32, 200.0, 200.0, 15.0)
generate_terrain_noise(terrain, 7.5, 5, 0.5, 2.0, 4.0)
let terrain_gpu = upload_terrain(terrain)
print "Terrain: 32x32 grid, 200x200 world units"

# ============================================================================
# Water
# ============================================================================
let water = create_water(200.0, 16, 3.0)
let water_gpu = upload_water(water, 0.0)
print "Water plane at y=3.0"

# ============================================================================
# Foliage
# ============================================================================
print "Scattering foliage..."
let tree_rule = create_scatter_rule("trees", 0.02, 5.0, 12.0, 0.0, 0.4)
tree_rule["scale_min"] = 0.6
tree_rule["scale_max"] = 1.5
let rock_rule = create_scatter_rule("rocks", 0.03, 3.0, 14.0, 0.0, 0.8)
rock_rule["scale_min"] = 0.3
rock_rule["scale_max"] = 0.8

let foliage_instances = scatter_foliage(terrain, [tree_rule, rock_rule], 42)
print "Foliage: " + str(foliage_count(foliage_instances)) + " instances"

# Upload foliage meshes
let tree_mesh = upload_mesh(cube_mesh())
let rock_mesh = upload_mesh(sphere_mesh(8, 8))

# ============================================================================
# ECS World with foliage entities
# ============================================================================
let world = create_world()

# Foliage as entities (capped for performance)
let max_foliage = 200
let fi = 0
while fi < len(foliage_instances) and fi < max_foliage:
    let inst = foliage_instances[fi]
    let fe = spawn(world)
    let ft = TransformComponent(inst["position"][0], inst["position"][1], inst["position"][2])
    ft["rotation"] = inst["rotation"]
    ft["scale"] = inst["scale"]
    if inst["rule_name"] == "trees":
        ft["scale"][1] = ft["scale"][1] * 2.5
        ft["position"][1] = ft["position"][1] + ft["scale"][1] * 0.5
        add_component(world, fe, "mesh_id", {"mesh": tree_mesh})
    else:
        add_component(world, fe, "mesh_id", {"mesh": rock_mesh})
    add_component(world, fe, "transform", ft)
    fi = fi + 1

print "Scene entities: " + str(entity_count(world))

# ============================================================================
# Input
# ============================================================================
let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "quit", [gpu.KEY_Q])
bind_action(inp, "toggle_capture", [gpu.KEY_ESCAPE])
bind_action(inp, "sprint", [gpu.KEY_SHIFT])
bind_action(inp, "time_dawn", [gpu.KEY_1])
bind_action(inp, "time_noon", [gpu.KEY_2])
bind_action(inp, "time_dusk", [gpu.KEY_3])
bind_action(inp, "time_night", [gpu.KEY_4])
bind_action(inp, "time_pause", [gpu.KEY_5])
bind_action(inp, "toggle_fog", [gpu.KEY_F])

# ============================================================================
# Player
# ============================================================================
let player = create_player_controller()
player["position"] = vec3(0.0, 0.0, 0.0)
# Set player to terrain height
let start_h = sample_height(terrain, 0.0, 0.0)
player["position"][1] = start_h
player["speed"] = 10.0
player["ground_y"] = start_h

# ============================================================================
# Main Loop
# ============================================================================
let ts = create_time_state()
let running = true
let fog_on = false
let water_update_timer = 0.0

print ""
print "Controls: WASD=Move  Mouse=Look  ESC=Capture  SHIFT=Sprint"
print "  1=Dawn 2=Noon 3=Dusk 4=Night 5=Pause time  F=Fog  Q=Quit"
print ""

while running:
    update_time(ts)
    let dt = ts["dt"]
    check_resize(r)
    update_input(inp)

    if action_just_pressed(inp, "quit"):
        running = false
        continue

    # Time controls
    if action_just_pressed(inp, "time_dawn"):
        set_time_of_day(day_cycle, 0.25)
    if action_just_pressed(inp, "time_noon"):
        set_time_of_day(day_cycle, 0.5)
    if action_just_pressed(inp, "time_dusk"):
        set_time_of_day(day_cycle, 0.75)
    if action_just_pressed(inp, "time_night"):
        set_time_of_day(day_cycle, 0.0)
    if action_just_pressed(inp, "time_pause"):
        day_cycle["paused"] = day_cycle["paused"] == false

    if action_just_pressed(inp, "toggle_fog"):
        fog_on = fog_on == false
        set_fog(ls, fog_on, 30.0, 120.0, 0.5, 0.55, 0.6)

    # Player
    update_player(player, inp, dt)
    # Snap to terrain
    let px = player["position"][0]
    let pz = player["position"][2]
    let th = sample_height(terrain, px, pz)
    player["ground_y"] = th

    # Day/night
    update_day_cycle(day_cycle, dt)
    apply_day_cycle_to_sky(day_cycle, sky)
    apply_day_cycle_to_lighting(day_cycle, ls, sun_idx)

    # Update water mesh periodically (every 0.1s for performance)
    water_update_timer = water_update_timer + dt
    if water_update_timer > 0.1:
        water_update_timer = 0.0
        water_gpu = upload_water(water, ts["total"])

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

    # Sky
    draw_sky(sky, cmd, view, aspect, radians(player["fov"]), ts["total"])

    # Terrain
    from math3d import mat4_identity
    let terrain_model = mat4_identity()
    let terrain_mvp = mat4_mul(vp, terrain_model)
    draw_mesh_lit(cmd, lit_mat, terrain_gpu, terrain_mvp, terrain_model, ls["desc_set"])

    # Water
    let water_model = mat4_identity()
    let water_mvp = mat4_mul(vp, water_model)
    draw_mesh_lit(cmd, lit_mat, water_gpu, water_mvp, water_model, ls["desc_set"])

    # Foliage entities
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

    let hour = get_hour(day_cycle)
    let h_str = str(math.floor(hour))
    let title = "Forge Engine | " + h_str + ":00"
    if day_cycle["paused"]:
        title = title + " [PAUSED]"
    update_title_fps(r, title)

gpu.device_wait_idle()
shutdown_renderer(r)
let tf = ts["frame_count"]
let te = ts["total"]
if te > 0:
    print "Frames: " + str(tf) + " (" + str(tf / te) + " FPS)"
print "Demo complete!"
