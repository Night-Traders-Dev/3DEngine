gc_disable()
# demo_nbody.sage — N-Body Gravitational Simulation
# Performance-optimized: pre-computed colors, minimal draw calls

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, default_fps_bindings, mouse_delta, scroll_value, bind_action
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from math3d import mat4_mul, mat4_perspective, mat4_look_at, mat4_translate, mat4_scale, mat4_rotate_x, radians
from mesh import sphere_mesh, upload_mesh
from render_system import create_unlit_material, draw_mesh_unlit
from nbody import create_nbody_sim, add_body, add_solar_system, add_binary_star
from nbody import step_simulation, alive_body_count, simulation_info, compute_gravitational_forces
from game_loop import create_time_state, update_time

print "=== N-Body Simulation ==="

let r = create_renderer(1280, 720, "N-Body Simulation")
if r == nil:
    raise "Failed to create renderer"

let mat = create_unlit_material(r["render_pass"])
if mat == nil:
    raise "Failed to create material"

let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "pause", [gpu.KEY_SPACE])
bind_action(inp, "speed_up", [gpu.KEY_UP])
bind_action(inp, "speed_down", [gpu.KEY_DOWN])
bind_action(inp, "preset_1", [gpu.KEY_1])
bind_action(inp, "preset_2", [gpu.KEY_2])
bind_action(inp, "preset_3", [gpu.KEY_3])

let cam_distance = 12.0
let cam_yaw = 0.6
let cam_pitch = -0.7

# Single sphere mesh — reused for everything
let sphere = upload_mesh(sphere_mesh(12, 12))

# Pre-computed planet colors (computed ONCE, not per frame)
let planet_colors = {
    "Sun":     [1.0, 0.92, 0.65, 1.0],
    "Mercury": [0.55, 0.55, 0.55, 1.0],
    "Venus":   [0.85, 0.75, 0.50, 1.0],
    "Earth":   [0.25, 0.45, 0.80, 1.0],
    "Mars":    [0.78, 0.35, 0.18, 1.0],
    "Jupiter": [0.75, 0.65, 0.50, 1.0],
    "Saturn":  [0.85, 0.78, 0.55, 1.0],
    "Uranus":  [0.55, 0.75, 0.82, 1.0],
    "Neptune": [0.22, 0.35, 0.80, 1.0],
    "Star A":  [1.0, 0.92, 0.65, 1.0],
    "Star B":  [0.65, 0.78, 1.0, 1.0],
    "Central": [1.0, 0.90, 0.60, 1.0]
}

# Planet sizes (pre-computed, not per frame)
let planet_sizes = {
    "Sun": 0.30, "Mercury": 0.025, "Venus": 0.035, "Earth": 0.04,
    "Mars": 0.03, "Jupiter": 0.14, "Saturn": 0.12, "Uranus": 0.07,
    "Neptune": 0.065, "Star A": 0.25, "Star B": 0.20, "Central": 0.30
}

# Background stars — only 40, pre-computed positions
let starfield = []
let star_i = 0
while star_i < 40:
    let theta = math.random() * 6.2831853
    let phi = math.random() * 3.1415926 - 1.5707963
    let dist = 90.0 + math.random() * 80.0
    let sx = math.cos(phi) * math.cos(theta) * dist
    let sy = math.sin(phi) * dist
    let sz = math.cos(phi) * math.sin(theta) * dist
    let b = 0.4 + math.random() * 0.6
    push(starfield, [sx, sy, sz, b])
    star_i = star_i + 1

proc draw_body(cmd, vp, pos, radius, color):
    let m = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_scale(radius, radius, radius))
    draw_mesh_unlit(cmd, mat, sphere, mat4_mul(vp, m), color)

# Simulation
let sim = create_nbody_sim()
sim["dt"] = 0.0005
sim["trail_enabled"] = true
add_solar_system(sim)
compute_gravitational_forces(sim)

print "✓ " + str(alive_body_count(sim)) + " bodies"
print "Mouse=Orbit | Scroll=Zoom | SPACE=Pause | Up/Down=Speed | 1/2/3=Presets"

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
        if sim["time_scale"] > 128.0:
            sim["time_scale"] = 128.0
    if action_just_pressed(inp, "speed_down"):
        sim["time_scale"] = sim["time_scale"] * 0.5
        if sim["time_scale"] < 0.125:
            sim["time_scale"] = 0.125

    if action_just_pressed(inp, "preset_1"):
        sim = create_nbody_sim()
        sim["trail_enabled"] = true
        add_solar_system(sim)
        compute_gravitational_forces(sim)
        cam_distance = 12.0
    if action_just_pressed(inp, "preset_2"):
        sim = create_nbody_sim()
        sim["trail_enabled"] = true
        add_binary_star(sim, 0.5, 0.7)
        compute_gravitational_forces(sim)
        cam_distance = 3.0
    if action_just_pressed(inp, "preset_3"):
        sim = create_nbody_sim()
        sim["trail_enabled"] = true
        let ci = 0
        while ci < 20:
            let angle = math.random() * 6.2831853
            let dist = 1.0 + math.random() * 4.0
            let speed = math.sqrt(39.478 / dist) * (0.8 + math.random() * 0.4)
            add_body(sim, "S" + str(ci), 0.002 + math.random() * 0.005, 40000.0,
                vec3(math.cos(angle) * dist, (math.random() - 0.5) * 0.3, math.sin(angle) * dist),
                vec3(0.0 - math.sin(angle) * speed, 0.0, math.cos(angle) * speed),
                [0.5 + math.random() * 0.5, 0.5 + math.random() * 0.5, 0.5 + math.random() * 0.5])
            ci = ci + 1
        let c = add_body(sim, "Central", 1.0, 696340.0, vec3(0,0,0), vec3(0,0,0), [1.0, 0.9, 0.5])
        c["type"] = "star"
        c["temperature"] = 5778.0
        compute_gravitational_forces(sim)
        cam_distance = 8.0

    # Camera
    let md = mouse_delta(inp)
    cam_yaw = cam_yaw + md[0] * 0.004
    cam_pitch = cam_pitch + md[1] * 0.004
    if cam_pitch > 1.5:
        cam_pitch = 1.5
    if cam_pitch < -1.5:
        cam_pitch = -1.5
    let sc = scroll_value(inp)
    if sc[1] != 0.0:
        cam_distance = cam_distance * (1.0 - sc[1] * 0.08)
        if cam_distance < 0.5:
            cam_distance = 0.5
        if cam_distance > 100.0:
            cam_distance = 100.0

    # Physics — only 2 steps per frame (was 4)
    step_simulation(sim, sim["dt"])
    step_simulation(sim, sim["dt"])

    let cam_pos = vec3(
        math.cos(cam_yaw) * math.cos(cam_pitch) * cam_distance,
        math.sin(cam_pitch) * cam_distance,
        math.sin(cam_yaw) * math.cos(cam_pitch) * cam_distance
    )

    r["clear_color"] = [0.003, 0.003, 0.012, 1.0]

    let frame = begin_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        check_resize(r)
        continue
    let cmd = frame["cmd"]

    let vp = mat4_mul(
        mat4_perspective(radians(60.0), r["width"] / r["height"], 0.01, 300.0),
        mat4_look_at(cam_pos, vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0))
    )

    # Background stars — draw only 10 per frame (cycle through)
    let star_offset = frame_count % 4
    let sfi = star_offset
    while sfi < len(starfield):
        let s = starfield[sfi]
        draw_body(cmd, vp, vec3(s[0], s[1], s[2]), 0.03, [s[3], s[3], s[3], 1.0])
        sfi = sfi + 4

    # Bodies
    let bi = 0
    while bi < len(sim["bodies"]):
        let body = sim["bodies"][bi]
        if not body["alive"]:
            bi = bi + 1
            continue

        let pos = body["position"]
        let name = body["name"]

        # Color — lookup pre-computed, fallback to body color
        let color = [body["color"][0], body["color"][1], body["color"][2], 1.0]
        if dict_has(planet_colors, name):
            color = planet_colors[name]

        # Size — lookup pre-computed, fallback to small
        let sz = 0.04
        if dict_has(planet_sizes, name):
            sz = planet_sizes[name]
        # Generic bodies in cluster mode
        if not dict_has(planet_sizes, name):
            sz = 0.03 + math.log(body["radius"] + 1.0) * 0.005
            if body["type"] == "star":
                sz = sz * 3.0

        draw_body(cmd, vp, pos, sz, color)

        # Saturn ring
        if body["rings"]:
            let ring_r = sz * 2.2
            let rm = mat4_mul(mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_rotate_x(0.4)), mat4_scale(ring_r, ring_r * 0.02, ring_r))
            draw_mesh_unlit(cmd, mat, sphere, mat4_mul(vp, rm), [0.82, 0.75, 0.55, 1.0])

        # Trail — only every 30th point, max 8 dots per body
        let trail = body["trail"]
        let tlen = len(trail)
        if tlen > 10:
            let drawn = 0
            let ti = tlen - 1
            while ti > 0 and drawn < 8:
                let tp = trail[ti]
                let fade = 0.3 + 0.4 * (ti / tlen)
                draw_body(cmd, vp, vec3(tp[0], tp[1], tp[2]), 0.004, [color[0] * fade, color[1] * fade, color[2] * fade, 1.0])
                drawn = drawn + 1
                ti = ti - 30

        bi = bi + 1

    # Title
    let info = simulation_info(sim)
    let paused = ""
    if sim["paused"]:
        paused = " [PAUSED]"
    update_title_fps(r, "N-Body | " + str(info["bodies"]) + " | " + str(int(info["time_years"] * 100) / 100.0) + "yr | x" + str(sim["time_scale"]) + paused)

    end_frame(r, frame)
    frame_count = frame_count + 1
    check_resize(r)

shutdown_renderer(r)
print "Done: " + str(frame_count) + " frames"
