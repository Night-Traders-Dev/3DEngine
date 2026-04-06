gc_disable()
# test_lit_vs_unlit.sage — Compare lit and unlit rendering
# Left side: unlit cubes (should always have color)
# Right side: lit cubes (may be black if lighting is broken)

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, default_fps_bindings
from math3d import vec3, mat4_mul, mat4_perspective, mat4_look_at, mat4_translate, radians
from mesh import cube_mesh, upload_mesh
from render_system import create_unlit_material, draw_mesh_unlit
from render_system import create_lit_material, draw_mesh_lit_surface_controlled
from lighting import create_light_scene, directional_light, add_light
from lighting import set_ambient, set_view_position, init_light_gpu, update_light_ubo

print "=== Lit vs Unlit Comparison ==="
print "LEFT: Unlit (should be colored)"
print "RIGHT: Lit (may be black if lighting broken)"

let r = create_renderer(1024, 768, "Lit vs Unlit Test")

# Unlit material (always works)
let unlit_mat = create_unlit_material(r["render_pass"])
print "Unlit mat: " + str(unlit_mat != nil)

# Lit material (might be broken)
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.3, -0.8, 0.5, 1.0, 0.95, 0.85, 1.5))
set_ambient(ls, 0.3, 0.3, 0.35, 0.5)
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])
print "Lit mat: " + str(lit_mat != nil)

let cube = upload_mesh(cube_mesh())

let inp = create_input()
default_fps_bindings(inp)

let cam_pos = vec3(0.0, 3.0, 8.0)
let view = mat4_look_at(cam_pos, vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0))
let proj = mat4_perspective(radians(60.0), 1.333, 0.1, 100.0)
let vp = mat4_mul(proj, view)

let running = true
let frame_count = 0

while running:
    update_input(inp)
    if action_just_pressed(inp, "escape"):
        running = false
    if gpu.window_should_close():
        running = false
        continue

    set_view_position(ls, cam_pos)
    update_light_ubo(ls)

    r["clear_color"] = [0.15, 0.15, 0.2, 1.0]

    let frame = begin_frame(r)
    if frame == nil:
        check_resize(r)
        frame_count = frame_count + 1
        continue
    let cmd = frame["cmd"]

    # LEFT SIDE: Unlit cubes (guaranteed visible)
    let model_left = mat4_translate(-3.0, 0.0, 0.0)
    let mvp_left = mat4_mul(vp, model_left)
    draw_mesh_unlit(cmd, unlit_mat, cube, mvp_left, [1.0, 0.3, 0.1, 1.0])

    let model_left2 = mat4_translate(-3.0, 2.0, 0.0)
    let mvp_left2 = mat4_mul(vp, model_left2)
    draw_mesh_unlit(cmd, unlit_mat, cube, mvp_left2, [0.1, 0.8, 0.3, 1.0])

    # RIGHT SIDE: Lit cubes (may be broken)
    if lit_mat != nil:
        let model_right = mat4_translate(3.0, 0.0, 0.0)
        let mvp_right = mat4_mul(vp, model_right)
        let surface = {"albedo": [1.0, 0.3, 0.1]}
        draw_mesh_lit_surface_controlled(cmd, lit_mat, cube, mvp_right, model_right, ls["desc_set"], surface, true)

        let model_right2 = mat4_translate(3.0, 2.0, 0.0)
        let mvp_right2 = mat4_mul(vp, model_right2)
        let surface2 = {"albedo": [0.1, 0.8, 0.3]}
        draw_mesh_lit_surface_controlled(cmd, lit_mat, cube, mvp_right2, model_right2, ls["desc_set"], surface2, true)

    update_title_fps(r, "Lit vs Unlit | Frame " + str(frame_count))
    end_frame(r, frame)
    frame_count = frame_count + 1
    check_resize(r)

shutdown_renderer(r)
print "Done: " + str(frame_count) + " frames"
