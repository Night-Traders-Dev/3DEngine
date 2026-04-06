gc_disable()
# demo_nbody.sage — N-Body Gravitational Simulation
# Universe Sandbox-style astrophysics with real solar system data
#
# Controls:
#   Mouse = Orbit camera | Scroll = Zoom
#   SPACE = Pause/Resume | Up/Down = Time scale
#   1 = Solar System | 2 = Binary Star | 3 = Random cluster
#   ESC = Quit

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta, scroll_value, bind_action
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from math3d import mat4_identity, mat4_mul, mat4_perspective, mat4_look_at, mat4_translate, mat4_scale, radians
from mesh import sphere_mesh, upload_mesh
from render_system import create_unlit_material, draw_mesh_unlit
from nbody import create_nbody_sim, add_body, add_solar_system, add_binary_star
from nbody import step_simulation, compute_total_energy, alive_body_count, simulation_info
from nbody import compute_gravitational_forces
from star_renderer import temperature_to_color
from game_loop import create_time_state, update_time

print "=== N-Body Gravitational Simulation ==="
print "Universe Sandbox-style astrophysics"
print ""

# ============================================================================
# Renderer — use UNLIT material for guaranteed color visibility
# ============================================================================
let r = create_renderer(1280, 720, "N-Body Simulation")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

let unlit_mat = create_unlit_material(r["render_pass"])
if unlit_mat == nil:
    raise "Failed to create unlit material"
print "✓ Unlit material ready"

# ============================================================================
# Input
# ============================================================================
let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "pause", [gpu.KEY_SPACE])
bind_action(inp, "speed_up", [gpu.KEY_UP])
bind_action(inp, "speed_down", [gpu.KEY_DOWN])
bind_action(inp, "preset_1", [gpu.KEY_1])
bind_action(inp, "preset_2", [gpu.KEY_2])
bind_action(inp, "preset_3", [gpu.KEY_3])

# ============================================================================
# Camera — orbit around origin
# ============================================================================
let cam_distance = 5.0
let cam_yaw = 0.3
let cam_pitch = -0.4

# ============================================================================
# Meshes
# ============================================================================
let sphere_hi = upload_mesh(sphere_mesh(16, 16))
let sphere_lo = upload_mesh(sphere_mesh(8, 8))

# ============================================================================
# Simulation
# ============================================================================
let sim = create_nbody_sim()
sim["dt"] = 0.0005
add_solar_system(sim)
compute_gravitational_forces(sim)

print "✓ Solar system: " + str(alive_body_count(sim)) + " bodies"
print ""
print "Controls: Mouse=Orbit | Scroll=Zoom | SPACE=Pause"
print "  Up/Down=Speed | 1=Solar | 2=Binary | 3=Cluster | ESC=Quit"
print ""

# ============================================================================
# Game Loop
# ============================================================================
let ts = create_time_state()
let running = true
let frame_count = 0

while running:
    update_time(ts)
    update_input(inp)

    if action_just_pressed(inp, "escape"):
        running = false

    if action_just_pressed(inp, "pause"):
        sim["paused"] = not sim["paused"]

    if action_just_pressed(inp, "speed_up"):
        sim["time_scale"] = sim["time_scale"] * 2.0
        if sim["time_scale"] > 256.0:
            sim["time_scale"] = 256.0
    if action_just_pressed(inp, "speed_down"):
        sim["time_scale"] = sim["time_scale"] * 0.5
        if sim["time_scale"] < 0.0625:
            sim["time_scale"] = 0.0625

    # Preset switching
    if action_just_pressed(inp, "preset_1"):
        sim = create_nbody_sim()
        add_solar_system(sim)
        compute_gravitational_forces(sim)
        cam_distance = 5.0
    if action_just_pressed(inp, "preset_2"):
        sim = create_nbody_sim()
        add_binary_star(sim, 0.5, 0.7)
        compute_gravitational_forces(sim)
        cam_distance = 2.0
    if action_just_pressed(inp, "preset_3"):
        sim = create_nbody_sim()
        let ci = 0
        while ci < 30:
            let px = (math.random() - 0.5) * 4.0
            let py = (math.random() - 0.5) * 0.5
            let pz = (math.random() - 0.5) * 4.0
            let mass = 0.001 + math.random() * 0.01
            let vx = (math.random() - 0.5) * 2.0
            let vz = (math.random() - 0.5) * 2.0
            let cr = 0.5 + math.random() * 0.5
            let cg = 0.5 + math.random() * 0.5
            let cb = 0.5 + math.random() * 0.5
            add_body(sim, "S" + str(ci), mass, 50000.0, vec3(px, py, pz), vec3(vx, 0.0, vz), [cr, cg, cb])
            ci = ci + 1
        add_body(sim, "Central", 1.0, 696340.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), [1.0, 0.9, 0.5])
        compute_gravitational_forces(sim)
        cam_distance = 6.0

    # Camera orbit
    let mdelta = mouse_delta(inp)
    cam_yaw = cam_yaw + mdelta[0] * 0.005
    cam_pitch = cam_pitch + mdelta[1] * 0.005
    if cam_pitch > 1.5:
        cam_pitch = 1.5
    if cam_pitch < -1.5:
        cam_pitch = -1.5

    let scroll = scroll_value(inp)
    if scroll[1] != 0.0:
        cam_distance = cam_distance - scroll[1] * cam_distance * 0.1
        if cam_distance < 0.1:
            cam_distance = 0.1
        if cam_distance > 200.0:
            cam_distance = 200.0

    # Simulation steps
    let si = 0
    while si < 4:
        step_simulation(sim, sim["dt"])
        si = si + 1

    # Camera position
    let cam_x = math.cos(cam_yaw) * math.cos(cam_pitch) * cam_distance
    let cam_y = math.sin(cam_pitch) * cam_distance
    let cam_z = math.sin(cam_yaw) * math.cos(cam_pitch) * cam_distance
    let cam_pos = vec3(cam_x, cam_y, cam_z)

    # Dark space background
    r["clear_color"] = [0.005, 0.005, 0.015, 1.0]

    # Render
    let frame = begin_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        check_resize(r)
        continue
    let cmd = frame["cmd"]

    let aspect = r["width"] / r["height"]
    let view = mat4_look_at(cam_pos, vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0))
    let proj = mat4_perspective(radians(60.0), aspect, 0.001, 500.0)
    let vp = mat4_mul(proj, view)

    # Draw each body as unlit colored sphere
    let bi = 0
    while bi < len(sim["bodies"]):
        let body = sim["bodies"][bi]
        if body["alive"]:
            let pos = body["position"]

            # Visual size — exaggerated for visibility
            let vis_r = 0.1 + math.log(body["radius"] + 1.0) * 0.02
            if body["type"] == "star":
                vis_r = vis_r * 5.0
            else:
                vis_r = vis_r * 2.5

            # Model matrix
            let model = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_scale(vis_r, vis_r, vis_r))
            let mvp = mat4_mul(vp, model)

            # Color — stars use temperature, planets use defined color
            let color = [body["color"][0], body["color"][1], body["color"][2], 1.0]
            if body["type"] == "star" and body["temperature"] > 0:
                let tc = temperature_to_color(body["temperature"])
                color = [tc[0] * 2.0, tc[1] * 2.0, tc[2] * 1.8, 1.0]

            # LOD
            let dist_to_cam = v3_length(v3_sub(pos, cam_pos))
            let mesh = sphere_hi
            if dist_to_cam > 15.0:
                mesh = sphere_lo

            draw_mesh_unlit(cmd, unlit_mat, mesh, mvp, color)

            # Draw trail points
            let ti = 0
            while ti < len(body["trail"]):
                let tp = body["trail"][ti]
                let trail_size = 0.008
                let t_model = mat4_mul(mat4_translate(tp[0], tp[1], tp[2]), mat4_scale(trail_size, trail_size, trail_size))
                let t_mvp = mat4_mul(vp, t_model)
                let fade = (ti + 1) / (len(body["trail"]) + 1)
                let t_color = [body["color"][0] * fade, body["color"][1] * fade, body["color"][2] * fade, fade]
                draw_mesh_unlit(cmd, unlit_mat, sphere_lo, t_mvp, t_color)
                ti = ti + 12  # Skip for performance
        bi = bi + 1

    # Title
    let info = simulation_info(sim)
    let time_str = str(int(info["time_years"] * 100.0) / 100.0)
    let paused_str = ""
    if sim["paused"]:
        paused_str = " [PAUSED]"
    update_title_fps(r, "N-Body | " + str(info["bodies"]) + " bodies | " + time_str + " yr | " + str(sim["time_scale"]) + "x" + paused_str)

    end_frame(r, frame)
    frame_count = frame_count + 1
    check_resize(r)

# Shutdown
print ""
print "Frames: " + str(frame_count) + " | Collisions: " + str(sim["collision_count"])
shutdown_renderer(r)
print "✓ Done"
