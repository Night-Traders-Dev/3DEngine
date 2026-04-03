# demo_voxel.sage - Forge Engine voxel template sandbox
# Minecraft-style first playable slice: block world, mine/place loop, palette
#
# Run: ./run.sh examples/demo_voxel.sage
# Controls:
#   WASD = Move | Mouse = Look | ESC = Capture mouse
#   SPACE = Jump | SHIFT = Sprint | TAB = Noclip | Q = Quit
#   Left Mouse = Break block / hit mob | Right Mouse = Place selected block
#   1-5 = Select palette | Z = Select planks | Mouse Wheel = Cycle palette | X = Craft planks from wood

import gpu
import math
import io
from renderer import create_renderer, begin_frame_commands, begin_swapchain_pass, end_frame
from renderer import shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, bind_action
from input import action_just_pressed, default_fps_bindings, scroll_value
from math3d import vec3, mat4_identity, mat4_mul, radians
from engine_math import make_transform, transform_to_matrix
from lighting import create_light_scene, directional_light
from lighting import add_light, set_ambient, set_fog, set_view_position
from lighting import init_light_gpu, update_light_ubo
from render_system import create_lit_material, create_lit_material_transparent, draw_mesh_lit_surface_controlled
from render_system import set_lit_material_shadow_source
from sky import create_sky, init_sky_gpu, draw_sky, sky_preset_vibrant_day
from shadow_map import create_shadow_renderer, compute_light_vp_stable
from shadow_map import begin_shadow_frame, end_shadow_frame, shadow_draw_mesh
from mesh import cube_mesh, upload_mesh
from player_controller import create_player_controller, update_player
from player_controller import player_view_matrix, player_eye_position
from player_controller import player_projection, player_forward
from game_loop import create_time_state, update_time
from font import create_font_renderer, load_font, begin_text, add_text, flush_text
from ui_renderer import create_ui_renderer, draw_ui
from json import cJSON_Parse, cJSON_Print, cJSON_Delete, cJSON_FromSage, cJSON_ToSage
from gameplay import HealthComponent, damage, health_percent, revive, update_health_regen
from voxel_world import create_voxel_world
from voxel_world import voxel_palette_ids
from voxel_world import voxel_block_name, voxel_block_surface, voxel_block_world_center, raycast_voxel_world
from voxel_world import set_voxel, sample_voxel_ground_radius, voxel_collides_player
from voxel_world import resolve_player_voxel_collision
from voxel_world import create_voxel_inventory, voxel_inventory_add, voxel_inventory_remove
from voxel_world import voxel_inventory_count, voxel_inventory_to_sage, voxel_inventory_from_sage
from voxel_world import voxel_world_to_sage, voxel_world_from_sage
from voxel_world import default_voxel_recipes, try_craft_voxel_recipe
from voxel_world import save_voxel_world_chunks, load_voxel_world_chunks, voxel_visible_draws
from voxel_world import voxel_chunk_coords_world, voxel_chunk_size
from voxel_world import ensure_voxel_generated_radius, voxel_generated_chunk_count
from voxel_hud import create_voxel_hud, update_voxel_hud
from voxel_gameplay import create_voxel_gameplay_state, spawn_voxel_pickup
from voxel_gameplay import update_voxel_pickups, pickup_draw_position
from voxel_gameplay import spawn_voxel_mob, ensure_voxel_mob_population, update_voxel_mobs
from voxel_gameplay import find_target_voxel_mob, collect_dead_voxel_mobs
from voxel_gameplay import voxel_pickup_count, voxel_alive_mob_count, mob_draw_position
from voxel_gameplay import voxel_gameplay_to_sage, voxel_gameplay_from_sage
from postprocess import create_postprocess, recreate_postprocess, begin_scene_pass, end_scene_pass
from postprocess import run_bloom_chain, draw_tonemap, pfx_shaderpack_day

print "=== Forge Engine - Voxel Template Sandbox ==="

let save_state_file = "/tmp/forge_voxel_template_save.json"
let save_world_file = "/tmp/forge_voxel_template_world.json"
let world_seed = 7.0
let generation_chunk_radius = 2
let stream_chunk_radius = 1

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
add_light(ls, directional_light(sun_dir[0], sun_dir[1], sun_dir[2], 1.0, 0.98, 0.92, 1.2))
set_ambient(ls, 0.10, 0.13, 0.18, 0.18)
set_fog(ls, true, 38.0, 155.0, 0.47, 0.62, 0.82)
ls["fog_density"] = 0.004

let postprocess = create_postprocess(r["width"], r["height"], r["render_pass"])
pfx_shaderpack_day(postprocess)

let sky = create_sky()
sky_preset_vibrant_day(sky)
init_sky_gpu(sky, postprocess["scene_target"]["render_pass"])

let lit_mat = create_lit_material(postprocess["scene_target"]["render_pass"], ls["desc_layout"], ls["desc_set"])
let lit_water_mat = create_lit_material_transparent(postprocess["scene_target"]["render_pass"], ls["desc_layout"], ls["desc_set"])
let shadow_renderer = nil
try:
    shadow_renderer = create_shadow_renderer(2048)
    if shadow_renderer != nil:
        set_lit_material_shadow_source(lit_mat, shadow_renderer)
        set_lit_material_shadow_source(lit_water_mat, shadow_renderer)
        print "Voxel shadows enabled"
catch e:
    print "Voxel shadows skipped: " + str(e)

# ============================================================================
# Fonts / overlay
# ============================================================================
let font_r = create_font_renderer(r["render_pass"])
load_font(font_r, "ui", "assets/DejaVuSans.ttf", 18.0)
let ui_renderer = create_ui_renderer(r["render_pass"])

proc _rebuild_scene_postprocess():
    postprocess = recreate_postprocess(postprocess, r["width"], r["height"], r["render_pass"])
    pfx_shaderpack_day(postprocess)
    sky = create_sky()
    sky_preset_vibrant_day(sky)
    init_sky_gpu(sky, postprocess["scene_target"]["render_pass"])
    lit_mat = create_lit_material(postprocess["scene_target"]["render_pass"], ls["desc_layout"], ls["desc_set"])
    lit_water_mat = create_lit_material_transparent(postprocess["scene_target"]["render_pass"], ls["desc_layout"], ls["desc_set"])
    if shadow_renderer != nil:
        set_lit_material_shadow_source(lit_mat, shadow_renderer)
        set_lit_material_shadow_source(lit_water_mat, shadow_renderer)

# ============================================================================
# Shared voxel world
# ============================================================================
let voxel = create_voxel_world(96, 24, 96)
let cube_gpu = upload_mesh(cube_mesh())
print "Voxel world bootstrap: seed=" + str(world_seed) + " generate=" + str(generation_chunk_radius) + " stream=" + str(stream_chunk_radius)
ensure_voxel_generated_radius(voxel, 0.0, 0.0, 0.0, generation_chunk_radius, world_seed)
print "Voxel world seeded: " + str(voxel_generated_chunk_count(voxel)) + " generated chunks"
let draws = voxel_visible_draws(voxel, 0.0, 0.0, 0.0, stream_chunk_radius)
print "Voxel world generated: " + str(voxel["solid_count"]) + " solid blocks across " + str(voxel_generated_chunk_count(voxel)) + " generated chunks"

let inventory = create_voxel_inventory()
voxel_inventory_add(inventory, 1, 32)
voxel_inventory_add(inventory, 2, 48)
voxel_inventory_add(inventory, 3, 64)
voxel_inventory_add(inventory, 4, 24)
voxel_inventory_add(inventory, 5, 24)
voxel_inventory_add(inventory, 6, 0)
voxel_inventory_add(inventory, 7, 24)
voxel_inventory_add(inventory, 8, 18)
voxel_inventory_add(inventory, 9, 12)
voxel_inventory_add(inventory, 10, 8)
let recipes = default_voxel_recipes()
let voxel_hud = create_voxel_hud()
let inventory_open = [false]
let gameplay_state = create_voxel_gameplay_state()

# ============================================================================
# Input
# ============================================================================
let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "quit", [gpu.KEY_Q])
bind_action(inp, "toggle_capture", [gpu.KEY_ESCAPE])
bind_action(inp, "noclip", [gpu.KEY_TAB])
bind_action(inp, "sprint", [gpu.KEY_SHIFT])
bind_action(inp, "toggle_inventory", [gpu.KEY_O])

# ============================================================================
# Player
# ============================================================================
let player = create_player_controller()
player["position"] = vec3(0.0, 0.0, 0.0)
player["speed"] = 7.0
player["sprint_speed"] = 12.0
player["air_speed"] = 4.0
player["captured"] = true
gpu.set_cursor_mode(gpu.CURSOR_DISABLED)
let start_ground = sample_voxel_ground_radius(voxel, player["position"][0], player["position"][2], player["radius"])
player["position"][1] = start_ground
player["ground_y"] = start_ground
player["grounded"] = true
let player_health = HealthComponent(100.0)
player_health["regen_rate"] = 2.5
player_health["regen_delay"] = 5.0
ensure_voxel_mob_population(gameplay_state, voxel, player["position"], 3, world_seed)

# ============================================================================
# Palette / targeting
# ============================================================================
let selected_block = [1]
let target_hit = nil
let mob_target = nil
let status_line = ["O inventory  C save  V load  Mine blocks to refill inventory"]
let status_timer = [4.0]

proc _highlight_surface():
    let surface = {}
    surface["albedo"] = vec3(0.96, 0.98, 1.0)
    surface["alpha"] = 1.0
    return surface

proc _set_status(text):
    status_line[0] = text
    status_timer[0] = 4.0

proc _palette_slot_label(block_id):
    let palette_ids = voxel_palette_ids(voxel)
    let i = 0
    while i < len(palette_ids):
        if palette_ids[i] == block_id:
            if i < 5:
                return str(i + 1)
            if block_id == 6:
                return "Z"
            return ""
        i = i + 1
    if block_id == 6:
        return "Z"
    return str(block_id)

proc _palette_index_for_block(block_id):
    let palette_ids = voxel_palette_ids(voxel)
    let i = 0
    while i < len(palette_ids):
        if palette_ids[i] == block_id:
            return i
        i = i + 1
    return 0

proc _set_selected_palette_index(index, announce):
    let palette_ids = voxel_palette_ids(voxel)
    if len(palette_ids) == 0:
        return
    while index < 0:
        index = index + len(palette_ids)
    while index >= len(palette_ids):
        index = index - len(palette_ids)
    let next_block = palette_ids[index]
    if selected_block[0] == next_block:
        return
    selected_block[0] = next_block
    if announce:
        _set_status("Selected " + voxel_block_name(voxel, next_block))

proc _select_palette_slot(slot_index):
    _set_selected_palette_index(slot_index, false)

proc _cycle_selected_block(step):
    let current = _palette_index_for_block(selected_block[0])
    _set_selected_palette_index(current + step, true)

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
    state["world_manifest_path"] = save_world_file
    state["inventory"] = voxel_inventory_to_sage(inv)
    state["gameplay"] = voxel_gameplay_to_sage(gameplay_state)
    state["player_health"] = player_health
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
print "  Left Mouse = Break block / hit slime  Right Mouse = Place block  1-5 = Palette  Z = Planks  Wheel = Cycle palette  X = Craft planks  O = Inventory"
print ""

while running:
    update_time(ts)
    let dt = ts["dt"]
    if status_timer[0] > 0.0:
        status_timer[0] = status_timer[0] - dt
        if status_timer[0] < 0.0:
            status_timer[0] = 0.0
    if check_resize(r):
        _rebuild_scene_postprocess()
    update_input(inp)

    if action_just_pressed(inp, "quit"):
        running = false
        continue

    if action_just_pressed(inp, "toggle_inventory"):
        inventory_open[0] = inventory_open[0] == false
        if inventory_open[0]:
            _set_status("Inventory opened")
        else:
            _set_status("Inventory closed")

    if gpu.key_just_pressed(gpu.KEY_1):
        _select_palette_slot(0)
    if gpu.key_just_pressed(gpu.KEY_2):
        _select_palette_slot(1)
    if gpu.key_just_pressed(gpu.KEY_3):
        _select_palette_slot(2)
    if gpu.key_just_pressed(gpu.KEY_4):
        _select_palette_slot(3)
    if gpu.key_just_pressed(gpu.KEY_5):
        _select_palette_slot(4)
    if gpu.key_just_pressed(gpu.KEY_Z):
        _select_palette_slot(5)
    let sv = scroll_value(inp)
    if sv[1] > 0.1:
        _cycle_selected_block(-1)
    else:
        if sv[1] < -0.1:
            _cycle_selected_block(1)
    if gpu.key_just_pressed(gpu.KEY_X):
        if try_craft_voxel_recipe(inventory, recipes[0]):
            selected_block[0] = recipes[0]["output_block"]
            _set_status("Crafted " + str(recipes[0]["output_count"]) + " " + voxel_block_name(voxel, recipes[0]["output_block"]) + " from " + voxel_block_name(voxel, recipes[0]["input_block"]))
        else:
            _set_status("Need " + str(recipes[0]["input_count"]) + " " + voxel_block_name(voxel, recipes[0]["input_block"]) + " to craft " + voxel_block_name(voxel, recipes[0]["output_block"]))

    if gpu.key_just_pressed(gpu.KEY_C):
        if save_voxel_world_chunks(voxel, save_world_file) == false:
            _set_status("Save failed: unable to write chunked voxel world")
        else:
            let json_str = _encode_json(_make_save_state(voxel, inventory, selected_block[0], player))
            if json_str == nil:
                _set_status("Save failed: unable to serialize sandbox state")
            else:
                io.writefile(save_state_file, json_str)
                _set_status("Saved sandbox to " + save_state_file)

    if gpu.key_just_pressed(gpu.KEY_V):
        if io.exists(save_state_file) == false:
            _set_status("No save file found at " + save_state_file)
        else:
            let state = _decode_json(io.readfile(save_state_file))
            if state == nil or dict_has(state, "world_manifest_path") == false:
                _set_status("Load failed: invalid sandbox save")
            else:
                let loaded_world = load_voxel_world_chunks(state["world_manifest_path"])
                if loaded_world == nil:
                    _set_status("Load failed: world data was invalid")
                else:
                    voxel = loaded_world
                    gameplay_state = create_voxel_gameplay_state()
                    draws = voxel_visible_draws(voxel, player["position"][0], player["position"][1], player["position"][2], stream_chunk_radius)
                    if dict_has(state, "inventory"):
                        inventory = voxel_inventory_from_sage(state["inventory"])
                    if dict_has(state, "gameplay"):
                        gameplay_state = voxel_gameplay_from_sage(state["gameplay"])
                    if dict_has(state, "player_health"):
                        player_health = state["player_health"]
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
                    ensure_voxel_mob_population(gameplay_state, voxel, player["position"], 3, world_seed)
                    _set_status("Loaded sandbox from " + save_state_file)

    ensure_voxel_generated_radius(voxel, player["position"][0], player["position"][1], player["position"][2], generation_chunk_radius, world_seed)
    let prev_pos = vec3(player["position"][0], player["position"][1], player["position"][2])
    player["ground_y"] = sample_voxel_ground_radius(voxel, player["position"][0], player["position"][2], player["radius"])
    update_player(player, inp, dt)
    update_health_regen(player_health, dt, ts["total"])
    let resolved = resolve_player_voxel_collision(voxel, prev_pos, player["position"], player["radius"], player["height"])
    player["position"] = resolved
    let ground_y = sample_voxel_ground_radius(voxel, player["position"][0], player["position"][2], player["radius"])
    player["ground_y"] = ground_y
    if player["position"][1] < ground_y:
        player["position"][1] = ground_y
        if player["velocity"][1] < 0.0:
            player["velocity"][1] = 0.0
        player["grounded"] = true

    let mob_events = update_voxel_mobs(gameplay_state, voxel, player["position"], player_health, dt, ts["total"])
    if len(mob_events) > 0:
        let evt = mob_events[0]
        _set_status(evt["mob_name"] + " hit you for " + str(evt["damage"]) + " | Health: " + str(math.floor(player_health["current"] + 0.5)))
    if player_health["alive"] == false:
        revive(player_health, player_health["max"])
        player["position"] = vec3(0.0, sample_voxel_ground_radius(voxel, 0.0, 0.0, player["radius"]), 0.0)
        player["velocity"] = vec3(0.0, 0.0, 0.0)
        player["ground_y"] = player["position"][1]
        _set_status("You were slimed. Respawned at world origin")

    let collected_items = update_voxel_pickups(gameplay_state, inventory, player["position"], dt)
    if len(collected_items) > 0:
        let collected = collected_items[0]
        _set_status("Picked up " + str(collected["count"]) + " " + voxel_block_name(voxel, collected["block_id"]))

    let eye = player_eye_position(player)
    target_hit = raycast_voxel_world(voxel, eye, player_forward(player), 8.0)
    mob_target = find_target_voxel_mob(gameplay_state, eye, player_forward(player), 4.25)

    if player["captured"] and gpu.mouse_just_pressed(gpu.MOUSE_LEFT):
        let attacked_mob = false
        if mob_target != nil and (target_hit == nil or mob_target["distance"] <= target_hit["distance"]):
            let dealt = damage(mob_target["mob"]["health"], 10.0, ts["total"])
            if dealt > 0.0:
                attacked_mob = true
                if mob_target["mob"]["health"]["alive"]:
                    _set_status("Hit " + mob_target["mob"]["name"] + " for " + str(dealt) + " | Mob HP: " + str(math.floor(mob_target["mob"]["health"]["current"] + 0.5)))
                else:
                    _set_status("Defeated " + mob_target["mob"]["name"])
        if attacked_mob == false and target_hit != nil and target_hit["y"] > 0:
            let mined_id = target_hit["block_id"]
            if set_voxel(voxel, target_hit["x"], target_hit["y"], target_hit["z"], 0):
                spawn_voxel_pickup(gameplay_state, mined_id, 1, voxel_block_world_center(voxel, target_hit["x"], target_hit["y"], target_hit["z"]))
                _set_status("Mined " + voxel_block_name(voxel, mined_id) + " | Drop spawned")
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

    let dead_mobs = collect_dead_voxel_mobs(gameplay_state)
    let dmi = 0
    while dmi < len(dead_mobs):
        let dead_mob = dead_mobs[dmi]
        if dead_mob["drop_spawned"] == false:
            spawn_voxel_pickup(gameplay_state, dead_mob["drop_block"], dead_mob["drop_count"], dead_mob["position"])
        dmi = dmi + 1

    ensure_voxel_mob_population(gameplay_state, voxel, player["position"], 3, world_seed)

    draws = voxel_visible_draws(voxel, player["position"][0], player["position"][1], player["position"][2], stream_chunk_radius)
    set_view_position(ls, eye)
    update_light_ubo(ls)

    if shadow_renderer != nil:
        let shadow_focus = vec3(player["position"][0], 6.0, player["position"][2])
        let light_vp = compute_light_vp_stable(sun_dir, shadow_focus, 26.0, shadow_renderer["resolution"] + 0.0)
        let shadow_cmd = begin_shadow_frame(shadow_renderer, light_vp, 0)
        let di = 0
        while di < len(draws):
            if draws[di]["block_id"] != 8:
                shadow_draw_mesh(shadow_renderer, shadow_cmd, draws[di]["gpu_mesh"], mat4_identity())
            di = di + 1
        let mi = 0
        while mi < len(gameplay_state["mobs"]):
            let mob = gameplay_state["mobs"][mi]
            if mob["health"]["alive"]:
                let mob_center = mob_draw_position(mob, ts["total"])
                let mob_scale_y = 0.74 + math.sin(ts["total"] * 3.5 + mob["id"] * 0.8) * 0.08
                let mob_t = make_transform(mob_center, vec3(0.0, ts["total"] * 0.4, 0.0), vec3(0.85, mob_scale_y, 0.85))
                shadow_draw_mesh(shadow_renderer, shadow_cmd, cube_gpu, transform_to_matrix(mob_t))
            mi = mi + 1
        end_shadow_frame(shadow_renderer, shadow_cmd)

    if gpu.window_should_close():
        running = false
        continue
    let frame = begin_frame_commands(r)
    if frame == nil:
        # Transient resize/minimize/swapchain blip - skip this frame
        continue
    let cmd = frame["cmd"]

    let view = player_view_matrix(player)
    let aspect = r["width"] / r["height"]
    let proj = player_projection(player, aspect)
    let vp = mat4_mul(proj, view)
    let identity = mat4_identity()
    let world_mvp = mat4_mul(vp, identity)
    let sw = r["width"] + 0.0
    let sh = r["height"] + 0.0
    update_voxel_hud(voxel_hud, voxel, inventory, selected_block[0], inventory_open[0], recipes, sw, sh)

    begin_scene_pass(postprocess, cmd, r["clear_color"])
    draw_sky(sky, cmd, view, aspect, radians(player["fov"]), ts["total"])

    let ri = 0
    while ri < len(draws):
        let draw = draws[ri]
        if draw["block_id"] != 8:
            draw_mesh_lit_surface_controlled(cmd, lit_mat, draw["gpu_mesh"], world_mvp, identity, ls["desc_set"], draw["surface"], true)
        ri = ri + 1

    ri = 0
    while ri < len(draws):
        let draw = draws[ri]
        if draw["block_id"] == 8:
            draw_mesh_lit_surface_controlled(cmd, lit_water_mat, draw["gpu_mesh"], world_mvp, identity, ls["desc_set"], draw["surface"], false)
        ri = ri + 1

    let pi = 0
    while pi < len(gameplay_state["pickups"]):
        let pickup = gameplay_state["pickups"][pi]
        let pickup_center = pickup_draw_position(pickup, ts["total"])
        let pickup_t = make_transform(pickup_center, vec3(0.0, ts["total"] * 1.9 + pickup["id"], 0.0), vec3(0.26, 0.26, 0.26))
        let pickup_model = transform_to_matrix(pickup_t)
        let pickup_mvp = mat4_mul(vp, pickup_model)
        draw_mesh_lit_surface_controlled(cmd, lit_mat, cube_gpu, pickup_mvp, pickup_model, ls["desc_set"], voxel_block_surface(voxel, pickup["block_id"]), true)
        pi = pi + 1

    let mi = 0
    while mi < len(gameplay_state["mobs"]):
        let mob = gameplay_state["mobs"][mi]
        if mob["health"]["alive"]:
            let mob_center = mob_draw_position(mob, ts["total"])
            let mob_scale_y = 0.74 + math.sin(ts["total"] * 3.5 + mob["id"] * 0.8) * 0.08
            let mob_t = make_transform(mob_center, vec3(0.0, ts["total"] * 0.4, 0.0), vec3(0.85, mob_scale_y, 0.85))
            let mob_model = transform_to_matrix(mob_t)
            let mob_mvp = mat4_mul(vp, mob_model)
            draw_mesh_lit_surface_controlled(cmd, lit_mat, cube_gpu, mob_mvp, mob_model, ls["desc_set"], mob["surface"], true)
        mi = mi + 1

    if target_hit != nil:
        let center = voxel_block_world_center(voxel, target_hit["x"], target_hit["y"], target_hit["z"])
        let highlight_t = make_transform(center, vec3(0.0, ts["total"] * 0.8, 0.0), vec3(1.04, 1.04, 1.04))
        let highlight_model = transform_to_matrix(highlight_t)
        let highlight_mvp = mat4_mul(vp, highlight_model)
        draw_mesh_lit_surface_controlled(cmd, lit_mat, cube_gpu, highlight_mvp, highlight_model, ls["desc_set"], _highlight_surface(), false)
    if mob_target != nil and (target_hit == nil or mob_target["distance"] <= target_hit["distance"]):
        let mob_center = mob_draw_position(mob_target["mob"], ts["total"])
        let highlight_t = make_transform(mob_center, vec3(0.0, ts["total"] * 0.8, 0.0), vec3(1.08, 0.96, 1.08))
        let highlight_model = transform_to_matrix(highlight_t)
        let highlight_mvp = mat4_mul(vp, highlight_model)
        draw_mesh_lit_surface_controlled(cmd, lit_mat, cube_gpu, highlight_mvp, highlight_model, ls["desc_set"], _highlight_surface(), false)

    end_scene_pass(cmd)
    run_bloom_chain(postprocess, cmd)
    begin_swapchain_pass(r, frame)
    draw_tonemap(cmd, postprocess)

    let player_chunk = voxel_chunk_coords_world(voxel, player["position"][0], player["position"][1], player["position"][2])
    draw_ui(ui_renderer, cmd, voxel_hud["root"], sw, sh)
    begin_text(font_r)
    add_text(font_r, "ui", "VOXEL TEMPLATE SANDBOX", 18.0, 18.0, 0.94, 0.96, 0.98, 1.0)
    add_text(font_r, "ui", "LMB break / hit  RMB place  1-5 palette  Z planks  Wheel cycle  X craft  O inventory  C save  V load  TAB noclip  ESC mouse", 18.0, 42.0, 0.70, 0.74, 0.80, 1.0)
    add_text(font_r, "ui", "Selected: [" + str(selected_block[0]) + "] " + voxel_block_name(voxel, selected_block[0]) + " x" + str(voxel_inventory_count(inventory, selected_block[0])) + " | Health: " + str(math.floor(player_health["current"] + 0.5)) + "/" + str(player_health["max"]) + " | Slimes: " + str(voxel_alive_mob_count(gameplay_state)) + " | Drops: " + str(voxel_pickup_count(gameplay_state)), 18.0, 66.0, 0.90, 0.92, 0.95, 1.0)
    add_text(font_r, "ui", "Chunk: " + str(player_chunk["x"]) + ", " + str(player_chunk["y"]) + ", " + str(player_chunk["z"]) + " | Chunk size: " + str(voxel_chunk_size(voxel)) + " | Generated chunks: " + str(voxel_generated_chunk_count(voxel)) + " | Visible chunk draws: " + str(len(draws)), 18.0, 90.0, 0.72, 0.84, 0.92, 1.0)
    if mob_target != nil and (target_hit == nil or mob_target["distance"] <= target_hit["distance"]):
        add_text(font_r, "ui", "Target Mob: " + mob_target["mob"]["name"] + " | HP " + str(math.floor(mob_target["mob"]["health"]["current"] + 0.5)) + " | Range " + str(math.floor(mob_target["distance"] * 10.0) / 10.0), 18.0, 114.0, 0.78, 0.94, 0.76, 1.0)
    else:
        if target_hit != nil:
            add_text(font_r, "ui", "Target Block: " + voxel_block_name(voxel, target_hit["block_id"]) + " @ " + str(target_hit["x"]) + ", " + str(target_hit["y"]) + ", " + str(target_hit["z"]), 18.0, 114.0, 0.86, 0.84, 0.72, 1.0)
        else:
            add_text(font_r, "ui", "Target: none", 18.0, 114.0, 0.55, 0.58, 0.63, 1.0)
    if target_hit != nil and (mob_target == nil or mob_target["distance"] > target_hit["distance"]):
        add_text(font_r, "ui", "Break to spawn pickup, then walk over it to collect.", 18.0, 138.0, 0.72, 0.84, 0.76, 1.0)
    else:
        add_text(font_r, "ui", "Slimes drop wood when defeated. Use X to craft planks.", 18.0, 138.0, 0.72, 0.84, 0.76, 1.0)
    if status_timer[0] > 0.0 and status_line[0] != "":
        add_text(font_r, "ui", status_line[0], 18.0, 162.0, 0.76, 0.90, 0.74, 1.0)

    let hs = voxel_hud["hotbar_slots"]
    let hi = 0
    while hi < len(hs):
        let slot = hs[hi]
        if slot["panel"]["visible"]:
            let sx = slot["panel"]["computed_x"]
            let sy = slot["panel"]["computed_y"]
            let label_alpha = 0.78
            if slot["selected"]:
                label_alpha = 1.0
            add_text(font_r, "ui", _palette_slot_label(slot["block_id"]), sx + 4.0, sy + 2.0, 0.96, 0.98, 1.0, label_alpha)
            add_text(font_r, "ui", str(slot["count"]), sx + 19.0, sy + 28.0, 0.92, 0.94, 0.97, label_alpha)
        hi = hi + 1

    let craft_panel = voxel_hud["craft_panel"]
    let craft_recipe = voxel_hud["craft_recipe"]
    add_text(font_r, "ui", "CRAFTING", craft_panel["computed_x"] + 14.0, craft_panel["computed_y"] + 10.0, 0.94, 0.96, 0.98, 1.0)
    if craft_recipe != nil:
        let craft_ready_alpha = 0.82
        let craft_ready_r = 0.90
        let craft_ready_g = 0.82
        let craft_ready_b = 0.36
        if voxel_hud["craft_ready"]:
            craft_ready_alpha = 1.0
            craft_ready_r = 0.42
            craft_ready_g = 0.88
            craft_ready_b = 0.46
        add_text(font_r, "ui", voxel_block_name(voxel, craft_recipe["input_block"]), craft_panel["computed_x"] + 14.0, craft_panel["computed_y"] + 88.0, 0.82, 0.86, 0.90, 1.0)
        add_text(font_r, "ui", voxel_block_name(voxel, craft_recipe["output_block"]), craft_panel["computed_x"] + 166.0, craft_panel["computed_y"] + 88.0, 0.82, 0.86, 0.90, 1.0)
        add_text(font_r, "ui", str(voxel_inventory_count(inventory, craft_recipe["input_block"])) + "/" + str(craft_recipe["input_count"]) + "  X Craft", craft_panel["computed_x"] + 76.0, craft_panel["computed_y"] + 44.0, craft_ready_r, craft_ready_g, craft_ready_b, craft_ready_alpha)

    if inventory_open[0]:
        let inv_panel = voxel_hud["inventory_panel"]
        add_text(font_r, "ui", "BACKPACK [O]", inv_panel["computed_x"] + 12.0, inv_panel["computed_y"] + 8.0, 0.94, 0.96, 0.98, 1.0)
        let rows = voxel_hud["inventory_rows"]
        let ri = 0
        while ri < len(rows):
            let row = rows[ri]
            if row["panel"]["visible"]:
                let rx = row["panel"]["computed_x"]
                let ry = row["panel"]["computed_y"]
                let row_surface = voxel_block_surface(voxel, row["block_id"])
                let row_color = row_surface["albedo"]
                add_text(font_r, "ui", row["label"], rx + 40.0, ry + 4.0, row_color[0], row_color[1], row_color[2], 1.0)
                add_text(font_r, "ui", "x" + str(row["count"]), rx + 178.0, ry + 4.0, 0.92, 0.94, 0.97, 1.0)
            ri = ri + 1
    add_text(font_r, "ui", "+", sw / 2.0 - 5.0, sh / 2.0 - 12.0, 1.0, 1.0, 1.0, 0.95)
    flush_text(font_r, cmd, sw, sh)

    end_frame(r, frame)
    gc_collect()

    let title = "Forge Engine | Voxel Template | " + voxel_block_name(voxel, selected_block[0])
    update_title_fps(r, title)

gpu.device_wait_idle()
shutdown_renderer(r)
