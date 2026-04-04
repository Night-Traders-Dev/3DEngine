# demo_voxel_fixed.sage - Working voxel demo
# Minecraft-style sandbox with all enhancements

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta, scroll_value
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from player_controller import create_player_controller, player_forward
from voxel_world import create_voxel_world, set_voxel, voxel_block_name
from voxel_world import create_voxel_inventory, voxel_inventory_add
from voxel_world import default_voxel_recipes
from voxel_gameplay import create_tool, create_voxel_gameplay_state, voxel_add_tool
from voxel_gameplay import spawn_voxel_mob, ensure_voxel_mob_population, update_voxel_mobs
from voxel_gameplay import update_voxel_pickups, voxel_alive_mob_count
from voxel_fluids import create_fluid_system
from voxel_biomes import default_biomes
from voxel_weather import create_weather_system, update_weather_system, get_weather_light_modifier
from voxel_mobai import create_behavior_state, update_mob_ai

print "=== Forge Engine - Voxel Sandbox ==="

let r = create_renderer(1280, 720, "Voxel World")
if r == nil:
    raise "Renderer failed"
print "Renderer OK"

let inp = create_input()
default_fps_bindings(inp)

let player = create_player_controller()
let ppos = vec3(32.0, 30.0, 32.0)
player["position"] = ppos

let world = create_voxel_world(64, 48, 64)
let game = create_voxel_gameplay_state()
let fluids = create_fluid_system()
let biomes = default_biomes()
let weather = create_weather_system()

# Add water
let z = 0
while z < 16:
    let x = 20
    while x < 30:
        set_voxel(world, x, 20, z, 14)
        x = x + 1
    z = z + 1

# Add lava  
let z2 = 0
while z2 < 8:
    let x2 = 40
    while x2 < 48:
        set_voxel(world, x2, 15, z2, 15)
        x2 = x2 + 1
    z2 = z2 + 1

ensure_voxel_mob_population(game, ppos, 64)
let i = 0
while i < len(game["mobs"]):
    game["mobs"][i]["behavior"] = create_behavior_state(game["mobs"][i]["type"])
    game["mobs"][i]["patrol_center"] = game["mobs"][i]["position"]
    i = i + 1

print "Mobs: " + str(voxel_alive_mob_count(game))
print ""

let running = true
let frames = 0
let dt = 0.016

while running:
    update_input(inp)
    
    if action_just_pressed(inp, "escape"):
        running = false
    
    player["position"] = ppos
    
    if action_held(inp, "forward"):
        ppos = v3_add(ppos, v3_scale(player_forward(player), 12.0 * dt))
    if action_held(inp, "backward"):
        ppos = v3_add(ppos, v3_scale(player_forward(player), -12.0 * dt))
    if action_held(inp, "left"):
        let right = vec3(-player_forward(player)[2], 0.0, player_forward(player)[0])
        ppos = v3_add(ppos, v3_scale(right, -12.0 * dt))
    if action_held(inp, "right"):
        let right = vec3(-player_forward(player)[2], 0.0, player_forward(player)[0])
        ppos = v3_add(ppos, v3_scale(right, 12.0 * dt))
    
    let scroll = scroll_value(inp)
    if scroll != 0.0:
        ppos = v3_add(ppos, vec3(0.0, scroll * 2.0, 0.0))
    
    let mdelta = mouse_delta(inp)
    player["yaw"] = player["yaw"] + mdelta[0] * 0.005
    player["pitch"] = player["pitch"] + mdelta[1] * 0.005
    
    update_weather_system(weather, dt)
    update_voxel_pickups(game, dt)
    
    let mi = 0
    while mi < len(game["mobs"]):
        if game["mobs"][mi] != nil and not game["mobs"][mi]["dead"]:
            if dict_has(game["mobs"][mi], "behavior"):
                update_mob_ai(game["mobs"][mi], game["mobs"][mi]["behavior"], ppos, dt)
        mi = mi + 1
    update_voxel_mobs(game, ppos, dt)
    
    if frames % 120 == 0:
        ensure_voxel_mob_population(game, ppos, 64)
    
    let frame = begin_frame(r)
    if frame == nil:
        frames = frames + 1
        continue
    
    let wmod = get_weather_light_modifier(weather)
    gpu.clear_color(0.52 * wmod, 0.76 * wmod, 0.95 * wmod, 1.0)
    gpu.clear()
    
    update_title_fps(r, "Voxel [F|B|W|AI] Mobs:" + str(voxel_alive_mob_count(game)))
    
    end_frame(r, frame)
    frames = frames + 1
    check_resize(r)

print "Complete | Frames: " + str(frames) + " | Mobs: " + str(voxel_alive_mob_count(game))
shutdown_renderer(r)
