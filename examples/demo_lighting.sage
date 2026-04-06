gc_disable()
# demo_lighting.sage - Forge Engine Phase 2 Demo
# Demonstrates: Lit rendering, point/directional lights, fog, procedural sky
#
# Run: ./run.sh examples/demo_lighting.sage
# Controls: WASD move | Mouse look (ESC capture) | Q quit
#           1=Day 2=Sunset 3=Night 4=Overcast | F=Toggle fog

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer
from renderer import check_resize, update_title_fps, aspect_ratio
from ecs import create_world, spawn, add_component, get_component, query
from ecs import register_system, tick_systems, flush_dead, add_tag
from components import TransformComponent, VelocityComponent, NameComponent
from input import create_input, update_input, bind_action, bind_axis
from input import action_held, action_just_pressed, axis_value
from input import mouse_delta, default_fps_bindings
from engine_math import transform_to_matrix, clamp
from math3d import vec3, v3_add, v3_scale, v3_normalize, v3_cross
from math3d import mat4_perspective, mat4_look_at, mat4_mul, radians, pack_mvp
from mesh import cube_mesh, plane_mesh, sphere_mesh, upload_mesh, mesh_vertex_binding, mesh_vertex_attribs
from lighting import create_light_scene, point_light, directional_light
from lighting import add_light, set_ambient, set_fog, set_view_position, init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit
from sky import create_sky, init_sky_gpu, draw_sky
from sky import sky_preset_day, sky_preset_sunset, sky_preset_night, sky_preset_overcast
from game_loop import create_time_state, update_time
import sys

print "=== Forge Engine - Phase 2: Lighting & Sky Demo ==="

# ============================================================================
# Renderer setup
# ============================================================================
let r = create_renderer(1280, 720, "Forge Engine - Lighting Demo")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

# ============================================================================
# Lighting setup
# ============================================================================
let ls = create_light_scene()
init_light_gpu(ls)

# Sun (directional)
let sun_idx = add_light(ls, directional_light(0.3, -0.8, 0.5, 1.0, 0.95, 0.85, 1.2))

# Colored point lights around the scene
add_light(ls, point_light(4.0, 2.0, 0.0, 1.0, 0.3, 0.1, 3.0, 15.0))
add_light(ls, point_light(-4.0, 2.0, 0.0, 0.1, 0.3, 1.0, 3.0, 15.0))
add_light(ls, point_light(0.0, 2.0, 4.0, 0.1, 1.0, 0.3, 3.0, 15.0))
add_light(ls, point_light(0.0, 2.0, -4.0, 1.0, 1.0, 0.2, 2.0, 12.0))

set_ambient(ls, 0.15, 0.15, 0.2, 0.3)
set_fog(ls, false, 30.0, 120.0, 0.6, 0.65, 0.7)

# ============================================================================
# Materials
# ============================================================================
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])
if lit_mat == nil:
    raise "Failed to create lit material"
print "Lit material created"

# ============================================================================
# Sky
# ============================================================================
let sky = create_sky()
sky_preset_day(sky)
let sky_ok = init_sky_gpu(sky, r["render_pass"])
if sky_ok == false:
    print "WARNING: Sky renderer failed to initialize"

# ============================================================================
# Meshes
# ============================================================================
let cube_gpu = upload_mesh(cube_mesh())
let ground_gpu = upload_mesh(plane_mesh(40.0))
let sphere_gpu = upload_mesh(sphere_mesh(24, 24))

# ============================================================================
# ECS World
# ============================================================================
let world = create_world()

# Ground
let ground_ent = spawn(world)
add_component(world, ground_ent, "transform", TransformComponent(0.0, 0.0, 0.0))
add_component(world, ground_ent, "name", NameComponent("Ground"))
add_component(world, ground_ent, "mesh_id", {"mesh": ground_gpu})

# Cubes ring
let NUM_CUBES = 12
let ci = 0
while ci < NUM_CUBES:
    let angle = (ci / NUM_CUBES) * 6.2831853
    let px = math.cos(angle) * 6.0
    let pz = math.sin(angle) * 6.0
    let e = spawn(world)
    add_component(world, e, "transform", TransformComponent(px, 0.5, pz))
    add_component(world, e, "velocity", VelocityComponent())
    add_component(world, e, "name", NameComponent("Cube_" + str(ci)))
    add_component(world, e, "mesh_id", {"mesh": cube_gpu})
    let vel = get_component(world, e, "velocity")
    vel["angular"] = vec3(0.3 + ci * 0.15, 0.8 + ci * 0.2, 0.1)
    ci = ci + 1

# Center sphere
let sphere_ent = spawn(world)
add_component(world, sphere_ent, "transform", TransformComponent(0.0, 1.5, 0.0))
add_component(world, sphere_ent, "velocity", VelocityComponent())
add_component(world, sphere_ent, "name", NameComponent("Sphere"))
add_component(world, sphere_ent, "mesh_id", {"mesh": sphere_gpu})
let sv = get_component(world, sphere_ent, "velocity")
sv["angular"] = vec3(0.0, 0.3, 0.0)

# Tall pillars
let pi_idx = 0
while pi_idx < 4:
    let pa = pi_idx * 1.5708
    let ppx = math.cos(pa) * 10.0
    let ppz = math.sin(pa) * 10.0
    let pe = spawn(world)
    let pt = TransformComponent(ppx, 2.0, ppz)
    pt["scale"] = vec3(0.5, 4.0, 0.5)
    add_component(world, pe, "transform", pt)
    add_component(world, pe, "name", NameComponent("Pillar_" + str(pi_idx)))
    add_component(world, pe, "mesh_id", {"mesh": cube_gpu})
    pi_idx = pi_idx + 1

print "Scene: " + str(NUM_CUBES) + " cubes, 1 sphere, 4 pillars, ground"

# ============================================================================
# Spin system
# ============================================================================
proc spin_system(w, entities, dt):
    let i = 0
    while i < len(entities):
        let e = entities[i]
        let t = get_component(w, e, "transform")
        let v = get_component(w, e, "velocity")
        t["rotation"][0] = t["rotation"][0] + v["angular"][0] * dt
        t["rotation"][1] = t["rotation"][1] + v["angular"][1] * dt
        t["rotation"][2] = t["rotation"][2] + v["angular"][2] * dt
        t["dirty"] = true
        i = i + 1

register_system(world, "spin", ["transform", "velocity"], spin_system)

# ============================================================================
# Input setup
# ============================================================================
let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "quit", [gpu.KEY_Q])
bind_action(inp, "toggle_capture", [gpu.KEY_ESCAPE])
bind_action(inp, "preset_day", [gpu.KEY_1])
bind_action(inp, "preset_sunset", [gpu.KEY_2])
bind_action(inp, "preset_night", [gpu.KEY_3])
bind_action(inp, "preset_overcast", [gpu.KEY_4])
bind_action(inp, "toggle_fog", [gpu.KEY_F])

# ============================================================================
# Camera
# ============================================================================
let cam = {}
cam["pos"] = vec3(0.0, 3.0, 12.0)
cam["yaw"] = -1.5708
cam["pitch"] = -0.2
cam["captured"] = false
cam["speed"] = 5.0

# ============================================================================
# Main loop
# ============================================================================
let ts = create_time_state()
let running = true
let fog_on = false

print "Controls: WASD move | Mouse (ESC capture) | Q quit"
print "          1=Day 2=Sunset 3=Night 4=Overcast | F=Fog"

while running:
    update_time(ts)
    let dt = ts["dt"]

    check_resize(r)
    update_input(inp)

    # --- Input ---
    if action_just_pressed(inp, "quit"):
        running = false
        continue

    if action_just_pressed(inp, "toggle_capture"):
        if cam["captured"]:
            cam["captured"] = false
            gpu.set_cursor_mode(gpu.CURSOR_NORMAL)
        else:
            cam["captured"] = true
            gpu.set_cursor_mode(gpu.CURSOR_DISABLED)

    # Sky presets
    if action_just_pressed(inp, "preset_day"):
        sky_preset_day(sky)
        set_ambient(ls, 0.15, 0.15, 0.2, 0.3)
        print "Sky: Day"
    if action_just_pressed(inp, "preset_sunset"):
        sky_preset_sunset(sky)
        set_ambient(ls, 0.2, 0.12, 0.08, 0.2)
        print "Sky: Sunset"
    if action_just_pressed(inp, "preset_night"):
        sky_preset_night(sky)
        set_ambient(ls, 0.02, 0.02, 0.05, 0.1)
        print "Sky: Night"
    if action_just_pressed(inp, "preset_overcast"):
        sky_preset_overcast(sky)
        set_ambient(ls, 0.25, 0.25, 0.28, 0.4)
        print "Sky: Overcast"

    if action_just_pressed(inp, "toggle_fog"):
        fog_on = fog_on == false
        set_fog(ls, fog_on, 30.0, 120.0, 0.6, 0.65, 0.7)
        if fog_on:
            print "Fog: ON"
        else:
            print "Fog: OFF"

    # Camera movement
    if cam["captured"]:
        let md = mouse_delta(inp)
        cam["yaw"] = cam["yaw"] + md[0] * 0.003
        cam["pitch"] = cam["pitch"] - md[1] * 0.003
        cam["pitch"] = clamp(cam["pitch"], -1.5, 1.5)

    let cy = math.cos(cam["yaw"])
    let sy = math.sin(cam["yaw"])
    let cp = math.cos(cam["pitch"])
    let sp = math.sin(cam["pitch"])
    let front = vec3(cy * cp, sp, sy * cp)
    let right = v3_normalize(v3_cross(front, vec3(0.0, 1.0, 0.0)))
    let ms = cam["speed"] * dt

    if action_held(inp, "move_forward"):
        cam["pos"] = v3_add(cam["pos"], v3_scale(front, ms))
    if action_held(inp, "move_back"):
        cam["pos"] = v3_add(cam["pos"], v3_scale(front, 0.0 - ms))
    if action_held(inp, "move_left"):
        cam["pos"] = v3_add(cam["pos"], v3_scale(right, 0.0 - ms))
    if action_held(inp, "move_right"):
        cam["pos"] = v3_add(cam["pos"], v3_scale(right, ms))
    if action_held(inp, "jump"):
        cam["pos"][1] = cam["pos"][1] + ms
    if action_held(inp, "crouch"):
        cam["pos"][1] = cam["pos"][1] - ms

    # --- Fixed update ---
    tick_systems(world, dt)
    flush_dead(world)

    # --- Update lighting UBO ---
    set_view_position(ls, cam["pos"])

    # Animate one point light in a circle
    let anim_t = ts["total"]
    let anim_light = ls["lights"][1]
    anim_light["position"][0] = math.cos(anim_t * 0.7) * 5.0
    anim_light["position"][2] = math.sin(anim_t * 0.7) * 5.0
    ls["dirty"] = true

    update_light_ubo(ls)

    # --- Render ---
    if gpu.window_should_close():
        running = false
        continue
    let frame = begin_frame(r)
    if frame == nil:
        # Transient resize/minimize/swapchain blip - skip this frame
        continue
    let cmd = frame["cmd"]

    # View/Projection
    let target = v3_add(cam["pos"], front)
    let view = mat4_look_at(cam["pos"], target, vec3(0.0, 1.0, 0.0))
    let aspect = r["width"] / r["height"]
    let proj = mat4_perspective(radians(60.0), aspect, 0.1, 500.0)
    let vp = mat4_mul(proj, view)

    # Draw sky first (writes to far depth)
    draw_sky(sky, cmd, view, aspect, radians(60.0), anim_t)

    # Draw all meshes with lit material
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

    end_frame(r, frame)
    update_title_fps(r, "Forge Engine - Lighting Demo")

gpu.device_wait_idle()
shutdown_renderer(r)
let total_frames = ts["frame_count"]
let elapsed = ts["total"]
if elapsed > 0:
    print "Total: " + str(total_frames) + " frames (" + str(total_frames / elapsed) + " FPS)"
print "Demo complete!"
