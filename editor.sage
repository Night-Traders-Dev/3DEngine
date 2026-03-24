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
#   Q = Duplicate | 5 = Generate code | 4 = Save scene | CTRL = Quit

import gpu
import math
import sys
from renderer import create_renderer, begin_frame, end_frame
from renderer import shutdown_renderer, check_resize, update_title_fps
from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, query, tick_systems, flush_dead
from ecs import entity_count, destroy, add_tag, has_tag
from components import TransformComponent, NameComponent
from input import create_input, update_input, bind_action
from input import action_held, action_just_pressed
from input import mouse_delta, scroll_value, mouse_position
from engine_math import transform_to_matrix
from math3d import vec3, v3_add, v3_scale, mat4_mul, mat4_identity, radians
from math3d import mat4_perspective, mat4_translate, mat4_scale
from mesh import cube_mesh, sphere_mesh, plane_mesh, upload_mesh
from lighting import create_light_scene, directional_light, point_light
from lighting import add_light, set_ambient, set_view_position
from lighting import init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit
from sky import create_sky, sky_preset_day, init_sky_gpu, draw_sky
from editor_grid import create_editor_grid, draw_editor_grid
from ui_renderer import create_ui_renderer, draw_ui, build_ui_vertices
from ui_core import create_widget, create_rect, create_panel, add_child, collect_quads, compute_layout
from font import create_font_renderer, load_font, draw_text
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
from editor_layout import create_editor_layout, get_viewport_bounds
from editor_viewport import create_editor_camera, editor_camera_view
from editor_viewport import editor_camera_position
from scene_editor import create_scene_editor, select_entity, deselect
from scene_editor import place_entity, delete_selected, duplicate_selected
from scene_editor import apply_gizmo_delta, editor_stats
from gizmo import set_gizmo_mode, get_gizmo_visuals
from gizmo import GIZMO_TRANSLATE, GIZMO_ROTATE, GIZMO_SCALE
from inspector import create_inspector, inspect_entity, clear_inspection, refresh_inspector
from codegen import generate_game_script
from scene_serial import save_scene
from game_loop import create_time_state, update_time
import io

print "=== Forge Engine Editor ==="

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(1440, 900, "Forge Engine Editor")
if r == nil:
    raise "Failed to create renderer"
# Dark gray background (Unreal-style viewport)
r["clear_color"] = [0.14, 0.14, 0.16, 1.0]
print "GPU: " + gpu.device_name()

# ============================================================================
# Lighting & Sky
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.3, -0.7, 0.5, 1.0, 0.95, 0.85, 1.0))
add_light(ls, point_light(5.0, 4.0, 3.0, 1.0, 0.8, 0.6, 3.0, 20.0))
set_ambient(ls, 0.25, 0.25, 0.3, 0.5)
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
let ground_gpu = upload_mesh(plane_mesh(40.0))

# ============================================================================
# UI
# ============================================================================
let ui_r = create_ui_renderer(r["render_pass"])
let layout = create_editor_layout(1440.0, 900.0)

# Load TrueType fonts
let font_r = create_font_renderer(r["render_pass"])
let font_regular = load_font(font_r, "regular", "assets/DejaVuSans.ttf", 14.0)
let font_bold = load_font(font_r, "bold", "assets/DejaVuSans-Bold.ttf", 14.0)
let font_small = load_font(font_r, "small", "assets/DejaVuSans.ttf", 11.0)
let font_title = load_font(font_r, "title", "assets/DejaVuSans-Bold.ttf", 16.0)

# ============================================================================
# ECS World (editor scene)
# ============================================================================
let world = create_world()
let editor = create_scene_editor(world)

# Default scene: ground plane
let ge = spawn(world)
add_component(world, ge, "transform", TransformComponent(0.0, 0.0, 0.0))
add_component(world, ge, "name", NameComponent("Ground"))
add_component(world, ge, "mesh_id", {"mesh": ground_gpu, "name": "ground"})
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

print "Editor loaded with " + str(entity_count(world)) + " entities"

# ============================================================================
# Editor camera
# ============================================================================
let cam = create_editor_camera()
cam["distance"] = 12.0
cam["pitch"] = 0.5
cam["yaw"] = 0.8

# ============================================================================
# Input
# ============================================================================
let inp = create_input()
bind_action(inp, "quit", [gpu.KEY_CTRL])
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
bind_action(inp, "orbit", [gpu.KEY_E])
bind_action(inp, "pan", [gpu.KEY_SHIFT])

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
print "  E+Mouse=Orbit  SHIFT+Mouse=Pan  Scroll=Zoom"
print "  R=Cube  F=Sphere  D=Delete  Q=Duplicate  ESC=Deselect"
print "  1=Translate 2=Rotate 3=Scale  4=Save  5=Generate Code"
print "  CTRL=Quit"
print ""

while running:
    update_time(ts)
    let dt = ts["dt"]
    check_resize(r)
    update_input(inp)

    if action_just_pressed(inp, "quit"):
        running = false
        continue

    # --- Camera orbit/pan/zoom ---
    let md = mouse_delta(inp)
    let sv = scroll_value(inp)

    if action_held(inp, "orbit"):
        cam["yaw"] = cam["yaw"] + md[0] * 0.005
        cam["pitch"] = cam["pitch"] + md[1] * 0.005
        if cam["pitch"] < -1.5:
            cam["pitch"] = -1.5
        if cam["pitch"] > 1.5:
            cam["pitch"] = 1.5

    if action_held(inp, "pan"):
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
        if cam["distance"] > 100.0:
            cam["distance"] = 100.0

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

    # Left click = select entity via raycast
    if gpu.key_just_pressed(gpu.MOUSE_LEFT):
        # Build pick ray from mouse position and editor camera
        let vp_bounds = get_viewport_bounds(layout)
        # Check if click is in viewport area
        if mx > vp_bounds["x"] and mx < vp_bounds["x"] + vp_bounds["w"]:
            if my > vp_bounds["y"] and my < vp_bounds["y"] + vp_bounds["h"]:
                let cam_pos = editor_camera_position(cam)
                let fov = radians(60.0)
                let aspect = vp_bounds["w"] / vp_bounds["h"]
                # Normalize mouse to viewport
                let norm_x = (mx - vp_bounds["x"]) / vp_bounds["w"] * 2.0 - 1.0
                let norm_y = 1.0 - (my - vp_bounds["y"]) / vp_bounds["h"] * 2.0
                let tan_half = math.tan(fov * 0.5)
                let rx = norm_x * aspect * tan_half
                let ry = norm_y * tan_half
                from math3d import v3_sub, v3_normalize, v3_cross
                let cam_fwd = v3_normalize(v3_sub(cam["target"], cam_pos))
                let cam_right = v3_normalize(v3_cross(cam_fwd, vec3(0.0, 1.0, 0.0)))
                let cam_up = v3_cross(cam_right, cam_fwd)
                let ray_dir = v3_normalize(v3_add(v3_add(v3_scale(cam_right, rx), v3_scale(cam_up, ry)), cam_fwd))
                # Raycast against all entities
                from scene_editor import select_by_ray
                select_by_ray(editor, cam_pos, ray_dir)

    # Right mouse = orbit (already handled above via E key)
    # Also allow right mouse button for orbit
    if gpu.mouse_button(gpu.MOUSE_RIGHT):
        cam["yaw"] = cam["yaw"] + md[0] * 0.005
        cam["pitch"] = cam["pitch"] + md[1] * 0.005
        if cam["pitch"] < -1.5:
            cam["pitch"] = -1.5
        if cam["pitch"] > 1.5:
            cam["pitch"] = 1.5

    # Middle mouse = pan
    if gpu.mouse_button(gpu.MOUSE_MIDDLE):
        let cy_pan = math.cos(cam["yaw"])
        let sy_pan = math.sin(cam["yaw"])
        let ps = cam["distance"] * 0.003
        cam["target"][0] = cam["target"][0] - md[0] * cy_pan * ps
        cam["target"][2] = cam["target"][2] + md[0] * sy_pan * ps
        cam["target"][1] = cam["target"][1] + md[1] * ps

    # --- Entity operations ---
    if action_just_pressed(inp, "select"):
        deselect(editor)

    if action_just_pressed(inp, "place_cube"):
        entity_counter = entity_counter + 1
        let pos = vec3(cam["target"][0], 0.5, cam["target"][2])
        let eid = place_entity(editor, pos, "Cube_" + str(entity_counter), cube_gpu)
        add_component(world, eid, "mesh_id", {"mesh": cube_gpu, "name": "cube"})

    if action_just_pressed(inp, "place_sphere"):
        entity_counter = entity_counter + 1
        let pos = vec3(cam["target"][0], 1.0, cam["target"][2])
        let eid = place_entity(editor, pos, "Sphere_" + str(entity_counter), sphere_gpu)
        add_component(world, eid, "mesh_id", {"mesh": sphere_gpu, "name": "sphere"})

    if action_just_pressed(inp, "delete"):
        delete_selected(editor)
        flush_dead(world)

    if action_just_pressed(inp, "duplicate"):
        duplicate_selected(editor)

    # --- Keyboard nudge for selected entity ---
    if editor["selected"] >= 0 and has_component(world, editor["selected"], "transform"):
        let nudge_speed = 2.0 * dt
        if gpu.key_pressed(gpu.KEY_W):
            apply_gizmo_delta(editor, vec3(0.0, 0.0, 0.0 - nudge_speed))
        if gpu.key_pressed(gpu.KEY_S):
            apply_gizmo_delta(editor, vec3(0.0, 0.0, nudge_speed))
        if gpu.key_pressed(gpu.KEY_A):
            apply_gizmo_delta(editor, vec3(0.0 - nudge_speed, 0.0, 0.0))
        if gpu.key_pressed(gpu.KEY_D):
            apply_gizmo_delta(editor, vec3(nudge_speed, 0.0, 0.0))

    # --- Hierarchy click-to-select (left panel entity list) ---
    if gpu.key_just_pressed(gpu.MOUSE_LEFT):
        if mx < layout["left_panel_w"] and my > 60.0:
            let click_idx = math.floor((my - 60.0) / 19.0)
            let all_ents = query(world, ["transform"])
            if click_idx >= 0 and click_idx < len(all_ents):
                select_entity(editor, all_ents[click_idx])

    # --- Save / Generate ---
    if action_just_pressed(inp, "save_scene"):
        save_scene(world, "EditorScene", "assets/editor_scene.json")

    if action_just_pressed(inp, "generate_code"):
        let code = generate_game_script(world, "GeneratedGame", {"width": 1280, "height": 720})
        io.writefile("assets/generated_game.sage", code)
        print "Generated: assets/generated_game.sage"

    # --- Update inspector ---
    if editor["selected"] >= 0:
        refresh_inspector(editor["inspector"])

    # --- Lighting ---
    let cam_pos = editor_camera_position(cam)
    set_view_position(ls, cam_pos)
    update_light_ubo(ls)

    # --- Render ---
    let frame = begin_frame(r)
    if frame == nil:
        running = false
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
    from frustum import extract_frustum_planes, aabb_in_frustum
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
    let lw = layout["left_panel_w"]
    let rw = layout["right_panel_w"]
    let tb_h = layout["toolbar_h"]
    let sb_h = layout["statusbar_h"]
    let bp_h = layout["bottom_panel_h"]
    let rp_x = sw - rw
    let cur_sel = editor["selected"]
    let cur_mode = editor["gizmo"]["mode"]

    # Draw panel backgrounds
    draw_ui(ui_r, cmd, layout["root"], sw, sh)

    # Mode button backgrounds + separators + selection highlight
    let ui_quads = []
    let modes = ["translate", "rotate", "scale"]
    let mx_b = 130.0
    let mi_b = 0
    while mi_b < 3:
        let bc = [0.22, 0.22, 0.25, 1.0]
        if cur_mode == modes[mi_b]:
            bc = [0.2, 0.45, 0.85, 1.0]
        push(ui_quads, {"x": mx_b, "y": 4.0, "w": 85.0, "h": 24.0, "color": bc})
        mx_b = mx_b + 90.0
        mi_b = mi_b + 1
    push(ui_quads, {"x": 0.0, "y": tb_h + 23.0, "w": lw, "h": 1.0, "color": [0.06, 0.06, 0.08, 1.0]})
    push(ui_quads, {"x": rp_x, "y": tb_h + 23.0, "w": rw, "h": 1.0, "color": [0.06, 0.06, 0.08, 1.0]})
    let bp_y_s = sh - bp_h - sb_h
    push(ui_quads, {"x": lw, "y": bp_y_s + 23.0, "w": sw - lw - rw, "h": 1.0, "color": [0.06, 0.06, 0.08, 1.0]})
    let ents = query(world, ["transform"])
    let ey = tb_h + 28.0
    let ei = 0
    while ei < len(ents) and ei < 25:
        if ents[ei] == cur_sel:
            push(ui_quads, {"x": 2.0, "y": ey - 1.0, "w": lw - 4.0, "h": 18.0, "color": [0.18, 0.35, 0.65, 0.5]})
        ey = ey + 19.0
        ei = ei + 1
    if len(ui_quads) > 0:
        let uv = build_quad_verts(ui_quads)
        gpu.buffer_upload(ui_r["vbuf"], uv)
        gpu.cmd_bind_graphics_pipeline(cmd, ui_r["pipeline"])
        gpu.cmd_push_constants(cmd, ui_r["pipe_layout"], gpu.STAGE_VERTEX, [sw, sh, 0.0, 0.0])
        gpu.cmd_bind_vertex_buffer(cmd, ui_r["vbuf"])
        gpu.cmd_draw(cmd, len(ui_quads) * 6, 1, 0, 0)

    # --- TrueType text ---
    proc _fn(n):
        return str(math.floor(n * 100.0 + 0.5) / 100.0)

    draw_text(font_r, cmd, "title", "FORGE", 10.0, 6.0, 0.3, 0.6, 1.0, 1.0, sw, sh)
    draw_text(font_r, cmd, "regular", "Move", 140.0, 8.0, 0.9, 0.9, 0.9, 1.0, sw, sh)
    draw_text(font_r, cmd, "regular", "Rotate", 230.0, 8.0, 0.9, 0.9, 0.9, 1.0, sw, sh)
    draw_text(font_r, cmd, "regular", "Scale", 320.0, 8.0, 0.9, 0.9, 0.9, 1.0, sw, sh)
    draw_text(font_r, cmd, "small", "4=Save  5=Generate Code", 430.0, 10.0, 0.45, 0.45, 0.45, 1.0, sw, sh)

    draw_text(font_r, cmd, "bold", "Outliner", 8.0, tb_h + 4.0, 0.8, 0.8, 0.8, 1.0, sw, sh)
    ey = tb_h + 28.0
    ei = 0
    while ei < len(ents) and ei < 25:
        let eid = ents[ei]
        let ename = "Entity_" + str(eid)
        if has_component(world, eid, "name"):
            ename = get_component(world, eid, "name")["name"]
        if eid == cur_sel:
            draw_text(font_r, cmd, "regular", ename, 16.0, ey + 1.0, 1.0, 1.0, 1.0, 1.0, sw, sh)
        else:
            draw_text(font_r, cmd, "small", ename, 16.0, ey + 2.0, 0.55, 0.55, 0.55, 1.0, sw, sh)
        ey = ey + 19.0
        ei = ei + 1

    draw_text(font_r, cmd, "bold", "Details", rp_x + 8.0, tb_h + 4.0, 0.8, 0.8, 0.8, 1.0, sw, sh)
    if cur_sel >= 0 and has_component(world, cur_sel, "transform"):
        let st = get_component(world, cur_sel, "transform")
        let iy = tb_h + 30.0
        if has_component(world, cur_sel, "name"):
            draw_text(font_r, cmd, "bold", get_component(world, cur_sel, "name")["name"], rp_x + 10.0, iy, 1.0, 1.0, 1.0, 1.0, sw, sh)
            iy = iy + 22.0
        draw_text(font_r, cmd, "regular", "Transform", rp_x + 10.0, iy, 0.6, 0.8, 1.0, 1.0, sw, sh)
        iy = iy + 20.0
        draw_text(font_r, cmd, "small", "Location", rp_x + 12.0, iy, 0.5, 0.5, 0.5, 1.0, sw, sh)
        iy = iy + 16.0
        draw_text(font_r, cmd, "small", "X " + _fn(st["position"][0]), rp_x + 14.0, iy, 0.9, 0.3, 0.3, 1.0, sw, sh)
        draw_text(font_r, cmd, "small", "Y " + _fn(st["position"][1]), rp_x + 100.0, iy, 0.3, 0.9, 0.3, 1.0, sw, sh)
        draw_text(font_r, cmd, "small", "Z " + _fn(st["position"][2]), rp_x + 186.0, iy, 0.3, 0.3, 0.9, 1.0, sw, sh)
        iy = iy + 18.0
        draw_text(font_r, cmd, "small", "Rotation", rp_x + 12.0, iy, 0.5, 0.5, 0.5, 1.0, sw, sh)
        iy = iy + 16.0
        draw_text(font_r, cmd, "small", "X " + _fn(st["rotation"][0]), rp_x + 14.0, iy, 0.9, 0.3, 0.3, 1.0, sw, sh)
        draw_text(font_r, cmd, "small", "Y " + _fn(st["rotation"][1]), rp_x + 100.0, iy, 0.3, 0.9, 0.3, 1.0, sw, sh)
        draw_text(font_r, cmd, "small", "Z " + _fn(st["rotation"][2]), rp_x + 186.0, iy, 0.3, 0.3, 0.9, 1.0, sw, sh)
        iy = iy + 18.0
        draw_text(font_r, cmd, "small", "Scale", rp_x + 12.0, iy, 0.5, 0.5, 0.5, 1.0, sw, sh)
        iy = iy + 16.0
        draw_text(font_r, cmd, "small", "X " + _fn(st["scale"][0]), rp_x + 14.0, iy, 0.9, 0.3, 0.3, 1.0, sw, sh)
        draw_text(font_r, cmd, "small", "Y " + _fn(st["scale"][1]), rp_x + 100.0, iy, 0.3, 0.9, 0.3, 1.0, sw, sh)
        draw_text(font_r, cmd, "small", "Z " + _fn(st["scale"][2]), rp_x + 186.0, iy, 0.3, 0.3, 0.9, 1.0, sw, sh)
    else:
        draw_text(font_r, cmd, "small", "Select an entity to view details", rp_x + 10.0, tb_h + 34.0, 0.4, 0.4, 0.4, 1.0, sw, sh)

    let bp_y = sh - bp_h - sb_h
    draw_text(font_r, cmd, "bold", "Content Browser", lw + 8.0, bp_y + 4.0, 0.8, 0.8, 0.8, 1.0, sw, sh)
    draw_text(font_r, cmd, "small", "R=Cube  F=Sphere  D=Delete  Q=Duplicate", lw + 10.0, bp_y + 28.0, 0.4, 0.4, 0.4, 1.0, sw, sh)
    draw_text(font_r, cmd, "small", "4=Save Scene  5=Generate SageLang Code", lw + 10.0, bp_y + 44.0, 0.4, 0.4, 0.4, 1.0, sw, sh)
    draw_text(font_r, cmd, "small", "LMB=Select  RMB=Orbit  MMB=Pan  Scroll=Zoom", lw + 10.0, bp_y + 60.0, 0.4, 0.4, 0.4, 1.0, sw, sh)

    let stats = editor_stats(editor)
    let status = str(stats["entities"]) + " entities  " + str(draw_count) + " drawn  " + stats["mode"]
    if stats["selected"] >= 0:
        status = status + "  |  #" + str(stats["selected"])
    status = status + "  |  FPS: " + str(math.floor(ts["fps"]))
    draw_text(font_r, cmd, "small", status, 8.0, sh - sb_h + 5.0, 0.4, 0.4, 0.4, 1.0, sw, sh)
    end_frame(r, frame)
    update_title_fps(r, "Forge Engine Editor")

gpu.device_wait_idle()
shutdown_renderer(r)
print "Editor closed"
