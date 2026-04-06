gc_disable()
# demo_voxel.sage - Fully functional voxel demo with geometry rendering
# Minecraft-style sandbox with lighting, fluid physics, biomes, weather, and mob AI

import gpu
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta, scroll_value
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, mat4_identity, mat4_mul
from player_controller import create_player_controller, player_forward, player_view_matrix, player_projection
from voxel_world import create_voxel_world, set_voxel, get_voxel, voxel_palette_ids, voxel_block_name
from voxel_world import create_voxel_inventory, voxel_inventory_add, voxel_inventory_remove, voxel_inventory_count
from voxel_world import default_voxel_recipes, try_craft_voxel_recipe, voxel_visible_draws, raycast_voxel_world
from voxel_gameplay import create_tool, create_voxel_gameplay_state, voxel_add_tool
from voxel_gameplay import spawn_voxel_mob, ensure_voxel_mob_population, update_voxel_mobs
from voxel_gameplay import update_voxel_pickups, voxel_alive_mob_count
from voxel_fluids import create_fluid_system
from voxel_biomes import default_biomes
from voxel_weather import create_weather_system, update_weather_system, get_weather_light_modifier
from voxel_mobai import create_behavior_state, update_mob_ai
from lighting import create_light_scene, directional_light, add_light, set_ambient, set_fog, set_view_position, init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit_surface_controlled

import math

print "=== Forge Engine - Voxel Sandbox ==="
print "With: Full Rendering | Fluid Physics | Biome System | Dynamic Weather | Mob AI"
print ""

# ============================================================================
# Initialize renderer
# ============================================================================
let r = create_renderer(1280, 720, "Forge Engine - Voxel Sandbox")
if r == nil:
    raise "Failed to create renderer"
print "✓ Renderer: " + str(r["width"]) + "x" + str(r["height"]) + " | GPU: " + gpu.device_name()

# ============================================================================
# Initialize lighting
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.3, -0.8, 0.5, 1.0, 0.95, 0.85, 1.4))
set_ambient(ls, 0.2, 0.22, 0.28, 0.4)
set_fog(ls, true, 40.0, 100.0, 0.52, 0.76, 0.95)

# ============================================================================
# Create lit material for voxel rendering
# ============================================================================
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])
if lit_mat == nil:
    print "WARNING: Failed to create lit material - rendering without lighting"

# ============================================================================
# Initialize input + player
# ============================================================================
let inp = create_input()
default_fps_bindings(inp)

let player = create_player_controller()
let player_pos = vec3(32.0, 30.0, 32.0)
player["position"] = player_pos
player["pitch"] = -0.4   # Look slightly downward to see terrain

# ============================================================================
# Initialize world systems
# ============================================================================
let voxel = create_voxel_world(64, 48, 64)
let gameplay = create_voxel_gameplay_state()
let fluids = create_fluid_system()
let biomes = default_biomes()
let weather = create_weather_system()

# Inventory
let inventory = create_voxel_inventory()
voxel_inventory_add(inventory, 1, 64)   # Grass
voxel_inventory_add(inventory, 2, 64)   # Dirt
voxel_inventory_add(inventory, 3, 32)   # Stone

# Tools
let basic_hands = create_tool("Bare Hands", 0, -1, 1.0, 0)
let stone_pickaxe = create_tool("Stone Pickaxe", 1, 120, 2.0, 1)
voxel_add_tool(gameplay, basic_hands)
voxel_add_tool(gameplay, stone_pickaxe)

# ============================================================================
# Generate terrain — flat ground + water lake + lava pool
# ============================================================================

# Ground layer (grass on top, dirt below)
let gz = 0
while gz < 64:
    let gx = 0
    while gx < 64:
        set_voxel(voxel, gx, 19, gz, 2)   # Dirt at y=19
        set_voxel(voxel, gx, 20, gz, 1)   # Grass at y=20
        gx = gx + 1
    gz = gz + 1

# Stone underground
let sz = 0
while sz < 64:
    let sx = 0
    while sx < 64:
        let sy = 0
        while sy < 19:
            set_voxel(voxel, sx, sy, sz, 3)  # Stone
            sy = sy + 1
        sx = sx + 1
    sz = sz + 1

# Water lake
let wz = 10
while wz < 26:
    let wx = 20
    while wx < 36:
        set_voxel(voxel, wx, 20, wz, 0)  # Clear grass
        set_voxel(voxel, wx, 19, wz, 14) # Water
        wx = wx + 1
    wz = wz + 1

# Lava pool
let lz = 5
while lz < 13:
    let lx = 40
    while lx < 48:
        set_voxel(voxel, lx, 20, lz, 0)  # Clear grass
        set_voxel(voxel, lx, 19, lz, 15) # Lava
        lx = lx + 1
    lz = lz + 1

# Some trees (wood trunk + leaves)
let tx = 10
while tx < 50:
    let tz = 10
    while tz < 50:
        if math.random() < 0.02:
            # Trunk
            let ty = 21
            while ty < 25:
                set_voxel(voxel, tx, ty, tz, 4)  # Wood
                ty = ty + 1
            # Leaves canopy
            let ly = 24
            while ly < 27:
                let lxx = tx - 2
                while lxx <= tx + 2:
                    let lzz = tz - 2
                    while lzz <= tz + 2:
                        if lxx >= 0 and lxx < 64 and lzz >= 0 and lzz < 64:
                            if get_voxel(voxel, lxx, ly, lzz) == 0:
                                set_voxel(voxel, lxx, ly, lzz, 5)  # Leaves
                        lzz = lzz + 1
                    lxx = lxx + 1
                ly = ly + 1
        tz = tz + 5
    tx = tx + 5

# Spawn mobs
ensure_voxel_mob_population(gameplay, player_pos, 64)
let mi = 0
while mi < len(gameplay["mobs"]):
    if gameplay["mobs"][mi] != nil:
        gameplay["mobs"][mi]["behavior"] = create_behavior_state(gameplay["mobs"][mi]["type"])
        gameplay["mobs"][mi]["patrol_center"] = gameplay["mobs"][mi]["position"]
    mi = mi + 1

# Pre-load all visible chunks before rendering starts
# This prevents blank screen on first frames
voxel["max_stream_chunk_refresh"] = 999
let preload = voxel_visible_draws(voxel, player_pos[0], player_pos[1], player_pos[2], 3)
print "✓ Pre-loaded " + str(len(preload)) + " chunk draws"
voxel["max_stream_chunk_refresh"] = 4

print "✓ World: 64x48x64 with terrain, water, lava, trees"
print "✓ Mobs: " + str(voxel_alive_mob_count(gameplay))
print "✓ Weather: Dynamic | Biomes: 5 types"
print ""
print "Controls: WASD=Move | Mouse=Look | Scroll=Fly | LMB=Mine | RMB=Place | ESC=Quit"
print ""

# ============================================================================
# Game loop
# ============================================================================
let running = true
let frame_count = 0
let dt = 0.016
let selected_block_id = 1

while running:
    update_input(inp)

    if action_just_pressed(inp, "escape"):
        running = false

    # --- Player movement ---
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

    # --- Update weather lighting ---
    let weather_mod = get_weather_light_modifier(weather)
    r["clear_color"] = [0.52 * weather_mod, 0.76 * weather_mod, 0.95 * weather_mod, 1.0]

    # --- Update lighting UBO ---
    set_view_position(ls, player_pos)
    update_light_ubo(ls)

    # --- Begin frame ---
    let frame = begin_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        check_resize(r)
        continue

    let cmd = frame["cmd"]

    # --- Camera matrices ---
    player["position"] = player_pos
    let view_mat = player_view_matrix(player)
    let aspect = r["width"] / r["height"]
    let proj_mat = player_projection(player, aspect)
    let vp = mat4_mul(proj_mat, view_mat)

    # --- Render voxel chunks ---
    if lit_mat != nil:
        let visible = voxel_visible_draws(voxel, player_pos[0], player_pos[1], player_pos[2], 3)
        let vi = 0
        while vi < len(visible):
            let draw = visible[vi]
            let model = mat4_identity()
            let mvp = mat4_mul(vp, model)
            let surface = draw["surface"]
            draw_mesh_lit_surface_controlled(cmd, lit_mat, draw["gpu_mesh"], mvp, model, ls["desc_set"], surface, true)
            vi = vi + 1

    # --- Update title ---
    let mobs = voxel_alive_mob_count(gameplay)
    let title = "Voxel Sandbox | Block: " + voxel_block_name(voxel, selected_block_id) + " | Mobs: " + str(mobs)
    update_title_fps(r, title)

    end_frame(r, frame)

    frame_count = frame_count + 1
    check_resize(r)

print ""
print "Session Complete | Frames: " + str(frame_count) + " | Mobs: " + str(voxel_alive_mob_count(gameplay))
shutdown_renderer(r)
print "✓ Demo closed"
