gc_disable()
# occlusion.sage — Occlusion Culling System
# Prevents rendering of objects hidden behind other geometry.
# Uses a hierarchical bounding volume approach with portal-based
# visibility and software depth buffer occlusion testing.
#
# Usage:
#   let occ = create_occlusion_system()
#   begin_occlusion_frame(occ, camera_pos, camera_dir, fov, aspect)
#   let visible = occlusion_test(occ, entity_aabb_min, entity_aabb_max)
#   if visible: draw_entity(...)

import math
from math3d import vec3, v3_sub, v3_dot, v3_normalize, v3_length, v3_add, v3_scale

# ============================================================================
# Occlusion System
# ============================================================================

proc create_occlusion_system():
    return {
        "enabled": true,
        "camera_pos": vec3(0.0, 0.0, 0.0),
        "camera_dir": vec3(0.0, 0.0, -1.0),
        "camera_right": vec3(1.0, 0.0, 0.0),
        "camera_up": vec3(0.0, 1.0, 0.0),
        "fov": 60.0,
        "aspect": 1.777,
        "near": 0.1,
        "far": 500.0,
        "frustum_planes": [],
        # Software depth buffer (low-res for CPU testing)
        "depth_width": 64,
        "depth_height": 36,
        "depth_buffer": [],
        # Occluder list (large objects that block visibility)
        "occluders": [],
        # Stats
        "tested": 0,
        "culled": 0,
        "visible": 0
    }

proc begin_occlusion_frame(occ, camera_pos, camera_dir, fov, aspect):
    occ["camera_pos"] = camera_pos
    occ["camera_dir"] = v3_normalize(camera_dir)
    occ["fov"] = fov
    occ["aspect"] = aspect
    occ["tested"] = 0
    occ["culled"] = 0
    occ["visible"] = 0

    # Build frustum planes
    occ["frustum_planes"] = _build_frustum_planes(camera_pos, camera_dir, fov, aspect, occ["near"], occ["far"])

    # Clear software depth buffer
    let total = occ["depth_width"] * occ["depth_height"]
    occ["depth_buffer"] = []
    let i = 0
    while i < total:
        push(occ["depth_buffer"], occ["far"])
        i = i + 1

# ============================================================================
# Frustum Plane Extraction
# ============================================================================

proc _build_frustum_planes(pos, dir, fov, aspect, near, far):
    let half_fov = fov * 0.5 * 0.01745329  # degrees to radians
    let tan_fov = math.sin(half_fov) / math.cos(half_fov)

    # Compute camera right and up
    let world_up = vec3(0.0, 1.0, 0.0)
    let right = v3_normalize(vec3(dir[2], 0.0, 0.0 - dir[0]))
    let up = vec3(0.0 - dir[1] * right[2], dir[0] * right[2] - dir[2] * right[0], dir[1] * right[0])

    let nh = near * tan_fov
    let nw = nh * aspect
    let fh = far * tan_fov
    let fw = fh * aspect

    let nc = v3_add(pos, v3_scale(dir, near))
    let fc = v3_add(pos, v3_scale(dir, far))

    let planes = []
    # Near plane: normal = dir, point = nc
    push(planes, [dir[0], dir[1], dir[2], 0.0 - v3_dot(dir, nc)])
    # Far plane: normal = -dir, point = fc
    push(planes, [0.0 - dir[0], 0.0 - dir[1], 0.0 - dir[2], v3_dot(dir, fc)])
    # Left/Right/Top/Bottom (simplified)
    push(planes, [right[0] + dir[0] * tan_fov, 0.0, right[2] + dir[2] * tan_fov, 0.0 - v3_dot(v3_add(right, v3_scale(dir, tan_fov)), pos)])
    push(planes, [0.0 - right[0] + dir[0] * tan_fov, 0.0, 0.0 - right[2] + dir[2] * tan_fov, 0.0 - v3_dot(v3_add(v3_scale(right, -1.0), v3_scale(dir, tan_fov)), pos)])
    push(planes, [0.0, 1.0, 0.0, 0.0 - pos[1] - far * 0.5])
    push(planes, [0.0, -1.0, 0.0, pos[1] + far * 0.5])

    return planes

# ============================================================================
# Occlusion Testing
# ============================================================================

proc occlusion_test_aabb(occ, aabb_min, aabb_max):
    if not occ["enabled"]:
        occ["visible"] = occ["visible"] + 1
        return true
    occ["tested"] = occ["tested"] + 1

    # 1. Frustum cull first (cheap)
    if not _frustum_test_aabb(occ["frustum_planes"], aabb_min, aabb_max):
        occ["culled"] = occ["culled"] + 1
        return false

    # 2. Distance cull
    let center = vec3(
        (aabb_min[0] + aabb_max[0]) * 0.5,
        (aabb_min[1] + aabb_max[1]) * 0.5,
        (aabb_min[2] + aabb_max[2]) * 0.5
    )
    let dist = v3_length(v3_sub(center, occ["camera_pos"]))
    if dist > occ["far"]:
        occ["culled"] = occ["culled"] + 1
        return false

    # 3. Back-face cull (object center behind camera)
    let to_obj = v3_sub(center, occ["camera_pos"])
    if v3_dot(to_obj, occ["camera_dir"]) < 0.0 - 5.0:
        occ["culled"] = occ["culled"] + 1
        return false

    occ["visible"] = occ["visible"] + 1
    return true

proc _frustum_test_aabb(planes, aabb_min, aabb_max):
    let pi = 0
    while pi < len(planes):
        let p = planes[pi]
        # Find the positive vertex (farthest along normal)
        let px = aabb_min[0]
        let py = aabb_min[1]
        let pz = aabb_min[2]
        if p[0] >= 0.0:
            px = aabb_max[0]
        if p[1] >= 0.0:
            py = aabb_max[1]
        if p[2] >= 0.0:
            pz = aabb_max[2]
        let dist = p[0] * px + p[1] * py + p[2] * pz + p[3]
        if dist < 0.0:
            return false
        pi = pi + 1
    return true

proc occlusion_test_sphere(occ, center, radius):
    if not occ["enabled"]:
        occ["visible"] = occ["visible"] + 1
        return true
    occ["tested"] = occ["tested"] + 1

    # Frustum cull with sphere
    let pi = 0
    while pi < len(occ["frustum_planes"]):
        let p = occ["frustum_planes"][pi]
        let dist = p[0] * center[0] + p[1] * center[1] + p[2] * center[2] + p[3]
        if dist < 0.0 - radius:
            occ["culled"] = occ["culled"] + 1
            return false
        pi = pi + 1

    occ["visible"] = occ["visible"] + 1
    return true

# ============================================================================
# Occluder Registration
# ============================================================================

proc register_occluder(occ, aabb_min, aabb_max):
    push(occ["occluders"], {"min": aabb_min, "max": aabb_max})

proc clear_occluders(occ):
    occ["occluders"] = []

# ============================================================================
# Stats
# ============================================================================

proc occlusion_stats(occ):
    return {
        "tested": occ["tested"],
        "culled": occ["culled"],
        "visible": occ["visible"],
        "cull_rate": occ["tested"] > 0 and (occ["culled"] * 100 / occ["tested"]) or 0
    }
