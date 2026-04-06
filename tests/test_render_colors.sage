gc_disable()
# test_render_colors.sage — Visual test for rendering pipeline
# Should show: red, green, blue cubes on grey background
# If all cubes are BLACK, the rendering pipeline is broken.

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, default_fps_bindings
from math3d import vec3, mat4_identity, mat4_mul, mat4_perspective, mat4_look_at, mat4_translate, mat4_scale, radians
from mesh import cube_mesh, sphere_mesh, upload_mesh
from render_system import create_unlit_material, draw_mesh_unlit

print "=== Render Color Test ==="
print "You should see: RED, GREEN, BLUE cubes on grey background"
print "If cubes are BLACK, rendering is broken."
print ""

let r = create_renderer(1024, 768, "Color Test - Should See RGB Cubes")
if r == nil:
    raise "Renderer failed"
print "GPU: " + gpu.device_name()

let mat = create_unlit_material(r["render_pass"])
if mat == nil:
    raise "Material failed"
print "Material OK"

let cube = upload_mesh(cube_mesh())
let sphere = upload_mesh(sphere_mesh(12, 12))
print "Meshes OK: cube idx=" + str(cube["index_count"]) + " sphere idx=" + str(sphere["index_count"])

let inp = create_input()
default_fps_bindings(inp)

# Camera looking at origin from an angle
let cam_pos = vec3(5.0, 4.0, 5.0)
let cam_target = vec3(0.0, 0.0, 0.0)
let view = mat4_look_at(cam_pos, cam_target, vec3(0.0, 1.0, 0.0))
let aspect = 1024.0 / 768.0
let proj = mat4_perspective(radians(60.0), aspect, 0.1, 100.0)
let vp = mat4_mul(proj, view)

print "Running... ESC to quit"
let running = true
let frame_count = 0

while running:
    update_input(inp)
    if action_just_pressed(inp, "escape"):
        running = false

    if gpu.window_should_close():
        running = false
        continue

    r["clear_color"] = [0.3, 0.3, 0.35, 1.0]  # Grey background

    let frame = begin_frame(r)
    if frame == nil:
        check_resize(r)
        frame_count = frame_count + 1
        continue
    let cmd = frame["cmd"]

    # RED cube at (-2, 0, 0)
    let red_model = mat4_translate(-2.0, 0.0, 0.0)
    let red_mvp = mat4_mul(vp, red_model)
    draw_mesh_unlit(cmd, mat, cube, red_mvp, [1.0, 0.0, 0.0, 1.0])

    # GREEN cube at (0, 0, 0)
    let green_model = mat4_translate(0.0, 0.0, 0.0)
    let green_mvp = mat4_mul(vp, green_model)
    draw_mesh_unlit(cmd, mat, cube, green_mvp, [0.0, 1.0, 0.0, 1.0])

    # BLUE cube at (2, 0, 0)
    let blue_model = mat4_translate(2.0, 0.0, 0.0)
    let blue_mvp = mat4_mul(vp, blue_model)
    draw_mesh_unlit(cmd, mat, cube, blue_mvp, [0.0, 0.0, 1.0, 1.0])

    # WHITE sphere at (0, 2, 0)
    let white_model = mat4_translate(0.0, 2.0, 0.0)
    let white_mvp = mat4_mul(vp, white_model)
    draw_mesh_unlit(cmd, mat, sphere, white_mvp, [1.0, 1.0, 1.0, 1.0])

    # YELLOW sphere at (0, -1, 2)
    let yellow_model = mat4_mul(mat4_translate(0.0, -1.0, 2.0), mat4_scale(0.5, 0.5, 0.5))
    let yellow_mvp = mat4_mul(vp, yellow_model)
    draw_mesh_unlit(cmd, mat, sphere, yellow_mvp, [1.0, 1.0, 0.0, 1.0])

    update_title_fps(r, "Color Test | Frame " + str(frame_count))
    end_frame(r, frame)
    frame_count = frame_count + 1
    check_resize(r)

shutdown_renderer(r)
print "Done: " + str(frame_count) + " frames"
