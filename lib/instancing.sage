gc_disable()
# instancing.sage — GPU Instanced Rendering
# Draws thousands of identical meshes in a single draw call using
# per-instance transform data uploaded to a GPU buffer.
#
# Usage:
#   let batch = create_instance_batch(tree_mesh_gpu, 10000)
#   add_instance(batch, position, rotation_y, scale)
#   upload_instance_data(batch)
#   draw_instanced(cmd, lit_mat, batch, vp, ls["desc_set"])

import gpu
import math
from math3d import vec3, mat4_identity, mat4_translate, mat4_rotate_y, mat4_scale, mat4_mul

# ============================================================================
# Instance Batch — holds per-instance transforms for one mesh
# ============================================================================

proc create_instance_batch(mesh_gpu, max_instances):
    return {
        "mesh": mesh_gpu,
        "max": max_instances,
        "count": 0,
        "transforms": [],        # Array of mat4 (16 floats each)
        "positions": [],          # Array of vec3 for culling
        "instance_buf": nil,      # GPU buffer (uploaded)
        "dirty": true
    }

proc add_instance(batch, position, rotation_y, scale_val):
    if batch["count"] >= batch["max"]:
        return false
    # Build model matrix: translate * rotate_y * scale
    let model = mat4_identity()
    model = mat4_mul(mat4_translate(position[0], position[1], position[2]), model)
    if rotation_y != 0.0:
        model = mat4_mul(mat4_rotate_y(rotation_y), model)
    if scale_val != 1.0:
        model = mat4_mul(mat4_scale(scale_val, scale_val, scale_val), model)

    push(batch["transforms"], model)
    push(batch["positions"], position)
    batch["count"] = batch["count"] + 1
    batch["dirty"] = true
    return true

proc add_instance_matrix(batch, model_matrix, position):
    if batch["count"] >= batch["max"]:
        return false
    push(batch["transforms"], model_matrix)
    push(batch["positions"], position)
    batch["count"] = batch["count"] + 1
    batch["dirty"] = true
    return true

proc clear_instances(batch):
    batch["transforms"] = []
    batch["positions"] = []
    batch["count"] = 0
    batch["dirty"] = true

# ============================================================================
# Upload — pack transforms into GPU buffer
# ============================================================================

proc upload_instance_data(batch):
    if not batch["dirty"] or batch["count"] == 0:
        return
    # Pack all model matrices into a float array (16 floats per instance)
    let data = []
    let i = 0
    while i < batch["count"]:
        let mat = batch["transforms"][i]
        let j = 0
        while j < 16:
            push(data, mat[j])
            j = j + 1
        i = i + 1

    # Upload as storage buffer
    if batch["instance_buf"] != nil:
        gpu.destroy_buffer(batch["instance_buf"])
    batch["instance_buf"] = gpu.create_buffer(len(data) * 4, gpu.BUFFER_STORAGE, gpu.MEMORY_HOST_VISIBLE)
    gpu.buffer_upload(batch["instance_buf"], data)
    batch["dirty"] = false

# ============================================================================
# Draw — single draw call for all instances
# ============================================================================

proc draw_instanced(cmd, lit_mat, batch, view_proj, desc_set):
    if batch["count"] == 0 or batch["mesh"] == nil:
        return

    gpu.cmd_bind_graphics_pipeline(cmd, lit_mat["pipeline"])
    gpu.cmd_bind_descriptor_set(cmd, lit_mat["pipe_layout"], 0, desc_set, 0)

    let mesh = batch["mesh"]
    gpu.cmd_bind_vertex_buffer(cmd, mesh["vbuf"])
    gpu.cmd_bind_index_buffer(cmd, mesh["ibuf"])

    # Draw all instances in one call
    gpu.cmd_draw_indexed(cmd, mesh["index_count"], batch["count"], 0, 0, 0)

# ============================================================================
# Frustum-culled instanced draw — only draws visible instances
# ============================================================================

proc draw_instanced_culled(cmd, lit_mat, batch, view_proj, desc_set, frustum_planes, cull_radius):
    if batch["count"] == 0 or batch["mesh"] == nil:
        return 0

    let visible = 0
    let i = 0
    while i < batch["count"]:
        let pos = batch["positions"][i]
        # Simple sphere-frustum test
        let inside = true
        let pi = 0
        while pi < len(frustum_planes):
            let plane = frustum_planes[pi]
            let dist = plane[0] * pos[0] + plane[1] * pos[1] + plane[2] * pos[2] + plane[3]
            if dist < 0.0 - cull_radius:
                inside = false
                break
            pi = pi + 1

        if inside:
            let model = batch["transforms"][i]
            let mvp = mat4_mul(view_proj, model)
            let stage_flags = gpu.STAGE_VERTEX | gpu.STAGE_FRAGMENT
            gpu.cmd_bind_graphics_pipeline(cmd, lit_mat["pipeline"])
            gpu.cmd_bind_descriptor_set(cmd, lit_mat["pipe_layout"], 0, desc_set, 0)
            let push_data = []
            let j = 0
            while j < 16:
                push(push_data, mvp[j])
                j = j + 1
            j = 0
            while j < 16:
                push(push_data, model[j])
                j = j + 1
            # base color + shadow flag
            push(push_data, 0.75)
            push(push_data, 0.75)
            push(push_data, 0.75)
            push(push_data, 1.0)
            push(push_data, 1.0)
            gpu.cmd_push_constants(cmd, lit_mat["pipe_layout"], stage_flags, push_data)
            let mesh = batch["mesh"]
            gpu.cmd_bind_vertex_buffer(cmd, mesh["vbuf"])
            gpu.cmd_bind_index_buffer(cmd, mesh["ibuf"])
            gpu.cmd_draw_indexed(cmd, mesh["index_count"], 1, 0, 0, 0)
            visible = visible + 1
        i = i + 1
    return visible

# ============================================================================
# Scatter helper — procedurally place instances on terrain
# ============================================================================

proc scatter_instances(batch, bounds_min, bounds_max, count, height_fn):
    let placed = 0
    let i = 0
    while i < count:
        let x = bounds_min[0] + math.random() * (bounds_max[0] - bounds_min[0])
        let z = bounds_min[2] + math.random() * (bounds_max[2] - bounds_min[2])
        let y = 0.0
        if height_fn != nil:
            y = height_fn(x, z)
        let rot = math.random() * 6.2831853
        let sc = 0.8 + math.random() * 0.4
        if add_instance(batch, vec3(x, y, z), rot, sc):
            placed = placed + 1
        i = i + 1
    return placed
