gc_disable()
# demo_nbody.sage — Realistic N-Body Gravitational Simulation
# Universe Sandbox-style rendering with glow, atmosphere, rings, starfield
#
# Controls:
#   Mouse = Orbit camera | Scroll = Zoom
#   SPACE = Pause/Resume | Up/Down = Time scale
#   1 = Solar System | 2 = Binary Star | 3 = Star cluster
#   ESC = Quit

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, action_held, default_fps_bindings, mouse_delta, scroll_value, bind_action
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from math3d import mat4_identity, mat4_mul, mat4_perspective, mat4_look_at, mat4_translate, mat4_scale, mat4_rotate_y, mat4_rotate_x, radians
from mesh import sphere_mesh, plane_mesh, upload_mesh
from render_system import create_unlit_material, draw_mesh_unlit
from nbody import create_nbody_sim, add_body, add_solar_system, add_binary_star
from nbody import step_simulation, alive_body_count, simulation_info
from nbody import compute_gravitational_forces
from star_renderer import temperature_to_color
from planet_mesh import draw_planet_detailed
from game_loop import create_time_state, update_time

print "=== Realistic N-Body Simulation ==="
print ""

# ============================================================================
# Renderer
# ============================================================================
let r = create_renderer(1280, 720, "N-Body Simulation")
if r == nil:
    raise "Failed to create renderer"
print "GPU: " + gpu.device_name()

let mat = create_unlit_material(r["render_pass"])
if mat == nil:
    raise "Failed to create material"

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
# Camera
# ============================================================================
let cam_distance = 12.0
let cam_yaw = 0.6
let cam_pitch = -0.7

# ============================================================================
# Meshes — multiple LODs for quality at different distances
# ============================================================================
let sphere_ultra = upload_mesh(sphere_mesh(32, 32))  # Stars and close planets
let sphere_hi = upload_mesh(sphere_mesh(16, 16))     # Medium distance
let sphere_lo = upload_mesh(sphere_mesh(8, 8))       # Far/trails/glow

# ============================================================================
# Background starfield — static random stars
# ============================================================================
let starfield = []
let star_i = 0
while star_i < 200:
    let theta = math.random() * 6.2831853
    let phi = math.random() * 3.1415926 - 1.5707963
    let dist = 80.0 + math.random() * 120.0
    let sx = math.cos(phi) * math.cos(theta) * dist
    let sy = math.sin(phi) * dist
    let sz = math.cos(phi) * math.sin(theta) * dist
    let brightness = 0.3 + math.random() * 0.7
    # Star color temperature variation
    let temp_rand = math.random()
    let sr = brightness
    let sg = brightness
    let sb = brightness
    if temp_rand < 0.15:
        # Blue-white hot star
        sr = brightness * 0.7
        sg = brightness * 0.8
        sb = brightness * 1.0
    elif temp_rand > 0.85:
        # Red cool star
        sr = brightness * 1.0
        sg = brightness * 0.6
        sb = brightness * 0.4
    let star_size = 0.02 + math.random() * 0.04
    push(starfield, {"pos": vec3(sx, sy, sz), "color": [sr, sg, sb, 1.0], "size": star_size})
    star_i = star_i + 1

# ============================================================================
# Simulation
# ============================================================================
let sim = create_nbody_sim()
sim["dt"] = 0.0005
sim["trail_enabled"] = true
add_solar_system(sim)
compute_gravitational_forces(sim)

print "✓ " + str(alive_body_count(sim)) + " bodies | " + str(len(starfield)) + " background stars"
print "Controls: Mouse=Orbit | Scroll=Zoom | SPACE=Pause"
print "  Up/Down=Speed | 1=Solar | 2=Binary | 3=Cluster | ESC=Quit"
print ""

# ============================================================================
# Rendering helpers
# ============================================================================

proc draw_sphere(cmd, vp, position, radius, color, mesh):
    let m = mat4_mul(mat4_translate(position[0], position[1], position[2]), mat4_scale(radius, radius, radius))
    let mvp = mat4_mul(vp, m)
    draw_mesh_unlit(cmd, mat, mesh, mvp, color)

# ============================================================================
# Game Loop
# ============================================================================
let ts = create_time_state()
let running = true
let frame_count = 0
let sim_time = 0.0

while running:
    update_time(ts)
    let dt = ts["dt"]
    sim_time = sim_time + dt
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

    # Presets
    if action_just_pressed(inp, "preset_1"):
        sim = create_nbody_sim()
        sim["trail_enabled"] = true
        add_solar_system(sim)
        compute_gravitational_forces(sim)
        cam_distance = 12.0
        cam_pitch = -0.7
    if action_just_pressed(inp, "preset_2"):
        sim = create_nbody_sim()
        sim["trail_enabled"] = true
        add_binary_star(sim, 0.5, 0.7)
        compute_gravitational_forces(sim)
        cam_distance = 3.0
        cam_pitch = -0.5
    if action_just_pressed(inp, "preset_3"):
        sim = create_nbody_sim()
        sim["trail_enabled"] = true
        let ci = 0
        while ci < 40:
            let angle = math.random() * 6.2831853
            let dist = 1.0 + math.random() * 5.0
            let px = math.cos(angle) * dist
            let pz = math.sin(angle) * dist
            let py = (math.random() - 0.5) * 0.5
            let speed = math.sqrt(39.478 / dist) * (0.8 + math.random() * 0.4)
            let vx = 0.0 - math.sin(angle) * speed
            let vz = math.cos(angle) * speed
            let mass = 0.0005 + math.random() * 0.005
            let cr = 0.4 + math.random() * 0.6
            let cg = 0.4 + math.random() * 0.6
            let cb = 0.4 + math.random() * 0.6
            add_body(sim, "S" + str(ci), mass, 30000.0 + math.random() * 70000.0, vec3(px, py, pz), vec3(vx, 0.0, vz), [cr, cg, cb])
            ci = ci + 1
        let central = add_body(sim, "Central", 1.0, 696340.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), [1.0, 0.9, 0.5])
        central["type"] = "star"
        central["temperature"] = 5778.0
        compute_gravitational_forces(sim)
        cam_distance = 10.0
        cam_pitch = -0.8

    # Camera orbit
    let mdelta = mouse_delta(inp)
    cam_yaw = cam_yaw + mdelta[0] * 0.004
    cam_pitch = cam_pitch + mdelta[1] * 0.004
    if cam_pitch > 1.5:
        cam_pitch = 1.5
    if cam_pitch < -1.5:
        cam_pitch = -1.5

    let scroll = scroll_value(inp)
    if scroll[1] != 0.0:
        cam_distance = cam_distance * (1.0 - scroll[1] * 0.08)
        if cam_distance < 0.3:
            cam_distance = 0.3
        if cam_distance > 200.0:
            cam_distance = 200.0

    # Simulation
    let steps = 4
    let si = 0
    while si < steps:
        step_simulation(sim, sim["dt"])
        si = si + 1

    # Camera
    let cam_x = math.cos(cam_yaw) * math.cos(cam_pitch) * cam_distance
    let cam_y = math.sin(cam_pitch) * cam_distance
    let cam_z = math.sin(cam_yaw) * math.cos(cam_pitch) * cam_distance
    let cam_pos = vec3(cam_x, cam_y, cam_z)

    # Deep space background
    r["clear_color"] = [0.002, 0.002, 0.008, 1.0]

    let frame = begin_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        check_resize(r)
        continue
    let cmd = frame["cmd"]

    let aspect = r["width"] / r["height"]
    let view = mat4_look_at(cam_pos, vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0))
    let proj = mat4_perspective(radians(60.0), aspect, 0.01, 500.0)
    let vp = mat4_mul(proj, view)

    # ---- Background starfield ----
    let sfi = 0
    while sfi < len(starfield):
        let sf = starfield[sfi]
        # Twinkling
        let twinkle = 0.8 + math.sin(sim_time * 3.0 + sfi * 1.7) * 0.2
        let sc = [sf["color"][0] * twinkle, sf["color"][1] * twinkle, sf["color"][2] * twinkle, 1.0]
        draw_sphere(cmd, vp, sf["pos"], sf["size"], sc, sphere_lo)
        sfi = sfi + 4  # Draw every 4th star for performance

    # ---- Draw celestial bodies ----
    # Size scale: Sun=0.3, Jupiter=0.15, Earth=0.06, Mercury=0.03
    # These are NOT to real scale (sun would fill screen) — artistic sizes
    let bi = 0
    while bi < len(sim["bodies"]):
        let body = sim["bodies"][bi]
        if not body["alive"]:
            bi = bi + 1
            continue

        let pos = body["position"]
        let dist_to_cam = v3_length(v3_sub(pos, cam_pos))

        # Choose mesh LOD
        let body_mesh = sphere_hi
        if dist_to_cam < cam_distance * 0.3:
            body_mesh = sphere_ultra
        elif dist_to_cam > cam_distance * 2.0:
            body_mesh = sphere_lo

        if body["type"] == "star":
            # ---- STAR with surface detail ----
            let star_r = 0.35
            # Draw with procedural granulation/sunspot banding
            draw_planet_detailed(cmd, mat, vp, pos, star_r, body["name"], body_mesh, 16)

        else:
            # ---- PLANET with procedural surface ----
            let planet_r = 0.03 + (body["radius"] / 70000.0) * 0.12
            if planet_r > 0.15:
                planet_r = 0.15
            if planet_r < 0.025:
                planet_r = 0.025

            # Draw with latitude-banded procedural coloring
            draw_planet_detailed(cmd, mat, vp, pos, planet_r, body["name"], body_mesh, 16)

            # Ring system for Saturn
            if body["rings"]:
                let ring_r = planet_r * 2.2
                let m_t = mat4_translate(pos[0], pos[1], pos[2])
                let m_tilt = mat4_rotate_x(0.4)
                let m_s = mat4_scale(ring_r, ring_r * 0.02, ring_r)
                let ring_model = mat4_mul(mat4_mul(m_t, m_tilt), m_s)
                let ring_mvp = mat4_mul(vp, ring_model)
                draw_mesh_unlit(cmd, mat, sphere_lo, ring_mvp, [0.82, 0.75, 0.55, 1.0])

        # ---- Orbit trail ----
        let trail = body["trail"]
        let trail_len = len(trail)
        if trail_len > 4:
            let ti = 2
            while ti < trail_len:
                let tp = trail[ti]
                let fade = (ti + 1.0) / trail_len
                let trail_size = 0.004 + 0.004 * fade
                let tc = body["color"]
                let trail_color = [tc[0] * fade * 0.5, tc[1] * fade * 0.5, tc[2] * fade * 0.5, 1.0]
                draw_sphere(cmd, vp, vec3(tp[0], tp[1], tp[2]), trail_size, trail_color, sphere_lo)
                ti = ti + 20

        bi = bi + 1

    # Title
    let info = simulation_info(sim)
    let time_str = str(int(info["time_years"] * 100.0) / 100.0)
    let paused = ""
    if sim["paused"]:
        paused = " [PAUSED]"
    update_title_fps(r, "N-Body | " + str(info["bodies"]) + " bodies | " + time_str + " yr | x" + str(sim["time_scale"]) + paused)

    end_frame(r, frame)
    frame_count = frame_count + 1
    check_resize(r)

print ""
print "Frames: " + str(frame_count)
shutdown_renderer(r)
print "✓ Done"
