gc_disable()
# -----------------------------------------
# voxel_world.sage - Shared voxel world helpers for the Forge voxel template
# Block storage, terrain generation, exposed-face meshing, raycast selection,
# and simple player collision helpers for Minecraft-style sandbox loops.
# -----------------------------------------

import math
from math3d import vec3

proc _palette_key(block_id):
    return str(block_id)

proc _register_block(vw, block_id, name, color):
    let entry = {}
    entry["id"] = block_id
    entry["name"] = name
    entry["color"] = color
    vw["palette"][_palette_key(block_id)] = entry
    push(vw["palette_ids"], block_id)

proc create_voxel_world(size_x, size_y, size_z):
    let vw = {}
    vw["size_x"] = size_x
    vw["size_y"] = size_y
    vw["size_z"] = size_z
    vw["origin_x"] = 0.0 - size_x / 2.0
    vw["origin_z"] = 0.0 - size_z / 2.0
    vw["blocks"] = []
    let total = size_x * size_y * size_z
    let i = 0
    while i < total:
        push(vw["blocks"], 0)
        i = i + 1
    vw["palette"] = {}
    vw["palette_ids"] = []
    _register_block(vw, 1, "Grass", vec3(0.42, 0.74, 0.28))
    _register_block(vw, 2, "Dirt", vec3(0.56, 0.37, 0.22))
    _register_block(vw, 3, "Stone", vec3(0.56, 0.58, 0.62))
    _register_block(vw, 4, "Wood", vec3(0.63, 0.45, 0.24))
    _register_block(vw, 5, "Leaf", vec3(0.28, 0.63, 0.26))
    vw["mesh_data"] = {}
    vw["gpu_meshes"] = {}
    vw["draws"] = []
    vw["dirty"] = true
    vw["solid_count"] = 0
    return vw

proc voxel_palette_ids(vw):
    return vw["palette_ids"]

proc voxel_palette_entry(vw, block_id):
    let key = _palette_key(block_id)
    if dict_has(vw["palette"], key):
        return vw["palette"][key]
    return nil

proc voxel_block_name(vw, block_id):
    let entry = voxel_palette_entry(vw, block_id)
    if entry == nil:
        return "Air"
    return entry["name"]

proc voxel_block_surface(vw, block_id):
    let surface = {}
    surface["albedo"] = vec3(0.75, 0.75, 0.75)
    surface["alpha"] = 1.0
    let entry = voxel_palette_entry(vw, block_id)
    if entry != nil:
        surface["albedo"] = entry["color"]
    return surface

proc voxel_in_bounds(vw, gx, gy, gz):
    if gx < 0 or gy < 0 or gz < 0:
        return false
    if gx >= vw["size_x"] or gy >= vw["size_y"] or gz >= vw["size_z"]:
        return false
    return true

proc voxel_index(vw, gx, gy, gz):
    return gy * (vw["size_x"] * vw["size_z"]) + gz * vw["size_x"] + gx

proc get_voxel(vw, gx, gy, gz):
    if voxel_in_bounds(vw, gx, gy, gz) == false:
        return 0
    return vw["blocks"][voxel_index(vw, gx, gy, gz)]

proc set_voxel(vw, gx, gy, gz, block_id):
    if voxel_in_bounds(vw, gx, gy, gz) == false:
        return false
    let idx = voxel_index(vw, gx, gy, gz)
    let prev = vw["blocks"][idx]
    if prev == block_id:
        return false
    if prev == 0 and block_id != 0:
        vw["solid_count"] = vw["solid_count"] + 1
    if prev != 0 and block_id == 0:
        vw["solid_count"] = vw["solid_count"] - 1
    vw["blocks"][idx] = block_id
    vw["dirty"] = true
    return true

proc voxel_block_world_min(vw, gx, gy, gz):
    return vec3(vw["origin_x"] + gx, gy + 0.0, vw["origin_z"] + gz)

proc voxel_block_world_center(vw, gx, gy, gz):
    return vec3(vw["origin_x"] + gx + 0.5, gy + 0.5, vw["origin_z"] + gz + 0.5)

proc voxel_is_surface_block(vw, gx, gy, gz):
    let block_id = get_voxel(vw, gx, gy, gz)
    if block_id == 0:
        return false
    if get_voxel(vw, gx + 1, gy, gz) == 0:
        return true
    if get_voxel(vw, gx - 1, gy, gz) == 0:
        return true
    if get_voxel(vw, gx, gy + 1, gz) == 0:
        return true
    if get_voxel(vw, gx, gy - 1, gz) == 0:
        return true
    if get_voxel(vw, gx, gy, gz + 1) == 0:
        return true
    if get_voxel(vw, gx, gy, gz - 1) == 0:
        return true
    return false

proc clear_voxel_world(vw):
    let i = 0
    while i < len(vw["blocks"]):
        vw["blocks"][i] = 0
        i = i + 1
    vw["solid_count"] = 0
    vw["dirty"] = true

proc fill_voxel_box(vw, x0, y0, z0, x1, y1, z1, block_id):
    let x = x0
    while x < x1:
        let y = y0
        while y < y1:
            let z = z0
            while z < z1:
                set_voxel(vw, x, y, z, block_id)
                z = z + 1
            y = y + 1
        x = x + 1

proc _template_height(vw, gx, gz, seed):
    let sx = vw["size_x"] / 2.0
    let sz = vw["size_z"] / 2.0
    let nx = gx - sx
    let nz = gz - sz
    let dist = math.sqrt(nx * nx + nz * nz)
    let falloff = 1.0 - dist / (sx * 1.25)
    if falloff < 0.0:
        falloff = 0.0
    let wave = math.sin((gx + seed) * 0.41) + math.cos((gz - seed) * 0.33) + math.sin((gx + gz) * 0.18)
    let h = 3 + math.floor((wave + 3.0) * 0.65 * falloff + falloff * 2.0)
    if h < 2:
        h = 2
    if h > vw["size_y"] - 4:
        h = vw["size_y"] - 4
    return h

proc _find_surface_y(vw, gx, gz):
    let y = vw["size_y"] - 1
    while y >= 0:
        if get_voxel(vw, gx, y, gz) != 0:
            return y
        y = y - 1
    return -1

proc _add_template_tree(vw, gx, gz):
    let ground_y = _find_surface_y(vw, gx, gz)
    if ground_y < 0:
        return false
    if ground_y + 5 >= vw["size_y"]:
        return false
    if get_voxel(vw, gx, ground_y, gz) != 1:
        return false
    let ty = ground_y + 1
    let i = 0
    while i < 3:
        set_voxel(vw, gx, ty + i, gz, 4)
        i = i + 1
    let lx = gx - 1
    while lx <= gx + 1:
        let lz = gz - 1
        while lz <= gz + 1:
            set_voxel(vw, lx, ty + 3, lz, 5)
            if lx == gx or lz == gz:
                set_voxel(vw, lx, ty + 4, lz, 5)
            lz = lz + 1
        lx = lx + 1
    set_voxel(vw, gx, ty + 5, gz, 5)
    return true

proc generate_voxel_template_world(vw, seed):
    clear_voxel_world(vw)
    let gx = 0
    while gx < vw["size_x"]:
        let gz = 0
        while gz < vw["size_z"]:
            let h = _template_height(vw, gx, gz, seed)
            let y = 0
            while y < h:
                let block_id = 3
                if y == h - 1:
                    block_id = 1
                else:
                    if y >= h - 3:
                        block_id = 2
                set_voxel(vw, gx, y, gz, block_id)
                y = y + 1
            gz = gz + 1
        gx = gx + 1

    _add_template_tree(vw, 3, 4)
    _add_template_tree(vw, vw["size_x"] - 4, vw["size_z"] - 5)
    _add_template_tree(vw, vw["size_x"] / 2, vw["size_z"] / 2 + 3)

proc _mesh_bucket(meshes, block_id):
    let key = _palette_key(block_id)
    if dict_has(meshes, key):
        return meshes[key]
    let bucket = {}
    bucket["block_id"] = block_id
    bucket["vertices"] = []
    bucket["indices"] = []
    bucket["face_count"] = 0
    meshes[key] = bucket
    return bucket

proc _append_voxel_face(bucket, wx, wy, wz, face_name):
    let verts = bucket["vertices"]
    let indices = bucket["indices"]
    let base = len(verts) / 8
    let p0 = nil
    let p1 = nil
    let p2 = nil
    let p3 = nil
    let normal = vec3(0.0, 1.0, 0.0)

    if face_name == "front":
        p0 = vec3(wx, wy, wz + 1.0)
        p1 = vec3(wx + 1.0, wy, wz + 1.0)
        p2 = vec3(wx + 1.0, wy + 1.0, wz + 1.0)
        p3 = vec3(wx, wy + 1.0, wz + 1.0)
        normal = vec3(0.0, 0.0, 1.0)
    else:
        if face_name == "back":
            p0 = vec3(wx + 1.0, wy, wz)
            p1 = vec3(wx, wy, wz)
            p2 = vec3(wx, wy + 1.0, wz)
            p3 = vec3(wx + 1.0, wy + 1.0, wz)
            normal = vec3(0.0, 0.0, -1.0)
        else:
            if face_name == "right":
                p0 = vec3(wx + 1.0, wy, wz + 1.0)
                p1 = vec3(wx + 1.0, wy, wz)
                p2 = vec3(wx + 1.0, wy + 1.0, wz)
                p3 = vec3(wx + 1.0, wy + 1.0, wz + 1.0)
                normal = vec3(1.0, 0.0, 0.0)
            else:
                if face_name == "left":
                    p0 = vec3(wx, wy, wz)
                    p1 = vec3(wx, wy, wz + 1.0)
                    p2 = vec3(wx, wy + 1.0, wz + 1.0)
                    p3 = vec3(wx, wy + 1.0, wz)
                    normal = vec3(-1.0, 0.0, 0.0)
                else:
                    if face_name == "top":
                        p0 = vec3(wx, wy + 1.0, wz + 1.0)
                        p1 = vec3(wx + 1.0, wy + 1.0, wz + 1.0)
                        p2 = vec3(wx + 1.0, wy + 1.0, wz)
                        p3 = vec3(wx, wy + 1.0, wz)
                        normal = vec3(0.0, 1.0, 0.0)
                    else:
                        p0 = vec3(wx, wy, wz)
                        p1 = vec3(wx + 1.0, wy, wz)
                        p2 = vec3(wx + 1.0, wy, wz + 1.0)
                        p3 = vec3(wx, wy, wz + 1.0)
                        normal = vec3(0.0, -1.0, 0.0)

    push(verts, p0[0])
    push(verts, p0[1])
    push(verts, p0[2])
    push(verts, normal[0])
    push(verts, normal[1])
    push(verts, normal[2])
    push(verts, 0.0)
    push(verts, 0.0)

    push(verts, p1[0])
    push(verts, p1[1])
    push(verts, p1[2])
    push(verts, normal[0])
    push(verts, normal[1])
    push(verts, normal[2])
    push(verts, 1.0)
    push(verts, 0.0)

    push(verts, p2[0])
    push(verts, p2[1])
    push(verts, p2[2])
    push(verts, normal[0])
    push(verts, normal[1])
    push(verts, normal[2])
    push(verts, 1.0)
    push(verts, 1.0)

    push(verts, p3[0])
    push(verts, p3[1])
    push(verts, p3[2])
    push(verts, normal[0])
    push(verts, normal[1])
    push(verts, normal[2])
    push(verts, 0.0)
    push(verts, 1.0)
    push(indices, base)
    push(indices, base + 1)
    push(indices, base + 2)
    push(indices, base)
    push(indices, base + 2)
    push(indices, base + 3)
    bucket["face_count"] = bucket["face_count"] + 1

proc build_voxel_meshes(vw):
    let meshes = {}
    let gx = 0
    while gx < vw["size_x"]:
        let gy = 0
        while gy < vw["size_y"]:
            let gz = 0
            while gz < vw["size_z"]:
                let block_id = get_voxel(vw, gx, gy, gz)
                if block_id != 0:
                    let bucket = _mesh_bucket(meshes, block_id)
                    let world_min = voxel_block_world_min(vw, gx, gy, gz)
                    if get_voxel(vw, gx, gy, gz + 1) == 0:
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "front")
                    if get_voxel(vw, gx, gy, gz - 1) == 0:
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "back")
                    if get_voxel(vw, gx + 1, gy, gz) == 0:
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "right")
                    if get_voxel(vw, gx - 1, gy, gz) == 0:
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "left")
                    if get_voxel(vw, gx, gy + 1, gz) == 0:
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "top")
                    if get_voxel(vw, gx, gy - 1, gz) == 0:
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "bottom")
                gz = gz + 1
            gy = gy + 1
        gx = gx + 1

    let built = {}
    let pi = 0
    while pi < len(vw["palette_ids"]):
        let block_id = vw["palette_ids"][pi]
        let key = _palette_key(block_id)
        if dict_has(meshes, key):
            let bucket = meshes[key]
            let mesh_data = {}
            mesh_data["block_id"] = block_id
            mesh_data["vertices"] = bucket["vertices"]
            mesh_data["indices"] = bucket["indices"]
            mesh_data["vertex_count"] = len(bucket["vertices"]) / 8
            mesh_data["index_count"] = len(bucket["indices"])
            mesh_data["has_normals"] = true
            mesh_data["has_uvs"] = true
            mesh_data["face_count"] = bucket["face_count"]
            built[key] = mesh_data
        pi = pi + 1
    vw["mesh_data"] = built
    return built

proc rebuild_voxel_world(vw):
    from mesh import upload_mesh
    let built = build_voxel_meshes(vw)
    let gpu_meshes = {}
    let draws = []
    let pi = 0
    while pi < len(vw["palette_ids"]):
        let block_id = vw["palette_ids"][pi]
        let key = _palette_key(block_id)
        if dict_has(built, key):
            let mesh_data = built[key]
            let gpu_mesh = upload_mesh(mesh_data)
            gpu_meshes[key] = gpu_mesh
            let draw = {}
            draw["block_id"] = block_id
            draw["gpu_mesh"] = gpu_mesh
            draw["surface"] = voxel_block_surface(vw, block_id)
            draw["name"] = voxel_block_name(vw, block_id)
            draw["face_count"] = mesh_data["face_count"]
            push(draws, draw)
        pi = pi + 1
    vw["gpu_meshes"] = gpu_meshes
    vw["draws"] = draws
    vw["dirty"] = false
    return draws

proc voxel_draws(vw):
    if vw["dirty"]:
        return rebuild_voxel_world(vw)
    return vw["draws"]

proc raycast_voxel_world(vw, origin, direction, max_dist):
    let dist = 0.0
    let step = 0.05
    let last_cell = ""
    let last_empty = nil
    while dist <= max_dist:
        let px = origin[0] + direction[0] * dist
        let py = origin[1] + direction[1] * dist
        let pz = origin[2] + direction[2] * dist
        let gx = math.floor(px - vw["origin_x"])
        let gy = math.floor(py)
        let gz = math.floor(pz - vw["origin_z"])
        let cell_id = str(gx) + ":" + str(gy) + ":" + str(gz)
        if cell_id != last_cell:
            last_cell = cell_id
            if voxel_in_bounds(vw, gx, gy, gz):
                let block_id = get_voxel(vw, gx, gy, gz)
                if block_id != 0:
                    let hit = {}
                    hit["x"] = gx
                    hit["y"] = gy
                    hit["z"] = gz
                    hit["block_id"] = block_id
                    hit["distance"] = dist
                    if last_empty != nil:
                        hit["place_x"] = last_empty["x"]
                        hit["place_y"] = last_empty["y"]
                        hit["place_z"] = last_empty["z"]
                    return hit
                last_empty = {"x": gx, "y": gy, "z": gz}
            else:
                last_empty = nil
        dist = dist + step
    return nil

proc voxel_top_solid_y(vw, gx, gz):
    let y = vw["size_y"] - 1
    while y >= 0:
        if get_voxel(vw, gx, y, gz) != 0:
            return y
        y = y - 1
    return -1

proc sample_voxel_ground(vw, wx, wz):
    let gx = math.floor(wx - vw["origin_x"])
    let gz = math.floor(wz - vw["origin_z"])
    if gx < 0 or gz < 0 or gx >= vw["size_x"] or gz >= vw["size_z"]:
        return 0.0
    let top_y = voxel_top_solid_y(vw, gx, gz)
    if top_y < 0:
        return 0.0
    return top_y + 1.0

proc sample_voxel_ground_radius(vw, wx, wz, radius):
    let h = sample_voxel_ground(vw, wx, wz)
    let h1 = sample_voxel_ground(vw, wx - radius, wz - radius)
    let h2 = sample_voxel_ground(vw, wx + radius, wz - radius)
    let h3 = sample_voxel_ground(vw, wx - radius, wz + radius)
    let h4 = sample_voxel_ground(vw, wx + radius, wz + radius)
    if h1 > h:
        h = h1
    if h2 > h:
        h = h2
    if h3 > h:
        h = h3
    if h4 > h:
        h = h4
    return h

proc voxel_collides_player(vw, pos, radius, height):
    let min_x = math.floor((pos[0] - radius) - vw["origin_x"])
    let max_x = math.floor((pos[0] + radius - 0.001) - vw["origin_x"])
    let min_y = math.floor(pos[1] + 0.05)
    let max_y = math.floor(pos[1] + height - 0.05)
    let min_z = math.floor((pos[2] - radius) - vw["origin_z"])
    let max_z = math.floor((pos[2] + radius - 0.001) - vw["origin_z"])
    let gx = min_x
    while gx <= max_x:
        let gy = min_y
        while gy <= max_y:
            let gz = min_z
            while gz <= max_z:
                if get_voxel(vw, gx, gy, gz) != 0:
                    return true
                gz = gz + 1
            gy = gy + 1
        gx = gx + 1
    return false

proc resolve_player_voxel_collision(vw, prev_pos, next_pos, radius, height):
    let resolved = vec3(next_pos[0], next_pos[1], next_pos[2])
    let vertical_test = vec3(prev_pos[0], resolved[1], prev_pos[2])
    if voxel_collides_player(vw, vertical_test, radius, height):
        resolved[1] = prev_pos[1]
    let x_test = vec3(resolved[0], resolved[1], prev_pos[2])
    if voxel_collides_player(vw, x_test, radius, height):
        resolved[0] = prev_pos[0]
    let z_test = vec3(resolved[0], resolved[1], resolved[2])
    if voxel_collides_player(vw, z_test, radius, height):
        resolved[2] = prev_pos[2]
    if voxel_collides_player(vw, resolved, radius, height):
        return vec3(prev_pos[0], prev_pos[1], prev_pos[2])
    return resolved
