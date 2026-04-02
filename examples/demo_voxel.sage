# demo_voxel.sage - Forge Engine voxel template sandbox
# Minecraft-style first playable slice: block world, mine/place loop, palette
#
# Run: ./run.sh examples/demo_voxel.sage
# Controls:
#   WASD = Move | Mouse = Look | ESC = Capture mouse
#   SPACE = Jump | SHIFT = Sprint | TAB = Noclip | Q = Quit
#   Left Mouse = Break block | Right Mouse = Place selected block
#   1-5 = Select block palette | Z = Select planks | X = Craft planks from wood

import gpu
import math
import io
from renderer import create_renderer, begin_frame, end_frame
from renderer import shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, bind_action
from input import action_just_pressed, default_fps_bindings
from math3d import vec3, mat4_identity, mat4_mul, radians
from engine_math import make_transform, transform_to_matrix
from lighting import create_light_scene, directional_light
from lighting import add_light, set_ambient, set_view_position
from lighting import init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit_surface_controlled
from render_system import set_lit_material_shadow_source
from sky import create_sky, init_sky_gpu, draw_sky, sky_preset_day
from shadow_map import create_shadow_renderer, compute_light_vp_stable
from shadow_map import begin_shadow_frame, end_shadow_frame, shadow_draw_mesh
from mesh import cube_mesh, upload_mesh
from player_controller import create_player_controller, update_player
from player_controller import player_view_matrix, player_eye_position
from player_controller import player_projection, player_forward
from game_loop import create_time_state, update_time
from font import create_font_renderer, load_font, begin_text, add_text, flush_text
from json import cJSON_Parse, cJSON_Print, cJSON_Delete, cJSON_FromSage, cJSON_ToSage
from voxel_world import create_voxel_world, generate_voxel_template_world, voxel_draws
from voxel_world import voxel_block_name, voxel_block_world_center, raycast_voxel_world
from voxel_world import set_voxel, sample_voxel_ground_radius, voxel_collides_player
from voxel_world import resolve_player_voxel_collision
from voxel_world import create_voxel_inventory, voxel_inventory_add, voxel_inventory_remove
from voxel_world import voxel_inventory_count, voxel_inventory_to_sage, voxel_inventory_from_sage
from voxel_world import voxel_world_to_sage, voxel_world_from_sage
from voxel_world import default_voxel_recipes, try_craft_voxel_recipe

print "=== Forge Engine - Voxel Template Sandbox ==="

let save_file = "/tmp/forge_voxel_template_save.json"

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(1280, 720, "Forge Engine - Voxel Template")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

# ============================================================================
# Lighting / sky / shadows
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
let sun_dir = vec3(-0.45, -0.82, -0.35)
add_light(ls, directional_light(sun_dir[0], sun_dir[1], sun_dir[2], 1.0, 0.98, 0.92, 1.6))
set_ambient(ls, 0.16, 0.18, 0.22, 0.45)

let sky = create_sky()
sky_preset_day(sky)
init_sky_gpu(sky, r["render_pass"])

let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])
let shadow_renderer = nil
try:
    shadow_renderer = create_shadow_renderer(2048)
    if shadow_renderer != nil:
        set_lit_material_shadow_source(lit_mat, shadow_renderer)
        print "Voxel shadows enabled"
catch e:
    print "Voxel shadows skipped: " + str(e)

# ============================================================================
# Fonts / overlay
# ============================================================================
let font_r = create_font_renderer(r["render_pass"])
load_font(font_r, "ui", "assets/DejaVuSans.ttf", 18.0)

# ============================================================================
# Shared voxel world
# ============================================================================
let voxel = create_voxel_world(32, 18, 32)
generate_voxel_template_world(voxel, 7.0)
let cube_gpu = upload_mesh(cube_mesh())
let draws = voxel_draws(voxel)
print "Voxel world generated: " + str(voxel["solid_count"]) + " solid blocks"

let inventory = create_voxel_inventory()
voxel_inventory_add(inventory, 1, 32)
voxel_inventory_add(inventory, 2, 48)
voxel_inventory_add(inventory, 3, 64)
voxel_inventory_add(inventory, 4, 24)
voxel_inventory_add(inventory, 5, 24)
voxel_inventory_add(inventory, 6, 0)
let recipes = default_voxel_recipes()

# ============================================================================
# Input
# ============================================================================
let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "quit", [gpu.KEY_Q])
bind_action(inp, "toggle_capture", [gpu.KEY_ESCAPE])
bind_action(inp, "noclip", [gpu.KEY_TAB])
bind_action(inp, "sprint", [gpu.KEY_SHIFT])

# ============================================================================
# Player
# ============================================================================
let player = create_player_controller()
player["position"] = vec3(0.0, 0.0, 8.0)
player["speed"] = 7.0
player["sprint_speed"] = 12.0
player["air_speed"] = 4.0
player["captured"] = true
gpu.set_cursor_mode(gpu.CURSOR_DISABLED)
let start_ground = sample_voxel_ground_radius(voxel, player["position"][0], player["position"][2], player["radius"])
player["position"][1] = start_ground
player["ground_y"] = start_ground
player["grounded"] = true

# ============================================================================
# Palette / targeting
# ============================================================================
let selected_block = [1]
let target_hit = nil
let status_line = ["C save  V load  Mine blocks to refill inventory"]
let status_timer = [4.0]

proc _highlight_surface():
    let surface = {}
    surface["albedo"] = vec3(0.96, 0.98, 1.0)
    surface["alpha"] = 1.0
    return surface

proc _set_status(text):
    status_line[0] = text
    status_timer[0] = 4.0

proc _encode_json(data):
    let node = cJSON_FromSage(data)
    if node == nil:
        return nil
    let out = cJSON_Print(node)
    cJSON_Delete(node)
    return out

proc _decode_json(text):
    let node = cJSON_Parse(text)
    if node == nil:
        return nil
    let out = cJSON_ToSage(node)
    cJSON_Delete(node)
    return out

proc _make_save_state(vw, inv, selected_id, player):
    let state = {}
    state["world"] = voxel_world_to_sage(vw)
    state["inventory"] = voxel_inventory_to_sage(inv)
    state["selected_block"] = selected_id
    let player_state = {}
    player_state["position"] = player["position"]
    player_state["yaw"] = player["yaw"]
    player_state["pitch"] = player["pitch"]
    player_state["noclip"] = player["noclip"]
    state["player"] = player_state
    return state

# ============================================================================
# Main loop
# ============================================================================
let ts = create_time_state()
let running = true

print ""
print "Controls:"
print "  WASD = Move  Mouse = Look  ESC = Capture mouse  TAB = Noclip"
print "  Left Mouse = Break block  Right Mouse = Place block  1-5 = Palette  Z = Planks  X = Craft planks"
print ""

while running:
    update_time(ts)
    let dt = ts["dt"]
    if status_timer[0] > 0.0:
        status_timer[0] = status_timer[0] - dt
        if status_timer[0] < 0.0:
            status_timer[0] = 0.0
    check_resize(r)
    update_input(inp)

    if action_just_pressed(inp, "quit"):
        running = false
        continue

    if gpu.key_just_pressed(gpu.KEY_1):
        selected_block[0] = 1
    if gpu.key_just_pressed(gpu.KEY_2):
        selected_block[0] = 2
    if gpu.key_just_pressed(gpu.KEY_3):
        selected_block[0] = 3
    if gpu.key_just_pressed(gpu.KEY_4):
        selected_block[0] = 4
    if gpu.key_just_pressed(gpu.KEY_5):
        selected_block[0] = 5
    if gpu.key_just_pressed(gpu.KEY_Z):
        selected_block[0] = 6
    if gpu.key_just_pressed(gpu.KEY_X):
        if try_craft_voxel_recipe(inventory, recipes[0]):
            selected_block[0] = recipes[0]["output_block"]
            _set_status("Crafted " + str(recipes[0]["output_count"]) + " " + voxel_block_name(voxel, recipes[0]["output_block"]) + " from " + voxel_block_name(voxel, recipes[0]["input_block"]))
        else:
            _set_status("Need " + str(recipes[0]["input_count"]) + " " + voxel_block_name(voxel, recipes[0]["input_block"]) + " to craft " + voxel_block_name(voxel, recipes[0]["output_block"]))

    if gpu.key_just_pressed(gpu.KEY_C):
        let json_str = _encode_json(_make_save_state(voxel, inventory, selected_block[0], player))
        if json_str == nil:
            _set_status("Save failed: unable to serialize sandbox")
        else:
            io.writefile(save_file, json_str)
            _set_status("Saved sandbox to " + save_file)

    if gpu.key_just_pressed(gpu.KEY_V):
        if io.exists(save_file) == false:
            _set_status("No save file found at " + save_file)
        else:
            let state = _decode_json(io.readfile(save_file))
            if state == nil or dict_has(state, "world") == false:
                _set_status("Load failed: invalid sandbox save")
            else:
                let loaded_world = voxel_world_from_sage(state["world"])
                if loaded_world == nil:
                    _set_status("Load failed: world data was invalid")
                else:
                    voxel = loaded_world
                    draws = voxel_draws(voxel)
                    if dict_has(state, "inventory"):
                        inventory = voxel_inventory_from_sage(state["inventory"])
                    if dict_has(state, "selected_block") and state["selected_block"] > 0:
                        selected_block[0] = state["selected_block"]
                    if dict_has(state, "player"):
                        let saved_player = state["player"]
                        if dict_has(saved_player, "position") and len(saved_player["position"]) >= 3:
                            let p = saved_player["position"]
                            player["position"] = vec3(p[0], p[1], p[2])
                        if dict_has(saved_player, "yaw"):
                            player["yaw"] = saved_player["yaw"]
                        if dict_has(saved_player, "pitch"):
                            player["pitch"] = saved_player["pitch"]
                        if dict_has(saved_player, "noclip"):
                            player["noclip"] = saved_player["noclip"]
                    player["velocity"] = vec3(0.0, 0.0, 0.0)
                    let load_ground = sample_voxel_ground_radius(voxel, player["position"][0], player["position"][2], player["radius"])
                    player["ground_y"] = load_ground
                    if player["noclip"] == false and player["position"][1] < load_ground:
                        player["position"][1] = load_ground
                    if voxel_collides_player(voxel, player["position"], player["radius"], player["height"]):
                        player["position"][1] = sample_voxel_ground_radius(voxel, player["position"][0], player["position"][2], player["radius"])
                    _set_status("Loaded sandbox from " + save_file)

    let prev_pos = vec3(player["position"][0], player["position"][1], player["position"][2])
    player["ground_y"] = sample_voxel_ground_radius(voxel, player["position"][0], player["position"][2], player["radius"])
    update_player(player, inp, dt)
    let resolved = resolve_player_voxel_collision(voxel, prev_pos, player["position"], player["radius"], player["height"])
    player["position"] = resolved
    let ground_y = sample_voxel_ground_radius(voxel, player["position"][0], player["position"][2], player["radius"])
    player["ground_y"] = ground_y
    if player["position"][1] < ground_y:
        player["position"][1] = ground_y
        if player["velocity"][1] < 0.0:
            player["velocity"][1] = 0.0
        player["grounded"] = true

    let eye = player_eye_position(player)
    target_hit = raycast_voxel_world(voxel, eye, player_forward(player), 8.0)

    if player["captured"] and target_hit != nil and gpu.mouse_just_pressed(gpu.MOUSE_LEFT):
        if target_hit["y"] > 0:
            let mined_id = target_hit["block_id"]
            if set_voxel(voxel, target_hit["x"], target_hit["y"], target_hit["z"], 0):
                voxel_inventory_add(inventory, mined_id, 1)
                _set_status("Mined " + voxel_block_name(voxel, mined_id) + " | Count: " + str(voxel_inventory_count(inventory, mined_id)))
                target_hit = nil

    if player["captured"] and target_hit != nil and dict_has(target_hit, "place_x") and gpu.mouse_just_pressed(gpu.MOUSE_RIGHT):
        if voxel_inventory_remove(inventory, selected_block[0], 1):
            if set_voxel(voxel, target_hit["place_x"], target_hit["place_y"], target_hit["place_z"], selected_block[0]):
                if voxel_collides_player(voxel, player["position"], player["radius"], player["height"]):
                    set_voxel(voxel, target_hit["place_x"], target_hit["place_y"], target_hit["place_z"], 0)
                    voxel_inventory_add(inventory, selected_block[0], 1)
                    _set_status("Placement blocked: player collision")
                else:
                    _set_status("Placed " + voxel_block_name(voxel, selected_block[0]) + " | Remaining: " + str(voxel_inventory_count(inventory, selected_block[0])))
            else:
                voxel_inventory_add(inventory, selected_block[0], 1)
        else:
            _set_status("No " + voxel_block_name(voxel, selected_block[0]) + " left in inventory")

    draws = voxel_draws(voxel)
    set_view_position(ls, eye)
    update_light_ubo(ls)

    if shadow_renderer != nil:
        let shadow_focus = vec3(player["position"][0], 6.0, player["position"][2])
        let light_vp = compute_light_vp_stable(sun_dir, shadow_focus, 26.0, shadow_renderer["resolution"] + 0.0)
        let shadow_cmd = begin_shadow_frame(shadow_renderer, light_vp, 0)
        let di = 0
        while di < len(draws):
            shadow_draw_mesh(shadow_renderer, shadow_cmd, draws[di]["gpu_mesh"], mat4_identity())
            di = di + 1
        end_shadow_frame(shadow_renderer, shadow_cmd)

    let frame = begin_frame(r)
    if frame == nil:
        running = false
        continue
    let cmd = frame["cmd"]

    let view = player_view_matrix(player)
    let aspect = r["width"] / r["height"]
    let proj = player_projection(player, aspect)
    let vp = mat4_mul(proj, view)
    let identity = mat4_identity()
    let world_mvp = mat4_mul(vp, identity)

    draw_sky(sky, cmd, view, aspect, radians(player["fov"]), ts["total"])

    let ri = 0
    while ri < len(draws):
        let draw = draws[ri]
        draw_mesh_lit_surface_controlled(cmd, lit_mat, draw["gpu_mesh"], world_mvp, identity, ls["desc_set"], draw["surface"], true)
        ri = ri + 1

    if target_hit != nil:
        let center = voxel_block_world_center(voxel, target_hit["x"], target_hit["y"], target_hit["z"])
        let highlight_t = make_transform(center, vec3(0.0, ts["total"] * 0.8, 0.0), vec3(1.04, 1.04, 1.04))
        let highlight_model = transform_to_matrix(highlight_t)
        let highlight_mvp = mat4_mul(vp, highlight_model)
        draw_mesh_lit_surface_controlled(cmd, lit_mat, cube_gpu, highlight_mvp, highlight_model, ls["desc_set"], _highlight_surface(), false)

    let sw = r["width"] + 0.0
    let sh = r["height"] + 0.0
    begin_text(font_r)
    add_text(font_r, "ui", "VOXEL TEMPLATE SANDBOX", 18.0, 18.0, 0.94, 0.96, 0.98, 1.0)
    add_text(font_r, "ui", "LMB break  RMB place  1-5 palette  Z planks  X craft  C save  V load  TAB noclip  ESC mouse", 18.0, 42.0, 0.70, 0.74, 0.80, 1.0)
    add_text(font_r, "ui", "Selected: [" + str(selected_block[0]) + "] " + voxel_block_name(voxel, selected_block[0]) + " x" + str(voxel_inventory_count(inventory, selected_block[0])) + " | Solid blocks: " + str(voxel["solid_count"]), 18.0, sh - 44.0, 0.90, 0.92, 0.95, 1.0)
    if target_hit != nil:
        add_text(font_r, "ui", "Target: " + voxel_block_name(voxel, target_hit["block_id"]) + " @ " + str(target_hit["x"]) + ", " + str(target_hit["y"]) + ", " + str(target_hit["z"]), 18.0, sh - 70.0, 0.86, 0.84, 0.72, 1.0)
    else:
        add_text(font_r, "ui", "Target: none", 18.0, sh - 70.0, 0.55, 0.58, 0.63, 1.0)
    if status_timer[0] > 0.0 and status_line[0] != "":
        add_text(font_r, "ui", status_line[0], 18.0, sh - 96.0, 0.76, 0.90, 0.74, 1.0)
    add_text(font_r, "ui", "+", sw / 2.0 - 5.0, sh / 2.0 - 12.0, 1.0, 1.0, 1.0, 0.95)
    flush_text(font_r, cmd, sw, sh)

    end_frame(r, frame)

    let title = "Forge Engine | Voxel Template | " + voxel_block_name(voxel, selected_block[0])
    update_title_fps(r, title)

gpu.device_wait_idle()
shutdown_renderer(r)
