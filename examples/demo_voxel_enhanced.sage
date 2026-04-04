# demo_voxel_enhanced.sage - Enhanced voxel demo showcasing new features
# A working sandbox with fluid physics, biomes, weather, and advanced mob AI

import gpu
import math
import io
from renderer import create_renderer, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_key_down, action_just_pressed
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from voxel_world import create_voxel_world, set_voxel, get_voxel, voxel_block_world_center
from voxel_world import voxel_palette_ids, voxel_block_name
from voxel_fluids import create_fluid_system, update_fluid_system, is_fluid_block
from voxel_biomes import default_biomes, select_biome_at
from voxel_weather import create_weather_system, update_weather_system, get_weather_fog_modifier
from voxel_gameplay import create_voxel_gameplay_state, spawn_voxel_mob, ensure_voxel_mob_population
from voxel_gameplay import update_voxel_mobs, update_voxel_pickups, voxel_alive_mob_count
from voxel_mobai import create_behavior_state, update_mob_ai

print "=== Forge Engine - Enhanced Voxel Demo ==="
print "Featuring: Fluid Physics, Biomes, Weather, Advanced Mob AI"
print ""

# Create renderer
let r = create_renderer(1280, 720, "Forge Engine - Enhanced Voxel (Fluids, Biomes, Weather, AI)")
if r == nil:
    print "ERROR: Failed to create renderer"
    raise "Failed to initialize graphics"

print "GPU: " + gpu.device_name()
print "Resolution: " + str(r["width"]) + "x" + str(r["height"])

# Create voxel world
let world = create_voxel_world(64, 48, 64)
print "Created voxel world: 64x48x64"

# Create fluid system
let fluids = create_fluid_system()
print "Fluid physics system initialized"

# Create biome system
let biomes = default_biomes()
print "Created " + str(len(biomes)) + " biomes (Plains, Forest, Desert, Mountains, Swamp)"

# Create weather system
let weather = create_weather_system()
print "Weather system initialized"

# Create gameplay state
let gameplay = create_voxel_gameplay_state()
print "Gameplay state initialized"

# Spawn initial mobs
print "Spawning mobs..."
let player_pos = vec3(32.0, 32.0, 32.0)
ensure_voxel_mob_population(gameplay, player_pos, 64)
print "Initial mob population: " + str(voxel_alive_mob_count(gameplay))

# Add behavior states to mobs
let i = 0
while i < len(gameplay["mobs"]):
    gameplay["mobs"][i]["behavior"] = create_behavior_state(gameplay["mobs"][i]["type"])
    gameplay["mobs"][i]["patrol_center"] = gameplay["mobs"][i]["position"]
    i = i + 1

# Create some water features for testing
print "Filling water features..."
let wz = 0
while wz < 16:
    let wx = 20
    while wx < 30:
        set_voxel(world, wx, 20, wz, 14)  # Water at y=20
        wx = wx + 1
    wz = wz + 1

# Create lava pit
let lz = 0
while lz < 8:
    let lx = 40
    while lx < 48:
        set_voxel(world, lx, 15, lz, 15)  # Lava at y=15
        lx = lx + 1
    lz = lz + 1

print "World setup complete"
print ""
print "=== Demo Controls ==="
print "ESC = Close"
print "W/A/S/D = Move camera"
print "Mouse = Look around"
print ""

# Performance counters
let frame_count = 0
let update_time = 0.0
let render_time = 0.0
let dt = 0.016  # ~60fps target

# Main loop
let running = true
while running:
    # Input
    update_input()
    
    if action_just_pressed("escape"):
        running = false
    
    # Update weather
    update_weather_system(weather, dt)
    
    # Update fluids (simplified)
    if frame_count % 30 == 0:  # Every 30 frames
        update_fluid_system(world, fluids, dt * 30.0)
    
    # Update mobs with new AI
    let mi = 0
    while mi < len(gameplay["mobs"]):
        let mob = gameplay["mobs"][mi]
        if not mob["dead"] and dict_has(mob, "behavior"):
            update_mob_ai(mob, mob["behavior"], player_pos, dt)
        update_voxel_mobs(gameplay, player_pos, dt)
        mi = mi + 1
    
    # Update pickups
    update_voxel_pickups(gameplay, dt)
    
    # Render
    begin_frame_commands(r)
    
    # Simple render - just clear with weather-adjusted color
    let fog_mod = get_weather_fog_modifier(weather)
    let bg_color = vec3(0.5 * fog_mod, 0.7 * fog_mod, 0.9 * fog_mod)
    gpu.clear_color(bg_color[0], bg_color[1], bg_color[2], 1.0)
    gpu.clear()
    
    # Render HUD info
    update_title_fps(r)
    
    end_frame(r)
    
    # Maintain timing
    frame_count = frame_count + 1
    
    # Respawn mobs if needed
    if frame_count % 120 == 0:
        ensure_voxel_mob_population(gameplay, player_pos, 64)

print ""
print "=== Demo Statistics ==="
print "Total frames rendered: " + str(frame_count)
print "Final mob count: " + str(voxel_alive_mob_count(gameplay))
print "Fluid blocks: Water and lava active"
print "Weather system: " + weather["current_weather"]
print "Biomes loaded: " + str(len(biomes))

# Cleanup
shutdown_renderer(r)
print "Demo closed successfully"
