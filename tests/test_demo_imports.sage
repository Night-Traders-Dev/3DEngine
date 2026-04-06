import gpu
# import math  # Import at end
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

print "All modules imported successfully"

import math
print "Math imported successfully"

print "Creating voxel world..."
let voxel = create_voxel_world(64, 48, 64)
print "✓ Voxel world created successfully"

print "Creating gameplay state..."
let gameplay = create_voxel_gameplay_state()
print "✓ Gameplay state created successfully"

print "Creating systems..."
let fluids = create_fluid_system()
let biomes = default_biomes()
let weather = create_weather_system()
print "✓ Systems created successfully"

print "Creating inventory..."
let inventory = create_voxel_inventory()
voxel_inventory_add(inventory, 1, 32)
voxel_inventory_add(inventory, 2, 48)
print "✓ Inventory created successfully"

print "Creating tools..."
let basic_hands = create_tool("Bare Hands", 0, -1, 1.0, 0)
let stone_pickaxe = create_tool("Stone Pickaxe", 1, 120, 2.0, 1)
voxel_add_tool(gameplay, basic_hands)
voxel_add_tool(gameplay, stone_pickaxe)
print "✓ Tools created successfully"

print "Setting up player..."
let player = create_player_controller()
let player_pos = vec3(32.0, 30.0, 32.0)
player["position"] = player_pos
print "✓ Player set up successfully"

print "Ensuring mob population..."
ensure_voxel_mob_population(gameplay, player_pos, 64)
print "✓ Mob population ensured successfully"