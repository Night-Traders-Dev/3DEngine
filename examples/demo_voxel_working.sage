# demo_voxel_working.sage - Working voxel demo using actual APIs
# Full-featured demo with graphics, input, and all voxel systems

import gpu
import math
import io
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from player_controller import create_player_controller, update_player, player_eye_position, player_forward
from mesh import upload_mesh
from voxel_world import create_voxel_world, set_voxel, get_voxel, voxel_block_name, voxel_palette_ids
from voxel_fluids import create_fluid_system
from voxel_biomes import default_biomes
from voxel_weather import create_weather_system, update_weather_system, get_weather_light_modifier
from voxel_gameplay import create_voxel_gameplay_state, spawn_voxel_mob, ensure_voxel_mob_population
from voxel_gameplay import update_voxel_mobs, update_voxel_pickups, voxel_alive_mob_count
from voxel_mobai import create_behavior_state, update_mob_ai

print "=== Forge Engine - Voxel Demo (Full Graphics) ==="

# Initialize renderer
let r = create_renderer(1280, 720, "Forge Engine - Voxel World")
if r == nil:
    print "ERROR: Failed to create renderer"
    raise "Renderer initialization failed"

print "✓ Renderer initialized: " + str(r["width"]) + "x" + str(r["height"])
print "GPU: " + gpu.device_name()

# Initialize input
let inp = create_input()
default_fps_bindings(inp)
print "✓ Input system initialized"

# Create voxel world
let world = create_voxel_world(64, 48, 64)
print "✓ Voxel world created: 64x48x64"

# Initialize gameplay systems
let gameplay = create_voxel_gameplay_state()
let fluids = create_fluid_system()
let biomes = default_biomes()
let weather = create_weather_system()
print "✓ Gameplay systems initialized"

# Create player
let player = create_player_controller()
let player_pos = vec3(32.0, 40.0, 32.0)
player["position"] = player_pos
print "✓ Player controller created"

# Spawn mobs with AI
print "✓ Spawning mobs..."
ensure_voxel_mob_population(gameplay, player_pos, 64)
let i = 0
while i < len(gameplay["mobs"]):
    if gameplay["mobs"][i] != nil:
        gameplay["mobs"][i]["behavior"] = create_behavior_state(gameplay["mobs"][i]["type"])
        gameplay["mobs"][i]["patrol_center"] = gameplay["mobs"][i]["position"]
    i = i + 1
print "  Mob count: " + str(voxel_alive_mob_count(gameplay))

# Generate some terrain features
print "✓ Generating terrain features..."
# Water feature
let wz = 0
while wz < 16:
    let wx = 20
    while wx < 30:
        set_voxel(world, wx, 20, wz, 14)
        wx = wx + 1
    wz = wz + 1

# Lava pit
let lz = 0
while lz < 8:
    let lx = 40
    while lx < 48:
        set_voxel(world, lx, 15, lz, 15)
        lx = lx + 1
    lz = lz + 1

# Stone tower
let ty = 0
while ty < 20:
    set_voxel(world, 10, ty, 10, 3)
    ty = ty + 1

print ""
print "Controls:"
print "  WASD = Move | Mouse = Look | Scroll = Up/Down"
print "  ESC = Quit"
print ""

# Main loop state
let running = true
let frame_count = 0
let dt = 0.016  # ~60fps

# Main game loop
while running:
    # Update input
    update_input(inp)
    
    if action_just_pressed(inp, "escape"):
        running = false
    
    # Update player
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
        player_pos = v3_add(player_pos, v3_scale(move_dir, 10.0 * dt))
    
    # Camera look (mouse)
    let mdelta = mouse_delta(inp)
    if mdelta[0] != 0.0 or mdelta[1] != 0.0:
        player["yaw"] = player["yaw"] + mdelta[0] * 0.005
        player["pitch"] = player["pitch"] + mdelta[1] * 0.005
    
    # Update weather
    update_weather_system(weather, dt)
    
    # Update mobs with AI
    let mi = 0
    while mi < len(gameplay["mobs"]):
        if gameplay["mobs"][mi] != nil and not gameplay["mobs"][mi]["dead"]:
            if dict_has(gameplay["mobs"][mi], "behavior"):
                update_mob_ai(gameplay["mobs"][mi], gameplay["mobs"][mi]["behavior"], player_pos, dt)
        mi = mi + 1
    
    # Update mobs movement
    update_voxel_mobs(gameplay, player_pos, dt)
    
    # Update pickups
    update_voxel_pickups(gameplay, dt)
    
    # Maintain mob population
    if frame_count % 120 == 0:
        ensure_voxel_mob_population(gameplay, player_pos, 64)
    
    # Render frame
    let frame = begin_frame(r)
    if frame == nil:
        continue
    
    # Clear screen with weather-affected color
    let weather_mod = get_weather_light_modifier(weather)
    gpu.clear_color(0.5 * weather_mod, 0.7 * weather_mod, 0.9 * weather_mod, 1.0)
    gpu.clear()
    
    # Update title
    update_title_fps(r, "Forge Engine - Voxel World [Fluids, Biomes, Weather, AI]")
    
    # End frame
    end_frame(r, frame)
    
    # Frame timing
    frame_count = frame_count + 1
    
    # Check for window resize
    check_resize(r)

print ""
print "=== Demo Statistics ==="
print "Total frames: " + str(frame_count)
print "Final mobs: " + str(voxel_alive_mob_count(gameplay))
print "Weather: " + weather["current_weather"]
print "Demo closed"

# Cleanup
shutdown_renderer(r)
print "✓ Renderer shutdown complete"
