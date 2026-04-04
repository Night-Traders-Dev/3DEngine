gc_disable()
# -----------------------------------------
# particle_renderer.sage - GPU particle rendering for Sage Engine
# Renders particles as billboarded quads using the UI pipeline
# Particles are drawn in 3D by projecting positions to screen space
# -----------------------------------------

import gpu
import math
from math3d import vec3, v3_sub, v3_add, v3_scale, v3_normalize, v3_cross
from math3d import mat4_mul_vec4, vec4
from particles import collect_particles

# ============================================================================
# Particle Renderer (reuses UI pipeline for colored quads)
# ============================================================================
proc create_particle_renderer(ui_renderer):
    let pr = {}
    pr["ui_renderer"] = ui_renderer
    pr["max_particles"] = 512
    return pr

# ============================================================================
# Project 3D position to screen coordinates
# ============================================================================
proc project_to_screen(pos, vp_matrix, screen_w, screen_h):
    let clip = mat4_mul_vec4(vp_matrix, vec4(pos[0], pos[1], pos[2], 1.0))
    if clip[3] <= 0.001:
        return nil
    let ndc_x = clip[0] / clip[3]
    let ndc_y = clip[1] / clip[3]
    let sx = (ndc_x + 1.0) * 0.5 * screen_w
    let sy = (1.0 - ndc_y) * 0.5 * screen_h
    let depth = clip[2] / clip[3]
    return [sx, sy, depth]

# ============================================================================
# Render particles from emitter as screen-space quads
# ============================================================================
proc render_particles(pr, cmd, emitter, vp_matrix, screen_w, screen_h):
    let ur = pr["ui_renderer"]
    if ur == nil or ur["initialized"] == false:
        return nil
    let alive = collect_particles(emitter)
    if len(alive) == 0:
        return nil
    # Build quad data
    let verts = []
    let vert_count = 0
    let max_v = pr["max_particles"] * 6
    let i = 0
    while i < len(alive) and vert_count < max_v:
        let p = alive[i]
        let scr = project_to_screen(p["position"], vp_matrix, screen_w, screen_h)
        if scr != nil:
            let sx = scr[0]
            let sy = scr[1]
            let depth = scr[2]
            # Skip behind camera or too far
            if depth > 0.0 and depth < 1.0:
                # Size scales with depth (perspective)
                let pixel_size = p["size"] * screen_h * 0.05 / (depth + 0.1)
                if pixel_size < 0.5:
                    pixel_size = 0.5
                if pixel_size > 200.0:
                    pixel_size = 200.0
                let half = pixel_size / 2.0
                let x0 = sx - half
                let y0 = sy - half
                let x1 = sx + half
                let y1 = sy + half
                let cr = p["color"][0]
                let cg = p["color"][1]
                let cb = p["color"][2]
                let ca = p["color"][3]
                # Tri 1
                push(verts, x0)
                push(verts, y0)
                push(verts, 0.0)
                push(verts, 0.0)
                push(verts, cr)
                push(verts, cg)
                push(verts, cb)
                push(verts, ca)
                push(verts, x1)
                push(verts, y0)
                push(verts, 1.0)
                push(verts, 0.0)
                push(verts, cr)
                push(verts, cg)
                push(verts, cb)
                push(verts, ca)
                push(verts, x1)
                push(verts, y1)
                push(verts, 1.0)
                push(verts, 1.0)
                push(verts, cr)
                push(verts, cg)
                push(verts, cb)
                push(verts, ca)
                # Tri 2
                push(verts, x0)
                push(verts, y0)
                push(verts, 0.0)
                push(verts, 0.0)
                push(verts, cr)
                push(verts, cg)
                push(verts, cb)
                push(verts, ca)
                push(verts, x1)
                push(verts, y1)
                push(verts, 1.0)
                push(verts, 1.0)
                push(verts, cr)
                push(verts, cg)
                push(verts, cb)
                push(verts, ca)
                push(verts, x0)
                push(verts, y1)
                push(verts, 0.0)
                push(verts, 1.0)
                push(verts, cr)
                push(verts, cg)
                push(verts, cb)
                push(verts, ca)
                vert_count = vert_count + 6
        i = i + 1
    if vert_count == 0:
        return nil
    # Upload and draw using UI pipeline
    gpu.buffer_upload(ur["vbuf"], verts)
    gpu.cmd_bind_graphics_pipeline(cmd, ur["pipeline"])
    let push_data = [screen_w, screen_h, 0.0, 0.0]
    gpu.cmd_push_constants(cmd, ur["pipe_layout"], gpu.STAGE_VERTEX, push_data)
    gpu.cmd_bind_vertex_buffer(cmd, ur["vbuf"])
    gpu.cmd_draw(cmd, vert_count, 1, 0, 0)
