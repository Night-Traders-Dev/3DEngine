# editor.sage - Forge Engine Visual Editor
# Unreal-style in-engine editor with viewport, hierarchy, inspector
# Auto-generates SageLang code from visual scene editing
#
# Run: ./run.sh editor.sage
# Controls:
#   Right Mouse = Orbit viewport | Middle Mouse = Pan | Scroll = Zoom
#   Left Click = Select entity | ESC = Deselect
#   1 = Translate | 2 = Rotate | 3 = Scale gizmo mode
#   R = Place cube | F = Place sphere | D = Delete selected
#   Q = Duplicate | 5 = Generate code | 4 = Save scene | CTRL+Q = Quit

import gpu
import math
import sys
from renderer import create_renderer, begin_frame, end_frame
from renderer import shutdown_renderer, check_resize, update_title_fps
from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, query, tick_systems, flush_dead
from ecs import entity_count, destroy, add_tag, has_tag, remove_component, register_system
from components import TransformComponent, NameComponent, PointLightComponent
from input import create_input, update_input, bind_action
from input import action_held, action_just_pressed
from input import mouse_delta, scroll_value, mouse_position
from engine_math import transform_to_matrix
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_cross
from math3d import mat4_mul, mat4_identity, radians, mat4_perspective, mat4_translate, mat4_scale
from mesh import cube_mesh, sphere_mesh, plane_mesh, upload_mesh
from lighting import create_light_scene, directional_light, point_light
from lighting import add_light, set_ambient, set_view_position
from lighting import init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit
from sky import create_sky, sky_preset_day, init_sky_gpu, draw_sky
from editor_grid import create_editor_grid, draw_editor_grid
from ui_renderer import create_ui_renderer, draw_ui, build_ui_vertices
from ui_core import create_widget, create_rect, create_panel, add_child, collect_quads, compute_layout
from font import create_font_renderer, load_font, begin_text, add_text, flush_text
from ui_window import create_ui_window, get_windows_sorted, update_windows
from ui_window import build_window_quads, window_content_area, bring_to_front
from ui_window import open_menu, close_menu, is_menu_open, build_menu_quads
from ui_window import get_menu_items, get_menu_pos, menu_item_at
import ui_widgets

# Theme colors (accessed via module to work around from-import limitation)
let THEME_BG = ui_widgets.THEME_BG
let THEME_PANEL = ui_widgets.THEME_PANEL
let THEME_HEADER = ui_widgets.THEME_HEADER
let THEME_BUTTON = ui_widgets.THEME_BUTTON
let THEME_ACCENT = ui_widgets.THEME_ACCENT
let THEME_TEXT = ui_widgets.THEME_TEXT
let THEME_TEXT_DIM = ui_widgets.THEME_TEXT_DIM
let THEME_SELECT = ui_widgets.THEME_SELECT
from editor_layout import create_editor_layout, get_viewport_bounds, resize_editor_layout
from editor_viewport import create_editor_camera, editor_camera_view
from editor_viewport import editor_camera_position
from scene_editor import create_scene_editor, select_entity, deselect, select_by_ray_mode
from scene_editor import place_entity, delete_selected, duplicate_selected
from scene_editor import apply_gizmo_delta, editor_stats
from scene_editor import select_all_entities, selected_entities, toggle_entity_selection
from gizmo import set_gizmo_mode, get_gizmo_visuals
from gizmo import GIZMO_TRANSLATE, GIZMO_ROTATE, GIZMO_SCALE
from inspector import create_inspector, inspect_entity, clear_inspection, refresh_inspector
from codegen import generate_game_script
from scene_serial import save_scene, load_scene, serialize_scene, load_scene_string
from physics import RigidbodyComponent, BoxColliderComponent, SphereColliderComponent
from physics import create_physics_world, create_physics_system
from undo_redo import execute_command, undo, redo, cmd_set_vec3
from gameplay import HealthComponent
import sys
from game_loop import create_time_state, update_time
from frustum import extract_frustum_planes, aabb_in_frustum
from asset_import import import_gltf, scan_importable_assets
import io

print "=== Forge Engine Editor ==="

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(1440, 900, "Forge Engine Editor")
if r == nil:
    raise "Failed to create renderer"
# Dark gray background (Unreal-style viewport)
# Viewport is brighter than panels (key design principle from UE5/Blender)
r["clear_color"] = [0.141, 0.141, 0.141, 1.0]
print "GPU: " + gpu.device_name()

# ============================================================================
# Lighting & Sky
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(-0.3, -0.8, -0.5, 1.0, 0.98, 0.92, 1.5))
add_light(ls, point_light(8.0, 6.0, 5.0, 1.0, 0.9, 0.8, 4.0, 30.0))
add_light(ls, point_light(-5.0, 4.0, -3.0, 0.8, 0.85, 1.0, 3.0, 25.0))
set_ambient(ls, 0.35, 0.35, 0.4, 0.6)
# Force initial UBO upload
set_view_position(ls, vec3(0.0, 5.0, 10.0))
update_light_ubo(ls)
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])

let sky = create_sky()
sky_preset_day(sky)
init_sky_gpu(sky, r["render_pass"])

# Editor grid (Unreal-style ground grid)
let grid = create_editor_grid(r["render_pass"])

# ============================================================================
# Meshes
# ============================================================================
let cube_gpu = upload_mesh(cube_mesh())
let sphere_gpu = upload_mesh(sphere_mesh(16, 16))
# No ground plane - the editor grid serves as the ground reference

# ============================================================================
# UI
# ============================================================================
let ui_r = create_ui_renderer(r["render_pass"])
let layout = create_editor_layout(1440.0, 900.0)

# Load TrueType fonts
let font_r = create_font_renderer(r["render_pass"])
# Single font atlas for all editor text (avoids multi-atlas batching issues)
let font_ui = load_font(font_r, "ui", "assets/DejaVuSans.ttf", 18.0)

# Floating windows
let win_outliner = create_ui_window("Outliner", 10.0, 66.0, layout["left_panel_w"], 450.0)
let win_details = create_ui_window("Details", 1180.0, 66.0, layout["right_panel_w"], 500.0)
let win_content = create_ui_window("Content Browser", 240.0, 700.0, 700.0, layout["bottom_panel_h"] + 40.0)

proc reset_layout_windows():
    let sw_l = layout["screen_w"]
    let sh_l = layout["screen_h"]
    let top_y = layout["menubar_h"] + layout["toolbar_h"] + 6.0
    win_outliner["visible"] = true
    win_details["visible"] = true
    win_content["visible"] = true
    win_outliner["collapsed"] = false
    win_details["collapsed"] = false
    win_content["collapsed"] = false
    win_outliner["x"] = 10.0
    win_outliner["y"] = top_y
    win_outliner["width"] = layout["left_panel_w"]
    win_outliner["height"] = sh_l - top_y - layout["statusbar_h"] - layout["bottom_panel_h"] - 22.0
    if win_outliner["height"] < 180.0:
        win_outliner["height"] = 180.0

    win_details["width"] = layout["right_panel_w"]
    win_details["height"] = sh_l - top_y - layout["statusbar_h"] - layout["bottom_panel_h"] - 22.0
    if win_details["height"] < 180.0:
        win_details["height"] = 180.0
    win_details["x"] = sw_l - win_details["width"] - 10.0
    win_details["y"] = top_y

    win_content["x"] = win_outliner["x"] + win_outliner["width"] + 10.0
    win_content["y"] = sh_l - layout["statusbar_h"] - layout["bottom_panel_h"] - 8.0
    win_content["width"] = sw_l - win_content["x"] - win_details["width"] - 20.0
    if win_content["width"] < 320.0:
        win_content["width"] = 320.0
    win_content["height"] = layout["bottom_panel_h"]

reset_layout_windows()

# Menu bar state
let menubar_active = -1

# ============================================================================
# ECS World (editor scene)
# ============================================================================
let world = create_world()
let editor = create_scene_editor(world)
let physics_world = create_physics_world()
register_system(world, "physics", ["rigidbody", "transform"], create_physics_system(physics_world))

# Default scene: ground plane
let ge = spawn(world)
add_component(world, ge, "transform", TransformComponent(0.0, 0.0, 0.0))
add_component(world, ge, "name", NameComponent("Ground"))
# No mesh - grid replaces ground plane visually
add_tag(world, ge, "editable")

# A few starter objects
let c1 = place_entity(editor, vec3(0.0, 0.5, 0.0), "Cube_1", cube_gpu)
add_component(world, c1, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
let c2 = place_entity(editor, vec3(3.0, 0.5, 0.0), "Cube_2", cube_gpu)
add_component(world, c2, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
let s1 = place_entity(editor, vec3(-2.0, 1.0, 2.0), "Sphere_1", sphere_gpu)
add_component(world, s1, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})

deselect(editor)
let entity_counter = 4
let play_mode = false
let play_snapshot = nil
let active_details_field = nil

proc _rehydrate_mesh_refs(w):
    let mids = query(w, ["mesh_id"])
    let mi = 0
    while mi < len(mids):
        let eid = mids[mi]
        let m = get_component(w, eid, "mesh_id")
        let mname = "cube"
        if dict_has(m, "name"):
            mname = m["name"]
        if mname == "sphere":
            m["mesh"] = sphere_gpu
        else:
            m["mesh"] = cube_gpu
        mi = mi + 1

# Scan for importable assets
let importable_assets = scan_importable_assets("assets")
let imported_models = {}
print "Found " + str(len(importable_assets)) + " importable assets"

# Auto-import any .gltf files found
let ai = 0
while ai < len(importable_assets):
    let ia = importable_assets[ai]
    if ia["type"] == "model" and endswith(ia["name"], ".gltf"):
        let asset = import_gltf(ia["path"])
        if asset != nil:
            imported_models[ia["name"]] = asset
    ai = ai + 1

print "Editor loaded with " + str(entity_count(world)) + " entities"
if len(dict_keys(imported_models)) > 0:
    print "Imported models: " + str(len(dict_keys(imported_models)))

# ============================================================================
# Editor camera
# ============================================================================
let cam = create_editor_camera()
cam["distance"] = 20.0
cam["pitch"] = 0.6
cam["yaw"] = 0.5

# ============================================================================
# Input
# ============================================================================
let inp = create_input()
bind_action(inp, "select", [gpu.KEY_ESCAPE])
bind_action(inp, "place_cube", [gpu.KEY_R])
bind_action(inp, "place_sphere", [gpu.KEY_F])
bind_action(inp, "delete", [gpu.KEY_D])
bind_action(inp, "duplicate", [gpu.KEY_Q])
bind_action(inp, "mode_translate", [gpu.KEY_1])
bind_action(inp, "mode_rotate", [gpu.KEY_2])
bind_action(inp, "mode_scale", [gpu.KEY_3])
bind_action(inp, "save_scene", [gpu.KEY_4])
bind_action(inp, "generate_code", [gpu.KEY_5])
bind_action(inp, "place_model", [gpu.KEY_E])
bind_action(inp, "pan", [gpu.KEY_SHIFT])
bind_action(inp, "toggle_physics", [gpu.KEY_TAB])
bind_action(inp, "play", [gpu.KEY_ENTER])

# ============================================================================
# Main loop
# ============================================================================
let ts = create_time_state()
let running = true
# UI text cache - rebuilt only when state changes
let _cached_text_quads = []
let _cached_text_verts = []
let _cached_text_vert_count = 0
let _cache_dirty = true
let _last_selected = -1
let _last_entity_count = 0
let _last_mode = ""
let _ui_rebuild_timer = 0.0

print ""
print "Controls:"
print "  RMB=Orbit  MMB=Pan  Scroll=Zoom  Right-Click=Context Menu"
print "  R=Cube  F=Sphere  E=Model  D=Delete  Q=Dup  TAB=Physics"
print "  1/2/3=Move/Rotate/Scale  4=Save  5=Code  ENTER=Play"
print "  CTRL+Z/Y=Undo/Redo  CTRL+A=Select All  CTRL+N/O/S=New/Open/Save"
print "  Drag window title bars to reposition panels"
print "  CTRL+Q=Quit"
print ""

while running:
    update_time(ts)
    let dt = ts["dt"]

    # Poll events FIRST, then handle resize, then input
    gpu.poll_events()
    if gpu.window_should_close():
        running = false
        continue
    # Handle resize after events are processed
    check_resize(r)
    let cur_w = r["width"] + 0.0
    let cur_h = r["height"] + 0.0
    if cur_w < 1.0 or cur_h < 1.0:
        continue
    if cur_w != layout["screen_w"] or cur_h != layout["screen_h"]:
        resize_editor_layout(layout, cur_w, cur_h)
    gpu.update_input()
    update_input(inp)

    # Global editor shortcuts
    if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_Q):
        running = false
        continue
    if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_Z):
        if undo(editor["history"]):
            refresh_inspector(editor["inspector"])
    if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_Y):
        if redo(editor["history"]):
            refresh_inspector(editor["inspector"])
    if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_A):
        let selected_count = select_all_entities(editor)
        if selected_count > 0:
            print "Selected " + str(selected_count) + " entities"
    if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_S):
        save_scene(world, "EditorScene", "assets/editor_scene.json")
        print "Scene saved: assets/editor_scene.json"
    if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_N):
        if play_mode:
            print "Stop Play mode before creating a new scene"
        else:
            let all_reset = query(world, ["transform"])
            let ri_reset = 0
            while ri_reset < len(all_reset):
                destroy(world, all_reset[ri_reset])
                ri_reset = ri_reset + 1
            flush_dead(world)
            let ge_new = spawn(world)
            add_component(world, ge_new, "transform", TransformComponent(0.0, 0.0, 0.0))
            add_component(world, ge_new, "name", NameComponent("Ground"))
            add_tag(world, ge_new, "editable")
            deselect(editor)
            entity_counter = 1
            print "New scene created"
    if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_O):
        if play_mode:
            print "Stop Play mode before opening a scene"
        else:
            if io.exists("assets/editor_scene.json"):
                let loaded_shortcut = load_scene("assets/editor_scene.json")
                if loaded_shortcut != nil:
                    world = loaded_shortcut["world"]
                    register_system(world, "physics", ["rigidbody", "transform"], create_physics_system(physics_world))
                    _rehydrate_mesh_refs(world)
                    editor["world"] = world
                    deselect(editor)
                    let entities_after_load = query(world, ["transform"])
                    entity_counter = len(entities_after_load) + 1
                    print "Scene opened: assets/editor_scene.json"
            else:
                print "Open failed: assets/editor_scene.json not found"

    # --- Camera orbit/pan/zoom (only when mouse is in viewport) ---
    let md = mouse_delta(inp)
    let sv = scroll_value(inp)
    let mp_temp = mouse_position(inp)
    let vp_b = get_viewport_bounds(layout)
    let mouse_in_viewport = mp_temp[0] > vp_b["x"] and mp_temp[0] < vp_b["x"] + vp_b["w"] and mp_temp[1] > vp_b["y"] and mp_temp[1] < vp_b["y"] + vp_b["h"]

    if mouse_in_viewport:
        if gpu.mouse_button(gpu.MOUSE_RIGHT):
            cam["yaw"] = cam["yaw"] + md[0] * 0.005
            cam["pitch"] = cam["pitch"] + md[1] * 0.005
            if cam["pitch"] < -1.5:
                cam["pitch"] = -1.5
            if cam["pitch"] > 1.5:
                cam["pitch"] = 1.5

        if gpu.mouse_button(gpu.MOUSE_MIDDLE):
            let cy = math.cos(cam["yaw"])
            let sy = math.sin(cam["yaw"])
            let pan_scale = cam["distance"] * 0.003
            cam["target"][0] = cam["target"][0] - md[0] * cy * pan_scale
            cam["target"][2] = cam["target"][2] + md[0] * sy * pan_scale
            cam["target"][1] = cam["target"][1] + md[1] * pan_scale

        if sv[1] != 0.0:
            cam["distance"] = cam["distance"] - sv[1] * 0.8
            if cam["distance"] < 1.0:
                cam["distance"] = 1.0
            if cam["distance"] > 200.0:
                cam["distance"] = 200.0

    # --- Gizmo mode ---
    if action_just_pressed(inp, "mode_translate"):
        set_gizmo_mode(editor["gizmo"], GIZMO_TRANSLATE)
    if action_just_pressed(inp, "mode_rotate"):
        set_gizmo_mode(editor["gizmo"], GIZMO_ROTATE)
    if action_just_pressed(inp, "mode_scale"):
        set_gizmo_mode(editor["gizmo"], GIZMO_SCALE)

    # --- Mouse picking and gizmo interaction ---
    let mp = mouse_position(inp)
    let mx = mp[0]
    let my = mp[1]
    let sw_f = r["width"] + 0.0
    let sh_f = r["height"] + 0.0

    # --- Floating window interaction ---
    let left_pressed = gpu.mouse_just_pressed(gpu.MOUSE_LEFT)
    let left_held = gpu.mouse_button(gpu.MOUSE_LEFT)
    let left_released = gpu.mouse_just_released(gpu.MOUSE_LEFT)
    let window_consumed = update_windows(mx, my, left_pressed, left_held, left_released)

    # --- Menu bar click handling ---
    if left_pressed and my < layout["menubar_h"]:
        let menu_x_positions = [8.0, 58.0, 108.0, 178.0, 240.0]
        let menu_w = [45.0, 45.0, 65.0, 55.0, 50.0]
        let clicked_menu = -1
        let cmi = 0
        while cmi < 5:
            if mx >= menu_x_positions[cmi] - 4.0 and mx < menu_x_positions[cmi] + menu_w[cmi]:
                clicked_menu = cmi
            cmi = cmi + 1
        if clicked_menu >= 0:
            if menubar_active == clicked_menu:
                menubar_active = -1
                close_menu()
            else:
                menubar_active = clicked_menu
                let menu_items_list = []
                if clicked_menu == 0:
                    menu_items_list = ["New Scene", "Open Scene...", "Save Scene", "---", "Export Game", "---", "Quit"]
                if clicked_menu == 1:
                    menu_items_list = ["Undo", "Redo", "---", "Delete", "Duplicate", "Select All"]
                if clicked_menu == 2:
                    menu_items_list = ["Outliner", "Details", "Content Browser", "---", "Reset Layout"]
                if clicked_menu == 3:
                    menu_items_list = ["Add Cube", "Add Sphere", "Add Physics Cube", "---", "Toggle Physics", "Generate Code"]
                if clicked_menu == 4:
                    menu_items_list = ["Controls", "---", "About Forge Engine"]
                open_menu(menu_x_positions[clicked_menu] - 4.0, layout["menubar_h"], menu_items_list)
            window_consumed = true
        else:
            menubar_active = -1
    # Close menu bar when clicking elsewhere
    if left_pressed and menubar_active >= 0 and my >= layout["menubar_h"]:
        if is_menu_open() and menu_item_at(mx, my) < 0:
            menubar_active = -1
            close_menu()

    # --- Toolbar button clicks ---
    if left_pressed and my >= layout["menubar_h"] and my < layout["menubar_h"] + layout["toolbar_h"]:
        # Play button
        if mx >= sw_f / 2.0 - 40.0 and mx < sw_f / 2.0 + 40.0:
            if play_mode == false:
                play_snapshot = serialize_scene(world, "PIE")
                play_mode = true
                print "Play mode started (ENTER or Play to stop)"
                gpu.set_title("Forge Engine Editor | PLAYING")
            else:
                if play_snapshot != nil:
                    let restored = load_scene_string(play_snapshot)
                    if restored != nil:
                        world = restored["world"]
                        register_system(world, "physics", ["rigidbody", "transform"], create_physics_system(physics_world))
                        _rehydrate_mesh_refs(world)
                        editor["world"] = world
                        deselect(editor)
                play_mode = false
                print "Play mode stopped"
                gpu.set_title("Forge Engine Editor")
            window_consumed = true
        # Save button
        if mx >= sw_f / 2.0 + 50.0 and mx < sw_f / 2.0 + 110.0:
            save_scene(world, "EditorScene", "assets/editor_scene.json")
            print "Scene saved: assets/editor_scene.json"
            window_consumed = true

    # Handle right-click context menu
    if gpu.mouse_just_pressed(gpu.MOUSE_RIGHT) and mouse_in_viewport:
        if is_menu_open():
            close_menu()
        else:
            open_menu(mx, my, ["Add Cube", "Add Sphere", "Add Physics Cube", "Add Light", "---", "Select All", "Delete Selected"])

    # Menu click (handles both context menu and menu bar dropdowns)
    if left_pressed and is_menu_open():
        let menu_idx = menu_item_at(mx, my)
        if menu_idx >= 0:
            let items = get_menu_items()
            let item = items[menu_idx]
            if play_mode and (item == "Add Cube" or item == "Add Sphere" or item == "Add Physics Cube" or item == "Add Light" or item == "Delete" or item == "Delete Selected" or item == "Duplicate" or item == "Toggle Physics" or item == "New Scene" or item == "Open Scene..."):
                print "Stop Play mode before editing the scene"
                close_menu()
                menubar_active = -1
                window_consumed = true
                continue
            # --- Tools / Context menu actions ---
            if item == "Add Cube":
                entity_counter = entity_counter + 1
                let pos = vec3(cam["target"][0], 0.5, cam["target"][2])
                let eid = place_entity(editor, pos, "Cube_" + str(entity_counter), cube_gpu)
                add_component(world, eid, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
            if item == "Add Sphere":
                entity_counter = entity_counter + 1
                let pos = vec3(cam["target"][0], 1.0, cam["target"][2])
                let eid = place_entity(editor, pos, "Sphere_" + str(entity_counter), sphere_gpu)
                add_component(world, eid, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})
            if item == "Add Physics Cube":
                entity_counter = entity_counter + 1
                let pos = vec3(cam["target"][0], 2.0, cam["target"][2])
                let eid = place_entity(editor, pos, "PhysCube_" + str(entity_counter), cube_gpu)
                add_component(world, eid, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
                add_component(world, eid, "rigidbody", RigidbodyComponent(1.0))
                add_component(world, eid, "collider", BoxColliderComponent(0.5, 0.5, 0.5))
                add_component(world, eid, "health", HealthComponent(50.0))
            if item == "Add Light":
                entity_counter = entity_counter + 1
                let pos = vec3(cam["target"][0], 2.5, cam["target"][2])
                let eid = place_entity(editor, pos, "Light_" + str(entity_counter), sphere_gpu)
                add_component(world, eid, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})
                add_component(world, eid, "light", PointLightComponent(1.0, 0.95, 0.85, 3.0, 18.0))
            # --- File menu ---
            if item == "New Scene":
                let all_reset_menu = query(world, ["transform"])
                let rm_i = 0
                while rm_i < len(all_reset_menu):
                    destroy(world, all_reset_menu[rm_i])
                    rm_i = rm_i + 1
                flush_dead(world)
                let ge_new_menu = spawn(world)
                add_component(world, ge_new_menu, "transform", TransformComponent(0.0, 0.0, 0.0))
                add_component(world, ge_new_menu, "name", NameComponent("Ground"))
                add_tag(world, ge_new_menu, "editable")
                deselect(editor)
                entity_counter = 1
                print "New scene created"
            if item == "Open Scene...":
                if io.exists("assets/editor_scene.json"):
                    let loaded_menu = load_scene("assets/editor_scene.json")
                    if loaded_menu != nil:
                        world = loaded_menu["world"]
                        register_system(world, "physics", ["rigidbody", "transform"], create_physics_system(physics_world))
                        _rehydrate_mesh_refs(world)
                        editor["world"] = world
                        deselect(editor)
                        let entities_after_load_menu = query(world, ["transform"])
                        entity_counter = len(entities_after_load_menu) + 1
                        print "Scene opened: assets/editor_scene.json"
                else:
                    print "Open failed: assets/editor_scene.json not found"
            if item == "Save Scene":
                save_scene(world, "EditorScene", "assets/editor_scene.json")
                print "Scene saved: assets/editor_scene.json"
            if item == "Export Game":
                let code = generate_game_script(world, "ForgeGame", {"width": 1280, "height": 720})
                io.writefile("assets/generated_game.sage", code)
                print "Game exported: assets/generated_game.sage"
            if item == "Quit":
                running = false
            # --- Edit menu ---
            if item == "Undo":
                if undo(editor["history"]):
                    refresh_inspector(editor["inspector"])
            if item == "Redo":
                if redo(editor["history"]):
                    refresh_inspector(editor["inspector"])
            if item == "Delete" or item == "Delete Selected":
                delete_selected(editor)
                flush_dead(world)
            if item == "Duplicate":
                duplicate_selected(editor)
            if item == "Select All":
                let csel = select_all_entities(editor)
                if csel > 0:
                    print "Selected " + str(csel) + " entities"
            # --- Window menu ---
            if item == "Outliner":
                win_outliner["visible"] = true
                bring_to_front(win_outliner)
            if item == "Details":
                win_details["visible"] = true
                bring_to_front(win_details)
            if item == "Content Browser":
                win_content["visible"] = true
                bring_to_front(win_content)
            if item == "Reset Layout":
                reset_layout_windows()
                print "Layout reset"
            # --- Tools menu ---
            if item == "Toggle Physics":
                if editor["selected"] >= 0:
                    let sel = editor["selected"]
                    if has_component(world, sel, "rigidbody"):
                        remove_component(world, sel, "rigidbody")
                        remove_component(world, sel, "collider")
                    else:
                        add_component(world, sel, "rigidbody", RigidbodyComponent(1.0))
                        add_component(world, sel, "collider", BoxColliderComponent(0.5, 0.5, 0.5))
                        add_component(world, sel, "health", HealthComponent(50.0))
            if item == "Generate Code":
                let code = generate_game_script(world, "GeneratedGame", {"width": 1280, "height": 720})
                io.writefile("assets/generated_game.sage", code)
                print "Generated: assets/generated_game.sage"
            # --- Help menu ---
            if item == "Controls":
                print "Controls: RMB orbit | MMB pan | Wheel zoom | R/F place | D delete | Q duplicate | TAB physics | ENTER play"
            if item == "About Forge Engine":
                print "Forge Engine Editor - UE-style SageLang editor (Vulkan backend)"
            close_menu()
            menubar_active = -1
            window_consumed = true
        else:
            # Clicked outside menu — close it (unless clicking another menu bar item)
            if my >= layout["menubar_h"] or mx < 0.0 or mx > 300.0:
                close_menu()
                menubar_active = -1

    # --- Floating window content clicks (handled even though window_consumed is true) ---
    if left_pressed:
        let oca_click = window_content_area(win_outliner)
        let in_outliner = win_outliner["visible"] and mx >= oca_click["x"] and mx < oca_click["x"] + oca_click["w"] and my >= oca_click["y"] and my < oca_click["y"] + oca_click["h"]
        if in_outliner:
            let click_idx = math.floor((my - oca_click["y"]) / 24.0)
            let all_ents = query(world, ["transform"])
            if click_idx >= 0 and click_idx < len(all_ents):
                if gpu.key_pressed(gpu.KEY_CTRL):
                    toggle_entity_selection(editor, all_ents[click_idx])
                else:
                    select_entity(editor, all_ents[click_idx])
            window_consumed = true
        let dca_click = window_content_area(win_details)
        let in_details = win_details["visible"] and win_details["collapsed"] == false and mx >= dca_click["x"] and mx < dca_click["x"] + dca_click["w"] and my >= dca_click["y"] and my < dca_click["y"] + dca_click["h"]
        if in_details and editor["selected"] >= 0 and has_component(world, editor["selected"], "transform"):
            active_details_field = nil
            let dx = dca_click["x"]
            let dw = dca_click["w"]
            let fw3 = (dw - 16.0) / 3.0
            let iy = dca_click["y"]
            if has_component(world, editor["selected"], "name"):
                iy = iy + 28.0
            iy = iy + 26.0
            iy = iy + 22.0
            let col = -1
            if mx >= dx + 2.0 and mx < dx + 2.0 + fw3:
                col = 0
            if mx >= dx + fw3 + 6.0 and mx < dx + fw3 + 6.0 + fw3:
                col = 1
            if mx >= dx + fw3 * 2.0 + 10.0 and mx < dx + fw3 * 2.0 + 10.0 + fw3:
                col = 2
            if col >= 0 and my >= iy and my < iy + 20.0:
                active_details_field = {"key": "position", "axis": col}
            iy = iy + 26.0
            iy = iy + 22.0
            if col >= 0 and my >= iy and my < iy + 20.0:
                active_details_field = {"key": "rotation", "axis": col}
            iy = iy + 26.0
            iy = iy + 22.0
            if col >= 0 and my >= iy and my < iy + 20.0:
                active_details_field = {"key": "scale", "axis": col}
            window_consumed = true
        if in_details == false and in_outliner == false:
            active_details_field = nil

    # --- Viewport click handler ---
    if left_pressed and window_consumed == false:
        let vp_bounds = get_viewport_bounds(layout)
        let in_vp = mx > vp_bounds["x"] and mx < vp_bounds["x"] + vp_bounds["w"] and my > vp_bounds["y"] and my < vp_bounds["y"] + vp_bounds["h"]
        if in_vp:
            let cam_pos = editor_camera_position(cam)
            let fov = radians(60.0)
            let aspect = vp_bounds["w"] / vp_bounds["h"]
            let norm_x = (mx - vp_bounds["x"]) / vp_bounds["w"] * 2.0 - 1.0
            let norm_y = 1.0 - (my - vp_bounds["y"]) / vp_bounds["h"] * 2.0
            let tan_half = math.tan(fov * 0.5)
            let rx = norm_x * aspect * tan_half
            let ry = norm_y * tan_half
            let cam_fwd = v3_normalize(v3_sub(cam["target"], cam_pos))
            let cam_right = v3_normalize(v3_cross(cam_fwd, vec3(0.0, 1.0, 0.0)))
            let cam_up = v3_cross(cam_right, cam_fwd)
            let ray_dir = v3_normalize(v3_add(v3_add(v3_scale(cam_right, rx), v3_scale(cam_up, ry)), cam_fwd))
            select_by_ray_mode(editor, cam_pos, ray_dir, gpu.key_pressed(gpu.KEY_CTRL))

    # Inspector quick-edit: scroll wheel over active transform field
    if play_mode == false and active_details_field != nil and editor["selected"] >= 0 and has_component(world, editor["selected"], "transform"):
        if sv[1] != 0.0:
            let t_edit = get_component(world, editor["selected"], "transform")
            let key = active_details_field["key"]
            let axis = active_details_field["axis"]
            let step = 0.1
            if gpu.key_pressed(gpu.KEY_SHIFT):
                step = 1.0
            if key == "scale":
                step = 0.05
            let nv = t_edit[key][axis] + sv[1] * step
            if key == "scale" and nv < 0.01:
                nv = 0.01
            execute_command(editor["history"], cmd_set_vec3(t_edit, key, axis, nv))
            t_edit["dirty"] = true

    # --- Entity operations ---
    if action_just_pressed(inp, "select"):
        deselect(editor)
        active_details_field = nil

    if play_mode == false and action_just_pressed(inp, "place_cube"):
        entity_counter = entity_counter + 1
        let pos = vec3(cam["target"][0], 0.5, cam["target"][2])
        let eid = place_entity(editor, pos, "Cube_" + str(entity_counter), cube_gpu)
        add_component(world, eid, "mesh_id", {"mesh": cube_gpu, "name": "cube"})

    if play_mode == false and action_just_pressed(inp, "place_sphere"):
        entity_counter = entity_counter + 1
        let pos = vec3(cam["target"][0], 1.0, cam["target"][2])
        let eid = place_entity(editor, pos, "Sphere_" + str(entity_counter), sphere_gpu)
        add_component(world, eid, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})

    if play_mode == false and action_just_pressed(inp, "place_model"):
        let model_keys = dict_keys(imported_models)
        if len(model_keys) > 0:
            let model_asset = imported_models[model_keys[0]]
            entity_counter = entity_counter + 1
            let pos = vec3(cam["target"][0], 0.0, cam["target"][2])
            let eid = place_entity(editor, pos, model_asset["name"] + "_" + str(entity_counter), nil)
            # Store the imported model's GPU meshes on the entity
            add_component(world, eid, "imported_asset", model_asset)
            # Also add the first mesh as mesh_id for basic rendering
            if len(model_asset["gpu_meshes"]) > 0:
                add_component(world, eid, "mesh_id", {"mesh": model_asset["gpu_meshes"][0]["gpu_mesh"], "name": "imported"})
        else:
            print "No imported models available. Place .gltf files in assets/"

    if play_mode == false and action_just_pressed(inp, "delete"):
        delete_selected(editor)
        flush_dead(world)
        active_details_field = nil

    if play_mode == false and action_just_pressed(inp, "duplicate"):
        duplicate_selected(editor)

    # Toggle physics on selected entity (TAB)
    if play_mode == false and action_just_pressed(inp, "toggle_physics"):
        if editor["selected"] >= 0:
            let sel = editor["selected"]
            if has_component(world, sel, "rigidbody"):
                # Remove physics
                from ecs import remove_component
                remove_component(world, sel, "rigidbody")
                remove_component(world, sel, "collider")
                print "Physics removed from #" + str(sel)
            else:
                # Add physics (1kg dynamic body with box collider)
                add_component(world, sel, "rigidbody", RigidbodyComponent(1.0))
                add_component(world, sel, "collider", BoxColliderComponent(0.5, 0.5, 0.5))
                add_component(world, sel, "health", HealthComponent(50.0))
                print "Physics + Health added to #" + str(sel)

    # Play mode (ENTER) — toggle Play-In-Editor simulation
    if action_just_pressed(inp, "play"):
        if play_mode == false:
            play_snapshot = serialize_scene(world, "PIE")
            play_mode = true
            print "Play mode started (ENTER to stop)"
            gpu.set_title("Forge Engine Editor | PLAYING")
        else:
            if play_snapshot != nil:
                let restored_enter = load_scene_string(play_snapshot)
                if restored_enter != nil:
                    world = restored_enter["world"]
                    register_system(world, "physics", ["rigidbody", "transform"], create_physics_system(physics_world))
                    _rehydrate_mesh_refs(world)
                    editor["world"] = world
                    deselect(editor)
            play_mode = false
            print "Play mode stopped"
            gpu.set_title("Forge Engine Editor")

    # --- Keyboard nudge for selected entity (arrow keys) ---
    if play_mode == false and editor["selected"] >= 0 and has_component(world, editor["selected"], "transform"):
        let nudge_speed = 3.0 * dt
        let nudge_targets = selected_entities(editor)
        if len(nudge_targets) == 0:
            nudge_targets = [editor["selected"]]
        if gpu.key_pressed(gpu.KEY_UP):
            let ni = 0
            while ni < len(nudge_targets):
                let t = get_component(world, nudge_targets[ni], "transform")
                if t != nil:
                    execute_command(editor["history"], cmd_set_vec3(t, "position", 2, t["position"][2] - nudge_speed))
                    t["dirty"] = true
                ni = ni + 1
        if gpu.key_pressed(gpu.KEY_DOWN):
            let ni = 0
            while ni < len(nudge_targets):
                let t = get_component(world, nudge_targets[ni], "transform")
                if t != nil:
                    execute_command(editor["history"], cmd_set_vec3(t, "position", 2, t["position"][2] + nudge_speed))
                    t["dirty"] = true
                ni = ni + 1
        if gpu.key_pressed(gpu.KEY_LEFT):
            let ni = 0
            while ni < len(nudge_targets):
                let t = get_component(world, nudge_targets[ni], "transform")
                if t != nil:
                    execute_command(editor["history"], cmd_set_vec3(t, "position", 0, t["position"][0] - nudge_speed))
                    t["dirty"] = true
                ni = ni + 1
        if gpu.key_pressed(gpu.KEY_RIGHT):
            let ni = 0
            while ni < len(nudge_targets):
                let t = get_component(world, nudge_targets[ni], "transform")
                if t != nil:
                    execute_command(editor["history"], cmd_set_vec3(t, "position", 0, t["position"][0] + nudge_speed))
                    t["dirty"] = true
                ni = ni + 1

    # (Click handling done above in unified handler)

    # --- Save / Generate ---
    if action_just_pressed(inp, "save_scene"):
        save_scene(world, "EditorScene", "assets/editor_scene.json")

    if action_just_pressed(inp, "generate_code"):
        let code = generate_game_script(world, "GeneratedGame", {"width": 1280, "height": 720})
        io.writefile("assets/generated_game.sage", code)
        print "Generated: assets/generated_game.sage"

    if play_mode:
        tick_systems(world, dt)
        flush_dead(world)

    # --- Update inspector ---
    if editor["selected"] >= 0:
        refresh_inspector(editor["inspector"])

    # --- Lighting ---
    let cam_pos = editor_camera_position(cam)
    set_view_position(ls, cam_pos)
    update_light_ubo(ls)

    # --- Render ---
    if gpu.window_should_close():
        running = false
        continue
    let frame = begin_frame(r)
    if frame == nil:
        # Frame failed (resize/minimize) - skip but don't quit
        continue
    let cmd = frame["cmd"]

    let view = editor_camera_view(cam)
    let aspect = r["width"] / r["height"]
    let proj = mat4_mul(mat4_identity(), mat4_identity())
    proj = mat4_perspective(radians(60.0), aspect, 0.1, 500.0)
    let vp = mat4_mul(proj, view)
    let sw = r["width"] + 0.0
    let sh = r["height"] + 0.0

    # Sky
    # Draw editor grid (Unreal-style) instead of sky
    draw_editor_grid(grid, cmd, vp)

    # 3D scene with frustum culling
    let frustum_planes = extract_frustum_planes(vp)
    let renderers = query(world, ["transform", "mesh_id"])
    let draw_count = 0
    let ri = 0
    while ri < len(renderers):
        let eid = renderers[ri]
        let t = get_component(world, eid, "transform")
        let pos = t["position"]
        # Frustum cull with generous bounds
        let half_ext = vec3(2.0, 2.0, 2.0)
        if aabb_in_frustum(frustum_planes, pos, half_ext):
            let mi = get_component(world, eid, "mesh_id")
            let model = transform_to_matrix(t)
            let mvp = mat4_mul(vp, model)
            draw_mesh_lit(cmd, lit_mat, mi["mesh"], mvp, model, ls["desc_set"])
            draw_count = draw_count + 1
        ri = ri + 1

    # Gizmo visualization (draw handles as colored boxes)
    if editor["selected"] >= 0:
        let gvis = get_gizmo_visuals(editor["gizmo"])
        let gi = 0
        while gi < len(gvis):
            let gv = gvis[gi]
            let gtrans = mat4_translate(gv["pos"][0], gv["pos"][1], gv["pos"][2])
            let gscl = mat4_scale(gv["half"][0] * 2.0, gv["half"][1] * 2.0, gv["half"][2] * 2.0)
            let gmodel = mat4_mul(gtrans, gscl)
            let gmvp = mat4_mul(vp, gmodel)
            draw_mesh_lit(cmd, lit_mat, cube_gpu, gmvp, gmodel, ls["desc_set"])
            gi = gi + 1


    # --- Editor UI (TrueType font rendering) ---
    let mb_h = layout["menubar_h"]
    let tb_h = layout["toolbar_h"]
    let sb_h = layout["statusbar_h"]
    let top_h = mb_h + tb_h
    let cur_sel = editor["selected"]
    let cur_mode = editor["gizmo"]["mode"]

    # Draw panel backgrounds (menu bar + toolbar + status bar)
    draw_ui(ui_r, cmd, layout["root"], sw, sh)

    # Extra quads: menu bar hover, toolbar mode buttons, viewport overlay
    let ui_quads = []

    # Menu bar hover highlight
    let menu_labels = ["File", "Edit", "Window", "Tools", "Help"]
    let menu_x_pos = [8.0, 58.0, 108.0, 178.0, 240.0]
    let menu_widths = [45.0, 45.0, 65.0, 55.0, 50.0]
    let mhi = 0
    while mhi < 5:
        if menubar_active == mhi:
            push(ui_quads, {"x": menu_x_pos[mhi] - 4.0, "y": 0.0, "w": menu_widths[mhi], "h": mb_h, "color": [0.290, 0.565, 0.851, 0.4]})
        mhi = mhi + 1

    # Toolbar mode buttons (below menu bar)
    let modes = ["translate", "rotate", "scale"]
    let mode_labels = ["Move", "Rotate", "Scale"]
    let mx_b = 10.0
    let mi_b = 0
    while mi_b < 3:
        let bc = [0.212, 0.212, 0.212, 1.0]
        if cur_mode == modes[mi_b]:
            bc = [0.290, 0.565, 0.851, 0.8]
        push(ui_quads, {"x": mx_b, "y": mb_h + 4.0, "w": 70.0, "h": 26.0, "color": bc})
        mx_b = mx_b + 75.0
        mi_b = mi_b + 1

    # Play button
    let play_btn_col = [0.15, 0.45, 0.15, 1.0]
    if play_mode:
        play_btn_col = [0.55, 0.20, 0.20, 1.0]
    push(ui_quads, {"x": sw / 2.0 - 40.0, "y": mb_h + 4.0, "w": 80.0, "h": 26.0, "color": play_btn_col})

    # Save button
    push(ui_quads, {"x": sw / 2.0 + 50.0, "y": mb_h + 4.0, "w": 60.0, "h": 26.0, "color": [0.212, 0.212, 0.212, 1.0]})

    # Viewport overlay bar (top of viewport area)
    let vp_b = get_viewport_bounds(layout)
    push(ui_quads, {"x": vp_b["x"], "y": vp_b["y"], "w": vp_b["w"], "h": 28.0, "color": [0.098, 0.098, 0.098, 0.75]})
    push(ui_quads, {"x": vp_b["x"], "y": vp_b["y"] + 28.0, "w": vp_b["w"], "h": 1.0, "color": [0.065, 0.065, 0.065, 0.5]})

    let ents = query(world, ["transform"])
    if len(ui_quads) > 0:
        let uv = build_quad_verts(ui_quads)
        gpu.buffer_upload(ui_r["vbuf"], uv)
        gpu.cmd_bind_graphics_pipeline(cmd, ui_r["pipeline"])
        gpu.cmd_push_constants(cmd, ui_r["pipe_layout"], gpu.STAGE_VERTEX, [sw, sh, 0.0, 0.0])
        gpu.cmd_bind_vertex_buffer(cmd, ui_r["vbuf"])
        gpu.cmd_draw(cmd, len(ui_quads) * 6, 1, 0, 0)

    # --- TrueType text (batched: begin -> add_text calls -> flush) ---
    begin_text(font_r)

    proc _fn(n):
        return str(math.floor(n * 100.0 + 0.5) / 100.0)

    # Menu bar text
    let mti = 0
    while mti < 5:
        let mc = [0.65, 0.65, 0.65, 1.0]
        if menubar_active == mti:
            mc = [1.0, 1.0, 1.0, 1.0]
        add_text(font_r, "ui", menu_labels[mti], menu_x_pos[mti], 5.0, mc[0], mc[1], mc[2], 1.0)
        mti = mti + 1
    # Project name on right side of menu bar
    add_text(font_r, "ui", "Forge Engine", sw - 130.0, 5.0, 0.439, 0.439, 0.439, 1.0)

    # Toolbar text
    add_text(font_r, "ui", "Move", 22.0, mb_h + 8.0, 0.78, 0.78, 0.78, 1.0)
    add_text(font_r, "ui", "Rotate", 92.0, mb_h + 8.0, 0.78, 0.78, 0.78, 1.0)
    add_text(font_r, "ui", "Scale", 172.0, mb_h + 8.0, 0.78, 0.78, 0.78, 1.0)
    let play_label = "Play"
    if play_mode:
        play_label = "Stop"
    add_text(font_r, "ui", play_label, sw / 2.0 - 22.0, mb_h + 8.0, 0.9, 0.9, 0.9, 1.0)
    add_text(font_r, "ui", "Save", sw / 2.0 + 62.0, mb_h + 8.0, 0.78, 0.78, 0.78, 1.0)

    # Viewport overlay text
    add_text(font_r, "ui", "Perspective", vp_b["x"] + 10.0, vp_b["y"] + 6.0, 0.65, 0.65, 0.65, 1.0)
    add_text(font_r, "ui", "Lit", vp_b["x"] + 120.0, vp_b["y"] + 6.0, 0.65, 0.65, 0.65, 1.0)
    add_text(font_r, "ui", "Show", vp_b["x"] + 160.0, vp_b["y"] + 6.0, 0.65, 0.65, 0.65, 1.0)

    # Status bar
    let stats = editor_stats(editor)
    let status = str(stats["entities"]) + " entities  " + str(draw_count) + " drawn  " + stats["mode"]
    if stats["selected_count"] > 1:
        status = status + "  |  " + str(stats["selected_count"]) + " selected"
    else:
        if stats["selected"] >= 0:
            status = status + "  |  #" + str(stats["selected"])
    if play_mode:
        status = status + "  |  PLAYING"
    status = status + "  |  FPS: " + str(math.floor(ts["fps"]))
    add_text(font_r, "ui", status, 8.0, sh - sb_h + 5.0, 0.439, 0.439, 0.439, 1.0)

    flush_text(font_r, cmd, sw, sh)

    # --- Floating windows (rendered on top of everything) ---
    let all_win_quads = []
    let sorted_wins = get_windows_sorted()
    let wi = 0
    while wi < len(sorted_wins):
        let wq = build_window_quads(sorted_wins[wi])
        array_extend(all_win_quads, wq)
        wi = wi + 1
    # Details panel section headers + input field backgrounds
    if win_details["visible"] and win_details["collapsed"] == false and cur_sel >= 0 and has_component(world, cur_sel, "transform"):
        let dca_q = window_content_area(win_details)
        let dqx = dca_q["x"]
        let dqy = dca_q["y"]
        let dqw = dca_q["w"]
        # Entity name bar
        if has_component(world, cur_sel, "name"):
            push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 24.0, "color": [0.176, 0.176, 0.176, 1.0]})
            dqy = dqy + 28.0
        # Transform section header
        push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 22.0, "color": [0.120, 0.120, 0.120, 1.0]})
        dqy = dqy + 26.0
        # Location row
        push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 18.0, "color": [0.110, 0.110, 0.110, 0.5]})
        dqy = dqy + 22.0
        # XYZ input fields for location
        let fw3 = (dqw - 16.0) / 3.0
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": fw3, "h": 20.0, "color": [0.098, 0.098, 0.098, 1.0]})
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.9, 0.22, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": fw3, "h": 20.0, "color": [0.098, 0.098, 0.098, 1.0]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.9, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": fw3, "h": 20.0, "color": [0.098, 0.098, 0.098, 1.0]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.22, 0.9, 0.8]})
        dqy = dqy + 26.0
        # Rotation row
        push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 18.0, "color": [0.110, 0.110, 0.110, 0.5]})
        dqy = dqy + 22.0
        # XYZ input fields for rotation
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": fw3, "h": 20.0, "color": [0.098, 0.098, 0.098, 1.0]})
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.9, 0.22, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": fw3, "h": 20.0, "color": [0.098, 0.098, 0.098, 1.0]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.9, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": fw3, "h": 20.0, "color": [0.098, 0.098, 0.098, 1.0]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.22, 0.9, 0.8]})
        dqy = dqy + 26.0
        # Scale row
        push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 18.0, "color": [0.110, 0.110, 0.110, 0.5]})
        dqy = dqy + 22.0
        # XYZ input fields for scale
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": fw3, "h": 20.0, "color": [0.098, 0.098, 0.098, 1.0]})
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.9, 0.22, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": fw3, "h": 20.0, "color": [0.098, 0.098, 0.098, 1.0]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.9, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": fw3, "h": 20.0, "color": [0.098, 0.098, 0.098, 1.0]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.22, 0.9, 0.8]})

    # Selection highlight in outliner window
    if win_outliner["visible"] and win_outliner["collapsed"] == false:
        let oca_h = window_content_area(win_outliner)
        let hey = oca_h["y"]
        let sel_ids = selected_entities(editor)
        let hei = 0
        while hei < len(ents) and hei < 25:
            let is_sel = false
            let si = 0
            while si < len(sel_ids):
                if ents[hei] == sel_ids[si]:
                    is_sel = true
                si = si + 1
            if is_sel:
                push(all_win_quads, {"x": oca_h["x"], "y": hey - 1.0, "w": oca_h["w"], "h": 20.0, "color": [0.290, 0.565, 0.851, 0.15]})
            hey = hey + 24.0
            hei = hei + 1
    # Add menu quads if open
    if is_menu_open():
        let mq = build_menu_quads()
        array_extend(all_win_quads, mq)
    if len(all_win_quads) > 0:
        let wv = build_quad_verts(all_win_quads)
        gpu.buffer_upload(ui_r["vbuf"], wv)
        gpu.cmd_bind_graphics_pipeline(cmd, ui_r["pipeline"])
        gpu.cmd_push_constants(cmd, ui_r["pipe_layout"], gpu.STAGE_VERTEX, [sw, sh, 0.0, 0.0])
        gpu.cmd_bind_vertex_buffer(cmd, ui_r["vbuf"])
        gpu.cmd_draw(cmd, len(all_win_quads) * 6, 1, 0, 0)

    # Floating window title + content text
    begin_text(font_r)
    wi = 0
    while wi < len(sorted_wins):
        let fw = sorted_wins[wi]
        if fw["visible"]:
            add_text(font_r, "ui", fw["title"], fw["x"] + 8.0, fw["y"] + 4.0, 0.784, 0.784, 0.784, 1.0)
        wi = wi + 1

    # --- Outliner content ---
    if win_outliner["visible"] and win_outliner["collapsed"] == false:
        let oca = window_content_area(win_outliner)
        let oy = oca["y"]
        let sel_out = selected_entities(editor)
        let oei = 0
        while oei < len(ents) and oei < 25:
            let eid = ents[oei]
            let ename = "Entity_" + str(eid)
            if has_component(world, eid, "name"):
                ename = get_component(world, eid, "name")["name"]
            let is_sel_text = false
            let so = 0
            while so < len(sel_out):
                if eid == sel_out[so]:
                    is_sel_text = true
                so = so + 1
            if is_sel_text:
                add_text(font_r, "ui", ename, oca["x"] + 6.0, oy, 1.0, 1.0, 1.0, 1.0)
            else:
                add_text(font_r, "ui", ename, oca["x"] + 6.0, oy, 0.55, 0.55, 0.55, 1.0)
            oy = oy + 24.0
            oei = oei + 1

    # --- Details content ---
    if win_details["visible"] and win_details["collapsed"] == false:
        let dca = window_content_area(win_details)
        let dx = dca["x"]
        let dy = dca["y"]
        let dw = dca["w"]
        let fw3 = (dw - 16.0) / 3.0
        if cur_sel >= 0 and has_component(world, cur_sel, "transform"):
            let st = get_component(world, cur_sel, "transform")
            let iy = dy
            if has_component(world, cur_sel, "name"):
                add_text(font_r, "ui", get_component(world, cur_sel, "name")["name"], dx + 6.0, iy + 3.0, 0.9, 0.9, 0.9, 1.0)
                iy = iy + 28.0
            # Transform section header
            add_text(font_r, "ui", "Transform", dx + 6.0, iy + 2.0, 0.784, 0.784, 0.784, 1.0)
            iy = iy + 26.0
            # Location
            add_text(font_r, "ui", "Location", dx + 4.0, iy + 1.0, 0.439, 0.439, 0.439, 1.0)
            iy = iy + 22.0
            add_text(font_r, "ui", _fn(st["position"][0]), dx + 10.0, iy + 2.0, 0.78, 0.78, 0.78, 1.0)
            add_text(font_r, "ui", _fn(st["position"][1]), dx + fw3 + 14.0, iy + 2.0, 0.78, 0.78, 0.78, 1.0)
            add_text(font_r, "ui", _fn(st["position"][2]), dx + fw3 * 2.0 + 18.0, iy + 2.0, 0.78, 0.78, 0.78, 1.0)
            iy = iy + 26.0
            # Rotation
            add_text(font_r, "ui", "Rotation", dx + 4.0, iy + 1.0, 0.439, 0.439, 0.439, 1.0)
            iy = iy + 22.0
            add_text(font_r, "ui", _fn(st["rotation"][0]), dx + 10.0, iy + 2.0, 0.78, 0.78, 0.78, 1.0)
            add_text(font_r, "ui", _fn(st["rotation"][1]), dx + fw3 + 14.0, iy + 2.0, 0.78, 0.78, 0.78, 1.0)
            add_text(font_r, "ui", _fn(st["rotation"][2]), dx + fw3 * 2.0 + 18.0, iy + 2.0, 0.78, 0.78, 0.78, 1.0)
            iy = iy + 26.0
            # Scale
            add_text(font_r, "ui", "Scale", dx + 4.0, iy + 1.0, 0.439, 0.439, 0.439, 1.0)
            iy = iy + 22.0
            add_text(font_r, "ui", _fn(st["scale"][0]), dx + 10.0, iy + 2.0, 0.78, 0.78, 0.78, 1.0)
            add_text(font_r, "ui", _fn(st["scale"][1]), dx + fw3 + 14.0, iy + 2.0, 0.78, 0.78, 0.78, 1.0)
            add_text(font_r, "ui", _fn(st["scale"][2]), dx + fw3 * 2.0 + 18.0, iy + 2.0, 0.78, 0.78, 0.78, 1.0)
            iy = iy + 28.0
            if active_details_field != nil:
                let axis_lbl = "X"
                if active_details_field["axis"] == 1:
                    axis_lbl = "Y"
                if active_details_field["axis"] == 2:
                    axis_lbl = "Z"
                add_text(font_r, "ui", "Edit: " + active_details_field["key"] + "." + axis_lbl + " (Wheel, SHIFT=fine)", dx + 8.0, iy, 0.357, 0.627, 0.914, 1.0)
                iy = iy + 22.0
            # Physics section
            if has_component(world, cur_sel, "rigidbody"):
                let rb = get_component(world, cur_sel, "rigidbody")
                add_text(font_r, "ui", "Physics", dx + 6.0, iy + 2.0, 0.784, 0.784, 0.784, 1.0)
                iy = iy + 24.0
                if rb["is_kinematic"]:
                    add_text(font_r, "ui", "Static Body", dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                else:
                    add_text(font_r, "ui", "Mass: " + _fn(rb["mass"]) + "  Bounce: " + _fn(rb["restitution"]), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                iy = iy + 20.0
            if has_component(world, cur_sel, "health"):
                let hp = get_component(world, cur_sel, "health")
                add_text(font_r, "ui", "Health: " + _fn(hp["current"]) + " / " + _fn(hp["max"]), dx + 8.0, iy, 0.3, 0.85, 0.3, 1.0)
                iy = iy + 22.0
            # Material section
            if has_component(world, cur_sel, "imported_asset"):
                let ia = get_component(world, cur_sel, "imported_asset")
                add_text(font_r, "ui", "Material", dx + 6.0, iy + 2.0, 0.784, 0.784, 0.784, 1.0)
                iy = iy + 24.0
                if len(ia["materials"]) > 0:
                    let mat = ia["materials"][0]
                    add_text(font_r, "ui", mat["name"], dx + 8.0, iy, 0.65, 0.65, 0.65, 1.0)
                    iy = iy + 18.0
                    add_text(font_r, "ui", "Metallic: " + _fn(mat["metallic"]), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                    iy = iy + 16.0
                    add_text(font_r, "ui", "Roughness: " + _fn(mat["roughness"]), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
        else:
            add_text(font_r, "ui", "Select an entity to view details", dx + 4.0, dy + 8.0, 0.439, 0.439, 0.439, 1.0)

    # --- Content Browser content ---
    if win_content["visible"] and win_content["collapsed"] == false:
        let cca = window_content_area(win_content)
        add_text(font_r, "ui", "R=Cube  F=Sphere  E=Model  D=Del  Q=Dup  TAB=Physics  ENTER=Play", cca["x"] + 4.0, cca["y"] + 4.0, 0.38, 0.38, 0.42, 1.0)
        add_text(font_r, "ui", "LClick=Select  RMB=Orbit  MMB=Pan  Scroll=Zoom  4=Save  5=Code", cca["x"] + 4.0, cca["y"] + 24.0, 0.38, 0.38, 0.42, 1.0)
        let model_names = dict_keys(imported_models)
        if len(model_names) > 0:
            let model_str = "Imported: "
            let mn = 0
            while mn < len(model_names):
                if mn > 0:
                    model_str = model_str + ", "
                model_str = model_str + model_names[mn]
                mn = mn + 1
            add_text(font_r, "ui", model_str, cca["x"] + 4.0, cca["y"] + 44.0, 0.357, 0.627, 0.914, 1.0)
    # Menu item text
    if is_menu_open():
        let mitems = get_menu_items()
        let mpos = get_menu_pos()
        let mii = 0
        while mii < len(mitems):
            let item_text = mitems[mii]
            if item_text != "---":
                add_text(font_r, "ui", item_text, mpos[0] + 12.0, mpos[1] + 6.0 + mii * 24.0, 0.8, 0.84, 0.96, 1.0)
            mii = mii + 1
    flush_text(font_r, cmd, sw, sh)

    end_frame(r, frame)
    update_title_fps(r, "Forge Engine Editor")

try:
    gpu.device_wait_idle()
    shutdown_renderer(r)
catch e:
    print "Shutdown warning: " + str(e)
print "Editor closed"
