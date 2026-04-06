# demo_nbody.sage — N-Body Simulation with realistic LIT rendering
# Stars glow (unlit + bright), planets receive directional + point lighting

import gpu
import math
from renderer import create_renderer, begin_frame, end_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, default_fps_bindings, mouse_delta, scroll_value, bind_action
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from math3d import mat4_mul, mat4_perspective, mat4_look_at, mat4_translate, mat4_scale, mat4_rotate_x, mat4_rotate_y, mat4_identity, radians
from mesh import sphere_mesh, upload_mesh
from lighting import create_light_scene, point_light, directional_light, add_light, set_ambient, set_fog, set_view_position, init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit_surface_controlled, create_unlit_material, draw_mesh_unlit
from nbody import create_nbody_sim, add_body, add_solar_system, add_binary_star
from nbody import step_simulation, alive_body_count, simulation_info, compute_gravitational_forces
from game_loop import create_time_state, update_time

print "=== N-Body Simulation (Realistic Rendering) ==="

let r = create_renderer(1280, 720, "N-Body Simulation")
if r == nil:
    raise "Failed to create renderer"

# Lighting — directional sun from above + warm ambient
let ls = create_light_scene()
init_light_gpu(ls)
# Main directional light (simulates distant sunlight direction for non-star bodies)
add_light(ls, directional_light(0.2, -0.5, 0.3, 1.0, 0.97, 0.90, 1.5))
# Secondary fill from opposite side (softer, bluer — simulates space scatter)
add_light(ls, directional_light(-0.3, 0.2, -0.4, 0.4, 0.5, 0.7, 0.3))
set_ambient(ls, 0.06, 0.06, 0.10, 0.3)

# Lit material for planets (proper 3D shading with specular highlights)
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])
if lit_mat == nil:
    print "WARNING: Lit material failed, falling back to unlit"
let unlit_mat = create_unlit_material(r["render_pass"])

let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "pause", [gpu.KEY_SPACE])
bind_action(inp, "speed_up", [gpu.KEY_UP])
bind_action(inp, "speed_down", [gpu.KEY_DOWN])
bind_action(inp, "preset_1", [gpu.KEY_1])
bind_action(inp, "preset_2", [gpu.KEY_2])
bind_action(inp, "preset_3", [gpu.KEY_3])

let cam_distance = 14.0
let cam_yaw = 0.5
let cam_pitch = -0.55

# Multiple sphere LODs for different object sizes
let sphere_hi = upload_mesh(sphere_mesh(20, 20))
let sphere_lo = upload_mesh(sphere_mesh(10, 10))
let sphere_tiny = upload_mesh(sphere_mesh(6, 6))

# Realistic planet colors (slightly brighter for lit rendering — light will modulate)
let planet_colors = {
    "Sun": [1.0, 0.95, 0.75],
    "Mercury": [0.62, 0.58, 0.55],
    "Venus": [0.92, 0.82, 0.52],
    "Earth": [0.25, 0.45, 0.85],
    "Mars": [0.82, 0.40, 0.20],
    "Jupiter": [0.80, 0.72, 0.52],
    "Saturn": [0.90, 0.82, 0.60],
    "Uranus": [0.62, 0.80, 0.88],
    "Neptune": [0.28, 0.42, 0.85]
}

# Rendered sizes (visual — not to physical scale, but ratio-preserving)
let planet_sizes = {
    "Sun": 0.32,
    "Mercury": 0.020,
    "Venus": 0.034,
    "Earth": 0.036,
    "Mars": 0.026,
    "Jupiter": 0.14,
    "Saturn": 0.12,
    "Uranus": 0.068,
    "Neptune": 0.064
}

# Atmosphere glow colors (faint halo around gas giants / Venus / Earth)
let atmosphere_colors = {
    "Earth": [0.3, 0.5, 1.0, 0.12],
    "Venus": [0.9, 0.7, 0.3, 0.08],
    "Jupiter": [0.7, 0.6, 0.4, 0.06],
    "Saturn": [0.8, 0.7, 0.5, 0.05],
    "Uranus": [0.5, 0.7, 0.8, 0.07],
    "Neptune": [0.3, 0.4, 0.8, 0.08]
}

let sim = create_nbody_sim()
sim["dt"] = 0.0005
sim["trail_enabled"] = false
add_solar_system(sim)
compute_gravitational_forces(sim)

# Orbit trail history
let orbit_history = {}
let MAX_ORBIT_PTS = 80

proc record_orbit(name, pos):
    if not dict_has(orbit_history, name):
        orbit_history[name] = []
    let h = orbit_history[name]
    push(h, [pos[0], pos[1], pos[2]])
    if len(h) > MAX_ORBIT_PTS:
        orbit_history[name] = slice(h, len(h) - MAX_ORBIT_PTS, len(h))

# Background star field (static positions, pre-computed)
let bg_stars = []
let bsi = 0
while bsi < 80:
    let theta = math.random() * 6.2831853
    let phi = math.acos(2.0 * math.random() - 1.0)
    let dist = 60.0 + math.random() * 40.0
    let x = math.sin(phi) * math.cos(theta) * dist
    let y = math.sin(phi) * math.sin(theta) * dist
    let z = math.cos(phi) * dist
    let bright = 0.4 + math.random() * 0.6
    # Slight color variation — some stars are blue-white, some yellow-white
    let temp = math.random()
    let sr = bright * (0.8 + temp * 0.2)
    let sg = bright * (0.85 + temp * 0.15)
    let sb = bright * (0.9 + (1.0 - temp) * 0.1)
    push(bg_stars, [x, y, z, sr, sg, sb])
    bsi = bsi + 1

print "✓ " + str(alive_body_count(sim)) + " bodies | Lit planets + Star glow"
print "Mouse=Orbit | Scroll=Zoom | SPACE=Pause | Up/Down=Speed | 1/2/3=Presets"

let ts = create_time_state()
let running = true
let frame_count = 0
let total_time = 0.0

while running:
    update_time(ts)
    let dt = ts["dt"]
    total_time = total_time + dt
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
        cam_distance = 14.0
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
            add_body(sim, "S" + str(ci), 0.003, 40000.0,
                vec3(math.cos(angle) * dist, 0.0, math.sin(angle) * dist),
                vec3(0.0 - math.sin(angle) * speed, 0.0, math.cos(angle) * speed),
                [0.5 + math.random() * 0.5, 0.5 + math.random() * 0.5, 0.5 + math.random() * 0.5])
            ci = ci + 1
        let c = add_body(sim, "Central", 1.0, 696340.0, vec3(0,0,0), vec3(0,0,0), [1.0, 0.9, 0.5])
        c["type"] = "star"
        compute_gravitational_forces(sim)
        orbit_history = {}
        cam_distance = 8.0

    # Camera orbit
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
        if cam_distance > 120.0:
            cam_distance = 120.0

    # Physics — two sub-steps per frame for stability
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

    # GC every 10 seconds
    if frame_count % 600 == 0 and frame_count > 0:
        gc_collect()

    let cam_pos = vec3(
        math.cos(cam_yaw) * math.cos(cam_pitch) * cam_distance,
        math.sin(cam_pitch) * cam_distance,
        math.sin(cam_yaw) * math.cos(cam_pitch) * cam_distance)

    set_view_position(ls, cam_pos)
    update_light_ubo(ls)

    r["clear_color"] = [0.002, 0.002, 0.008, 1.0]

    let frame = begin_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        check_resize(r)
        continue
    let cmd = frame["cmd"]

    let aspect = r["width"] / r["height"]
    let vp = mat4_mul(
        mat4_perspective(radians(55.0), aspect, 0.005, 500.0),
        mat4_look_at(cam_pos, vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0)))

    # ---- Background stars (tiny unlit dots) ----
    # Draw 20 per frame in rotation to spread cost
    let star_batch_start = (frame_count * 20) % len(bg_stars)
    let star_batch_count = 20
    if star_batch_count > len(bg_stars):
        star_batch_count = len(bg_stars)
    let sti = 0
    while sti < star_batch_count:
        let si = (star_batch_start + sti) % len(bg_stars)
        let s = bg_stars[si]
        let sm = mat4_mul(mat4_translate(s[0], s[1], s[2]), mat4_scale(0.08, 0.08, 0.08))
        draw_mesh_unlit(cmd, unlit_mat, sphere_tiny, mat4_mul(vp, sm), [s[3], s[4], s[5], 1.0])
        sti = sti + 1

    # ---- Draw simulation bodies ----
    let bi = 0
    while bi < len(sim["bodies"]):
        let body = sim["bodies"][bi]
        if not body["alive"]:
            bi = bi + 1
            continue

        let pos = body["position"]
        let name = body["name"]
        let color = body["color"]
        if dict_has(planet_colors, name):
            color = planet_colors[name]

        let sz = 0.035
        if dict_has(planet_sizes, name):
            sz = planet_sizes[name]
        elif body["type"] == "star":
            sz = 0.28

        let is_star = body["type"] == "star"

        # Choose mesh LOD based on size
        let mesh = sphere_lo
        if sz > 0.08:
            mesh = sphere_hi
        elif sz < 0.025:
            mesh = sphere_tiny

        let model = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_scale(sz, sz, sz))
        let mvp = mat4_mul(vp, model)

        if is_star:
            # Stars: draw as bright unlit (self-illuminating)
            # Pulsing brightness for realism
            let pulse = 1.0 + math.sin(total_time * 2.0 + pos[0]) * 0.03
            let star_color = [color[0] * pulse, color[1] * pulse, color[2] * pulse * 0.95, 1.0]
            draw_mesh_unlit(cmd, unlit_mat, mesh, mvp, star_color)

            # Star glow halo (slightly larger, dimmer sphere)
            let glow_sz = sz * 1.35
            let glow_model = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_scale(glow_sz, glow_sz, glow_sz))
            let glow_mvp = mat4_mul(vp, glow_model)
            let glow_bright = 0.35 + math.sin(total_time * 1.5) * 0.05
            draw_mesh_unlit(cmd, unlit_mat, sphere_lo, glow_mvp, [color[0] * glow_bright, color[1] * glow_bright, color[2] * glow_bright * 0.8, 1.0])
        else:
            # Planets: draw with lit material for proper 3D shading
            if lit_mat != nil:
                let surface = {"albedo": color}
                draw_mesh_lit_surface_controlled(cmd, lit_mat, mesh, mvp, model, ls["desc_set"], surface, true)

                # Atmosphere glow for planets that have one
                if dict_has(atmosphere_colors, name):
                    let atmo = atmosphere_colors[name]
                    let atmo_sz = sz * 1.08
                    let atmo_model = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_scale(atmo_sz, atmo_sz, atmo_sz))
                    let atmo_mvp = mat4_mul(vp, atmo_model)
                    # Draw atmosphere as a slightly tinted unlit shell
                    draw_mesh_unlit(cmd, unlit_mat, sphere_lo, atmo_mvp, [atmo[0] * 0.15, atmo[1] * 0.15, atmo[2] * 0.15, 1.0])
            else:
                draw_mesh_unlit(cmd, unlit_mat, mesh, mvp, [color[0], color[1], color[2], 1.0])

        # Saturn ring
        if body["rings"]:
            let rr = sz * 2.4
            let rm = mat4_mul(mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_rotate_x(0.45)), mat4_scale(rr, rr * 0.015, rr))
            let rmvp = mat4_mul(vp, rm)
            if lit_mat != nil:
                draw_mesh_lit_surface_controlled(cmd, lit_mat, sphere_lo, rmvp, rm, ls["desc_set"], {"albedo": [0.85, 0.78, 0.58]}, false)
            else:
                draw_mesh_unlit(cmd, unlit_mat, sphere_lo, rmvp, [0.85, 0.78, 0.58, 1.0])

        bi = bi + 1

    # ---- Orbit trails (unlit, fading dots) ----
    let okeys = dict_keys(orbit_history)
    let oi = 0
    while oi < len(okeys):
        let hist = orbit_history[okeys[oi]]
        let hlen = len(hist)
        # Get trail color from planet color
        let tc_base = [0.3, 0.3, 0.3]
        if dict_has(planet_colors, okeys[oi]):
            tc_base = planet_colors[okeys[oi]]
        if hlen > 8:
            let num_dots = 8
            let step = hlen / num_dots
            let di = 0
            while di < num_dots:
                let idx = di * step
                if idx < hlen:
                    # Fade: older dots are dimmer
                    let fade = (di + 1.0) / num_dots
                    let brightness = fade * 0.25
                    let tp = hist[idx]
                    let tm = mat4_mul(mat4_translate(tp[0], tp[1], tp[2]), mat4_scale(0.004, 0.004, 0.004))
                    draw_mesh_unlit(cmd, unlit_mat, sphere_tiny, mat4_mul(vp, tm),
                        [tc_base[0] * brightness, tc_base[1] * brightness, tc_base[2] * brightness, 1.0])
                di = di + 1
        oi = oi + 1

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
