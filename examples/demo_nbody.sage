# demo_nbody.sage — N-Body Gravitational Simulation
# Optimized: fixed memory, capped trails, periodic GC

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

let sphere = upload_mesh(sphere_mesh(14, 14))

# Pre-computed colors — realistic planet colors
let planet_colors = {
    "Sun":     [1.0, 0.93, 0.65, 1.0],
    "Mercury": [0.60, 0.56, 0.52, 1.0],
    "Venus":   [0.90, 0.78, 0.48, 1.0],
    "Earth":   [0.22, 0.42, 0.82, 1.0],
    "Mars":    [0.80, 0.38, 0.18, 1.0],
    "Jupiter": [0.78, 0.68, 0.48, 1.0],
    "Saturn":  [0.88, 0.80, 0.58, 1.0],
    "Uranus":  [0.58, 0.78, 0.85, 1.0],
    "Neptune": [0.24, 0.38, 0.82, 1.0]
}

let planet_sizes = {
    "Sun": 0.28, "Mercury": 0.022, "Venus": 0.032, "Earth": 0.035,
    "Mars": 0.028, "Jupiter": 0.13, "Saturn": 0.11, "Uranus": 0.065,
    "Neptune": 0.060
}

# Simulation — trails DISABLED to prevent RAM leak
let sim = create_nbody_sim()
sim["dt"] = 0.0005
sim["trail_enabled"] = false   # <-- FIX: no trail accumulation
add_solar_system(sim)
compute_gravitational_forces(sim)

# Instead of per-body trails, keep a small fixed-size orbit history per body
let orbit_history = {}
let MAX_ORBIT_POINTS = 60

proc record_orbit(name, pos):
    if not dict_has(orbit_history, name):
        orbit_history[name] = []
    let hist = orbit_history[name]
    push(hist, [pos[0], pos[1], pos[2]])
    # Fixed cap — delete oldest when full
    if len(hist) > MAX_ORBIT_POINTS:
        orbit_history[name] = slice(hist, len(hist) - MAX_ORBIT_POINTS, len(hist))

print "✓ " + str(alive_body_count(sim)) + " bodies"
print "Mouse=Orbit | Scroll=Zoom | SPACE=Pause | Up/Down=Speed"

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
        if sim["time_scale"] > 64.0:
            sim["time_scale"] = 64.0
    if action_just_pressed(inp, "speed_down"):
        sim["time_scale"] = sim["time_scale"] * 0.5
        if sim["time_scale"] < 0.125:
            sim["time_scale"] = 0.125

    if action_just_pressed(inp, "preset_1"):
        sim = create_nbody_sim()
        sim["trail_enabled"] = false
        add_solar_system(sim)
        compute_gravitational_forces(sim)
        orbit_history = {}
        cam_distance = 12.0
    if action_just_pressed(inp, "preset_2"):
        sim = create_nbody_sim()
        sim["trail_enabled"] = false
        add_binary_star(sim, 0.5, 0.7)
        compute_gravitational_forces(sim)
        orbit_history = {}
        cam_distance = 3.0
    if action_just_pressed(inp, "preset_3"):
        sim = create_nbody_sim()
        sim["trail_enabled"] = false
        let ci = 0
        while ci < 15:
            let angle = math.random() * 6.2831853
            let dist = 1.0 + math.random() * 4.0
            let speed = math.sqrt(39.478 / dist) * (0.8 + math.random() * 0.4)
            add_body(sim, "S" + str(ci), 0.003 + math.random() * 0.005, 40000.0,
                vec3(math.cos(angle) * dist, 0.0, math.sin(angle) * dist),
                vec3(0.0 - math.sin(angle) * speed, 0.0, math.cos(angle) * speed),
                [0.5 + math.random() * 0.5, 0.5 + math.random() * 0.5, 0.5 + math.random() * 0.5])
            ci = ci + 1
        let c = add_body(sim, "Central", 1.0, 696340.0, vec3(0,0,0), vec3(0,0,0), [1.0, 0.9, 0.5])
        c["type"] = "star"
        compute_gravitational_forces(sim)
        orbit_history = {}
        cam_distance = 8.0

    # Camera
    let md = mouse_delta(inp)
    cam_yaw = cam_yaw + md[0] * 0.004
    cam_pitch = cam_pitch + md[1] * 0.004
    if cam_pitch > 1.4:
        cam_pitch = 1.4
    if cam_pitch < -1.4:
        cam_pitch = -1.4
    let sc = scroll_value(inp)
    if sc[1] != 0.0:
        cam_distance = cam_distance * (1.0 - sc[1] * 0.08)
        if cam_distance < 0.5:
            cam_distance = 0.5
        if cam_distance > 80.0:
            cam_distance = 80.0

    # Physics — 2 steps
    step_simulation(sim, sim["dt"])
    step_simulation(sim, sim["dt"])

    # Record orbits every 3rd frame
    if frame_count % 3 == 0:
        let ri = 0
        while ri < len(sim["bodies"]):
            let b = sim["bodies"][ri]
            if b["alive"] and b["type"] != "star":
                record_orbit(b["name"], b["position"])
            ri = ri + 1

    # Periodic GC to prevent RAM growth (every 600 frames ~10 sec)
    if frame_count % 600 == 0 and frame_count > 0:
        gc_collect()

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

    # ---- Draw bodies ----
    let bi = 0
    while bi < len(sim["bodies"]):
        let body = sim["bodies"][bi]
        if not body["alive"]:
            bi = bi + 1
            continue

        let pos = body["position"]
        let name = body["name"]

        # Color
        let color = [body["color"][0], body["color"][1], body["color"][2], 1.0]
        if dict_has(planet_colors, name):
            color = planet_colors[name]

        # Size
        let sz = 0.035
        if dict_has(planet_sizes, name):
            sz = planet_sizes[name]
        elif body["type"] == "star":
            sz = 0.25

        # Day/night shading for planets (sun-facing side brighter)
        if body["type"] != "star":
            let to_sun = v3_normalize(v3_scale(pos, -1.0))
            let to_cam = v3_normalize(v3_sub(cam_pos, pos))
            let light = to_sun[0] * to_cam[0] + to_sun[1] * to_cam[1] + to_sun[2] * to_cam[2]
            let shade = 0.4 + 0.6 * ((light + 1.0) * 0.5)
            color = [color[0] * shade, color[1] * shade, color[2] * shade, 1.0]

        # Draw body
        let m = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_scale(sz, sz, sz))
        draw_mesh_unlit(cmd, mat, sphere, mat4_mul(vp, m), color)

        # Saturn ring
        if body["rings"]:
            let rr = sz * 2.2
            let rm = mat4_mul(mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_rotate_x(0.4)), mat4_scale(rr, rr * 0.02, rr))
            draw_mesh_unlit(cmd, mat, sphere, mat4_mul(vp, rm), [0.82, 0.75, 0.55, 1.0])

        bi = bi + 1

    # ---- Draw orbit trails (fixed-size history, max 5 dots per body) ----
    let okeys = dict_keys(orbit_history)
    let oi = 0
    while oi < len(okeys):
        let oname = okeys[oi]
        let hist = orbit_history[oname]
        let hlen = len(hist)
        # Color from planet
        let tc = [0.3, 0.3, 0.3, 1.0]
        if dict_has(planet_colors, oname):
            let pc = planet_colors[oname]
            tc = [pc[0] * 0.4, pc[1] * 0.4, pc[2] * 0.4, 1.0]
        # Draw max 5 evenly spaced dots
        if hlen > 5:
            let step = hlen / 5
            let di = 0
            while di < 5:
                let idx = di * step
                if idx < hlen:
                    let tp = hist[idx]
                    let tm = mat4_mul(mat4_translate(tp[0], tp[1], tp[2]), mat4_scale(0.003, 0.003, 0.003))
                    draw_mesh_unlit(cmd, mat, sphere, mat4_mul(vp, tm), tc)
                di = di + 1
        oi = oi + 1

    # Title
    let info = simulation_info(sim)
    let p = ""
    if sim["paused"]:
        p = " PAUSED"
    update_title_fps(r, str(info["bodies"]) + " bodies | " + str(int(info["time_years"] * 100) / 100.0) + "yr | x" + str(sim["time_scale"]) + p)

    end_frame(r, frame)
    frame_count = frame_count + 1
    check_resize(r)

shutdown_renderer(r)
print "Done"
