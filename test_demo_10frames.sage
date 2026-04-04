# Quick test to see if demo outputs start correctly
import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta, scroll_value
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from player_controller import create_player_controller, player_forward
from voxel_world import create_voxel_world, set_voxel, get_voxel, voxel_palette_ids, voxel_block_name
from voxel_world import create_voxel_inventory, voxel_inventory_add, voxel_inventory_remove, voxel_inventory_count
from voxel_world import default_voxel_recipes, try_craft_voxel_recipe
from voxel_hud import create_voxel_hud, update_voxel_hud
from voxel_gameplay import create_tool, create_voxel_gameplay_state, voxel_add_tool
from voxel_gameplay import spawn_voxel_mob, ensure_voxel_mob_population, update_voxel_mobs
from voxel_gameplay import update_voxel_pickups, voxel_alive_mob_count
from voxel_fluids import create_fluid_system
from voxel_biomes import default_biomes
from voxel_weather import create_weather_system, update_weather_system, get_weather_light_modifier
from voxel_mobai import create_behavior_state, update_mob_ai

print "=== Forge Engine - Voxel Template Sandbox ==="
print "With: Fluid Physics | Biome System | Dynamic Weather | Advanced Mob AI"
print ""

# Initialize systems
let r = create_renderer(1280, 720, "Forge Engine - Voxel Template")
if r == nil:
    raise "Failed to create renderer"
print "✓ Renderer: " + str(r["width"]) + "x" + str(r["height"]) + " | GPU: " + gpu.device_name()

let inp = create_input()
default_fps_bindings(inp)

let player = create_player_controller()
let player_pos = vec3(32.0, 30.0, 32.0)
player["position"] = player_pos

let voxel = create_voxel_world(64, 48, 64)
let gameplay = create_voxel_gameplay_state()
let fluids = create_fluid_system()
let biomes = default_biomes()
let weather = create_weather_system()

let inventory = create_voxel_inventory()
voxel_inventory_add(inventory, 1, 32)
voxel_inventory_add(inventory, 2, 48)

let basic_hands = create_tool("Bare Hands", 0, -1, 1.0, 0)
let stone_pickaxe = create_tool("Stone Pickaxe", 1, 120, 2.0, 1)
voxel_add_tool(gameplay, basic_hands)
voxel_add_tool(gameplay, stone_pickaxe)

# Generate terrain
let wz = 0
while wz < 16:
    let wx = 20
    while wx < 30:
        set_voxel(voxel, wx, 20, wz, 14)
        wx = wx + 1
    wz = wz + 1

let lz = 0
while lz < 8:
    let lx = 40
    while lx < 48:
        set_voxel(voxel, lx, 15, lz, 15)
        lx = lx + 1
    lz = lz + 1

ensure_voxel_mob_population(gameplay, player_pos, 64)
let i = 0
while i < len(gameplay["mobs"]):
    if gameplay["mobs"][i] != nil:
        gameplay["mobs"][i]["behavior"] = create_behavior_state(gameplay["mobs"][i]["type"])
        gameplay["mobs"][i]["patrol_center"] = gameplay["mobs"][i]["position"]
    i = i + 1

print "✓ World: 64x48x64 | Mobs: " + str(voxel_alive_mob_count(gameplay))
print "✓ Fluids: Water & Lava | Biomes: Plains, Forest, Desert, Mountains, Swamp"
print "✓ Weather: Dynamic transitions | Mob AI: Advanced behavior trees"
print ""
print "Controls: WASD=Move | Mouse=Look | Scroll=Up/Down | ESC=Quit"
print ""

let running = true
let frame_count = 0
let dt = 0.016
let max_frames = 10  # Just run 10 frames for testing

while running and frame_count < max_frames:
    update_input(inp)
    
    if action_just_pressed(inp, "escape"):
        running = false
        print "ESC pressed, stopping..."
    
    player["position"] = player_pos
    let move_dir = vec3(0.0, 0.0, 0.0)
    
    if action_held(inp, "forward"):
        move_dir = v3_add(move_dir, player_forward(player))
    if action_held(inp, "backward"):
        move_dir = v3_add(move_dir, v3_scale(player_forward(player), -1.0))
    if action_held(inp, "left"):
        let right = vec3(-player_forward(player)[2], 0.0, player_forward(player)[0])
        move_dir = v3_add(move_dir, v3_scale(right, -1.0))
    if action_held(inp, "right"):
        let right = vec3(-player_forward(player)[2], 0.0, player_forward(player)[0])
        move_dir = v3_add(move_dir, right)
    
    if v3_length(move_dir) > 0.0:
        move_dir = v3_normalize(move_dir)
        player_pos = v3_add(player_pos, v3_scale(move_dir, 12.0 * dt))
    
    let scroll = scroll_value(inp)
    if scroll[1] != 0.0:
        player_pos = v3_add(player_pos, vec3(0.0, scroll[1] * 2.0, 0.0))
    
    let mdelta = mouse_delta(inp)
    if mdelta[0] != 0.0 or mdelta[1] != 0.0:
        player["yaw"] = player["yaw"] + mdelta[0] * 0.005
        player["pitch"] = player["pitch"] + mdelta[1] * 0.005
    
    # Temporarily disable heavy updates to prevent freeze
    # update_weather_system(weather, dt)
    # update_voxel_pickups(gameplay, dt)
    
    # let mi = 0
    # while mi < len(gameplay["mobs"]):
    #     if gameplay["mobs"][mi] != nil and not gameplay["mobs"][mi]["dead"]:
    #         if dict_has(gameplay["mobs"][mi], "behavior"):
    #             update_mob_ai(gameplay["mobs"][mi], gameplay["mobs"][mi]["behavior"], player_pos, dt)
    #     mi = mi + 1
    # update_voxel_mobs(gameplay, player_pos, dt)
    
    # if frame_count % 120 == 0:
    #     ensure_voxel_mob_population(gameplay, player_pos, 64)
    
    let frame = begin_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        continue
    
    update_title_fps(r, "Voxel Sandbox [Fluids|Biomes|Weather|AI] Mobs:" + str(voxel_alive_mob_count(gameplay)))
    
    end_frame(r, frame)
    
    frame_count = frame_count + 1
    check_resize(r)

print ""
print "Session Complete | Frames: " + str(frame_count) + " | Mobs: " + str(voxel_alive_mob_count(gameplay))

shutdown_renderer(r)
print "✓ Demo closed"