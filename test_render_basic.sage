gc_disable()
# Minecraft-style voxel sandbox - RENDERING FOCUS
# Goal: Get voxel meshes visible on screen

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta, scroll_value
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, mat4_identity, mat4_mul
from player_controller import create_player_controller, player_forward, player_view_matrix, player_projection
from voxel_world import create_voxel_world, set_voxel, voxel_visible_draws, voxel_block_name
from voxel_world import create_voxel_inventory, voxel_inventory_add
from voxel_gameplay import create_voxel_gameplay_state, ensure_voxel_mob_population, voxel_alive_mob_count
from voxel_weather import create_weather_system, update_weather_system, get_weather_light_modifier
from render_system import create_unlit_material, draw_mesh_unlit

print "=== Minecraft Voxel Sandbox - Rendering Test ==="
print "Initializing world and rendering systems..."
print ""

# Create renderer
let r = create_renderer(1280, 720, "Forge Engine - Voxel Sandbox")
if r == nil:
    raise "Failed to create renderer"
print "✓ Renderer: " + str(r["width"]) + "x" + str(r["height"]) + " | GPU: " + gpu.device_name()

# Create input and player
let inp = create_input()
default_fps_bindings(inp)

let player = create_player_controller()
let player_pos = vec3(32.0, 30.0, 32.0)

# Create world systems
let voxel = create_voxel_world(64, 48, 64)
let gameplay = create_voxel_gameplay_state()
let weather = create_weather_system()

# Setup inventory
let inventory = create_voxel_inventory()
voxel_inventory_add(inventory, 1, 64)
voxel_inventory_add(inventory, 2, 64)

# Generate terrain
print "Generating terrain..."
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

# Spawn mobs
ensure_voxel_mob_population(gameplay, player_pos, 64)

print "✓ World: 64x48x64"
print "✓ Terrain generated"
print "✓ Mobs spawned: " + str(voxel_alive_mob_count(gameplay))
print ""
print "Controls: WASD=Move | Mouse=Look | Scroll=Fly | ESC=Quit"
print ""

let running = true
let frame_count = 0
let dt = 0.016
let selected_block = 1

while running:
    update_input(inp)
    
    if action_just_pressed(inp, "escape"):
        running = false
        print ""
        print "ESC pressed - exiting..."
    
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
        player_pos = v3_add(player_pos, v3_scale(move_dir, 12.0 * dt))
    
    # Vertical movement
    let scroll = scroll_value(inp)
    if scroll[1] != 0.0:
        player_pos = v3_add(player_pos, vec3(0.0, scroll[1] * 2.0, 0.0))
    
    # Mouse look
    let mdelta = mouse_delta(inp)
    if mdelta[0] != 0.0 or mdelta[1] != 0.0:
        player["yaw"] = player["yaw"] + mdelta[0] * 0.005
        player["pitch"] = player["pitch"] + mdelta[1] * 0.005
    
    # Update weather
    update_weather_system(weather, dt)
    
    # Set sky clear color based on weather
    let weather_mod = get_weather_light_modifier(weather)
    r["clear_color"] = [0.52 * weather_mod, 0.76 * weather_mod, 0.95 * weather_mod, 1.0]
    
    # Begin frame
    let frame = begin_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        check_resize(r)
        continue
    
    let cmd = frame["cmd"]
    
    # Setup camera
    player["position"] = player_pos
    let view_mat = player_view_matrix(player)
    let proj_mat = player_projection(player, r["width"] / r["height"])
    
    # Get visible voxel chunks
    let visible_chunks = voxel_visible_draws(voxel, player_pos[0], player_pos[1], player_pos[2], 3)
    
    # RENDER VOXEL MESHES
    let di = 0
    while di < len(visible_chunks):
        let draw = visible_chunks[di]
        if draw != nil and dict_has(draw, "gpu_mesh"):
            let mesh = draw["gpu_mesh"]
            if mesh != nil:
                # Calculate MVP matrix for this chunk
                let model = mat4_identity()
                let mvp = mat4_mul(proj_mat, mat4_mul(view_mat, model))
                
                # Draw the chunk mesh
                draw_mesh_unlit(cmd, unlit_mat, mesh, mvp, [1.0, 1.0, 1.0, 1.0])
        di = di + 1
    
    let chunk_count = len(visible_chunks)
    
    # Update title with rendering info
    let mobs = voxel_alive_mob_count(gameplay)
    update_title_fps(r, "Voxel Sandbox | Chunks: " + str(chunk_count) + " | Mobs: " + str(mobs))
    
    end_frame(r, frame)
    
    frame_count = frame_count + 1
    check_resize(r)
    
    # Stop after 2 minutes
    if frame_count > 7200:
        running = false

print "Session ended | Frames: " + str(frame_count)
shutdown_renderer(r)
print "✓ Renderer closed"
