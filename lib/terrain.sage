gc_disable()
# -----------------------------------------
# terrain.sage - Heightmap terrain for Sage Engine
# Procedural generation, chunked mesh, height queries, LOD
# -----------------------------------------

import math
import gpu
from math3d import vec3, v3_normalize, v3_cross, v3_sub

# ============================================================================
# Noise (value noise with smooth interpolation)
# ============================================================================
proc _hash2d(x, z):
    # Simple sin-based hash that stays in double precision range
    let ix = math.floor(x) + 0.1
    let iz = math.floor(z) + 0.1
    let dot = ix * 127.1 + iz * 311.7
    let s = math.sin(dot) * 43758.5453
    return s - math.floor(s)

proc _smooth(t):
    return t * t * (3.0 - 2.0 * t)

proc _lerp(a, b, t):
    return a + (b - a) * t

proc value_noise(x, z):
    let ix = math.floor(x)
    let iz = math.floor(z)
    let fx = x - ix
    let fz = z - iz
    fx = _smooth(fx)
    fz = _smooth(fz)
    let v00 = _hash2d(ix, iz)
    let v10 = _hash2d(ix + 1, iz)
    let v01 = _hash2d(ix, iz + 1)
    let v11 = _hash2d(ix + 1, iz + 1)
    let a = _lerp(v00, v10, fx)
    let b = _lerp(v01, v11, fx)
    return _lerp(a, b, fz)

proc fbm_noise(x, z, octaves, persistence, lacunarity):
    let total = 0.0
    let amplitude = 1.0
    let frequency = 1.0
    let max_val = 0.0
    let i = 0
    while i < octaves:
        total = total + value_noise(x * frequency, z * frequency) * amplitude
        max_val = max_val + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
        i = i + 1
    return total / max_val

# ============================================================================
# Terrain heightmap
# ============================================================================
proc create_terrain(res_x, res_z, world_size_x, world_size_z, max_height):
    let t = {}
    t["res_x"] = res_x
    t["res_z"] = res_z
    t["size_x"] = world_size_x
    t["size_z"] = world_size_z
    t["max_height"] = max_height
    t["origin_x"] = 0.0 - world_size_x / 2.0
    t["origin_z"] = 0.0 - world_size_z / 2.0
    t["cell_x"] = world_size_x / res_x
    t["cell_z"] = world_size_z / res_z
    # Heightmap array
    let heights = []
    let i = 0
    while i < (res_x + 1) * (res_z + 1):
        push(heights, 0.0)
        i = i + 1
    t["heights"] = heights
    t["gpu_mesh"] = nil
    return t

proc terrain_index(t, gx, gz):
    return gz * (t["res_x"] + 1) + gx

proc set_height(t, gx, gz, h):
    if gx < 0 or gx > t["res_x"]:
        return nil
    if gz < 0 or gz > t["res_z"]:
        return nil
    t["heights"][terrain_index(t, gx, gz)] = h

proc get_height_grid(t, gx, gz):
    if gx < 0:
        gx = 0
    if gz < 0:
        gz = 0
    if gx > t["res_x"]:
        gx = t["res_x"]
    if gz > t["res_z"]:
        gz = t["res_z"]
    return t["heights"][terrain_index(t, gx, gz)]

# ============================================================================
# Generate terrain from noise
# ============================================================================
proc generate_terrain_noise(t, seed, octaves, persistence, lacunarity, scale):
    let rx = t["res_x"]
    let rz = t["res_z"]
    let gx = 0
    while gx <= rx:
        let gz = 0
        while gz <= rz:
            let nx = (gx / rx) * scale + seed
            let nz = (gz / rz) * scale + seed
            let h = fbm_noise(nx, nz, octaves, persistence, lacunarity)
            set_height(t, gx, gz, h * t["max_height"])
            gz = gz + 1
        gx = gx + 1

proc generate_terrain_flat(t, height):
    let rx = t["res_x"]
    let rz = t["res_z"]
    let gx = 0
    while gx <= rx:
        let gz = 0
        while gz <= rz:
            set_height(t, gx, gz, height)
            gz = gz + 1
        gx = gx + 1

# ============================================================================
# Sample height at world position (bilinear interpolation)
# ============================================================================
proc sample_height(t, wx, wz):
    let lx = (wx - t["origin_x"]) / t["cell_x"]
    let lz = (wz - t["origin_z"]) / t["cell_z"]
    let gx = math.floor(lx)
    let gz = math.floor(lz)
    let fx = lx - gx
    let fz = lz - gz
    let h00 = get_height_grid(t, gx, gz)
    let h10 = get_height_grid(t, gx + 1, gz)
    let h01 = get_height_grid(t, gx, gz + 1)
    let h11 = get_height_grid(t, gx + 1, gz + 1)
    let a = h00 + (h10 - h00) * fx
    let b = h01 + (h11 - h01) * fx
    return a + (b - a) * fz

# ============================================================================
# Compute normal at grid position
# ============================================================================
proc terrain_normal(t, gx, gz):
    let hl = get_height_grid(t, gx - 1, gz)
    let hr = get_height_grid(t, gx + 1, gz)
    let hd = get_height_grid(t, gx, gz - 1)
    let hu = get_height_grid(t, gx, gz + 1)
    let sx = t["cell_x"] * 2.0
    let sz = t["cell_z"] * 2.0
    return v3_normalize(vec3((hl - hr) / sx, 1.0, (hd - hu) / sz))

# ============================================================================
# Build terrain mesh (position + normal + UV, stride 32 bytes)
# ============================================================================
proc build_terrain_mesh(t):
    let rx = t["res_x"]
    let rz = t["res_z"]
    let verts = []
    let indices = []
    let gx = 0
    while gx <= rx:
        let gz = 0
        while gz <= rz:
            let wx = t["origin_x"] + gx * t["cell_x"]
            let wz = t["origin_z"] + gz * t["cell_z"]
            let wy = get_height_grid(t, gx, gz)
            let n = terrain_normal(t, gx, gz)
            let u = gx / rx
            let v = gz / rz
            # pos
            push(verts, wx)
            push(verts, wy)
            push(verts, wz)
            # normal
            push(verts, n[0])
            push(verts, n[1])
            push(verts, n[2])
            # uv
            push(verts, u)
            push(verts, v)
            gz = gz + 1
        gx = gx + 1
    # Indices
    gx = 0
    while gx < rx:
        let gz = 0
        while gz < rz:
            let stride = rz + 1
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
    result["vertex_count"] = (rx + 1) * (rz + 1)
    result["index_count"] = len(indices)
    result["has_normals"] = true
    result["has_uvs"] = true
    return result

# ============================================================================
# Upload terrain to GPU
# ============================================================================
proc upload_terrain(t):
    from mesh import upload_mesh
    let mesh_data = build_terrain_mesh(t)
    t["gpu_mesh"] = upload_mesh(mesh_data)
    return t["gpu_mesh"]
