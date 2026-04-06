gc_disable()
# demo_nbody.sage — N-Body Gravitational Simulation
# Universe Sandbox-style astrophysics with real solar system data
#
# Controls:
#   WASD = Orbit camera | Mouse = Look | Scroll = Zoom
#   SPACE = Pause/Resume | +/- = Time scale
#   1 = Solar System | 2 = Binary Star | 3 = Random cluster
#   ESC = Quit

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta, scroll_value, bind_action
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, mat4_identity, mat4_mul, mat4_perspective, mat4_look_at, radians
from mesh import sphere_mesh, upload_mesh
from lighting import create_light_scene, directional_light, point_light, add_light, set_ambient, set_fog, set_view_position, init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit_surface_controlled
from nbody import create_nbody_sim, add_body, add_solar_system, add_binary_star
from nbody import step_simulation, compute_total_energy, alive_body_count, simulation_info, find_body
from nbody import orbital_velocity_circular
from star_renderer import temperature_to_color, create_star_visuals, update_star_visuals
from game_loop import create_time_state, update_time

print "=== N-Body Gravitational Simulation ==="
print "Universe Sandbox-style astrophysics with Forge Engine"
print ""

# ============================================================================
# Renderer + Lighting
# ============================================================================
let r = create_renderer(1280, 720, "N-Body Simulation - Solar System")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

let ls = create_light_scene()
init_light_gpu(ls)
# Strong directional light (illuminates everything regardless of distance)
from lighting import directional_light
add_light(ls, directional_light(0.3, -0.5, 0.2, 1.0, 0.95, 0.85, 1.5))
# High ambient so bodies are always visible in space
set_ambient(ls, 0.25, 0.25, 0.3, 0.6)

let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])

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
# Camera — orbit camera around system center
# ============================================================================
let cam_distance = 5.0
let cam_yaw = 0.0
let cam_pitch = -0.3
let cam_target = vec3(0.0, 0.0, 0.0)

# ============================================================================
# Meshes — sphere for each body (different LOD sizes)
# ============================================================================
let sphere_hi = upload_mesh(sphere_mesh(16, 16))
let sphere_lo = upload_mesh(sphere_mesh(8, 8))

# ============================================================================
# Simulation
# ============================================================================
let sim = create_nbody_sim()
sim["dt"] = 0.0005  # ~4.38 hours per step
sim["time_scale"] = 1.0
add_solar_system(sim)

# Initial force computation
from nbody import compute_gravitational_forces
compute_gravitational_forces(sim)

print "✓ Solar system loaded: " + str(alive_body_count(sim)) + " bodies"
print ""
print "Controls: WASD/Mouse=Camera | Scroll=Zoom | SPACE=Pause"
print "  Up/Down = Time scale | 1=Solar | 2=Binary | 3=Cluster | ESC=Quit"
print ""

# ============================================================================
# Game Loop
# ============================================================================
let ts = create_time_state()
let running = true
let frame_count = 0
let steps_per_frame = 4

while running:
    update_time(ts)
    let dt = ts["dt"]
    update_input(inp)

    # Quit
    if action_just_pressed(inp, "escape"):
        running = false

    # Pause
    if action_just_pressed(inp, "pause"):
        sim["paused"] = not sim["paused"]

    # Time scale
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
        # Random star cluster
        let ci = 0
        while ci < 30:
            let px = (math.random() - 0.5) * 4.0
            let py = (math.random() - 0.5) * 0.5
            let pz = (math.random() - 0.5) * 4.0
            let mass = 0.001 + math.random() * 0.01
            let vx = (math.random() - 0.5) * 2.0
            let vy = (math.random() - 0.5) * 0.5
            let vz = (math.random() - 0.5) * 2.0
            let cr = 0.5 + math.random() * 0.5
            let cg = 0.5 + math.random() * 0.5
            let cb = 0.5 + math.random() * 0.5
            add_body(sim, "Star_" + str(ci), mass, 50000.0, vec3(px, py, pz), vec3(vx, vy, vz), [cr, cg, cb])
            ci = ci + 1
        # Central massive body
        add_body(sim, "Central", 1.0, 696340.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), [1.0, 0.9, 0.5])
        compute_gravitational_forces(sim)
        cam_distance = 6.0

    # Camera controls
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
    while si < steps_per_frame:
        step_simulation(sim, sim["dt"])
        si = si + 1

    # Camera position (orbit around center)
    let cam_x = math.cos(cam_yaw) * math.cos(cam_pitch) * cam_distance
    let cam_y = math.sin(cam_pitch) * cam_distance
    let cam_z = math.sin(cam_yaw) * math.cos(cam_pitch) * cam_distance
    let cam_pos = vec3(cam_x + cam_target[0], cam_y + cam_target[1], cam_z + cam_target[2])

    # Lighting
    set_view_position(ls, cam_pos)
    update_light_ubo(ls)

    # Sky color (dark space)
    r["clear_color"] = [0.01, 0.01, 0.02, 1.0]

    # Render
    let frame = begin_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        check_resize(r)
        continue
    let cmd = frame["cmd"]

    let aspect = r["width"] / r["height"]
    let view = mat4_look_at(cam_pos, cam_target, vec3(0.0, 1.0, 0.0))
    let proj = mat4_perspective(radians(60.0), aspect, 0.001, 500.0)
    let vp = mat4_mul(proj, view)

    # Draw bodies
    if lit_mat != nil:
        let bi = 0
        while bi < len(sim["bodies"]):
            let body = sim["bodies"][bi]
            if body["alive"]:
                let pos = body["position"]
                # Scale radius for visibility (log scale for huge range)
                let visual_radius = 0.02 + math.log(body["radius"] + 1.0) * 0.005
                if body["type"] == "star":
                    visual_radius = visual_radius * 3.0

                # Model matrix: translate to position, scale
                let model = mat4_identity()
                # Simple translate via matrix manipulation
                model[12] = pos[0]
                model[13] = pos[1]
                model[14] = pos[2]
                model[0] = visual_radius
                model[5] = visual_radius
                model[10] = visual_radius

                let mvp = mat4_mul(vp, model)
                # Surface color — stars use temperature-based color, planets use defined color
                let albedo = body["color"]
                if body["type"] == "star":
                    if body["temperature"] > 0:
                        albedo = temperature_to_color(body["temperature"])
                    # Boost star brightness significantly
                    albedo = [albedo[0] * 3.0, albedo[1] * 3.0, albedo[2] * 2.5]
                else:
                    # Boost planet colors for visibility
                    albedo = [albedo[0] * 1.5, albedo[1] * 1.5, albedo[2] * 1.5]
                let surface = {"albedo": albedo}

                let mesh = sphere_hi
                if v3_length(v3_sub(pos, cam_pos)) > 10.0:
                    mesh = sphere_lo

                draw_mesh_lit_surface_controlled(cmd, lit_mat, mesh, mvp, model, ls["desc_set"], surface, false)

                # Draw trail
                let ti = 1
                while ti < len(body["trail"]):
                    let tp = body["trail"][ti]
                    let trail_model = mat4_identity()
                    trail_model[12] = tp[0]
                    trail_model[13] = tp[1]
                    trail_model[14] = tp[2]
                    let trail_size = 0.002
                    trail_model[0] = trail_size
                    trail_model[5] = trail_size
                    trail_model[10] = trail_size
                    let trail_mvp = mat4_mul(vp, trail_model)
                    let trail_alpha = ti / len(body["trail"])
                    let trail_surface = {"albedo": [body["color"][0] * trail_alpha, body["color"][1] * trail_alpha, body["color"][2] * trail_alpha]}
                    draw_mesh_lit_surface_controlled(cmd, lit_mat, sphere_lo, trail_mvp, trail_model, ls["desc_set"], trail_surface, false)
                    ti = ti + 8  # Skip trail points for performance
            bi = bi + 1

    # Title with simulation info
    let info = simulation_info(sim)
    let time_str = str(int(info["time_years"] * 100.0) / 100.0)
    let scale_str = str(sim["time_scale"])
    let paused_str = ""
    if sim["paused"]:
        paused_str = " [PAUSED]"
    let title = "N-Body | Bodies: " + str(info["bodies"]) + " | Time: " + time_str + " yr | Speed: " + scale_str + "x" + paused_str
    update_title_fps(r, title)

    end_frame(r, frame)
    frame_count = frame_count + 1
    check_resize(r)

# Shutdown
let final_info = simulation_info(sim)
print ""
print "Simulation ended | " + str(frame_count) + " frames | " + str(final_info["bodies"]) + " bodies | " + str(final_info["collisions"]) + " collisions"
compute_total_energy(sim)
print "Total energy: " + str(sim["total_energy"])
shutdown_renderer(r)
print "✓ Done"
