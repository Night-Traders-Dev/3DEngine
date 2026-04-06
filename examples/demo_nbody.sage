# demo_nbody.sage — N-Body Simulation with HDR bloom + lit rendering
# Stars emit HDR light that blooms, planets receive 3D lit shading

import gpu
import math
from renderer import create_renderer, acquire_frame, begin_swapchain_pass, end_swapchain_pass, submit_frame, shutdown_renderer, check_resize, update_title_fps
from input import create_input, update_input, action_just_pressed, default_fps_bindings, mouse_delta, scroll_value, bind_action
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length
from math3d import mat4_mul, mat4_perspective, mat4_look_at, mat4_translate, mat4_scale, mat4_rotate_x, mat4_rotate_y, mat4_identity, radians
from mesh import sphere_mesh, upload_mesh
from lighting import create_light_scene, point_light, directional_light, add_light, set_ambient, set_fog, set_view_position, init_light_gpu, update_light_ubo
from render_system import create_lit_material, draw_mesh_lit_surface_controlled, create_unlit_material, draw_mesh_unlit
from postprocess import create_postprocess, create_tonemap_pipeline, begin_hdr_pass, end_hdr_pass, execute_bloom, draw_tonemap
from nbody import create_nbody_sim, add_body, add_solar_system, add_binary_star
from nbody import step_simulation, alive_body_count, simulation_info, compute_gravitational_forces
from game_loop import create_time_state, update_time

print "=== N-Body Simulation (HDR + Bloom) ==="

let r = create_renderer(1280, 720, "N-Body Simulation")
if r == nil:
    raise "Failed to create renderer"

# Post-processing (HDR + bloom + tonemapping)
let pp = create_postprocess(1280, 720)
let use_bloom = false  # Start with bloom OFF, press O to enable
if pp["enabled"]:
    create_tonemap_pipeline(pp, r["render_pass"])
    pp["exposure"] = 1.0
    pp["bloom_intensity"] = 0.4
    pp["bloom_threshold"] = 0.9
    pp["bloom_knee"] = 0.3
    pp["gamma"] = 2.2
    pp["contrast"] = 1.05
    pp["saturation"] = 1.08
    pp["warmth"] = 0.02
    pp["vignette"] = 0.12
    print "✓ HDR + Bloom available (press O to toggle, starts OFF)"
else:
    print "⚠ Bloom unavailable, using direct rendering"

# Lighting
let ls = create_light_scene()
init_light_gpu(ls)
add_light(ls, directional_light(0.2, -0.5, 0.3, 1.0, 0.97, 0.90, 1.5))
add_light(ls, directional_light(-0.3, 0.2, -0.4, 0.4, 0.5, 0.7, 0.3))
set_ambient(ls, 0.06, 0.06, 0.10, 0.3)

# Materials for swapchain render pass (always works)
let lit_mat = create_lit_material(r["render_pass"], ls["desc_layout"], ls["desc_set"])
if lit_mat == nil:
    print "WARNING: Lit material failed, falling back to unlit"
let unlit_mat = create_unlit_material(r["render_pass"])

# Materials for HDR render pass (for bloom mode)
let hdr_lit_mat = nil
let hdr_unlit_mat = nil
if use_bloom:
    let hdr_rp = pp["hdr_target"]["render_pass"]
    hdr_lit_mat = create_lit_material(hdr_rp, ls["desc_layout"], ls["desc_set"])
    hdr_unlit_mat = create_unlit_material(hdr_rp)
    if hdr_lit_mat == nil:
        print "WARNING: HDR lit material failed"

let inp = create_input()
default_fps_bindings(inp)
bind_action(inp, "pause", [gpu.KEY_SPACE])
bind_action(inp, "speed_up", [gpu.KEY_UP])
bind_action(inp, "speed_down", [gpu.KEY_DOWN])
bind_action(inp, "preset_1", [gpu.KEY_1])
bind_action(inp, "preset_2", [gpu.KEY_2])
bind_action(inp, "preset_3", [gpu.KEY_3])
bind_action(inp, "toggle_bloom", [gpu.KEY_O])

let cam_distance = 14.0
let cam_yaw = 0.5
let cam_pitch = -0.55

let sphere_hi = upload_mesh(sphere_mesh(20, 20))
let sphere_lo = upload_mesh(sphere_mesh(10, 10))
let sphere_tiny = upload_mesh(sphere_mesh(6, 6))

# Planet visual data
let planet_colors = {
    "Sun": [1.0, 0.95, 0.75], "Mercury": [0.62, 0.58, 0.55],
    "Venus": [0.92, 0.82, 0.52], "Earth": [0.25, 0.45, 0.85],
    "Mars": [0.82, 0.40, 0.20], "Jupiter": [0.80, 0.72, 0.52],
    "Saturn": [0.90, 0.82, 0.60], "Uranus": [0.62, 0.80, 0.88],
    "Neptune": [0.28, 0.42, 0.85]
}
let planet_sizes = {
    "Sun": 0.32, "Mercury": 0.020, "Venus": 0.034, "Earth": 0.036,
    "Mars": 0.026, "Jupiter": 0.14, "Saturn": 0.12, "Uranus": 0.068, "Neptune": 0.064
}
let planet_spin = {
    "Sun": 0.15, "Mercury": 0.02, "Venus": -0.01, "Earth": 1.0,
    "Mars": 0.95, "Jupiter": 2.5, "Saturn": 2.2, "Uranus": -1.4, "Neptune": 1.5
}
let planet_tilt = {
    "Sun": 0.0, "Mercury": 0.0, "Venus": 0.05, "Earth": 0.41,
    "Mars": 0.44, "Jupiter": 0.05, "Saturn": 0.47, "Uranus": 1.71, "Neptune": 0.49
}
let atmosphere_colors = {
    "Earth": [0.3, 0.5, 1.0], "Venus": [0.9, 0.7, 0.3],
    "Jupiter": [0.7, 0.6, 0.4], "Saturn": [0.8, 0.7, 0.5],
    "Uranus": [0.5, 0.7, 0.8], "Neptune": [0.3, 0.4, 0.8]
}

let sim = create_nbody_sim()
sim["dt"] = 0.0005
sim["trail_enabled"] = false
add_solar_system(sim)
compute_gravitational_forces(sim)

let orbit_history = {}
let MAX_ORBIT_PTS = 80

proc record_orbit(name, pos):
    if not dict_has(orbit_history, name):
        orbit_history[name] = []
    let h = orbit_history[name]
    push(h, [pos[0], pos[1], pos[2]])
    if len(h) > MAX_ORBIT_PTS:
        orbit_history[name] = slice(h, len(h) - MAX_ORBIT_PTS, len(h))

# Background star field
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
    let temp = math.random()
    push(bg_stars, [x, y, z,
        bright * (0.8 + temp * 0.2),
        bright * (0.85 + temp * 0.15),
        bright * (0.9 + (1.0 - temp) * 0.1)])
    bsi = bsi + 1

print "✓ " + str(alive_body_count(sim)) + " bodies | Lit planets + HDR stars"
print "Mouse=Orbit | Scroll=Zoom | SPACE=Pause | Up/Down=Speed | 1/2/3=Presets | O=Bloom"

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

    if action_just_pressed(inp, "toggle_bloom"):
        if pp["enabled"]:
            use_bloom = not use_bloom
            if use_bloom:
                print "Bloom: ON"
            else:
                print "Bloom: OFF"

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
        if cam_distance > 120.0:
            cam_distance = 120.0

    step_simulation(sim, sim["dt"])
    step_simulation(sim, sim["dt"])

    if frame_count % 3 == 0:
        let ri = 0
        while ri < len(sim["bodies"]):
            let b = sim["bodies"][ri]
            if b["alive"] and b["type"] != "star":
                record_orbit(b["name"], b["position"])
            ri = ri + 1

    if frame_count % 600 == 0 and frame_count > 0:
        gc_collect()

    let cam_pos = vec3(
        math.cos(cam_yaw) * math.cos(cam_pitch) * cam_distance,
        math.sin(cam_pitch) * cam_distance,
        math.sin(cam_yaw) * math.cos(cam_pitch) * cam_distance)

    set_view_position(ls, cam_pos)
    update_light_ubo(ls)

    r["clear_color"] = [0.002, 0.002, 0.008, 1.0]

    # ====== Frame acquisition ======
    let frame = acquire_frame(r)
    if frame == nil:
        frame_count = frame_count + 1
        check_resize(r)
        continue
    let cmd = frame["cmd"]

    let aspect = r["width"] / r["height"]
    let vp = mat4_mul(
        mat4_perspective(radians(55.0), aspect, 0.005, 500.0),
        mat4_look_at(cam_pos, vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0)))

    # ====== Scene rendering (HDR target if bloom, else swapchain) ======
    if use_bloom:
        begin_hdr_pass(pp, cmd)
    else:
        begin_swapchain_pass(r, frame)

    # Select materials for current render pass
    let cur_lit = lit_mat
    let cur_unlit = unlit_mat
    if use_bloom and hdr_lit_mat != nil:
        cur_lit = hdr_lit_mat
        cur_unlit = hdr_unlit_mat

    # ---- Background stars ----
    let star_batch_start = (frame_count * 20) % len(bg_stars)
    let sti = 0
    while sti < 20:
        let si = (star_batch_start + sti) % len(bg_stars)
        let s = bg_stars[si]
        let sm = mat4_mul(mat4_translate(s[0], s[1], s[2]), mat4_scale(0.08, 0.08, 0.08))
        draw_mesh_unlit(cmd, cur_unlit, sphere_tiny, mat4_mul(vp, sm), [s[3], s[4], s[5], 1.0])
        sti = sti + 1

    # ---- Simulation bodies ----
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

        let mesh = sphere_lo
        if sz > 0.08:
            mesh = sphere_hi
        elif sz < 0.025:
            mesh = sphere_tiny

        let spin_angle = 0.0
        let tilt_angle = 0.0
        if dict_has(planet_spin, name):
            spin_angle = total_time * planet_spin[name]
        if dict_has(planet_tilt, name):
            tilt_angle = planet_tilt[name]
        let model = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]),
                     mat4_mul(mat4_rotate_x(tilt_angle),
                      mat4_mul(mat4_rotate_y(spin_angle), mat4_scale(sz, sz, sz))))
        let mvp = mat4_mul(vp, model)

        if is_star:
            # Stars: HDR bright (values > 1.0 trigger bloom)
            let pulse = 1.0 + math.sin(total_time * 2.0 + pos[0]) * 0.03
            # Core — super bright for bloom
            let hdr_mult = 2.5
            if not use_bloom:
                hdr_mult = 1.0
            draw_mesh_unlit(cmd, cur_unlit, mesh, mvp,
                [color[0] * pulse * hdr_mult, color[1] * pulse * hdr_mult, color[2] * pulse * 0.95 * hdr_mult, 1.0])

            # Inner corona
            let g1 = sz * 1.2
            let g1m = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_scale(g1, g1, g1))
            let corona_mult = 1.5
            if not use_bloom:
                corona_mult = 0.55
            draw_mesh_unlit(cmd, cur_unlit, sphere_lo, mat4_mul(vp, g1m),
                [color[0] * corona_mult * 0.8, color[1] * corona_mult * 0.75, color[2] * corona_mult * 0.5, 1.0])

            # Outer corona
            let g2 = sz * 1.5
            let g2m = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_scale(g2, g2, g2))
            let outer = 0.8 + math.sin(total_time * 1.3) * 0.1
            if not use_bloom:
                outer = 0.22
            draw_mesh_unlit(cmd, cur_unlit, sphere_lo, mat4_mul(vp, g2m),
                [color[0] * outer * 0.7, color[1] * outer * 0.6, color[2] * outer * 0.4, 1.0])
        else:
            # Planets: lit material for 3D shading
            if cur_lit != nil:
                draw_mesh_lit_surface_controlled(cmd, cur_lit, mesh, mvp, model, ls["desc_set"], {"albedo": color}, true)
                # Atmosphere halo
                if dict_has(atmosphere_colors, name):
                    let ac = atmosphere_colors[name]
                    let asz = sz * 1.08
                    let am = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_scale(asz, asz, asz))
                    draw_mesh_unlit(cmd, cur_unlit, sphere_lo, mat4_mul(vp, am), [ac[0] * 0.15, ac[1] * 0.15, ac[2] * 0.15, 1.0])
            else:
                draw_mesh_unlit(cmd, cur_unlit, mesh, mvp, [color[0], color[1], color[2], 1.0])

        # Gas giant banding
        if not is_star and (name == "Jupiter" or name == "Saturn"):
            let bcols_j = [[0.72, 0.62, 0.42], [0.85, 0.75, 0.55], [0.65, 0.55, 0.38]]
            let bcols_s = [[0.82, 0.74, 0.52], [0.92, 0.85, 0.65], [0.78, 0.70, 0.50]]
            let bcols = bcols_j
            if name == "Saturn":
                bcols = bcols_s
            let bandi = 0
            while bandi < 3:
                let by = (bandi - 1.0) * sz * 0.5
                let bm = mat4_mul(mat4_translate(pos[0], pos[1] + by, pos[2]),
                         mat4_mul(mat4_rotate_x(tilt_angle),
                          mat4_mul(mat4_rotate_y(spin_angle),
                           mat4_scale(sz * 1.002, sz * 0.22, sz * 1.002))))
                if cur_lit != nil:
                    draw_mesh_lit_surface_controlled(cmd, cur_lit, sphere_tiny, mat4_mul(vp, bm), bm, ls["desc_set"], {"albedo": bcols[bandi]}, false)
                bandi = bandi + 1

        # Rings
        if body["rings"] or name == "Uranus":
            if name == "Uranus":
                let ur = sz * 1.8
                let urm = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]),
                          mat4_mul(mat4_rotate_x(1.71), mat4_scale(ur, ur * 0.008, ur)))
                draw_mesh_unlit(cmd, cur_unlit, sphere_lo, mat4_mul(vp, urm), [0.5, 0.55, 0.58, 1.0])
            else:
                let rr1 = sz * 1.8
                let rr2 = sz * 2.5
                let rm1 = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]),
                          mat4_mul(mat4_rotate_x(0.47), mat4_scale(rr1, rr1 * 0.012, rr1)))
                let rm2 = mat4_mul(mat4_translate(pos[0], pos[1], pos[2]),
                          mat4_mul(mat4_rotate_x(0.47), mat4_scale(rr2, rr2 * 0.010, rr2)))
                if cur_lit != nil:
                    draw_mesh_lit_surface_controlled(cmd, cur_lit, sphere_lo, mat4_mul(vp, rm1), rm1, ls["desc_set"], {"albedo": [0.88, 0.82, 0.62]}, false)
                    draw_mesh_lit_surface_controlled(cmd, cur_lit, sphere_lo, mat4_mul(vp, rm2), rm2, ls["desc_set"], {"albedo": [0.70, 0.65, 0.50]}, false)
                else:
                    draw_mesh_unlit(cmd, cur_unlit, sphere_lo, mat4_mul(vp, rm1), [0.88, 0.82, 0.62, 1.0])
                    draw_mesh_unlit(cmd, cur_unlit, sphere_lo, mat4_mul(vp, rm2), [0.70, 0.65, 0.50, 1.0])
        bi = bi + 1

    # ---- Orbit trails ----
    let okeys = dict_keys(orbit_history)
    let oi = 0
    while oi < len(okeys):
        let hist = orbit_history[okeys[oi]]
        let hlen = len(hist)
        let tc_base = [0.3, 0.3, 0.3]
        if dict_has(planet_colors, okeys[oi]):
            tc_base = planet_colors[okeys[oi]]
        if hlen > 12:
            let num_dots = 12
            let step = hlen / num_dots
            let di = 0
            while di < num_dots:
                let idx = di * step
                if idx < hlen:
                    let fade = (di + 1.0) / num_dots
                    let brightness = fade * 0.30
                    let dot_sz = 0.003 + fade * 0.002
                    let tp = hist[idx]
                    let tm = mat4_mul(mat4_translate(tp[0], tp[1], tp[2]), mat4_scale(dot_sz, dot_sz, dot_sz))
                    draw_mesh_unlit(cmd, cur_unlit, sphere_tiny, mat4_mul(vp, tm),
                        [tc_base[0] * brightness, tc_base[1] * brightness, tc_base[2] * brightness, 1.0])
                di = di + 1
        oi = oi + 1

    # ====== End scene, apply bloom, composite to screen ======
    if use_bloom:
        end_hdr_pass(cmd)
        execute_bloom(pp, cmd)
        begin_swapchain_pass(r, frame)
        draw_tonemap(pp, cmd)
        end_swapchain_pass(cmd)
    else:
        end_swapchain_pass(cmd)

    submit_frame(r, frame)

    let info = simulation_info(sim)
    let p = ""
    if sim["paused"]:
        p = " PAUSED"
    update_title_fps(r, str(info["bodies"]) + " bodies | " + str(int(info["time_years"] * 100) / 100.0) + "yr | x" + str(sim["time_scale"]) + p)

    frame_count = frame_count + 1
    check_resize(r)

shutdown_renderer(r)
print "Done"
