# editor.sage - Sage Engine Visual Editor
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
from ui_renderer import create_ui_renderer, draw_ui, build_ui_vertices
from ui_text import build_text_quads, measure_text
from ui_core import create_widget, create_rect, create_panel, add_child, collect_quads, compute_layout
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

print "=== Sage Engine Editor ==="

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(1440, 900, "Sage Engine Editor")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

# ============================================================================
# Lighting & Sky
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.3, -0.7, 0.5, 1.0, 0.95, 0.85, 1.0))
add_light(ls, point_light(5.0, 4.0, 3.0, 1.0, 0.8, 0.6, 3.0, 20.0))
set_ambient(ls, 0.15, 0.15, 0.2, 0.35)
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])

let sky = create_sky()
sky_preset_day(sky)
init_sky_gpu(sky, r["render_pass"])

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
    draw_sky(sky, cmd, view, aspect, radians(60.0), ts["total"])

    # 3D scene
    let renderers = query(world, ["transform", "mesh_id"])
    let ri = 0
    while ri < len(renderers):
        let eid = renderers[ri]
        let t = get_component(world, eid, "transform")
        let mi = get_component(world, eid, "mesh_id")
        let model = transform_to_matrix(t)
        let mvp = mat4_mul(vp, model)
        draw_mesh_lit(cmd, lit_mat, mi["mesh"], mvp, model, ls["desc_set"])
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

    # --- Editor UI overlay ---
    # Build text quads for panels
    let text_quads = []
    let psize = 2.0

    # Toolbar text
    let mode_name = editor["gizmo"]["mode"]
    let tb_text = "Sage Editor | Mode: " + mode_name
    let tbq = build_text_quads(tb_text, 8.0, 8.0, psize, THEME_TEXT)
    let tbi = 0
    while tbi < len(tbq):
        push(text_quads, tbq[tbi])
        tbi = tbi + 1

    # Left panel: scene hierarchy
    let lp_title = "Scene Hierarchy"
    let lpq = build_text_quads(lp_title, 8.0, 38.0, psize, THEME_TEXT)
    tbi = 0
    while tbi < len(lpq):
        push(text_quads, lpq[tbi])
        tbi = tbi + 1

    let ents = query(world, ["transform"])
    let ey = 58.0
    let ei = 0
    while ei < len(ents) and ei < 25:
        let eid = ents[ei]
        let ename = "Entity_" + str(eid)
        if has_component(world, eid, "name"):
            ename = get_component(world, eid, "name")["name"]
        let ecolor = THEME_TEXT_DIM
        if eid == editor["selected"]:
            ecolor = THEME_ACCENT
            # Selection highlight
            push(text_quads, {"x": 4.0, "y": ey - 1.0, "w": 212.0, "h": 14.0, "color": [0.2, 0.35, 0.6, 0.4]})
        let eq = build_text_quads(ename, 12.0, ey, psize, ecolor)
        let eqi = 0
        while eqi < len(eq):
            push(text_quads, eq[eqi])
            eqi = eqi + 1
        ey = ey + 16.0
        ei = ei + 1

    # Right panel: inspector
    let rp_x = sw - 272.0
    let rp_title = "Details"
    let rpq = build_text_quads(rp_title, rp_x + 8.0, 38.0, psize, THEME_TEXT)
    tbi = 0
    while tbi < len(rpq):
        push(text_quads, rpq[tbi])
        tbi = tbi + 1

    if editor["selected"] >= 0:
        let sel_eid = editor["selected"]
        let iy = 60.0
        if has_component(world, sel_eid, "name"):
            let n = get_component(world, sel_eid, "name")
            let nq = build_text_quads("Name: " + n["name"], rp_x + 8.0, iy, psize, THEME_TEXT)
            let nqi = 0
            while nqi < len(nq):
                push(text_quads, nq[nqi])
                nqi = nqi + 1
            iy = iy + 18.0
        if has_component(world, sel_eid, "transform"):
            let t = get_component(world, sel_eid, "transform")
            import math
            let px = str(math.floor(t["position"][0] * 100.0 + 0.5) / 100.0)
            let py = str(math.floor(t["position"][1] * 100.0 + 0.5) / 100.0)
            let pz = str(math.floor(t["position"][2] * 100.0 + 0.5) / 100.0)
            let pq = build_text_quads("Pos: " + px + " " + py + " " + pz, rp_x + 8.0, iy, psize, THEME_TEXT_DIM)
            let pqi = 0
            while pqi < len(pq):
                push(text_quads, pq[pqi])
                pqi = pqi + 1
            iy = iy + 16.0
            let rx = str(math.floor(t["rotation"][0] * 100.0 + 0.5) / 100.0)
            let ry = str(math.floor(t["rotation"][1] * 100.0 + 0.5) / 100.0)
            let rz = str(math.floor(t["rotation"][2] * 100.0 + 0.5) / 100.0)
            let rq = build_text_quads("Rot: " + rx + " " + ry + " " + rz, rp_x + 8.0, iy, psize, THEME_TEXT_DIM)
            let rqi = 0
            while rqi < len(rq):
                push(text_quads, rq[rqi])
                rqi = rqi + 1
            iy = iy + 16.0
            let scx = str(math.floor(t["scale"][0] * 100.0 + 0.5) / 100.0)
            let scy = str(math.floor(t["scale"][1] * 100.0 + 0.5) / 100.0)
            let scz = str(math.floor(t["scale"][2] * 100.0 + 0.5) / 100.0)
            let sq = build_text_quads("Scl: " + scx + " " + scy + " " + scz, rp_x + 8.0, iy, psize, THEME_TEXT_DIM)
            let sqi = 0
            while sqi < len(sq):
                push(text_quads, sq[sqi])
                sqi = sqi + 1

    # Bottom panel: asset browser / console
    let bp_x = 220.0
    let bp_y = sh - 204.0
    let bp_text = "Assets | R=Cube F=Sphere | 5=Generate Code 4=Save"
    let bpq = build_text_quads(bp_text, bp_x + 8.0, bp_y + 4.0, psize, THEME_TEXT)
    tbi = 0
    while tbi < len(bpq):
        push(text_quads, bpq[tbi])
        tbi = tbi + 1

    # Status bar
    let stats = editor_stats(editor)
    let status = "Entities: " + str(stats["entities"])
    status = status + " | Mode: " + stats["mode"]
    if stats["selected"] >= 0:
        status = status + " | Selected: #" + str(stats["selected"])
    let stq = build_text_quads(status, 8.0, sh - 20.0, psize, THEME_TEXT_DIM)
    tbi = 0
    while tbi < len(stq):
        push(text_quads, stq[tbi])
        tbi = tbi + 1

    # Draw layout panels + all text
    draw_ui(ui_r, cmd, layout["root"], sw, sh)

    # Draw text quads
    if len(text_quads) > 0:
        let tverts = build_ui_vertices(text_quads)
        let tvc = len(text_quads) * 6
        if tvc > 3072:
            tvc = 3072
        gpu.buffer_upload(ui_r["vbuf"], tverts)
        gpu.cmd_bind_graphics_pipeline(cmd, ui_r["pipeline"])
        let push = [sw, sh, 0.0, 0.0]
        gpu.cmd_push_constants(cmd, ui_r["pipe_layout"], gpu.STAGE_VERTEX, push)
        gpu.cmd_bind_vertex_buffer(cmd, ui_r["vbuf"])
        gpu.cmd_draw(cmd, tvc, 1, 0, 0)

    end_frame(r, frame)
    update_title_fps(r, "Sage Engine Editor")

gpu.device_wait_idle()
shutdown_renderer(r)
print "Editor closed"
