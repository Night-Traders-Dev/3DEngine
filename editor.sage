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
from launch_screen import run_launch_screen
from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, query, tick_systems, flush_dead
from ecs import entity_count, destroy, add_tag, has_tag, remove_component, register_system
from components import TransformComponent, NameComponent, PointLightComponent, DirectionalLightComponent, MaterialComponent
from components import MeshRendererComponent
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
from render_system import create_lit_material, draw_mesh_lit, draw_mesh_lit_surface
from render_system import draw_mesh_lit_surface_skinned, draw_mesh_lit_controlled
from render_system import draw_mesh_lit_surface_controlled, draw_mesh_lit_surface_skinned_controlled
from render_system import set_lit_material_shadow_source
from pbr_material import create_pbr_renderer, create_pbr_fallback_textures
from pbr_material import create_pbr_material_from_imported, bind_pbr_material, draw_pbr
from pbr_material import draw_pbr_skinned, draw_pbr_controlled, draw_pbr_skinned_controlled
from pbr_material import set_pbr_shadow_source
from sky import create_sky, sky_preset_day, init_sky_gpu, draw_sky
from editor_grid import create_editor_grid, draw_editor_grid
from ui_renderer import create_ui_renderer, draw_ui, build_ui_vertices
from ui_core import create_widget, create_rect, create_panel, add_child, collect_quads, compute_layout
from font import create_font_renderer, load_font, begin_text, add_text, flush_text
from ui_window import create_ui_window, get_windows_sorted, update_windows
from ui_window import build_window_quads, window_content_area, bring_to_front
from ui_window import open_menu, close_menu, is_menu_open, build_menu_quads
from ui_window import get_menu_items, get_menu_pos, menu_item_at
from ui_window import scroll_window, update_window_content_height, mouse_in_window_content
from ui_window import set_screen_dims, snap_window_to_edge
from ui_window import show_modal, close_modal, is_modal_open, get_modal, build_modal_quads, modal_click
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
# Inline gizmo mode constants (avoids LLVM cross-module resolution issue)
let GIZMO_TRANSLATE = "translate"
let GIZMO_ROTATE = "rotate"
let GIZMO_SCALE = "scale"
from inspector import create_inspector, inspect_entity, clear_inspection, refresh_inspector
from codegen import generate_game_script
from scene_serial import save_scene, load_scene, serialize_scene, load_scene_string
from physics import RigidbodyComponent, BoxColliderComponent, SphereColliderComponent
from physics import create_physics_world, create_physics_system
from undo_redo import execute_command, undo, redo, cmd_set_vec3, cmd_set_property
from gameplay import HealthComponent
import sys
from game_loop import create_time_state, update_time
from frustum import extract_frustum_planes, aabb_in_frustum
from shadow_map import create_shadow_renderer, compute_light_vp, primary_shadow_light
from shadow_map import begin_shadow_frame, end_shadow_frame, shadow_draw_mesh, shadow_draw_mesh_skinned
from post_fx import create_postfx, pfx_cinematic, build_vignette_quads
from lod import create_lod_config, compute_lod
from asset_import import import_gltf, scan_importable_assets, imported_asset_draws
from asset_import import imported_animation_clip_names, imported_animation_index
from asset_import import imported_animation_duration, create_imported_animation_state
from asset_import import advance_imported_animation_state, cycle_imported_animation_clip, step_imported_animation_time
from forge_version import engine_name, editor_title, editor_play_title, about_text
import io

print "=== Forge Engine Editor ==="

# ============================================================================
# Engine config (supports FORGE_WIDTH, FORGE_HEIGHT env vars)
# ============================================================================
import sys
let _init_w = 1440
let _init_h = 900
let _env_w = sys.getenv("FORGE_WIDTH")
let _env_h = sys.getenv("FORGE_HEIGHT")
if _env_w != nil and _env_w != "":
    _init_w = tonumber(_env_w)
if _env_h != nil and _env_h != "":
    _init_h = tonumber(_env_h)

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(_init_w, _init_h, editor_title())
if r == nil:
    raise "Failed to create renderer"
# Very dark viewport so lit 3D objects stand out clearly
r["clear_color"] = [0.028, 0.028, 0.032, 1.0]
print "GPU: " + gpu.device_name()

# ============================================================================
# Launch Screen (project browser — runs before editor)
# ============================================================================
let _launch_result = run_launch_screen(r)
if _launch_result["action"] == "exit":
    gpu.device_wait_idle()
    shutdown_renderer(r)
    print "Exited from launcher."
    raise "exit"
let _launch_template = _launch_result["template"]
let _launch_action = _launch_result["action"]
if _launch_template != nil:
    print "Template: " + str(_launch_template)
if _launch_action == "open":
    print "Opening existing project..."

# ============================================================================
# Lighting & Sky
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
set_ambient(ls, 0.25, 0.25, 0.3, 0.5)
# Force initial UBO upload
set_view_position(ls, vec3(0.0, 5.0, 10.0))
update_light_ubo(ls)
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])
let pbr_renderer = create_pbr_renderer(r["render_pass"], ls["desc_layout"])
let pbr_sampler = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_REPEAT)
let pbr_fallbacks = create_pbr_fallback_textures()

let sky = create_sky()
sky_preset_day(sky)
init_sky_gpu(sky, r["render_pass"])

# Editor grid (Unreal-style ground grid)
let grid = create_editor_grid(r["render_pass"])

# Post-processing effects (subtle vignette for cinematic viewport)
let editor_postfx = create_postfx()
editor_postfx["vignette_enabled"] = true
editor_postfx["vignette_intensity"] = 0.25
editor_postfx["vignette_radius"] = 0.85
editor_postfx["vignette_softness"] = 0.4

# LOD configuration (distances for mesh detail levels)
let editor_lod = create_lod_config([30.0, 80.0, 200.0, 500.0, 1000.0])

# Shadow map (2048x2048 resolution) — optional, may fail on some GPUs
let shadow_renderer = nil
try:
    shadow_renderer = create_shadow_renderer(2048)
    if shadow_renderer != nil:
        set_lit_material_shadow_source(lit_mat, shadow_renderer)
        if pbr_renderer != nil:
            set_pbr_shadow_source(pbr_renderer, shadow_renderer)
        let shadow_light_vp = compute_light_vp(vec3(-0.3, -0.8, -0.5), vec3(0.0, 0.0, 0.0), 50.0)
        shadow_renderer["light_vp"] = shadow_light_vp
        print "Shadow map initialized (2048x2048)"
catch e:
    print "Shadow map skipped: " + str(e)

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
_ensure_entity_mesh_renderer(world, c1, "cube")
let c2 = place_entity(editor, vec3(3.0, 0.5, 0.0), "Cube_2", cube_gpu)
add_component(world, c2, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
_ensure_entity_mesh_renderer(world, c2, "cube")
let s1 = place_entity(editor, vec3(-2.0, 1.0, 2.0), "Sphere_1", sphere_gpu)
add_component(world, s1, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})
_ensure_entity_mesh_renderer(world, s1, "sphere")

_sync_world_lights(ls, world)
update_light_ubo(ls)

deselect(editor)
let entity_counter = 4
let play_mode = false
let play_snapshot = nil
let active_details_field = nil
let details_edit_tf = nil
let show_shortcuts = false

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
            if mname == "imported":
                _ensure_entity_mesh_renderer(w, eid, "imported")
                mi = mi + 1
                continue
            m["mesh"] = cube_gpu
        _ensure_entity_mesh_renderer(w, eid, mname)
        mi = mi + 1

proc _rehydrate_imported_assets(w):
    let imported_ids = query(w, ["imported_asset"])
    let ii = 0
    while ii < len(imported_ids):
        let eid = imported_ids[ii]
        let ia = get_component(w, eid, "imported_asset")
        let source = ""
        if dict_has(ia, "source"):
            source = ia["source"]
        if source != "":
            let asset = nil
            if dict_has(ia, "name") and dict_has(imported_models, ia["name"]):
                asset = imported_models[ia["name"]]
            if asset == nil:
                asset = import_gltf(source)
                if asset != nil:
                    _ensure_imported_pbr_materials(asset)
                    if dict_has(ia, "name"):
                        imported_models[ia["name"]] = asset
            if asset != nil:
                add_component(w, eid, "imported_asset", asset)
                if len(asset["gpu_meshes"]) > 0:
                    add_component(w, eid, "mesh_id", {"mesh": asset["gpu_meshes"][0]["gpu_mesh"], "name": "imported"})
                    _ensure_entity_mesh_renderer(w, eid, "imported")
        ii = ii + 1

# Scan for importable assets
let importable_assets = scan_importable_assets("assets")
let imported_models = {}
let content_assets_all = []
let content_assets_models = []
let content_assets_textures = []
let content_assets_sprites = []
let content_assets_animations = []
let content_filter = "all"
let content_selected_index = 0

proc _add_content_asset(name, kind, path):
    let row = {"name": name, "kind": kind, "path": path}
    push(content_assets_all, row)
    if kind == "model":
        push(content_assets_models, row)
    if kind == "texture":
        push(content_assets_textures, row)
    if kind == "sprite":
        push(content_assets_sprites, row)
    if kind == "animation":
        push(content_assets_animations, row)

proc _add_animation_content_asset(name, path, clip_name):
    let row = {"name": name, "kind": "animation", "path": path, "clip": clip_name}
    push(content_assets_all, row)
    push(content_assets_animations, row)

proc _content_filtered():
    if content_filter == "models":
        return content_assets_models
    if content_filter == "textures":
        return content_assets_textures
    if content_filter == "sprites":
        return content_assets_sprites
    if content_filter == "animations":
        return content_assets_animations
    return content_assets_all

proc _set_content_filter(filter_name):
    content_filter = filter_name
    content_selected_index = 0
    win_content["visible"] = true
    bring_to_front(win_content)

proc _clip_text_line(text, max_chars):
    if max_chars < 4:
        return ""
    if len(text) <= max_chars:
        return text
    let out = ""
    let i = 0
    while i < max_chars - 3:
        out = out + text[i]
        i = i + 1
    return out + "..."

proc _surface_from_imported_material(mat_info):
    if mat_info == nil:
        return nil
    let surface = {}
    surface["albedo"] = vec3(1.0, 1.0, 1.0)
    surface["alpha"] = 1.0
    if dict_has(mat_info, "albedo_color"):
        surface["albedo"] = vec3(mat_info["albedo_color"][0], mat_info["albedo_color"][1], mat_info["albedo_color"][2])
        if len(mat_info["albedo_color"]) > 3:
            surface["alpha"] = mat_info["albedo_color"][3]
    return surface

proc _ensure_imported_pbr_materials(asset):
    if asset == nil:
        return []
    if dict_has(asset, "pbr_materials") and len(asset["pbr_materials"]) == len(asset["materials"]):
        return asset["pbr_materials"]
    let built = []
    let mats = []
    if dict_has(asset, "materials"):
        mats = asset["materials"]
    let i = 0
    while i < len(mats):
        let pbr_mat = create_pbr_material_from_imported(mats[i], pbr_fallbacks)
        if pbr_renderer != nil and pbr_sampler >= 0:
            bind_pbr_material(pbr_renderer, pbr_mat, pbr_sampler)
        push(built, pbr_mat)
        i = i + 1
    asset["pbr_materials"] = built
    return built

proc _ensure_entity_mesh_renderer(w, eid, material_id):
    let mesh_handle = nil
    if has_component(w, eid, "mesh_id"):
        let mi = get_component(w, eid, "mesh_id")
        if mi != nil and dict_has(mi, "mesh"):
            mesh_handle = mi["mesh"]
    if has_component(w, eid, "mesh_renderer"):
        let mr = get_component(w, eid, "mesh_renderer")
        mr["mesh"] = mesh_handle
        if dict_has(mr, "material") == false or mr["material"] == nil or mr["material"] == "":
            mr["material"] = material_id
        if dict_has(mr, "visible") == false:
            mr["visible"] = true
        if dict_has(mr, "cast_shadows") == false:
            mr["cast_shadows"] = true
        if dict_has(mr, "receive_shadows") == false:
            mr["receive_shadows"] = true
        return mr
    let mr = MeshRendererComponent(mesh_handle, material_id)
    add_component(w, eid, "mesh_renderer", mr)
    return mr

proc _mesh_visible(w, eid):
    if has_component(w, eid, "mesh_renderer"):
        let mr = get_component(w, eid, "mesh_renderer")
        if mr != nil and dict_has(mr, "visible"):
            return mr["visible"]
    return true

proc _mesh_casts_shadows(w, eid):
    if _mesh_visible(w, eid) == false:
        return false
    if has_component(w, eid, "mesh_renderer"):
        let mr = get_component(w, eid, "mesh_renderer")
        if mr != nil and dict_has(mr, "cast_shadows"):
            return mr["cast_shadows"]
    return true

proc _mesh_receives_shadows(w, eid):
    if _mesh_visible(w, eid) == false:
        return false
    if has_component(w, eid, "mesh_renderer"):
        let mr = get_component(w, eid, "mesh_renderer")
        if mr != nil and dict_has(mr, "receive_shadows"):
            return mr["receive_shadows"]
    return true

proc _directional_light_dir_from_transform(transform):
    let rot = transform["rotation"]
    let has_rotation = math.abs(rot[0]) > 0.0001 or math.abs(rot[1]) > 0.0001 or math.abs(rot[2]) > 0.0001
    if has_rotation == false:
        return vec3(-0.3, -0.8, -0.5)
    let pitch = rot[0]
    let yaw = rot[1]
    let cp = math.cos(pitch)
    let sp = math.sin(pitch)
    let cy = math.cos(yaw)
    let sy = math.sin(yaw)
    return vec3(0.0 - sy * cp, 0.0 - sp, 0.0 - cy * cp)

proc _add_default_editor_lights(light_scene):
    light_scene["lights"] = []
    add_light(light_scene, directional_light(-0.3, -0.8, -0.5, 1.0, 0.98, 0.92, 1.8))
    add_light(light_scene, point_light(8.0, 6.0, 5.0, 1.0, 0.95, 0.85, 4.5, 35.0))
    add_light(light_scene, point_light(-5.0, 4.0, -3.0, 0.7, 0.8, 1.0, 3.0, 25.0))
    add_light(light_scene, point_light(-8.0, 3.0, 6.0, 0.6, 0.65, 0.8, 2.0, 30.0))
    add_light(light_scene, point_light(0.0, 8.0, -8.0, 0.9, 0.9, 1.0, 2.5, 40.0))

proc _sync_world_lights(light_scene, w):
    let authored = query(w, ["transform", "light"])
    light_scene["lights"] = []
    if len(authored) == 0:
        _add_default_editor_lights(light_scene)
        return 5
    let i = 0
    while i < len(authored):
        let eid = authored[i]
        let t = get_component(w, eid, "transform")
        let light = get_component(w, eid, "light")
        if t != nil and light != nil:
            if light["type"] == "directional":
                let dir = _directional_light_dir_from_transform(t)
                let l = directional_light(dir[0], dir[1], dir[2], light["color"][0], light["color"][1], light["color"][2], light["intensity"])
                if dict_has(light, "cast_shadows"):
                    l["cast_shadows"] = light["cast_shadows"]
                add_light(light_scene, l)
            else:
                let pos = t["position"]
                let radius = 20.0
                if dict_has(light, "radius"):
                    radius = light["radius"]
                let l = point_light(pos[0], pos[1], pos[2], light["color"][0], light["color"][1], light["color"][2], light["intensity"], radius)
                if dict_has(light, "cast_shadows"):
                    l["cast_shadows"] = light["cast_shadows"]
                add_light(light_scene, l)
        i = i + 1
    return len(light_scene["lights"])

proc _update_imported_animation_states(w, dt):
    let animated = query(w, ["imported_asset", "animation_state"])
    let i = 0
    while i < len(animated):
        let eid = animated[i]
        let asset = get_component(w, eid, "imported_asset")
        let anim_state = get_component(w, eid, "animation_state")
        if asset != nil and anim_state != nil:
            advance_imported_animation_state(asset, anim_state, dt)
        i = i + 1

proc _render_shadow_world(sr, w, light_scene, focus_point, radius):
    if sr == nil:
        return false
    let shadow_light = primary_shadow_light(light_scene)
    if shadow_light["index"] < 0:
        return false
    let light_vp = compute_light_vp(shadow_light["direction"], focus_point, radius)
    let cmd = begin_shadow_frame(sr, light_vp, shadow_light["index"])
    let renderers = query(w, ["transform", "mesh_id"])
    let i = 0
    while i < len(renderers):
        let eid = renderers[i]
        let t = get_component(w, eid, "transform")
        if t != nil and _mesh_casts_shadows(w, eid):
            let model = transform_to_matrix(t)
            if has_component(w, eid, "imported_asset"):
                let asset = get_component(w, eid, "imported_asset")
                let anim_state = nil
                if has_component(w, eid, "animation_state"):
                    anim_state = get_component(w, eid, "animation_state")
                let draws = imported_asset_draws(asset, anim_state)
                let gi = 0
                while gi < len(draws):
                    let gm = draws[gi]
                    let imported_model = mat4_mul(model, gm["model"])
                    shadow_draw_mesh_skinned(sr, cmd, gm["gpu_mesh"], imported_model, gm)
                    gi = gi + 1
            else:
                let mi = get_component(w, eid, "mesh_id")
                if mi != nil and dict_has(mi, "mesh") and mi["mesh"] != nil:
                    shadow_draw_mesh(sr, cmd, mi["mesh"], model)
        i = i + 1
    end_shadow_frame(sr, cmd)
    return true

print "Found " + str(len(importable_assets)) + " importable assets"

# Auto-import any .gltf files found
let ai = 0
while ai < len(importable_assets):
    let ia = importable_assets[ai]
    if ia["type"] == "model":
        _add_content_asset(ia["name"], "model", ia["path"])
    if ia["type"] == "texture":
        _add_content_asset(ia["name"], "texture", ia["path"])
        if endswith(ia["name"], ".png"):
            _add_content_asset(ia["name"], "sprite", ia["path"])
    if ia["type"] == "model" and endswith(ia["name"], ".gltf"):
        let asset = import_gltf(ia["path"])
        if asset != nil:
            _ensure_imported_pbr_materials(asset)
            imported_models[ia["name"]] = asset
            if asset["animation_count"] > 0:
                let ani = 0
                while ani < asset["animation_count"]:
                    let aname = "Anim_" + str(ani)
                    if ani < len(asset["animations"]):
                        let a = asset["animations"][ani]
                        if dict_has(a, "name"):
                            aname = a["name"]
                    _add_animation_content_asset(ia["name"] + " :: " + aname, ia["path"], aname)
                    ani = ani + 1
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
# Hoisted procs (LLVM backend requires module-level proc definitions)
# ============================================================================
proc _quit_callback():
    running = false

proc _commit_field(val):
    let n = ui_widgets.parse_number(val)
    let t = get_component(world, editor["selected"], "transform")
    let cmd = cmd_set_vec3(t, active_details_field["key"], active_details_field["axis"], n)
    execute_command(editor["history"], cmd)
    active_details_field = nil
    details_edit_tf = nil

proc _fmt_num(n):
    return str(math.floor(n * 100.0 + 0.5) / 100.0)

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
        set_screen_dims(cur_w, cur_h)
        reset_layout_windows()
    gpu.update_input()
    update_input(inp)

    # Text input processing (when a field is focused, consume keyboard input)
    ui_widgets.update_text_input(dt)
    let text_editing = ui_widgets.is_any_field_focused()

    # F1 = shortcuts overlay
    if gpu.key_just_pressed(gpu.KEY_F1):
        show_shortcuts = show_shortcuts == false

    # Modal dialog input (blocks everything else)
    if is_modal_open():
        if left_pressed:
            modal_click(mx, my, sw_f, sh_f)
        if gpu.key_just_pressed(gpu.KEY_ESCAPE):
            close_modal()
        continue

    # Global editor shortcuts (suppressed during text editing)
    if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_Q):
        show_modal("Quit", "Are you sure you want to quit?", _quit_callback, nil)
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
                    _rehydrate_imported_assets(world)
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

    # Scroll in floating windows (intercept before viewport)
    let scroll_consumed = false
    if sv[1] != 0.0:
        if mouse_in_window_content(win_outliner, mp_temp[0], mp_temp[1]):
            scroll_window(win_outliner, sv[1] * -20.0)
            scroll_consumed = true
        if mouse_in_window_content(win_details, mp_temp[0], mp_temp[1]):
            scroll_window(win_details, sv[1] * -20.0)
            scroll_consumed = true
        if mouse_in_window_content(win_content, mp_temp[0], mp_temp[1]):
            scroll_window(win_content, sv[1] * -20.0)
            scroll_consumed = true

    if mouse_in_viewport and scroll_consumed == false:
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

        if sv[1] != 0.0 and scroll_consumed == false:
            cam["distance"] = cam["distance"] - sv[1] * 0.8
            if cam["distance"] < 1.0:
                cam["distance"] = 1.0
            if cam["distance"] > 200.0:
                cam["distance"] = 200.0

    # --- Gizmo mode ---
    if text_editing == false and action_just_pressed(inp, "mode_translate"):
        set_gizmo_mode(editor["gizmo"], GIZMO_TRANSLATE)
    if text_editing == false and action_just_pressed(inp, "mode_rotate"):
        set_gizmo_mode(editor["gizmo"], GIZMO_ROTATE)
    if text_editing == false and action_just_pressed(inp, "mode_scale"):
        set_gizmo_mode(editor["gizmo"], GIZMO_SCALE)

    # --- Mouse picking and gizmo interaction ---
    let mp = mouse_position(inp)
    let mx = mp[0]
    let my = mp[1]
    let sw_f = r["width"] + 0.0
    let sh_f = r["height"] + 0.0
    let cca_scroll = window_content_area(win_content)
    let mouse_in_content = win_content["visible"] and win_content["collapsed"] == false and mx >= cca_scroll["x"] and mx < cca_scroll["x"] + cca_scroll["w"] and my >= cca_scroll["y"] and my < cca_scroll["y"] + cca_scroll["h"]
    if mouse_in_content and sv[1] != 0.0:
        let filtered_scroll = _content_filtered()
        if len(filtered_scroll) > 0:
            content_selected_index = content_selected_index - math.floor(sv[1])
            if content_selected_index < 0:
                content_selected_index = 0
            if content_selected_index >= len(filtered_scroll):
                content_selected_index = len(filtered_scroll) - 1

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
                    menu_items_list = ["New Scene", "Open Scene...", "Save Scene", "Save Screenshot", "---", "Export Game", "Compile Native", "---", "Quit"]
                if clicked_menu == 1:
                    menu_items_list = ["Undo", "Redo", "---", "Delete", "Duplicate", "Select All"]
                if clicked_menu == 2:
                    menu_items_list = ["Outliner", "Details", "Content Browser", "---", "Reset Layout"]
                if clicked_menu == 3:
                    menu_items_list = ["Add Cube", "Add Sphere", "Add Physics Cube", "Add Light", "Add Directional Light", "---", "Apply Metal", "Apply Wood", "Apply Glass", "Apply Gold", "---", "Toggle Visibility", "Toggle Cast Shadows", "Toggle Receive Shadows", "Toggle Physics", "Save as Prefab", "---", "Generate Code"]
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
                gpu.set_title(editor_play_title())
            else:
                if play_snapshot != nil:
                    let restored = load_scene_string(play_snapshot)
                    if restored != nil:
                        world = restored["world"]
                        register_system(world, "physics", ["rigidbody", "transform"], create_physics_system(physics_world))
                        _rehydrate_mesh_refs(world)
                        _rehydrate_imported_assets(world)
                        editor["world"] = world
                        deselect(editor)
                play_mode = false
                print "Play mode stopped"
                gpu.set_title(editor_title())
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
            open_menu(mx, my, ["Add Cube", "Add Sphere", "Add Physics Cube", "Add Light", "Add Directional Light", "---", "Place Selected Asset", "Browse Assets", "Browse Textures", "Browse Sprites", "Browse Animations", "---", "Toggle Visibility", "Toggle Cast Shadows", "Toggle Receive Shadows", "---", "Select All", "Delete Selected"])

    # Menu click (handles both context menu and menu bar dropdowns)
    if left_pressed and is_menu_open():
        let menu_idx = menu_item_at(mx, my)
        if menu_idx >= 0:
            let items = get_menu_items()
            let item = items[menu_idx]
            if play_mode and (item == "Add Cube" or item == "Add Sphere" or item == "Add Physics Cube" or item == "Add Light" or item == "Add Directional Light" or item == "Place Selected Asset" or item == "Delete" or item == "Delete Selected" or item == "Duplicate" or item == "Toggle Visibility" or item == "Toggle Cast Shadows" or item == "Toggle Receive Shadows" or item == "Toggle Physics" or item == "New Scene" or item == "Open Scene..."):
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
                _ensure_entity_mesh_renderer(world, eid, "cube")
            if item == "Add Sphere":
                entity_counter = entity_counter + 1
                let pos = vec3(cam["target"][0], 1.0, cam["target"][2])
                let eid = place_entity(editor, pos, "Sphere_" + str(entity_counter), sphere_gpu)
                add_component(world, eid, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})
                _ensure_entity_mesh_renderer(world, eid, "sphere")
            if item == "Add Physics Cube":
                entity_counter = entity_counter + 1
                let pos = vec3(cam["target"][0], 2.0, cam["target"][2])
                let eid = place_entity(editor, pos, "PhysCube_" + str(entity_counter), cube_gpu)
                add_component(world, eid, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
                _ensure_entity_mesh_renderer(world, eid, "cube")
                add_component(world, eid, "rigidbody", RigidbodyComponent(1.0))
                add_component(world, eid, "collider", BoxColliderComponent(0.5, 0.5, 0.5))
                add_component(world, eid, "health", HealthComponent(50.0))
            if item == "Add Light":
                entity_counter = entity_counter + 1
                let pos = vec3(cam["target"][0], 2.5, cam["target"][2])
                let eid = place_entity(editor, pos, "Light_" + str(entity_counter), sphere_gpu)
                add_component(world, eid, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})
                _ensure_entity_mesh_renderer(world, eid, "sphere")
                add_component(world, eid, "light", PointLightComponent(1.0, 0.95, 0.85, 3.0, 18.0))
            if item == "Add Directional Light":
                entity_counter = entity_counter + 1
                let pos = vec3(cam["target"][0], 6.0, cam["target"][2] + 4.0)
                let eid = place_entity(editor, pos, "SunLight_" + str(entity_counter), sphere_gpu)
                add_component(world, eid, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})
                _ensure_entity_mesh_renderer(world, eid, "sphere")
                let sun = DirectionalLightComponent(1.0, 0.95, 0.9, 1.6)
                add_component(world, eid, "light", sun)
            if item == "Browse Assets":
                _set_content_filter("all")
                print "Content filter: all assets (" + str(len(content_assets_all)) + ")"
            if item == "Browse Textures":
                _set_content_filter("textures")
                print "Content filter: textures (" + str(len(content_assets_textures)) + ")"
            if item == "Browse Sprites":
                _set_content_filter("sprites")
                print "Content filter: sprites (" + str(len(content_assets_sprites)) + ")"
            if item == "Browse Animations":
                _set_content_filter("animations")
                print "Content filter: animations (" + str(len(content_assets_animations)) + ")"
            if item == "Place Selected Asset":
                let filtered_assets = _content_filtered()
                if len(filtered_assets) == 0:
                    print "No assets available in current filter"
                else:
                    if content_selected_index < 0:
                        content_selected_index = 0
                    if content_selected_index >= len(filtered_assets):
                        content_selected_index = len(filtered_assets) - 1
                    let selected_asset = filtered_assets[content_selected_index]
                    if selected_asset["kind"] == "model":
                        let model_key = selected_asset["name"]
                        if dict_has(imported_models, model_key) == false:
                            if endswith(selected_asset["path"], ".gltf") or endswith(selected_asset["path"], ".glb"):
                                let imported = import_gltf(selected_asset["path"])
                                if imported != nil:
                                    _ensure_imported_pbr_materials(imported)
                                    imported_models[model_key] = imported
                        if dict_has(imported_models, model_key):
                            let model_asset = imported_models[model_key]
                            _ensure_imported_pbr_materials(model_asset)
                            entity_counter = entity_counter + 1
                            let pos = vec3(cam["target"][0], 0.0, cam["target"][2])
                            let eid = place_entity(editor, pos, "Model_" + str(entity_counter), nil)
                            add_component(world, eid, "imported_asset", model_asset)
                            if len(model_asset["gpu_meshes"]) > 0:
                                add_component(world, eid, "mesh_id", {"mesh": model_asset["gpu_meshes"][0]["gpu_mesh"], "name": "imported"})
                                _ensure_entity_mesh_renderer(world, eid, "imported")
                        else:
                            print "Model import failed: " + selected_asset["name"]
                    if selected_asset["kind"] == "texture" or selected_asset["kind"] == "sprite":
                        entity_counter = entity_counter + 1
                        let pos = vec3(cam["target"][0], 0.5, cam["target"][2])
                        let eid = place_entity(editor, pos, "Asset_" + str(entity_counter), cube_gpu)
                        add_component(world, eid, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
                        _ensure_entity_mesh_renderer(world, eid, "cube")
                        add_component(world, eid, "asset_ref", selected_asset)
                    if selected_asset["kind"] == "animation":
                        let model_key = ""
                        let mk = dict_keys(imported_models)
                        let mki = 0
                        while mki < len(mk):
                            if imported_models[mk[mki]]["source"] == selected_asset["path"]:
                                model_key = mk[mki]
                            mki = mki + 1
                        if model_key == "" and len(mk) > 0:
                            model_key = mk[0]
                        if model_key != "":
                            let model_asset = imported_models[model_key]
                            _ensure_imported_pbr_materials(model_asset)
                            entity_counter = entity_counter + 1
                            let pos = vec3(cam["target"][0], 0.0, cam["target"][2])
                            let eid = place_entity(editor, pos, "Anim_" + str(entity_counter), nil)
                            let clip_name = selected_asset["name"]
                            if dict_has(selected_asset, "clip"):
                                clip_name = selected_asset["clip"]
                            add_component(world, eid, "imported_asset", model_asset)
                            add_component(world, eid, "animation_state", create_imported_animation_state(model_asset, clip_name))
                            if len(model_asset["gpu_meshes"]) > 0:
                                add_component(world, eid, "mesh_id", {"mesh": model_asset["gpu_meshes"][0]["gpu_mesh"], "name": "imported"})
                                _ensure_entity_mesh_renderer(world, eid, "imported")
                        else:
                            print "No imported model available for animation placement"
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
                        _rehydrate_imported_assets(world)
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
            if item == "Save Screenshot":
                gpu.save_screenshot("assets/screenshot.png")
                print "Screenshot saved: assets/screenshot.png"
            if item == "Export Game":
                let code = generate_game_script(world, "ForgeGame", {"width": 1280, "height": 720})
                io.writefile("assets/generated_game.sage", code)
                print "Game exported: assets/generated_game.sage"
            if item == "Compile Native":
                from codegen import compile_game_native
                compile_game_native(world, "ForgeGame", {"width": 1280, "height": 720})
            if item == "Quit":
                show_modal("Quit", "Are you sure you want to quit?", _quit_callback, nil)
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
            if item == "Toggle Visibility":
                if editor["selected"] >= 0:
                    let sel = editor["selected"]
                    let mr = _ensure_entity_mesh_renderer(world, sel, "default")
                    mr["visible"] = _mesh_visible(world, sel) == false
                    if mr["visible"]:
                        print "Visibility enabled for #" + str(sel)
                    else:
                        print "Visibility disabled for #" + str(sel)
            if item == "Toggle Cast Shadows":
                if editor["selected"] >= 0:
                    let sel = editor["selected"]
                    let mr = _ensure_entity_mesh_renderer(world, sel, "default")
                    mr["cast_shadows"] = _mesh_casts_shadows(world, sel) == false
                    if mr["cast_shadows"]:
                        print "Cast Shadows enabled for #" + str(sel)
                    else:
                        print "Cast Shadows disabled for #" + str(sel)
            if item == "Toggle Receive Shadows":
                if editor["selected"] >= 0:
                    let sel = editor["selected"]
                    let mr = _ensure_entity_mesh_renderer(world, sel, "default")
                    mr["receive_shadows"] = _mesh_receives_shadows(world, sel) == false
                    if mr["receive_shadows"]:
                        print "Receive Shadows enabled for #" + str(sel)
                    else:
                        print "Receive Shadows disabled for #" + str(sel)
            if item == "Apply Metal" or item == "Apply Wood" or item == "Apply Glass" or item == "Apply Gold":
                if editor["selected"] >= 0:
                    let preset_name = replace(item, "Apply ", "")
                    from material import create_material_preset
                    let mat_comp = create_material_preset(preset_name)
                    if mat_comp != nil:
                        add_component(world, editor["selected"], "material", mat_comp)
                        print "Applied " + preset_name + " material to #" + str(editor["selected"])
            if item == "Save as Prefab":
                if editor["selected"] >= 0:
                    let sel_id = editor["selected"]
                    let pname = "Entity_" + str(sel_id)
                    if has_component(world, sel_id, "name"):
                        pname = get_component(world, sel_id, "name")["name"]
                    from scene_serial import save_prefab
                    save_prefab(world, sel_id, pname, "assets/prefabs/" + pname + ".prefab.json")
                    print "Prefab saved: assets/prefabs/" + pname + ".prefab.json"
            if item == "Generate Code":
                let code = generate_game_script(world, "GeneratedGame", {"width": 1280, "height": 720})
                io.writefile("assets/generated_game.sage", code)
                print "Generated: assets/generated_game.sage"
            # --- Help menu ---
            if item == "Controls":
                show_shortcuts = show_shortcuts == false
            if item == "About Forge Engine":
                let about_msg = about_text(gpu.device_name())
                show_modal("About", about_msg, nil, nil)
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
                let cur_val = get_component(world, editor["selected"], "transform")["position"][col]
                details_edit_tf = ui_widgets.create_text_field(0.0, 0.0, 80.0, str(math.floor(cur_val * 1000.0 + 0.5) / 1000.0))
                details_edit_tf["on_commit"] = _commit_field
                ui_widgets.focus_text_field(details_edit_tf)
            iy = iy + 26.0
            iy = iy + 22.0
            if col >= 0 and my >= iy and my < iy + 20.0:
                active_details_field = {"key": "rotation", "axis": col}
                let cur_val = get_component(world, editor["selected"], "transform")["rotation"][col]
                details_edit_tf = ui_widgets.create_text_field(0.0, 0.0, 80.0, str(math.floor(cur_val * 1000.0 + 0.5) / 1000.0))
                details_edit_tf["on_commit"] = _commit_field
                ui_widgets.focus_text_field(details_edit_tf)
            iy = iy + 26.0
            iy = iy + 22.0
            if col >= 0 and my >= iy and my < iy + 20.0:
                active_details_field = {"key": "scale", "axis": col}
                let cur_val = get_component(world, editor["selected"], "transform")["scale"][col]
                details_edit_tf = ui_widgets.create_text_field(0.0, 0.0, 80.0, str(math.floor(cur_val * 1000.0 + 0.5) / 1000.0))
                details_edit_tf["on_commit"] = _commit_field
                ui_widgets.focus_text_field(details_edit_tf)
            window_consumed = true
        let cca_click = window_content_area(win_content)
        let in_content = win_content["visible"] and win_content["collapsed"] == false and mx >= cca_click["x"] and mx < cca_click["x"] + cca_click["w"] and my >= cca_click["y"] and my < cca_click["y"] + cca_click["h"]
        if in_content:
            let list_y = cca_click["y"] + 62.0
            if my >= list_y:
                let local_idx = math.floor((my - list_y) / 18.0)
                let filtered_click = _content_filtered()
                if local_idx >= 0 and local_idx < len(filtered_click):
                    content_selected_index = local_idx
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

    if play_mode == false and text_editing == false and action_just_pressed(inp, "place_cube"):
        entity_counter = entity_counter + 1
        let pos = vec3(cam["target"][0], 0.5, cam["target"][2])
        let eid = place_entity(editor, pos, "Cube_" + str(entity_counter), cube_gpu)
        add_component(world, eid, "mesh_id", {"mesh": cube_gpu, "name": "cube"})
        _ensure_entity_mesh_renderer(world, eid, "cube")

    if play_mode == false and text_editing == false and action_just_pressed(inp, "place_sphere"):
        entity_counter = entity_counter + 1
        let pos = vec3(cam["target"][0], 1.0, cam["target"][2])
        let eid = place_entity(editor, pos, "Sphere_" + str(entity_counter), sphere_gpu)
        add_component(world, eid, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})
        _ensure_entity_mesh_renderer(world, eid, "sphere")

    if play_mode == false and text_editing == false and action_just_pressed(inp, "place_model"):
        let model_keys = dict_keys(imported_models)
        if len(model_keys) > 0:
            let model_asset = imported_models[model_keys[0]]
            _ensure_imported_pbr_materials(model_asset)
            entity_counter = entity_counter + 1
            let pos = vec3(cam["target"][0], 0.0, cam["target"][2])
            let eid = place_entity(editor, pos, model_asset["name"] + "_" + str(entity_counter), nil)
            # Store the imported model's GPU meshes on the entity
            add_component(world, eid, "imported_asset", model_asset)
            # Also add the first mesh as mesh_id for basic rendering
            if len(model_asset["gpu_meshes"]) > 0:
                add_component(world, eid, "mesh_id", {"mesh": model_asset["gpu_meshes"][0]["gpu_mesh"], "name": "imported"})
                _ensure_entity_mesh_renderer(world, eid, "imported")
        else:
            print "No imported models available. Place .gltf files in assets/"

    if play_mode == false and text_editing == false and action_just_pressed(inp, "delete"):
        delete_selected(editor)
        flush_dead(world)
        active_details_field = nil

    if play_mode == false and text_editing == false and action_just_pressed(inp, "duplicate"):
        duplicate_selected(editor)

    # Toggle physics on selected entity (TAB)
    if play_mode == false and text_editing == false and action_just_pressed(inp, "toggle_physics"):
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
            gpu.set_title(editor_play_title())
        else:
            if play_snapshot != nil:
                let restored_enter = load_scene_string(play_snapshot)
                if restored_enter != nil:
                    world = restored_enter["world"]
                    register_system(world, "physics", ["rigidbody", "transform"], create_physics_system(physics_world))
                    _rehydrate_mesh_refs(world)
                    _rehydrate_imported_assets(world)
                    editor["world"] = world
                    deselect(editor)
            play_mode = false
            print "Play mode stopped"
            gpu.set_title(editor_title())

    # Imported animation controls on selected asset
    if play_mode == false and text_editing == false and editor["selected"] >= 0 and has_component(world, editor["selected"], "imported_asset"):
        let sel = editor["selected"]
        let imported = get_component(world, sel, "imported_asset")
        let clip_names = imported_animation_clip_names(imported)
        if len(clip_names) > 0:
            let wants_anim_control = gpu.key_just_pressed(gpu.KEY_SPACE) or gpu.key_just_pressed(gpu.KEY_MINUS) or gpu.key_just_pressed(gpu.KEY_EQUAL)
            if gpu.key_pressed(gpu.KEY_CTRL) and (gpu.key_just_pressed(gpu.KEY_LEFT) or gpu.key_just_pressed(gpu.KEY_RIGHT) or gpu.key_just_pressed(gpu.KEY_UP) or gpu.key_just_pressed(gpu.KEY_DOWN)):
                wants_anim_control = true
            if has_component(world, sel, "animation_state") == false and wants_anim_control:
                add_component(world, sel, "animation_state", create_imported_animation_state(imported, clip_names[0]))
            if has_component(world, sel, "animation_state"):
                let anim_state = get_component(world, sel, "animation_state")
                advance_imported_animation_state(imported, anim_state, 0.0)
                if gpu.key_pressed(gpu.KEY_SHIFT) and gpu.key_just_pressed(gpu.KEY_SPACE):
                    let looping = true
                    if dict_has(anim_state, "looping"):
                        looping = anim_state["looping"]
                    anim_state["looping"] = looping == false
                    if anim_state["looping"]:
                        print "Animation loop enabled"
                    else:
                        print "Animation loop disabled"
                else:
                    if gpu.key_just_pressed(gpu.KEY_SPACE):
                        let playing = true
                        if dict_has(anim_state, "playing"):
                            playing = anim_state["playing"]
                        anim_state["playing"] = playing == false
                        if anim_state["playing"]:
                            print "Animation playing"
                        else:
                            print "Animation paused"
                if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_LEFT):
                    if cycle_imported_animation_clip(imported, anim_state, -1):
                        print "Animation clip: " + anim_state["clip"]
                if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_RIGHT):
                    if cycle_imported_animation_clip(imported, anim_state, 1):
                        print "Animation clip: " + anim_state["clip"]
                if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_UP):
                    let t_scrub = step_imported_animation_time(imported, anim_state, 0.1)
                    print "Animation time: " + _fmt_num(t_scrub)
                if gpu.key_pressed(gpu.KEY_CTRL) and gpu.key_just_pressed(gpu.KEY_DOWN):
                    let t_scrub = step_imported_animation_time(imported, anim_state, -0.1)
                    print "Animation time: " + _fmt_num(t_scrub)
                if gpu.key_just_pressed(gpu.KEY_MINUS):
                    let speed = 1.0
                    if dict_has(anim_state, "speed"):
                        speed = anim_state["speed"]
                    speed = speed - 0.25
                    if speed < 0.1:
                        speed = 0.1
                    anim_state["speed"] = speed
                    print "Animation speed: " + _fmt_num(speed)
                if gpu.key_just_pressed(gpu.KEY_EQUAL):
                    let speed = 1.0
                    if dict_has(anim_state, "speed"):
                        speed = anim_state["speed"]
                    speed = speed + 0.25
                    anim_state["speed"] = speed
                    print "Animation speed: " + _fmt_num(speed)

    # --- Keyboard nudge for selected entity (arrow keys) ---
    if play_mode == false and gpu.key_pressed(gpu.KEY_CTRL) == false and editor["selected"] >= 0 and has_component(world, editor["selected"], "transform"):
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
    _sync_world_lights(ls, world)
    set_view_position(ls, cam_pos)
    update_light_ubo(ls)
    _update_imported_animation_states(world, ts["dt"])

    # --- Render ---
    if gpu.window_should_close():
        running = false
        continue
    _render_shadow_world(shadow_renderer, world, ls, cam_pos, 45.0)
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

    # Sky dome (behind everything)
    draw_sky(sky, cmd, view, aspect, 60.0, ts["elapsed"])
    # Editor grid overlay
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
        # Frustum cull + LOD
        let half_ext = vec3(2.0, 2.0, 2.0)
        if _mesh_visible(world, eid) and aabb_in_frustum(frustum_planes, pos, half_ext):
            let lod_level = compute_lod(editor_lod, cam_pos, pos)
            if lod_level < 5:
                let model = transform_to_matrix(t)
                let mvp = mat4_mul(vp, model)
                let receive_shadows = _mesh_receives_shadows(world, eid)
                if has_component(world, eid, "imported_asset"):
                    let asset = get_component(world, eid, "imported_asset")
                    let pbr_materials = _ensure_imported_pbr_materials(asset)
                    let anim_state = nil
                    if has_component(world, eid, "animation_state"):
                        anim_state = get_component(world, eid, "animation_state")
                    let draws = imported_asset_draws(asset, anim_state)
                    let gi = 0
                    while gi < len(draws):
                        let gm = draws[gi]
                        let material_index = -1
                        if dict_has(gm, "material_index"):
                            material_index = gm["material_index"]
                        let imported_model = mat4_mul(model, gm["model"])
                        let imported_mvp = mat4_mul(vp, imported_model)
                        if pbr_renderer != nil and material_index >= 0 and material_index < len(pbr_materials):
                            draw_pbr_skinned_controlled(cmd, pbr_renderer, gm["gpu_mesh"], imported_mvp, imported_model, ls["desc_set"], pbr_materials[material_index], gm, receive_shadows)
                        else:
                            let surface = nil
                            if material_index >= 0 and material_index < len(asset["materials"]):
                                surface = _surface_from_imported_material(asset["materials"][material_index])
                            draw_mesh_lit_surface_skinned_controlled(cmd, lit_mat, gm["gpu_mesh"], imported_mvp, imported_model, ls["desc_set"], surface, gm, receive_shadows)
                        draw_count = draw_count + 1
                        gi = gi + 1
                else:
                    let mi = get_component(world, eid, "mesh_id")
                    if has_component(world, eid, "material"):
                        let surface = get_component(world, eid, "material")
                        draw_mesh_lit_surface_controlled(cmd, lit_mat, mi["mesh"], mvp, model, ls["desc_set"], surface, receive_shadows)
                    else:
                        draw_mesh_lit_controlled(cmd, lit_mat, mi["mesh"], mvp, model, ls["desc_set"], receive_shadows)
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

    # Viewport vignette overlay (subtle cinematic darkening)
    let vig_quads = build_vignette_quads(editor_postfx, sw, sh)
    if len(vig_quads) > 0:
        let vigv = build_quad_verts(vig_quads)
        gpu.buffer_upload(ui_r["vbuf"], vigv)
        gpu.cmd_bind_graphics_pipeline(cmd, ui_r["pipeline"])
        gpu.cmd_push_constants(cmd, ui_r["pipe_layout"], gpu.STAGE_VERTEX, [sw, sh, 0.0, 0.0])
        gpu.cmd_bind_vertex_buffer(cmd, ui_r["vbuf"])
        gpu.cmd_draw(cmd, len(vig_quads) * 6, 1, 0, 0)

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
            push(ui_quads, {"x": menu_x_pos[mhi] - 4.0, "y": 0.0, "w": menu_widths[mhi], "h": mb_h, "color": [THEME_ACCENT[0], THEME_ACCENT[1], THEME_ACCENT[2], 0.4]})
        mhi = mhi + 1

    # Toolbar mode buttons (below menu bar)
    let modes = ["translate", "rotate", "scale"]
    let mode_labels = ["Move", "Rotate", "Scale"]
    let mx_b = 10.0
    let mi_b = 0
    while mi_b < 3:
        let bc = [THEME_BUTTON[0], THEME_BUTTON[1], THEME_BUTTON[2], 1.0]
        if cur_mode == modes[mi_b]:
            bc = [THEME_ACCENT[0], THEME_ACCENT[1], THEME_ACCENT[2], 0.8]
        push(ui_quads, {"x": mx_b, "y": mb_h + 4.0, "w": 70.0, "h": 26.0, "color": bc})
        mx_b = mx_b + 75.0
        mi_b = mi_b + 1

    # Play button
    let play_btn_col = [0.18, 0.50, 0.24, 1.0]
    if play_mode:
        play_btn_col = [0.60, 0.22, 0.22, 1.0]
    push(ui_quads, {"x": sw / 2.0 - 40.0, "y": mb_h + 4.0, "w": 80.0, "h": 26.0, "color": play_btn_col})

    # Save button
    push(ui_quads, {"x": sw / 2.0 + 50.0, "y": mb_h + 4.0, "w": 60.0, "h": 26.0, "color": [THEME_BUTTON[0], THEME_BUTTON[1], THEME_BUTTON[2], 1.0]})

    # Viewport overlay bar (top of viewport area)
    let vp_b = get_viewport_bounds(layout)
    push(ui_quads, {"x": vp_b["x"], "y": vp_b["y"], "w": vp_b["w"], "h": 28.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 0.75]})
    push(ui_quads, {"x": vp_b["x"], "y": vp_b["y"] + 28.0, "w": vp_b["w"], "h": 1.0, "color": [0.06, 0.06, 0.06, 0.5]})

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

    # _fmt_num is defined at module level for LLVM compat

    # Menu bar text (bright white on dark header)
    let mti = 0
    while mti < 5:
        let mc = [THEME_TEXT[0], THEME_TEXT[1], THEME_TEXT[2], 1.0]
        if menubar_active == mti:
            mc = [1.0, 1.0, 1.0, 1.0]
        add_text(font_r, "ui", menu_labels[mti], menu_x_pos[mti], 4.0, mc[0], mc[1], mc[2], 1.0)
        mti = mti + 1
    # Project name on right side of menu bar
    add_text(font_r, "ui", engine_name(), sw - 130.0, 4.0, 0.5, 0.5, 0.5, 1.0)

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
            push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 24.0, "color": [THEME_HEADER[0], THEME_HEADER[1], THEME_HEADER[2], 1.0]})
            dqy = dqy + 28.0
        # Transform section header
        push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 22.0, "color": [THEME_PANEL[0], THEME_PANEL[1], THEME_PANEL[2], 1.0]})
        dqy = dqy + 26.0
        # Location row
        push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 18.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 0.5]})
        dqy = dqy + 22.0
        # XYZ input fields for location
        let fw3 = (dqw - 16.0) / 3.0
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": fw3, "h": 20.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 1.0]})
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.9, 0.22, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": fw3, "h": 20.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 1.0]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.9, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": fw3, "h": 20.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 1.0]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.22, 0.9, 0.8]})
        dqy = dqy + 26.0
        # Rotation row
        push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 18.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 0.5]})
        dqy = dqy + 22.0
        # XYZ input fields for rotation
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": fw3, "h": 20.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 1.0]})
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.9, 0.22, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": fw3, "h": 20.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 1.0]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.9, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": fw3, "h": 20.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 1.0]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.22, 0.9, 0.8]})
        dqy = dqy + 26.0
        # Scale row
        push(all_win_quads, {"x": dqx, "y": dqy, "w": dqw, "h": 18.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 0.5]})
        dqy = dqy + 22.0
        # XYZ input fields for scale
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": fw3, "h": 20.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 1.0]})
        push(all_win_quads, {"x": dqx + 2.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.9, 0.22, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": fw3, "h": 20.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 1.0]})
        push(all_win_quads, {"x": dqx + fw3 + 6.0, "y": dqy, "w": 3.0, "h": 20.0, "color": [0.22, 0.9, 0.22, 0.8]})
        push(all_win_quads, {"x": dqx + fw3 * 2.0 + 10.0, "y": dqy, "w": fw3, "h": 20.0, "color": [THEME_BG[0], THEME_BG[1], THEME_BG[2], 1.0]})
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
                push(all_win_quads, {"x": oca_h["x"], "y": hey - 1.0, "w": oca_h["w"], "h": 20.0, "color": [THEME_ACCENT[0], THEME_ACCENT[1], THEME_ACCENT[2], 0.15]})
            hey = hey + 24.0
            hei = hei + 1
    # Menu quads rendered separately AFTER all window text (see below)
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
        update_window_content_height(win_outliner, len(ents) * 24.0)
        let oy = oca["y"] - win_outliner["scroll_y"]
        let sel_out = selected_entities(editor)
        let oei = 0
        while oei < len(ents):
            let eid = ents[oei]
            # Only render if within visible content area
            if oy + 24.0 > oca["y"] and oy < oca["y"] + oca["h"]:
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
        let dy = dca["y"] - win_details["scroll_y"]
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
            let edit_key = ""
            let edit_axis = -1
            if active_details_field != nil:
                edit_key = active_details_field["key"]
                edit_axis = active_details_field["axis"]
            # Position X/Y/Z (show editing field if active)
            let pxo = [dx + 10.0, dx + fw3 + 14.0, dx + fw3 * 2.0 + 18.0]
            let pxi = 0
            while pxi < 3:
                if edit_key == "position" and edit_axis == pxi and details_edit_tf != nil:
                    let ev = details_edit_tf["text_value"]
                    let blink = details_edit_tf["blink_timer"]
                    if math.floor(blink * 2.0) % 2 == 0:
                        ev = ev + "|"
                    add_text(font_r, "ui", ev, pxo[pxi], iy + 2.0, 0.290, 0.565, 0.851, 1.0)
                else:
                    add_text(font_r, "ui", _fmt_num(st["position"][pxi]), pxo[pxi], iy + 2.0, 0.78, 0.78, 0.78, 1.0)
                pxi = pxi + 1
            iy = iy + 26.0
            # Rotation
            add_text(font_r, "ui", "Rotation", dx + 4.0, iy + 1.0, 0.439, 0.439, 0.439, 1.0)
            iy = iy + 22.0
            let rxi = 0
            while rxi < 3:
                if edit_key == "rotation" and edit_axis == rxi and details_edit_tf != nil:
                    let ev = details_edit_tf["text_value"]
                    let blink = details_edit_tf["blink_timer"]
                    if math.floor(blink * 2.0) % 2 == 0:
                        ev = ev + "|"
                    add_text(font_r, "ui", ev, pxo[rxi], iy + 2.0, 0.290, 0.565, 0.851, 1.0)
                else:
                    add_text(font_r, "ui", _fmt_num(st["rotation"][rxi]), pxo[rxi], iy + 2.0, 0.78, 0.78, 0.78, 1.0)
                rxi = rxi + 1
            iy = iy + 26.0
            # Scale
            add_text(font_r, "ui", "Scale", dx + 4.0, iy + 1.0, 0.439, 0.439, 0.439, 1.0)
            iy = iy + 22.0
            let sxi = 0
            while sxi < 3:
                if edit_key == "scale" and edit_axis == sxi and details_edit_tf != nil:
                    let ev = details_edit_tf["text_value"]
                    let blink = details_edit_tf["blink_timer"]
                    if math.floor(blink * 2.0) % 2 == 0:
                        ev = ev + "|"
                    add_text(font_r, "ui", ev, pxo[sxi], iy + 2.0, 0.290, 0.565, 0.851, 1.0)
                else:
                    add_text(font_r, "ui", _fmt_num(st["scale"][sxi]), pxo[sxi], iy + 2.0, 0.78, 0.78, 0.78, 1.0)
                sxi = sxi + 1
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
                    add_text(font_r, "ui", "Mass: " + _fmt_num(rb["mass"]) + "  Bounce: " + _fmt_num(rb["restitution"]), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                iy = iy + 20.0
            if has_component(world, cur_sel, "health"):
                let hp = get_component(world, cur_sel, "health")
                add_text(font_r, "ui", "Health: " + _fmt_num(hp["current"]) + " / " + _fmt_num(hp["max"]), dx + 8.0, iy, 0.3, 0.85, 0.3, 1.0)
                iy = iy + 22.0
            # Material section
            if has_component(world, cur_sel, "imported_asset"):
                let ia = get_component(world, cur_sel, "imported_asset")
                add_text(font_r, "ui", "Material", dx + 6.0, iy + 2.0, 0.784, 0.784, 0.784, 1.0)
                iy = iy + 24.0
                add_text(font_r, "ui", "Meshes: " + str(len(ia["gpu_meshes"])) + "  Nodes: " + str(len(ia["nodes"])), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                iy = iy + 18.0
                if dict_has(ia, "skin_count") and ia["skin_count"] > 0:
                    add_text(font_r, "ui", "Skins: " + str(ia["skin_count"]) + "  Joints: " + str(ia["joint_count"]), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                    iy = iy + 18.0
                if len(ia["materials"]) > 0:
                    let mat = ia["materials"][0]
                    add_text(font_r, "ui", mat["name"], dx + 8.0, iy, 0.65, 0.65, 0.65, 1.0)
                    iy = iy + 18.0
                    add_text(font_r, "ui", "Metallic: " + _fmt_num(mat["metallic"]), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                    iy = iy + 16.0
                    add_text(font_r, "ui", "Roughness: " + _fmt_num(mat["roughness"]), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                    iy = iy + 16.0
                let clip_names = imported_animation_clip_names(ia)
                if len(clip_names) > 0:
                    let clip_name = clip_names[0]
                    let clip_idx = 0
                    let anim_time = 0.0
                    let anim_speed = 1.0
                    let anim_playing = false
                    let anim_looping = true
                    if has_component(world, cur_sel, "animation_state"):
                        let anim = get_component(world, cur_sel, "animation_state")
                        advance_imported_animation_state(ia, anim, 0.0)
                        if dict_has(anim, "clip"):
                            clip_name = anim["clip"]
                        clip_idx = imported_animation_index(ia, clip_name)
                        if clip_idx < 0:
                            clip_idx = 0
                            clip_name = clip_names[0]
                        if dict_has(anim, "time"):
                            anim_time = anim["time"]
                        if dict_has(anim, "speed"):
                            anim_speed = anim["speed"]
                        if dict_has(anim, "playing"):
                            anim_playing = anim["playing"]
                        if dict_has(anim, "looping"):
                            anim_looping = anim["looping"]
                    let clip_duration = imported_animation_duration(ia, clip_name)
                    add_text(font_r, "ui", "Clips: " + str(len(clip_names)) + "  Active: " + str(clip_idx + 1) + "/" + str(len(clip_names)), dx + 8.0, iy, 0.65, 0.65, 0.65, 1.0)
                    iy = iy + 18.0
                    add_text(font_r, "ui", "Clip: " + clip_name, dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                    iy = iy + 16.0
                    let state_text = "Paused"
                    if anim_playing:
                        state_text = "Playing"
                    let loop_text = "On"
                    if anim_looping == false:
                        loop_text = "Off"
                    add_text(font_r, "ui", "State: " + state_text + "  Loop: " + loop_text, dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                    iy = iy + 16.0
                    add_text(font_r, "ui", "Time: " + _fmt_num(anim_time) + " / " + _fmt_num(clip_duration), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                    iy = iy + 16.0
                    add_text(font_r, "ui", "Speed: " + _fmt_num(anim_speed), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                    iy = iy + 16.0
                    add_text(font_r, "ui", "SPACE play  SHIFT+SPACE loop", dx + 8.0, iy, 0.357, 0.627, 0.914, 1.0)
                    iy = iy + 16.0
                    add_text(font_r, "ui", "CTRL+LEFT/RIGHT clip  CTRL+UP/DOWN scrub  -/= speed", dx + 8.0, iy, 0.357, 0.627, 0.914, 1.0)
            # MaterialComponent (if present)
            if has_component(world, cur_sel, "material"):
                let mc = get_component(world, cur_sel, "material")
                iy = iy + 22.0
                add_text(font_r, "ui", "Material", dx + 6.0, iy + 2.0, 0.784, 0.784, 0.784, 1.0)
                iy = iy + 24.0
                add_text(font_r, "ui", "Albedo: " + _fmt_num(mc["albedo"][0]) + " " + _fmt_num(mc["albedo"][1]) + " " + _fmt_num(mc["albedo"][2]), dx + 8.0, iy, 0.65, 0.65, 0.65, 1.0)
                iy = iy + 18.0
                add_text(font_r, "ui", "Metallic: " + _fmt_num(mc["metallic"]) + "  Roughness: " + _fmt_num(mc["roughness"]), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                iy = iy + 16.0
                if mc["emission_strength"] > 0.0:
                    add_text(font_r, "ui", "Emission: " + _fmt_num(mc["emission_strength"]), dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                    iy = iy + 16.0
            if has_component(world, cur_sel, "mesh_renderer"):
                let mr = get_component(world, cur_sel, "mesh_renderer")
                iy = iy + 22.0
                add_text(font_r, "ui", "Render", dx + 6.0, iy + 2.0, 0.784, 0.784, 0.784, 1.0)
                iy = iy + 24.0
                let visible_text = "On"
                if dict_has(mr, "visible") and mr["visible"] == false:
                    visible_text = "Off"
                add_text(font_r, "ui", "Visible: " + visible_text, dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                iy = iy + 16.0
                let cast_text = "On"
                if dict_has(mr, "cast_shadows") and mr["cast_shadows"] == false:
                    cast_text = "Off"
                add_text(font_r, "ui", "Cast Shadows: " + cast_text, dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                iy = iy + 16.0
                let receive_text = "On"
                if dict_has(mr, "receive_shadows") and mr["receive_shadows"] == false:
                    receive_text = "Off"
                add_text(font_r, "ui", "Receive Shadows: " + receive_text, dx + 8.0, iy, 0.439, 0.439, 0.439, 1.0)
                iy = iy + 16.0
                add_text(font_r, "ui", "Tools menu toggles render flags", dx + 8.0, iy, 0.357, 0.627, 0.914, 1.0)
        else:
            add_text(font_r, "ui", "Select an entity to view details", dx + 4.0, dy + 8.0, 0.439, 0.439, 0.439, 1.0)

    # --- Content Browser content (with scroll clipping) ---
    if win_content["visible"] and win_content["collapsed"] == false:
        let cca = window_content_area(win_content)
        let cb_max_y = cca["y"] + cca["h"]
        let cb_scroll = win_content["scroll_y"]
        let cb_base_y = cca["y"] - cb_scroll
        let cb_max_chars = math.floor((cca["w"] - 10.0) / 8.0)
        if cb_base_y + 4.0 < cb_max_y:
            add_text(font_r, "ui", _clip_text_line("R=Cube  F=Sphere  E=Model  D=Del  Q=Dup  TAB=Physics", cb_max_chars), cca["x"] + 4.0, cb_base_y + 4.0, 0.38, 0.38, 0.42, 1.0)
        if cb_base_y + 22.0 < cb_max_y:
            add_text(font_r, "ui", _clip_text_line("LClick=Select  RMB=Orbit  Scroll=Zoom  ENTER=Play", cb_max_chars), cca["x"] + 4.0, cb_base_y + 22.0, 0.38, 0.38, 0.42, 1.0)
        let content_rows = _content_filtered()
        let total_h = 44.0 + len(content_rows) * 18.0
        update_window_content_height(win_content, total_h)
        if len(content_rows) > 0:
            let cbi = 0
            let cy = cb_base_y + 42.0
            while cbi < len(content_rows):
                if cy + 18.0 > cca["y"] and cy < cb_max_y:
                    let row = content_rows[cbi]
                    let row_prefix = "  "
                    let rc = [0.55, 0.55, 0.55, 1.0]
                    if row["kind"] == "texture":
                        rc = [0.65, 0.65, 0.85, 1.0]
                    if row["kind"] == "sprite":
                        rc = [0.65, 0.85, 0.65, 1.0]
                    if row["kind"] == "model":
                        rc = [0.65, 0.65, 0.65, 1.0]
                    if row["kind"] == "animation":
                        rc = [0.85, 0.65, 0.65, 1.0]
                    if cbi == content_selected_index:
                        row_prefix = "> "
                        rc = [1.0, 1.0, 1.0, 1.0]
                    let row_text = row_prefix + "[" + row["kind"] + "] " + row["name"]
                    add_text(font_r, "ui", _clip_text_line(row_text, cb_max_chars), cca["x"] + 4.0, cy, rc[0], rc[1], rc[2], 1.0)
                cy = cy + 18.0
                cbi = cbi + 1
    flush_text(font_r, cmd, sw, sh)

    # --- Menu dropdown (rendered ON TOP of all window text) ---
    if is_menu_open():
        let menu_quads = build_menu_quads()
        # Hover highlight
        let hover_idx = menu_item_at(mx, my)
        if hover_idx >= 0:
            let mitems_hov = get_menu_items()
            if mitems_hov[hover_idx] != "---":
                let mpos_hov = get_menu_pos()
                push(menu_quads, {"x": mpos_hov[0] + 2.0, "y": mpos_hov[1] + 4.0 + hover_idx * 24.0, "w": 176.0, "h": 22.0, "color": [0.290, 0.565, 0.851, 0.4]})
        if len(menu_quads) > 0:
            let mqv = build_quad_verts(menu_quads)
            gpu.buffer_upload(ui_r["vbuf"], mqv)
            gpu.cmd_bind_graphics_pipeline(cmd, ui_r["pipeline"])
            gpu.cmd_push_constants(cmd, ui_r["pipe_layout"], gpu.STAGE_VERTEX, [sw, sh, 0.0, 0.0])
            gpu.cmd_bind_vertex_buffer(cmd, ui_r["vbuf"])
            gpu.cmd_draw(cmd, len(menu_quads) * 6, 1, 0, 0)
        # Menu text (on top of menu quads)
        begin_text(font_r)
        let mitems = get_menu_items()
        let mpos = get_menu_pos()
        let mii = 0
        while mii < len(mitems):
            let item_text = mitems[mii]
            if item_text == "---":
                # Separator: just skip (line drawn via quads if needed)
                mii = mii + 1
                continue
            let mtc = [0.92, 0.92, 0.92, 1.0]
            if hover_idx == mii:
                mtc = [1.0, 1.0, 1.0, 1.0]
            add_text(font_r, "ui", item_text, mpos[0] + 12.0, mpos[1] + 6.0 + mii * 24.0, mtc[0], mtc[1], mtc[2], 1.0)
            mii = mii + 1
        flush_text(font_r, cmd, sw, sh)

    # --- Modal dialog (rendered on top of everything) ---
    if is_modal_open():
        let modal_quads = build_modal_quads(sw, sh)
        if len(modal_quads) > 0:
            let mv = build_quad_verts(modal_quads)
            gpu.buffer_upload(ui_r["vbuf"], mv)
            gpu.cmd_bind_graphics_pipeline(cmd, ui_r["pipeline"])
            gpu.cmd_push_constants(cmd, ui_r["pipe_layout"], gpu.STAGE_VERTEX, [sw, sh, 0.0, 0.0])
            gpu.cmd_bind_vertex_buffer(cmd, ui_r["vbuf"])
            gpu.cmd_draw(cmd, len(modal_quads) * 6, 1, 0, 0)
        # Modal text
        begin_text(font_r)
        let modal = get_modal()
        let mdw = 340.0
        let mdx = (sw - mdw) / 2.0
        let mdy = (sh - 140.0) / 2.0
        add_text(font_r, "ui", modal["title"], mdx + 10.0, mdy + 5.0, 0.9, 0.9, 0.9, 1.0)
        add_text(font_r, "ui", modal["message"], mdx + 16.0, mdy + 50.0, 0.7, 0.7, 0.7, 1.0)
        add_text(font_r, "ui", "Yes", mdx + mdw - 145.0, mdy + 107.0, 0.9, 0.9, 0.9, 1.0)
        add_text(font_r, "ui", "No", mdx + mdw - 58.0, mdy + 107.0, 0.78, 0.78, 0.78, 1.0)
        flush_text(font_r, cmd, sw, sh)

    # --- Shortcuts overlay (F1) ---
    if show_shortcuts:
        let skw = 360.0
        let skh = 380.0
        let skx = (sw - skw) / 2.0
        let sky_pos = (sh - skh) / 2.0
        let sk_quads = []
        push(sk_quads, {"x": skx + 4.0, "y": sky_pos + 4.0, "w": skw, "h": skh, "color": [0.0, 0.0, 0.0, 0.35]})
        push(sk_quads, {"x": skx, "y": sky_pos, "w": skw, "h": skh, "color": [THEME_PANEL[0], THEME_PANEL[1], THEME_PANEL[2], 0.97]})
        push(sk_quads, {"x": skx, "y": sky_pos, "w": skw, "h": 28.0, "color": [THEME_HEADER[0], THEME_HEADER[1], THEME_HEADER[2], 1.0]})
        let skv = build_quad_verts(sk_quads)
        gpu.buffer_upload(ui_r["vbuf"], skv)
        gpu.cmd_bind_graphics_pipeline(cmd, ui_r["pipeline"])
        gpu.cmd_push_constants(cmd, ui_r["pipe_layout"], gpu.STAGE_VERTEX, [sw, sh, 0.0, 0.0])
        gpu.cmd_bind_vertex_buffer(cmd, ui_r["vbuf"])
        gpu.cmd_draw(cmd, len(sk_quads) * 6, 1, 0, 0)
        begin_text(font_r)
        add_text(font_r, "ui", "Keyboard Shortcuts", skx + 10.0, sky_pos + 5.0, 0.9, 0.9, 0.9, 1.0)
        let ky = sky_pos + 36.0
        let kx = skx + 12.0
        let kx2 = skx + 180.0
        add_text(font_r, "ui", "CTRL+Q", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Quit", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "CTRL+S", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Save Scene", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "CTRL+Z / CTRL+Y", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Undo / Redo", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "R", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Place Cube", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "F", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Place Sphere", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "E", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Place Model", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "D", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Delete Selected", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "Q", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Duplicate", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "TAB", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Toggle Physics", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "ENTER", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Play / Stop", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "1 / 2 / 3", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Move / Rotate / Scale", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "RMB", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Orbit Camera", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "MMB", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Pan Camera", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "Scroll", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Zoom / Scroll Panels", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 20.0
        add_text(font_r, "ui", "Right-Click", kx, ky, 0.290, 0.565, 0.851, 1.0)
        add_text(font_r, "ui", "Context Menu", kx2, ky, 0.65, 0.65, 0.65, 1.0)
        ky = ky + 24.0
        add_text(font_r, "ui", "Press F1 to close", skx + skw / 2.0 - 70.0, ky, 0.4, 0.4, 0.4, 1.0)
        flush_text(font_r, cmd, sw, sh)

    end_frame(r, frame)
    gc_collect()
    update_title_fps(r, editor_title())

try:
    gpu.device_wait_idle()
    shutdown_renderer(r)
catch e:
    print "Shutdown warning: " + str(e)
print "Editor closed"
