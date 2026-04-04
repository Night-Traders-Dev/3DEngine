# voxel_game_template.sage - Template for creating voxel-based games
# Copy this file and customize it for your voxel game project

import gpu
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

import math  # Import math after voxel modules

# ============================================================================
# GAME CONFIGURATION - Customize these values for your game
# ============================================================================

let GAME_TITLE = "My Voxel Game"
let WORLD_SIZE_X = 64
let WORLD_SIZE_Y = 48
let WORLD_SIZE_Z = 64
let INITIAL_PLAYER_POS = vec3(32.0, 30.0, 32.0)
let MAX_MOBS = 16
let ENABLE_WEATHER = true
let ENABLE_FLUIDS = true
let ENABLE_MOBS = true

# ============================================================================
# INITIALIZATION
# ============================================================================

print "=== " + GAME_TITLE + " ==="
print "Initializing game systems..."
print ""

let r = create_renderer(1280, 720, GAME_TITLE)
if r == nil:
    raise "Failed to create renderer"
print "✓ Renderer: " + str(r["width"]) + "x" + str(r["height"]) + " | GPU: " + gpu.device_name()

let inp = create_input()
default_fps_bindings(inp)

let player = create_player_controller()
let player_pos = INITIAL_PLAYER_POS
player["position"] = player_pos

# Create voxel world
let voxel = create_voxel_world(WORLD_SIZE_X, WORLD_SIZE_Y, WORLD_SIZE_Z)
print "✓ World: " + str(WORLD_SIZE_X) + "x" + str(WORLD_SIZE_Y) + "x" + str(WORLD_SIZE_Z)

# Initialize game systems
let gameplay = create_voxel_gameplay_state()
let inventory = create_voxel_inventory()

# Add starting items
voxel_inventory_add(inventory, 1, 32)  # Dirt blocks
voxel_inventory_add(inventory, 2, 16)  # Stone blocks

# Add tools
let basic_hands = create_tool("Bare Hands", 0, -1, 1.0, 0)
let stone_pickaxe = create_tool("Stone Pickaxe", 1, 120, 2.0, 1)
voxel_add_tool(gameplay, basic_hands)
voxel_add_tool(gameplay, stone_pickaxe)

# Initialize optional systems
let fluids = nil
if ENABLE_FLUIDS:
    fluids = create_fluid_system()
    print "✓ Fluid physics enabled"

let biomes = default_biomes()
print "✓ Biomes loaded: " + str(len(biomes))

let weather = nil
if ENABLE_WEATHER:
    weather = create_weather_system()
    print "✓ Weather system enabled"

# ============================================================================
# WORLD GENERATION - Customize terrain generation here
# ============================================================================

proc generate_world(world):
    print "Generating world..."

    # Example: Create a simple platform
    let z = 10
    while z < 20:
        let x = 10
        while x < 20:
            set_voxel(world, x, 15, z, 2)  # Stone platform
            x = x + 1
        z = z + 1

    # Example: Add some trees
    generate_tree(world, 25, 16, 25)
    generate_tree(world, 40, 16, 40)

    print "✓ World generation complete"

proc generate_tree(world, x, y, z):
    # Tree trunk
    let height = 4
    let h = 0
    while h < height:
        set_voxel(world, x, y + h, z, 5)  # Wood
        h = h + 1

    # Tree leaves
    let leaf_y = y + height - 1
    let lz = z - 2
    while lz <= z + 2:
        let lx = x - 2
        while lx <= x + 2:
            if lx != x or lz != z:  # Don't overwrite trunk
                set_voxel(world, lx, leaf_y, lz, 6)  # Leaves
            lx = lx + 1
        lz = lz + 1

# Generate the initial world
generate_world(voxel)

# ============================================================================
# GAME LOOP
# ============================================================================

if ENABLE_MOBS:
    ensure_voxel_mob_population(gameplay, player_pos, MAX_MOBS)
    # Add AI to mobs
    let i = 0
    while i < len(gameplay["mobs"]):
        if gameplay["mobs"][i] != nil:
            gameplay["mobs"][i]["behavior"] = create_behavior_state(gameplay["mobs"][i]["type"])
            gameplay["mobs"][i]["patrol_center"] = gameplay["mobs"][i]["position"]
        i = i + 1
    print "✓ Mobs spawned: " + str(voxel_alive_mob_count(gameplay))

print ""
print "Controls: WASD=Move | Mouse=Look | Scroll=Up/Down | ESC=Quit"
print "Starting game loop..."
print ""

let running = true
let frame_count = 0
let dt = 0.016

while running:
    update_input(inp)

    if action_just_pressed(inp, "escape"):
        running = false

    # Update player position
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

    # Handle vertical movement
    let scroll = scroll_value(inp)
    if scroll[1] != 0.0:
        player_pos = v3_add(player_pos, vec3(0.0, scroll[1] * 2.0, 0.0))

    # Handle mouse look
    let mdelta = mouse_delta(inp)
    if mdelta[0] != 0.0 or mdelta[1] != 0.0:
        player["yaw"] = player["yaw"] + mdelta[0] * 0.005
        player["pitch"] = player["pitch"] + mdelta[1] * 0.005

    # Update game systems
    if ENABLE_WEATHER:
        update_weather_system(weather, dt)

    update_voxel_pickups(gameplay, dt)

    if ENABLE_MOBS:
        # Update mob AI
        let mi = 0
        while mi < len(gameplay["mobs"]):
            if gameplay["mobs"][mi] != nil and not gameplay["mobs"][mi]["dead"]:
                if dict_has(gameplay["mobs"][mi], "behavior"):
                    update_mob_ai(gameplay["mobs"][mi], gameplay["mobs"][mi]["behavior"], player_pos, dt)
            mi = mi + 1
        update_voxel_mobs(gameplay, player_pos, dt)

        # Maintain mob population
        if frame_count % 300 == 0:  # Every 5 seconds at 60fps
            ensure_voxel_mob_population(gameplay, player_pos, MAX_MOBS)

    # ============================================================================
    # RENDERING - Customize rendering here
    # ============================================================================

    let frame = begin_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        continue

    # Set sky color based on weather
    let weather_mod = ENABLE_WEATHER ? get_weather_light_modifier(weather) : 1.0
    gpu.clear_color(0.52 * weather_mod, 0.76 * weather_mod, 0.95 * weather_mod, 1.0)
    gpu.clear()

    # Update window title with game stats
    let mob_count = ENABLE_MOBS ? voxel_alive_mob_count(gameplay) : 0
    update_title_fps(r, GAME_TITLE + " | Mobs: " + str(mob_count))

    # TODO: Add your custom rendering code here
    # - Render voxel world
    # - Render HUD/UI
    # - Render particles/effects

    end_frame(r, frame)

    frame_count = frame_count + 1
    check_resize(r)

# ============================================================================
# SHUTDOWN
# ============================================================================

print ""
print "Game Over | Frames: " + str(frame_count)
if ENABLE_MOBS:
    print "Final mob count: " + str(voxel_alive_mob_count(gameplay))

shutdown_renderer(r)
print "✓ Game closed successfully"