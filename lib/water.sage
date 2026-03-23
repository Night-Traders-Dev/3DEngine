gc_disable()
# -----------------------------------------
# water.sage - Animated water plane for Sage Engine
# Generates a subdivided plane with vertex displacement for waves
# -----------------------------------------

import math
import gpu
from math3d import vec3, v3_normalize

# ============================================================================
# Water settings
# ============================================================================
proc create_water(size, subdivisions, water_y):
    let w = {}
    w["size"] = size
    w["subdivisions"] = subdivisions
    w["water_y"] = water_y
    w["wave_speed"] = 1.0
    w["wave_height"] = 0.3
    w["wave_freq"] = 2.0
    w["wave_dir_x"] = 1.0
    w["wave_dir_z"] = 0.5
    w["color"] = vec3(0.1, 0.3, 0.5)
    w["opacity"] = 0.7
    w["gpu_mesh"] = nil
    w["time"] = 0.0
    return w

# ============================================================================
# Wave height at a position
# ============================================================================
proc wave_height_at(w, x, z, time):
    let freq = w["wave_freq"]
    let spd = w["wave_speed"]
    let amp = w["wave_height"]
    let dx = w["wave_dir_x"]
    let dz = w["wave_dir_z"]
    let phase = (x * dx + z * dz) * freq + time * spd
    let h1 = math.sin(phase) * amp
    let h2 = math.sin(phase * 1.7 + 1.3) * amp * 0.5
    let h3 = math.sin(x * 0.8 + z * 1.2 + time * 0.7) * amp * 0.3
    return w["water_y"] + h1 + h2 + h3

# ============================================================================
# Build water mesh (standard vertex format: pos+normal+uv)
# ============================================================================
proc build_water_mesh(w, time):
    let sub = w["subdivisions"]
    let half = w["size"] / 2.0
    let step = w["size"] / sub
    let verts = []
    let indices = []
    let gx = 0
    while gx <= sub:
        let gz = 0
        while gz <= sub:
            let wx = 0.0 - half + gx * step
            let wz = 0.0 - half + gz * step
            let wy = wave_height_at(w, wx, wz, time)
            # Approximate normal via finite differences
            let eps = step * 0.5
            let hl = wave_height_at(w, wx - eps, wz, time)
            let hr = wave_height_at(w, wx + eps, wz, time)
            let hd = wave_height_at(w, wx, wz - eps, time)
            let hu = wave_height_at(w, wx, wz + eps, time)
            let n = v3_normalize(vec3((hl - hr) / (eps * 2.0), 1.0, (hd - hu) / (eps * 2.0)))
            let u = gx / sub
            let v = gz / sub
            push(verts, wx)
            push(verts, wy)
            push(verts, wz)
            push(verts, n[0])
            push(verts, n[1])
            push(verts, n[2])
            push(verts, u)
            push(verts, v)
            gz = gz + 1
        gx = gx + 1
    gx = 0
    while gx < sub:
        let gz = 0
        while gz < sub:
            let stride = sub + 1
            let tl = gx * stride + gz
            let tr = (gx + 1) * stride + gz
            let bl = gx * stride + gz + 1
            let br = (gx + 1) * stride + gz + 1
            push(indices, tl)
            push(indices, bl)
            push(indices, tr)
            push(indices, tr)
            push(indices, bl)
            push(indices, br)
            gz = gz + 1
        gx = gx + 1
    let result = {}
    result["vertices"] = verts
    result["indices"] = indices
    result["vertex_count"] = (sub + 1) * (sub + 1)
    result["index_count"] = len(indices)
    result["has_normals"] = true
    result["has_uvs"] = true
    return result

# ============================================================================
# Upload / update water mesh
# ============================================================================
proc upload_water(w, time):
    from mesh import upload_mesh
    w["time"] = time
    let mesh_data = build_water_mesh(w, time)
    w["gpu_mesh"] = upload_mesh(mesh_data)
    return w["gpu_mesh"]
