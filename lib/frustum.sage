gc_disable()
# -----------------------------------------
# frustum.sage - Frustum culling and draw batching for Sage Engine
# Extracts frustum planes from VP matrix, tests AABBs
# -----------------------------------------

import math
from math3d import vec3, v3_dot, v3_length, mat4_mul

# ============================================================================
# Frustum plane: [nx, ny, nz, d] where nx*x + ny*y + nz*z + d = 0
# ============================================================================
proc extract_frustum_planes(vp):
    let planes = []
    # Left: row3 + row0
    push(planes, [vp[3]+vp[0], vp[7]+vp[4], vp[11]+vp[8], vp[15]+vp[12]])
    # Right: row3 - row0
    push(planes, [vp[3]-vp[0], vp[7]-vp[4], vp[11]-vp[8], vp[15]-vp[12]])
    # Bottom: row3 + row1
    push(planes, [vp[3]+vp[1], vp[7]+vp[5], vp[11]+vp[9], vp[15]+vp[13]])
    # Top: row3 - row1
    push(planes, [vp[3]-vp[1], vp[7]-vp[5], vp[11]-vp[9], vp[15]-vp[13]])
    # Near: row3 + row2
    push(planes, [vp[3]+vp[2], vp[7]+vp[6], vp[11]+vp[10], vp[15]+vp[14]])
    # Far: row3 - row2
    push(planes, [vp[3]-vp[2], vp[7]-vp[6], vp[11]-vp[10], vp[15]-vp[14]])
    # Normalize each plane
    let i = 0
    while i < 6:
        let p = planes[i]
        let len_inv = 1.0 / math.sqrt(p[0]*p[0] + p[1]*p[1] + p[2]*p[2])
        planes[i] = [p[0]*len_inv, p[1]*len_inv, p[2]*len_inv, p[3]*len_inv]
        i = i + 1
    return planes

# ============================================================================
# Test point against frustum
# ============================================================================
proc point_in_frustum(planes, px, py, pz):
    let i = 0
    while i < 6:
        let p = planes[i]
        let dist = p[0]*px + p[1]*py + p[2]*pz + p[3]
        if dist < 0.0:
            return false
        i = i + 1
    return true

# ============================================================================
# Test sphere against frustum
# ============================================================================
proc sphere_in_frustum(planes, cx, cy, cz, radius):
    let i = 0
    while i < 6:
        let p = planes[i]
        let dist = p[0]*cx + p[1]*cy + p[2]*cz + p[3]
        if dist < 0.0 - radius:
            return false
        i = i + 1
    return true

# ============================================================================
# Test AABB against frustum
# ============================================================================
proc aabb_in_frustum(planes, center, half_ext):
    let i = 0
    while i < 6:
        let p = planes[i]
        # Positive extent along plane normal
        let ex = half_ext[0] * math.abs(p[0])
        let ey = half_ext[1] * math.abs(p[1])
        let ez = half_ext[2] * math.abs(p[2])
        let r = ex + ey + ez
        let dist = p[0]*center[0] + p[1]*center[1] + p[2]*center[2] + p[3]
        if dist < 0.0 - r:
            return false
        i = i + 1
    return true

# ============================================================================
# Cull a list of render items, return only visible ones
# Each item: {entity, position, bounds_half}
# ============================================================================
proc cull_render_list(planes, items):
    let visible = []
    let i = 0
    while i < len(items):
        let item = items[i]
        if aabb_in_frustum(planes, item["position"], item["bounds_half"]):
            push(visible, item)
        i = i + 1
    return visible

# ============================================================================
# Draw call batcher - groups by material/mesh
# ============================================================================
proc create_draw_batch():
    let b = {}
    b["items"] = []
    b["sorted"] = false
    return b

proc add_to_batch(batch, mesh_key, material_key, entity, transform):
    let item = {}
    item["mesh"] = mesh_key
    item["material"] = material_key
    item["entity"] = entity
    item["transform"] = transform
    push(batch["items"], item)
    batch["sorted"] = false

proc sort_batch(batch):
    # Simple bucket sort by material then mesh
    let buckets = {}
    let i = 0
    while i < len(batch["items"]):
        let item = batch["items"][i]
        let key = item["material"] + "|" + item["mesh"]
        if dict_has(buckets, key) == false:
            buckets[key] = []
        push(buckets[key], item)
        i = i + 1
    # Flatten back
    let sorted = []
    let keys = dict_keys(buckets)
    i = 0
    while i < len(keys):
        let group = buckets[keys[i]]
        let j = 0
        while j < len(group):
            push(sorted, group[j])
            j = j + 1
        i = i + 1
    batch["items"] = sorted
    batch["sorted"] = true

proc clear_batch(batch):
    batch["items"] = []
    batch["sorted"] = false

proc batch_count(batch):
    return len(batch["items"])
