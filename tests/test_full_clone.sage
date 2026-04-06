gc_disable()
# Minecraft Clone - Full Gameplay + Rendering
# Combines voxel mechanics with 3D graphics

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta, scroll_value, bind_action
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot, mat4_identity, mat4_mul, mat4_zero, mat4_translate, radians
from player_controller import create_player_controller, player_forward, player_view_matrix, player_projection
from voxel_world import create_voxel_world, set_voxel, get_voxel, voxel_visible_draws, voxel_block_name
from voxel_world import create_voxel_inventory, voxel_inventory_add, voxel_inventory_remove, voxel_inventory_count
from voxel_world import default_voxel_recipes, try_craft_voxel_recipe, raycast_voxel_world
from voxel_gameplay import create_tool, create_voxel_gameplay_state, voxel_add_tool
from voxel_gameplay import spawn_voxel_mob, ensure_voxel_mob_population, update_voxel_mobs
from voxel_gameplay import update_voxel_pickups, voxel_alive_mob_count
from voxel_weather import create_weather_system, update_weather_system, get_weather_light_modifier
from render_system import create_unlit_material, draw_mesh_unlit

print "=== Minecraft Clone - Full Gameplay + Rendering ==="
print "Features: Mining | Placing | Crafting | Mobs | Weather | 3D Graphics"
print ""

# Create renderer
let r = create_renderer(1280, 720, "Minecraft Clone - Forge Engine")
if r == nil:
    raise "Failed to create renderer"
print "✓ Renderer: " + str(r["width"]) + "x" + str(r["height"]) + " | GPU: " + gpu.device_name()

# Create input and player
let inp = create_input()
default_fps_bindings(inp)

# Add mouse bindings for mining/placing
bind_action(inp, "left_click", [gpu.MOUSE_LEFT])
bind_action(inp, "right_click", [gpu.MOUSE_RIGHT])
bind_action(inp, "scroll_up", [gpu.MOUSE_SCROLL_UP])
bind_action(inp, "scroll_down", [gpu.MOUSE_SCROLL_DOWN])

let player = create_player_controller()
let player_pos = vec3(26.0, 24.0, 8.0)

# Create world systems
let voxel = create_voxel_world(64, 48, 64)
let gameplay = create_voxel_gameplay_state()
let weather = create_weather_system()

# Setup inventory
let inventory = create_voxel_inventory()
voxel_inventory_add(inventory, 1, 32)  # Grass
voxel_inventory_add(inventory, 2, 48)  # Dirt

# Setup tools
let basic_hands = create_tool("Bare Hands", 0, -1, 1.0, 0)
let stone_pickaxe = create_tool("Stone Pickaxe", 1, 120, 2.0, 1)
voxel_add_tool(gameplay, basic_hands)
voxel_add_tool(gameplay, stone_pickaxe)

# Generate terrain
print "Generating terrain..."
let gz = 0
while gz < 32:
    let gx = 0
    while gx < 32:
        set_voxel(voxel, gx + 16, 10, gz + 4, 1)  # grass
        if gz % 4 == 0 and gx % 4 == 0:
            set_voxel(voxel, gx + 18, 11, gz + 6, 2)  # dirt pillars
        gx = gx + 1
    gz = gz + 1

# Floating platforms
let wz = 0
while wz < 16:
    let wx = 20
    while wx < 30:
        set_voxel(voxel, wx, 20, wz, 14)  # water
        wx = wx + 1
    wz = wz + 1

let lz = 0
while lz < 8:
    let lx = 40
    while lx < 48:
        set_voxel(voxel, lx, 15, lz, 15)  # lava
        lx = lx + 1
    lz = lz + 1

# Spawn mobs
ensure_voxel_mob_population(gameplay, player_pos, 64)

print "✓ World: 64x48x64"
print "✓ Terrain generated"
print "✓ Mobs spawned: " + str(voxel_alive_mob_count(gameplay))
print ""
print "Controls: WASD=Move | Mouse=Look | Left Click=Mine | Right Click=Place"
print "Scroll=Select Block | Q=Drop | E=Craft | ESC=Quit"
print ""

# Create unlit material for voxel rendering
let unlit_mat = create_unlit_material(r["render_pass"])
if unlit_mat == nil:
    print "WARNING: Failed to create unlit material"
else:
    print "✓ Unlit material created"

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
    
    # Mining and placing
    if action_just_pressed(inp, "left_click"):
        let ray = raycast_voxel_world(voxel, player_pos, player_forward(player), 5.0)
        if ray != nil and ray["hit"]:
            let hit_pos = ray["position"]
            let hit_normal = ray["normal"]
            let block_pos = v3_add(hit_pos, hit_normal)
            set_voxel(voxel, int(block_pos[0]), int(block_pos[1]), int(block_pos[2]), 0)
    
    if action_just_pressed(inp, "right_click"):
        let ray = raycast_voxel_world(voxel, player_pos, player_forward(player), 5.0)
        if ray != nil and ray["hit"]:
            let hit_pos = ray["position"]
            let hit_normal = ray["normal"]
            let place_pos = v3_sub(hit_pos, hit_normal)
            if get_voxel(voxel, int(place_pos[0]), int(place_pos[1]), int(place_pos[2])) == 0:
                set_voxel(voxel, int(place_pos[0]), int(place_pos[1]), int(place_pos[2]), selected_block)
    
    # Block selection
    if action_just_pressed(inp, "scroll_up"):
        selected_block = selected_block + 1
        if selected_block > 15:
            selected_block = 1
    if action_just_pressed(inp, "scroll_down"):
        selected_block = selected_block - 1
        if selected_block < 1:
            selected_block = 15
    
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
    
    # Custom projection matrix for Vulkan (no Y flip)
    let fov_y = radians(player["fov"])
    let aspect = r["width"] / r["height"]
    let near = player["near"]
    let far = player["far"]
    let f = 1.0 / math.tan(fov_y / 2.0)
    let proj_mat = mat4_zero()
    proj_mat[0] = f / aspect
    proj_mat[5] = f  # Positive Y (no flip for Vulkan)
    proj_mat[10] = far / (near - far)
    proj_mat[11] = -1.0
    proj_mat[14] = (near * far) / (near - far)
    
    # Get visible voxel chunks
    let visible_chunks = voxel_visible_draws(voxel, player_pos[0], player_pos[1], player_pos[2], 3)
    
    # RENDER VOXEL MESHES
    let di = 0
    let rendered_chunks = 0
    while di < len(visible_chunks):
        let draw = visible_chunks[di]
        if draw != nil and dict_has(draw, "gpu_mesh"):
            let mesh = draw["gpu_mesh"]
            if mesh != nil:
                # World-space mesh vertices are already positioned
                let model = mat4_identity()
                let mvp = mat4_mul(proj_mat, mat4_mul(view_mat, model))
                
                # Choose color by block type
                let block_id = 0
                if dict_has(draw, "block_id"):
                    block_id = draw["block_id"]
                let color = [1.0, 1.0, 1.0, 1.0]
                if block_id == 1:
                    color = [0.2, 0.75, 0.25, 1.0]  # grass
                else:
                    if block_id == 2:
                        color = [0.55, 0.35, 0.20, 1.0]  # dirt
                    else:
                        if block_id == 14:
                            color = [0.20, 0.55, 0.95, 1.0]  # water
                        else:
                            if block_id == 15:
                                color = [0.95, 0.45, 0.10, 1.0]  # lava
                
                draw_mesh_unlit(cmd, unlit_mat, mesh, mvp, color)
                rendered_chunks = rendered_chunks + 1
        di = di + 1
    
    let chunk_count = len(visible_chunks)
    
    # Update title with game info
    let mobs = voxel_alive_mob_count(gameplay)
    let block_name = voxel_block_name(voxel, selected_block)
    update_title_fps(r, "Minecraft Clone | " + block_name + " | Chunks: " + str(chunk_count) + " | Mobs: " + str(mobs))
    
    end_frame(r, frame)
    
    frame_count = frame_count + 1
    check_resize(r)
    
    # Stop after 10 minutes
    if frame_count > 36000:
        running = false

print "Session ended | Frames: " + str(frame_count)
shutdown_renderer(r)
print "✓ Renderer closed"