# demo_voxel_init_only.sage - Just initialization, no main loop
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

print "=== Forge Engine - Voxel Template Sandbox (Init Only) ==="
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
print "Testing one frame..."

update_input(inp)

print "Player yaw before: " + str(player["yaw"])
print "Player pitch before: " + str(player["pitch"])

if action_just_pressed(inp, "escape"):
    print "Escape pressed"

player["position"] = player_pos
let move_dir = vec3(0.0, 0.0, 0.0)

print "Move dir initial: " + str(move_dir)

if action_held(inp, "forward"):
    let pf = player_forward(player)
    print "Player forward: " + str(pf)
    move_dir = v3_add(move_dir, pf)
    print "Move dir after forward: " + str(move_dir)

print "About to check v3_length..."
let move_len = v3_length(move_dir)
print "Move length: " + str(move_len)

if move_len > 0.0:
    print "Normalizing move_dir..."
    move_dir = v3_normalize(move_dir)
    print "Scaling move_dir..."
    let scaled = v3_scale(move_dir, 12.0 * 0.016)
    print "Adding to player_pos..."
    player_pos = v3_add(player_pos, scaled)
    print "Player pos updated"

print "Checking scroll..."
let scroll = scroll_value(inp)
print "Scroll: " + str(scroll)

if scroll != 0.0:
    let scroll_vec = vec3(0.0, scroll * 2.0, 0.0)
    player_pos = v3_add(player_pos, scroll_vec)

print "Checking mouse delta..."
let mdelta = mouse_delta(inp)
print "Mouse delta: " + str(mdelta)

if mdelta[0] != 0.0 or mdelta[1] != 0.0:
    print "Updating yaw and pitch..."
    player["yaw"] = player["yaw"] + mdelta[0] * 0.005
    player["pitch"] = player["pitch"] + mdelta[1] * 0.005

print "Player movement test complete"