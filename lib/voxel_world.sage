gc_disable()
# -----------------------------------------
# voxel_world.sage - Shared voxel world helpers for the Forge voxel template
# Block storage, terrain generation, exposed-face meshing, raycast selection,
# and simple player collision helpers for Minecraft-style sandbox loops.
# -----------------------------------------

import gpu
import math
import io
from math3d import vec3
from json import cJSON_Parse, cJSON_Print, cJSON_Delete, cJSON_FromSage, cJSON_ToSage

proc _clone_sage(value):
    let node = cJSON_FromSage(value)
    if node == nil:
        return value
    let out = cJSON_ToSage(node)
    cJSON_Delete(node)
    return out

proc _destroy_voxel_gpu_mesh(gpu_mesh):
    if gpu_mesh == nil:
        return
    if dict_has(gpu_mesh, "vbuf") and gpu_mesh["vbuf"] != nil:
        gpu.destroy_buffer(gpu_mesh["vbuf"])
    if dict_has(gpu_mesh, "ibuf") and gpu_mesh["ibuf"] != nil:
        gpu.destroy_buffer(gpu_mesh["ibuf"])

proc _reset_voxel_stream_state(vw):
    vw["stream_chunks"] = {}
    vw["stream_draws"] = []
    vw["stream_center_chunk"] = {"x": -9999, "y": -9999, "z": -9999}
    vw["stream_chunk_radius"] = -1

proc _clear_voxel_mesh_cache(vw):
    let keys = dict_keys(vw["gpu_meshes"])
    let i = 0
    while i < len(keys):
        _destroy_voxel_gpu_mesh(vw["gpu_meshes"][keys[i]])
        i = i + 1
    vw["gpu_meshes"] = {}
    let chunk_keys = dict_keys(vw["stream_chunks"])
    let ci = 0
    while ci < len(chunk_keys):
        let draws = vw["stream_chunks"][chunk_keys[ci]]
        let di = 0
        while di < len(draws):
            _destroy_voxel_gpu_mesh(draws[di]["gpu_mesh"])
            di = di + 1
        ci = ci + 1
    _reset_voxel_stream_state(vw)

proc _palette_key(block_id):
    return str(block_id)

proc _face_palette_key(block_id, face_group):
    return str(block_id) + ":" + face_group

proc _register_block(vw, block_id, name, top_color, side_color, bottom_color):
    let entry = {}
    entry["id"] = block_id
    entry["name"] = name
    entry["color"] = top_color
    entry["top_color"] = top_color
    entry["side_color"] = side_color
    entry["bottom_color"] = bottom_color
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
    _register_block(vw, 1, "Grass", vec3(0.34, 0.76, 0.22), vec3(0.54, 0.62, 0.25), vec3(0.50, 0.33, 0.19))
    _register_block(vw, 2, "Dirt", vec3(0.60, 0.40, 0.24), vec3(0.52, 0.34, 0.20), vec3(0.44, 0.28, 0.17))
    _register_block(vw, 3, "Stone", vec3(0.68, 0.70, 0.74), vec3(0.56, 0.58, 0.62), vec3(0.40, 0.42, 0.46))
    _register_block(vw, 4, "Wood", vec3(0.78, 0.64, 0.38), vec3(0.60, 0.40, 0.20), vec3(0.70, 0.55, 0.31))
    _register_block(vw, 5, "Leaf", vec3(0.34, 0.70, 0.28), vec3(0.27, 0.57, 0.23), vec3(0.22, 0.46, 0.19))
    _register_block(vw, 6, "Plank", vec3(0.84, 0.69, 0.40), vec3(0.74, 0.56, 0.29), vec3(0.62, 0.45, 0.22))
    vw["mesh_data"] = {}
    vw["gpu_meshes"] = {}
    vw["draws"] = []
    vw["dirty"] = true
    vw["solid_count"] = 0
    vw["template_seed"] = 0.0
    vw["chunk_size"] = 16
    vw["max_stream_chunk_refresh"] = 2
    vw["dirty_chunks"] = {}
    vw["generated_chunks"] = {}
    _reset_voxel_stream_state(vw)
    return vw

proc create_voxel_inventory():
    let inv = {}
    inv["counts"] = {}
    return inv

proc voxel_inventory_count(inv, block_id):
    if inv == nil or block_id == 0:
        return 0
    let key = _palette_key(block_id)
    if dict_has(inv["counts"], key):
        return inv["counts"][key]
    return 0

proc voxel_inventory_add(inv, block_id, amount):
    if inv == nil or block_id == 0 or amount <= 0:
        return voxel_inventory_count(inv, block_id)
    let key = _palette_key(block_id)
    let count = voxel_inventory_count(inv, block_id)
    inv["counts"][key] = count + amount
    return inv["counts"][key]

proc voxel_inventory_remove(inv, block_id, amount):
    if inv == nil or block_id == 0 or amount <= 0:
        return false
    let key = _palette_key(block_id)
    let count = voxel_inventory_count(inv, block_id)
    if count < amount:
        return false
    inv["counts"][key] = count - amount
    return true

proc voxel_inventory_to_sage(inv):
    let out = create_voxel_inventory()
    if inv == nil or dict_has(inv, "counts") == false:
        return out
    let keys = dict_keys(inv["counts"])
    let i = 0
    while i < len(keys):
        out["counts"][keys[i]] = inv["counts"][keys[i]]
        i = i + 1
    return out

proc voxel_inventory_from_sage(data):
    let inv = create_voxel_inventory()
    if data == nil or dict_has(data, "counts") == false:
        return inv
    let keys = dict_keys(data["counts"])
    let i = 0
    while i < len(keys):
        inv["counts"][keys[i]] = data["counts"][keys[i]]
        i = i + 1
    return inv

proc create_voxel_recipe(name, input_block, input_count, output_block, output_count):
    let recipe = {}
    recipe["name"] = name
    recipe["input_block"] = input_block
    recipe["input_count"] = input_count
    recipe["output_block"] = output_block
    recipe["output_count"] = output_count
    return recipe

proc default_voxel_recipes():
    let recipes = []
    push(recipes, create_voxel_recipe("Planks", 4, 1, 6, 4))
    return recipes

proc try_craft_voxel_recipe(inv, recipe):
    if inv == nil or recipe == nil:
        return false
    if voxel_inventory_remove(inv, recipe["input_block"], recipe["input_count"]) == false:
        return false
    voxel_inventory_add(inv, recipe["output_block"], recipe["output_count"])
    return true

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
    return voxel_block_face_surface(vw, block_id, "top")

proc _voxel_face_texture_id(face_group):
    if face_group == "top":
        return 0
    if face_group == "bottom":
        return 2
    return 1

proc voxel_block_face_surface(vw, block_id, face_group):
    let surface = {}
    surface["albedo"] = vec3(0.75, 0.75, 0.75)
    surface["alpha"] = 1.0
    let entry = voxel_palette_entry(vw, block_id)
    if entry != nil:
        if face_group == "bottom" and dict_has(entry, "bottom_color"):
            surface["albedo"] = entry["bottom_color"]
        else:
            if face_group == "side" and dict_has(entry, "side_color"):
                surface["albedo"] = entry["side_color"]
            else:
                if face_group == "top" and dict_has(entry, "top_color"):
                    surface["albedo"] = entry["top_color"]
                else:
                    surface["albedo"] = entry["color"]
        surface["voxel_texture"] = true
        surface["voxel_block_id"] = block_id + 0.0
        surface["voxel_face_id"] = _voxel_face_texture_id(face_group) + 0.0
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
    _mark_voxel_dirty_chunks(vw, gx, gy, gz)
    vw["dirty"] = true
    return true

proc voxel_block_world_min(vw, gx, gy, gz):
    return vec3(vw["origin_x"] + gx, gy + 0.0, vw["origin_z"] + gz)

proc voxel_block_world_center(vw, gx, gy, gz):
    return vec3(vw["origin_x"] + gx + 0.5, gy + 0.5, vw["origin_z"] + gz + 0.5)

proc voxel_chunk_size(vw):
    return vw["chunk_size"]

proc _voxel_chunk_count_axis(size, chunk_size):
    return math.floor((size + chunk_size - 1) / chunk_size)

proc voxel_chunk_count_x(vw):
    return _voxel_chunk_count_axis(vw["size_x"], voxel_chunk_size(vw))

proc voxel_chunk_count_y(vw):
    return _voxel_chunk_count_axis(vw["size_y"], voxel_chunk_size(vw))

proc voxel_chunk_count_z(vw):
    return _voxel_chunk_count_axis(vw["size_z"], voxel_chunk_size(vw))

proc voxel_chunk_key(cx, cy, cz):
    return str(cx) + ":" + str(cy) + ":" + str(cz)

proc voxel_chunk_coords(vw, gx, gy, gz):
    let cs = voxel_chunk_size(vw)
    return {"x": math.floor(gx / cs), "y": math.floor(gy / cs), "z": math.floor(gz / cs)}

proc _voxel_chunk_valid(vw, cx, cy, cz):
    if cx < 0 or cy < 0 or cz < 0:
        return false
    if cx >= voxel_chunk_count_x(vw) or cy >= voxel_chunk_count_y(vw) or cz >= voxel_chunk_count_z(vw):
        return false
    return true

proc _mark_chunk_dirty(vw, cx, cy, cz):
    if _voxel_chunk_valid(vw, cx, cy, cz) == false:
        return
    let key = voxel_chunk_key(cx, cy, cz)
    vw["dirty_chunks"][key] = {"x": cx, "y": cy, "z": cz}

proc _mark_chunk_generated(vw, cx, cy, cz):
    if _voxel_chunk_valid(vw, cx, cy, cz) == false:
        return
    let key = voxel_chunk_key(cx, cy, cz)
    vw["generated_chunks"][key] = {"x": cx, "y": cy, "z": cz}

proc voxel_generated_chunk_count(vw):
    return len(dict_keys(vw["generated_chunks"]))

proc _mark_voxel_dirty_chunks(vw, gx, gy, gz):
    let center = voxel_chunk_coords(vw, gx, gy, gz)
    let dx = -1
    while dx <= 1:
        let dy = -1
        while dy <= 1:
            let dz = -1
            while dz <= 1:
                _mark_chunk_dirty(vw, center["x"] + dx, center["y"] + dy, center["z"] + dz)
                dz = dz + 1
            dy = dy + 1
        dx = dx + 1

proc voxel_chunk_coords_world(vw, wx, wy, wz):
    let gx = math.floor(wx - vw["origin_x"])
    let gy = math.floor(wy)
    let gz = math.floor(wz - vw["origin_z"])
    return voxel_chunk_coords(vw, gx, gy, gz)

proc voxel_chunk_bounds(vw, cx, cy, cz):
    let cs = voxel_chunk_size(vw)
    let x0 = cx * cs
    let y0 = cy * cs
    let z0 = cz * cs
    let x1 = x0 + cs
    let y1 = y0 + cs
    let z1 = z0 + cs
    if x1 > vw["size_x"]:
        x1 = vw["size_x"]
    if y1 > vw["size_y"]:
        y1 = vw["size_y"]
    if z1 > vw["size_z"]:
        z1 = vw["size_z"]
    return {"x0": x0, "y0": y0, "z0": z0, "x1": x1, "y1": y1, "z1": z1}

proc voxel_chunk_world_center(vw, cx, cy, cz):
    let bounds = voxel_chunk_bounds(vw, cx, cy, cz)
    let wx = vw["origin_x"] + (bounds["x0"] + bounds["x1"]) / 2.0
    let wy = (bounds["y0"] + bounds["y1"]) / 2.0
    let wz = vw["origin_z"] + (bounds["z0"] + bounds["z1"]) / 2.0
    return vec3(wx, wy, wz)

proc voxel_chunk_solid_count(vw, cx, cy, cz):
    let bounds = voxel_chunk_bounds(vw, cx, cy, cz)
    let count = 0
    let gx = bounds["x0"]
    while gx < bounds["x1"]:
        let gy = bounds["y0"]
        while gy < bounds["y1"]:
            let gz = bounds["z0"]
            while gz < bounds["z1"]:
                if get_voxel(vw, gx, gy, gz) != 0:
                    count = count + 1
                gz = gz + 1
            gy = gy + 1
        gx = gx + 1
    return count

proc voxel_nonempty_chunks(vw):
    let chunks = []
    let cx = 0
    while cx < voxel_chunk_count_x(vw):
        let cy = 0
        while cy < voxel_chunk_count_y(vw):
            let cz = 0
            while cz < voxel_chunk_count_z(vw):
                let solid_count = voxel_chunk_solid_count(vw, cx, cy, cz)
                if solid_count > 0:
                    let entry = {"x": cx, "y": cy, "z": cz, "solid_count": solid_count}
                    push(chunks, entry)
                cz = cz + 1
            cy = cy + 1
        cx = cx + 1
    return chunks

proc voxel_manifest_chunks(vw):
    let manifest = {}
    let existing = voxel_nonempty_chunks(vw)
    let i = 0
    while i < len(existing):
        let chunk = existing[i]
        manifest[voxel_chunk_key(chunk["x"], chunk["y"], chunk["z"])] = chunk
        i = i + 1
    let generated_keys = dict_keys(vw["generated_chunks"])
    let gi = 0
    while gi < len(generated_keys):
        let key = generated_keys[gi]
        if dict_has(manifest, key) == false:
            let chunk = vw["generated_chunks"][key]
            manifest[key] = {"x": chunk["x"], "y": chunk["y"], "z": chunk["z"], "solid_count": 0}
        gi = gi + 1
    return dict_values(manifest)

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
    _clear_voxel_mesh_cache(vw)
    let i = 0
    while i < len(vw["blocks"]):
        vw["blocks"][i] = 0
        i = i + 1
    vw["solid_count"] = 0
    vw["dirty_chunks"] = {}
    vw["generated_chunks"] = {}
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

proc _set_voxel_if_in_bounds(vw, gx, gy, gz, block_id):
    if voxel_in_bounds(vw, gx, gy, gz):
        set_voxel(vw, gx, gy, gz, block_id)

proc _set_voxel_if_in_chunk(vw, bounds, gx, gy, gz, block_id):
    if gx < bounds["x0"] or gx >= bounds["x1"]:
        return
    if gy < bounds["y0"] or gy >= bounds["y1"]:
        return
    if gz < bounds["z0"] or gz >= bounds["z1"]:
        return
    _set_voxel_if_in_bounds(vw, gx, gy, gz, block_id)

proc _template_tree_metric(gx, gz, seed):
    return math.sin((gx + seed) * 0.73) + math.cos((gz - seed) * 0.61) + math.sin((gx * 0.19) + (gz * 0.27) + seed * 0.11)

proc _template_has_tree(vw, gx, gz, seed):
    if gx < 2 or gz < 2 or gx >= vw["size_x"] - 2 or gz >= vw["size_z"] - 2:
        return false
    let metric = _template_tree_metric(gx, gz, seed)
    if metric < 2.15:
        return false
    let surface_y = _template_height(vw, gx, gz, seed) - 1
    return surface_y + 5 < vw["size_y"]

proc _apply_template_tree_chunk(vw, bounds, gx, gz, seed):
    if _template_has_tree(vw, gx, gz, seed) == false:
        return false
    let ground_y = _template_height(vw, gx, gz, seed) - 1
    if ground_y < 0:
        return false
    let ty = ground_y + 1
    let i = 0
    while i < 3:
        _set_voxel_if_in_chunk(vw, bounds, gx, ty + i, gz, 4)
        i = i + 1
    let lx = gx - 1
    while lx <= gx + 1:
        let lz = gz - 1
        while lz <= gz + 1:
            _set_voxel_if_in_chunk(vw, bounds, lx, ty + 3, lz, 5)
            if lx == gx or lz == gz:
                _set_voxel_if_in_chunk(vw, bounds, lx, ty + 4, lz, 5)
            lz = lz + 1
        lx = lx + 1
    _set_voxel_if_in_chunk(vw, bounds, gx, ty + 5, gz, 5)
    return true

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

proc generate_voxel_template_chunk(vw, cx, cy, cz, seed):
    if _voxel_chunk_valid(vw, cx, cy, cz) == false:
        return false
    let chunk_key = voxel_chunk_key(cx, cy, cz)
    if dict_has(vw["generated_chunks"], chunk_key):
        return false
    let bounds = voxel_chunk_bounds(vw, cx, cy, cz)
    let gx = bounds["x0"]
    while gx < bounds["x1"]:
        let gz = bounds["z0"]
        while gz < bounds["z1"]:
            let h = _template_height(vw, gx, gz, seed)
            let y = bounds["y0"]
            while y < bounds["y1"]:
                let block_id = 0
                if y < h:
                    block_id = 3
                    if y == h - 1:
                        block_id = 1
                    else:
                        if y >= h - 3:
                            block_id = 2
                _set_voxel_if_in_bounds(vw, gx, y, gz, block_id)
                y = y + 1
            gz = gz + 1
        gx = gx + 1

    let tx = bounds["x0"] - 1
    while tx <= bounds["x1"]:
        let tz = bounds["z0"] - 1
        while tz <= bounds["z1"]:
            _apply_template_tree_chunk(vw, bounds, tx, tz, seed)
            tz = tz + 1
        tx = tx + 1
    _mark_chunk_generated(vw, cx, cy, cz)
    return true

proc ensure_voxel_generated_radius(vw, wx, wy, wz, chunk_radius, seed):
    vw["template_seed"] = seed
    let center_chunk = voxel_chunk_coords_world(vw, wx, wy, wz)
    let generated_now = 0
    let cx = center_chunk["x"] - chunk_radius
    while cx <= center_chunk["x"] + chunk_radius:
        let cy = center_chunk["y"] - chunk_radius
        while cy <= center_chunk["y"] + chunk_radius:
            let cz = center_chunk["z"] - chunk_radius
            while cz <= center_chunk["z"] + chunk_radius:
                if generate_voxel_template_chunk(vw, cx, cy, cz, seed):
                    generated_now = generated_now + 1
                cz = cz + 1
            cy = cy + 1
        cx = cx + 1
    return generated_now

proc generate_voxel_template_world(vw, seed):
    clear_voxel_world(vw)
    vw["template_seed"] = seed
    let cx = 0
    while cx < voxel_chunk_count_x(vw):
        let cy = 0
        while cy < voxel_chunk_count_y(vw):
            let cz = 0
            while cz < voxel_chunk_count_z(vw):
                generate_voxel_template_chunk(vw, cx, cy, cz, seed)
                cz = cz + 1
            cy = cy + 1
        cx = cx + 1

proc voxel_world_to_sage(vw):
    let data = {}
    data["size_x"] = vw["size_x"]
    data["size_y"] = vw["size_y"]
    data["size_z"] = vw["size_z"]
    data["origin_x"] = vw["origin_x"]
    data["origin_z"] = vw["origin_z"]
    data["solid_count"] = vw["solid_count"]
    data["template_seed"] = vw["template_seed"]
    data["chunk_size"] = voxel_chunk_size(vw)
    data["blocks"] = _clone_sage(vw["blocks"])
    data["palette"] = _clone_sage(vw["palette"])
    data["palette_ids"] = _clone_sage(vw["palette_ids"])
    return data

proc voxel_world_manifest_to_sage(vw):
    let data = {}
    data["size_x"] = vw["size_x"]
    data["size_y"] = vw["size_y"]
    data["size_z"] = vw["size_z"]
    data["origin_x"] = vw["origin_x"]
    data["origin_z"] = vw["origin_z"]
    data["solid_count"] = vw["solid_count"]
    data["template_seed"] = vw["template_seed"]
    data["chunk_size"] = voxel_chunk_size(vw)
    data["palette"] = _clone_sage(vw["palette"])
    data["palette_ids"] = _clone_sage(vw["palette_ids"])
    data["chunks"] = voxel_manifest_chunks(vw)
    return data

proc voxel_chunk_to_sage(vw, cx, cy, cz):
    let chunk = {}
    chunk["x"] = cx
    chunk["y"] = cy
    chunk["z"] = cz
    chunk["chunk_size"] = voxel_chunk_size(vw)
    let bounds = voxel_chunk_bounds(vw, cx, cy, cz)
    chunk["size_x"] = bounds["x1"] - bounds["x0"]
    chunk["size_y"] = bounds["y1"] - bounds["y0"]
    chunk["size_z"] = bounds["z1"] - bounds["z0"]
    let blocks = []
    let solid_count = 0
    let gx = bounds["x0"]
    while gx < bounds["x1"]:
        let gy = bounds["y0"]
        while gy < bounds["y1"]:
            let gz = bounds["z0"]
            while gz < bounds["z1"]:
                let block_id = get_voxel(vw, gx, gy, gz)
                push(blocks, block_id)
                if block_id != 0:
                    solid_count = solid_count + 1
                gz = gz + 1
            gy = gy + 1
        gx = gx + 1
    chunk["solid_count"] = solid_count
    chunk["blocks"] = blocks
    return chunk

proc voxel_world_from_sage(data):
    if data == nil:
        return nil
    if dict_has(data, "size_x") == false or dict_has(data, "size_y") == false or dict_has(data, "size_z") == false:
        return nil
    let vw = create_voxel_world(data["size_x"], data["size_y"], data["size_z"])
    if dict_has(data, "origin_x"):
        vw["origin_x"] = data["origin_x"]
    if dict_has(data, "origin_z"):
        vw["origin_z"] = data["origin_z"]
    if dict_has(data, "template_seed"):
        vw["template_seed"] = data["template_seed"]
    if dict_has(data, "chunk_size"):
        vw["chunk_size"] = data["chunk_size"]
    if dict_has(data, "palette") and data["palette"] != nil:
        vw["palette"] = _clone_sage(data["palette"])
    if dict_has(data, "palette_ids") and data["palette_ids"] != nil:
        vw["palette_ids"] = _clone_sage(data["palette_ids"])
    let blocks = nil
    if dict_has(data, "blocks"):
        blocks = data["blocks"]
    let solid_count = 0
    if blocks != nil and len(blocks) == len(vw["blocks"]):
        let i = 0
        while i < len(blocks):
            vw["blocks"][i] = blocks[i]
            if blocks[i] != 0:
                solid_count = solid_count + 1
            i = i + 1
    vw["solid_count"] = solid_count
    vw["mesh_data"] = {}
    vw["gpu_meshes"] = {}
    vw["draws"] = []
    vw["dirty_chunks"] = {}
    vw["generated_chunks"] = {}
    _reset_voxel_stream_state(vw)
    vw["dirty"] = true
    return vw

proc voxel_world_from_manifest(data):
    if data == nil:
        return nil
    let vw = voxel_world_from_sage(data)
    if vw == nil:
        return nil
    clear_voxel_world(vw)
    vw["template_seed"] = 0.0
    if dict_has(data, "template_seed"):
        vw["template_seed"] = data["template_seed"]
    return vw

proc serialize_voxel_world(vw):
    let node = cJSON_FromSage(voxel_world_to_sage(vw))
    if node == nil:
        return nil
    let json_str = cJSON_Print(node)
    cJSON_Delete(node)
    return json_str

proc deserialize_voxel_world(json_str):
    let root = cJSON_Parse(json_str)
    if root == nil:
        return nil
    let data = cJSON_ToSage(root)
    cJSON_Delete(root)
    return voxel_world_from_sage(data)

proc save_voxel_world(vw, file_path):
    let json_str = serialize_voxel_world(vw)
    if json_str == nil:
        return false
    io.writefile(file_path, json_str)
    return true

proc load_voxel_world(file_path):
    if io.exists(file_path) == false:
        return nil
    let content = io.readfile(file_path)
    if content == nil or content == "":
        return nil
    return deserialize_voxel_world(content)

proc _voxel_chunk_file_path(base_path, cx, cy, cz):
    return base_path + ".chunk_" + str(cx) + "_" + str(cy) + "_" + str(cz) + ".json"

proc save_voxel_world_chunks(vw, manifest_path):
    let manifest = voxel_world_manifest_to_sage(vw)
    let chunks = manifest["chunks"]
    let i = 0
    while i < len(chunks):
        let chunk = chunks[i]
        let chunk_path = _voxel_chunk_file_path(manifest_path, chunk["x"], chunk["y"], chunk["z"])
        let chunk_node = cJSON_FromSage(voxel_chunk_to_sage(vw, chunk["x"], chunk["y"], chunk["z"]))
        if chunk_node == nil:
            return false
        let chunk_json = cJSON_Print(chunk_node)
        cJSON_Delete(chunk_node)
        if chunk_json == nil:
            return false
        io.writefile(chunk_path, chunk_json)
        chunk["path"] = chunk_path
        i = i + 1
    let manifest_node = cJSON_FromSage(manifest)
    if manifest_node == nil:
        return false
    let manifest_json = cJSON_Print(manifest_node)
    cJSON_Delete(manifest_node)
    if manifest_json == nil:
        return false
    io.writefile(manifest_path, manifest_json)
    return true

proc load_voxel_world_chunks(manifest_path):
    if io.exists(manifest_path) == false:
        return nil
    let manifest_root = cJSON_Parse(io.readfile(manifest_path))
    if manifest_root == nil:
        return nil
    let manifest = cJSON_ToSage(manifest_root)
    cJSON_Delete(manifest_root)
    let vw = voxel_world_from_manifest(manifest)
    if vw == nil:
        return nil
    if dict_has(manifest, "chunks") == false:
        return vw
    let chunks = manifest["chunks"]
    let i = 0
    while i < len(chunks):
        let info = chunks[i]
        _mark_chunk_generated(vw, info["x"], info["y"], info["z"])
        if dict_has(info, "path") and io.exists(info["path"]):
            let chunk_root = cJSON_Parse(io.readfile(info["path"]))
            if chunk_root != nil:
                let chunk = cJSON_ToSage(chunk_root)
                cJSON_Delete(chunk_root)
                let bounds = voxel_chunk_bounds(vw, chunk["x"], chunk["y"], chunk["z"])
                let blocks = chunk["blocks"]
                let bi = 0
                let gx = bounds["x0"]
                while gx < bounds["x1"]:
                    let gy = bounds["y0"]
                    while gy < bounds["y1"]:
                        let gz = bounds["z0"]
                        while gz < bounds["z1"]:
                            if bi < len(blocks):
                                set_voxel(vw, gx, gy, gz, blocks[bi])
                            bi = bi + 1
                            gz = gz + 1
                        gy = gy + 1
                    gx = gx + 1
        i = i + 1
    return vw

proc _voxel_face_group(face_name):
    if face_name == "top":
        return "top"
    if face_name == "bottom":
        return "bottom"
    return "side"

proc _mesh_bucket(meshes, block_id, face_group):
    let key = _face_palette_key(block_id, face_group)
    if dict_has(meshes, key):
        return meshes[key]
    let bucket = {}
    bucket["block_id"] = block_id
    bucket["face_group"] = face_group
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

proc _build_voxel_meshes_range(vw, x0, y0, z0, x1, y1, z1):
    let meshes = {}
    let gx = x0
    while gx < x1:
        let gy = y0
        while gy < y1:
            let gz = z0
            while gz < z1:
                let block_id = get_voxel(vw, gx, gy, gz)
                if block_id != 0:
                    let world_min = voxel_block_world_min(vw, gx, gy, gz)
                    if get_voxel(vw, gx, gy, gz + 1) == 0:
                        let bucket = _mesh_bucket(meshes, block_id, _voxel_face_group("front"))
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "front")
                    if get_voxel(vw, gx, gy, gz - 1) == 0:
                        let bucket = _mesh_bucket(meshes, block_id, _voxel_face_group("back"))
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "back")
                    if get_voxel(vw, gx + 1, gy, gz) == 0:
                        let bucket = _mesh_bucket(meshes, block_id, _voxel_face_group("right"))
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "right")
                    if get_voxel(vw, gx - 1, gy, gz) == 0:
                        let bucket = _mesh_bucket(meshes, block_id, _voxel_face_group("left"))
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "left")
                    if get_voxel(vw, gx, gy + 1, gz) == 0:
                        let bucket = _mesh_bucket(meshes, block_id, _voxel_face_group("top"))
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "top")
                    if get_voxel(vw, gx, gy - 1, gz) == 0:
                        let bucket = _mesh_bucket(meshes, block_id, _voxel_face_group("bottom"))
                        _append_voxel_face(bucket, world_min[0], world_min[1], world_min[2], "bottom")
                gz = gz + 1
            gy = gy + 1
        gx = gx + 1

    let built = {}
    let pi = 0
    let face_groups = ["top", "side", "bottom"]
    while pi < len(vw["palette_ids"]):
        let block_id = vw["palette_ids"][pi]
        let fi = 0
        while fi < len(face_groups):
            let face_group = face_groups[fi]
            let key = _face_palette_key(block_id, face_group)
            if dict_has(meshes, key):
                let bucket = meshes[key]
                if bucket["face_count"] > 0 and len(bucket["vertices"]) > 0 and len(bucket["indices"]) > 0:
                    let mesh_data = {}
                    mesh_data["block_id"] = block_id
                    mesh_data["face_group"] = face_group
                    mesh_data["vertices"] = bucket["vertices"]
                    mesh_data["indices"] = bucket["indices"]
                    mesh_data["vertex_count"] = len(bucket["vertices"]) / 8
                    mesh_data["index_count"] = len(bucket["indices"])
                    mesh_data["has_normals"] = true
                    mesh_data["has_uvs"] = true
                    mesh_data["face_count"] = bucket["face_count"]
                    built[key] = mesh_data
            fi = fi + 1
        pi = pi + 1
    return built

proc build_voxel_meshes(vw):
    let built = _build_voxel_meshes_range(vw, 0, 0, 0, vw["size_x"], vw["size_y"], vw["size_z"])
    vw["mesh_data"] = built
    return built

proc build_voxel_chunk_meshes(vw, cx, cy, cz):
    let bounds = voxel_chunk_bounds(vw, cx, cy, cz)
    return _build_voxel_meshes_range(vw, bounds["x0"], bounds["y0"], bounds["z0"], bounds["x1"], bounds["y1"], bounds["z1"])

proc _build_uploaded_voxel_chunk_draws(vw, cx, cy, cz):
    from mesh import upload_mesh
    let built = build_voxel_chunk_meshes(vw, cx, cy, cz)
    let draws = []
    let pi = 0
    let face_groups = ["top", "side", "bottom"]
    while pi < len(vw["palette_ids"]):
        let block_id = vw["palette_ids"][pi]
        let fi = 0
        while fi < len(face_groups):
            let face_group = face_groups[fi]
            let key = _face_palette_key(block_id, face_group)
            if dict_has(built, key):
                let mesh_data = built[key]
                let gpu_mesh = upload_mesh(mesh_data)
                let draw = {}
                draw["block_id"] = block_id
                draw["face_group"] = face_group
                draw["gpu_mesh"] = gpu_mesh
                draw["surface"] = voxel_block_face_surface(vw, block_id, face_group)
                draw["name"] = voxel_block_name(vw, block_id) + " " + face_group
                draw["face_count"] = mesh_data["face_count"]
                draw["chunk_x"] = cx
                draw["chunk_y"] = cy
                draw["chunk_z"] = cz
                draw["chunk_key"] = voxel_chunk_key(cx, cy, cz)
                draw["chunk_center"] = voxel_chunk_world_center(vw, cx, cy, cz)
                push(draws, draw)
            fi = fi + 1
        pi = pi + 1
    return {"mesh_data": built, "draws": draws}

proc _remove_stream_chunk(vw, chunk_key):
    if dict_has(vw["stream_chunks"], chunk_key) == false:
        return
    let draws = vw["stream_chunks"][chunk_key]
    let di = 0
    while di < len(draws):
        _destroy_voxel_gpu_mesh(draws[di]["gpu_mesh"])
        di = di + 1
    dict_delete(vw["stream_chunks"], chunk_key)

proc _refresh_stream_chunk(vw, cx, cy, cz):
    let chunk_key = voxel_chunk_key(cx, cy, cz)
    _remove_stream_chunk(vw, chunk_key)
    let uploaded = _build_uploaded_voxel_chunk_draws(vw, cx, cy, cz)
    vw["stream_chunks"][chunk_key] = uploaded["draws"]
    if dict_has(vw["dirty_chunks"], chunk_key):
        dict_delete(vw["dirty_chunks"], chunk_key)

proc rebuild_voxel_world(vw):
    _clear_voxel_mesh_cache(vw)
    let gpu_meshes = {}
    let draws = []
    let all_mesh_data = {}
    let cx = 0
    while cx < voxel_chunk_count_x(vw):
        let cy = 0
        while cy < voxel_chunk_count_y(vw):
            let cz = 0
            while cz < voxel_chunk_count_z(vw):
                let chunk_key = voxel_chunk_key(cx, cy, cz)
                let uploaded = _build_uploaded_voxel_chunk_draws(vw, cx, cy, cz)
                let built = uploaded["mesh_data"]
                let chunk_draws = uploaded["draws"]
                let di = 0
                while di < len(chunk_draws):
                    let draw = chunk_draws[di]
                    let draw_key = chunk_key + ":" + _palette_key(draw["block_id"])
                    gpu_meshes[draw_key] = draw["gpu_mesh"]
                    all_mesh_data[draw_key] = built[_palette_key(draw["block_id"])]
                    push(draws, draw)
                    di = di + 1
                cz = cz + 1
            cy = cy + 1
        cx = cx + 1
    vw["gpu_meshes"] = gpu_meshes
    vw["mesh_data"] = all_mesh_data
    vw["draws"] = draws
    vw["dirty_chunks"] = {}
    vw["dirty"] = false
    return draws

proc voxel_draws(vw):
    if vw["dirty"]:
        return rebuild_voxel_world(vw)
    return vw["draws"]

proc voxel_visible_draws(vw, wx, wy, wz, chunk_radius):
    let center_chunk = voxel_chunk_coords_world(vw, wx, wy, wz)
    let wanted = {}
    let cx = center_chunk["x"] - chunk_radius
    while cx <= center_chunk["x"] + chunk_radius:
        let cy = center_chunk["y"] - chunk_radius
        while cy <= center_chunk["y"] + chunk_radius:
            let cz = center_chunk["z"] - chunk_radius
            while cz <= center_chunk["z"] + chunk_radius:
                if _voxel_chunk_valid(vw, cx, cy, cz):
                    let key = voxel_chunk_key(cx, cy, cz)
                    wanted[key] = {"x": cx, "y": cy, "z": cz}
                cz = cz + 1
            cy = cy + 1
        cx = cx + 1

    let loaded_keys = dict_keys(vw["stream_chunks"])
    let li = 0
    while li < len(loaded_keys):
        if dict_has(wanted, loaded_keys[li]) == false:
            _remove_stream_chunk(vw, loaded_keys[li])
        li = li + 1

    let wanted_keys = dict_keys(wanted)
    let wi = 0
    let max_refresh = 2
    if dict_has(vw, "max_stream_chunk_refresh"):
        max_refresh = vw["max_stream_chunk_refresh"]
    if max_refresh < 1:
        max_refresh = 1
    let refreshed = 0
    let pending_refresh = false
    while wi < len(wanted_keys):
        let key = wanted_keys[wi]
        let chunk = wanted[key]
        if dict_has(vw["stream_chunks"], key) == false or dict_has(vw["dirty_chunks"], key):
            if refreshed < max_refresh:
                _refresh_stream_chunk(vw, chunk["x"], chunk["y"], chunk["z"])
                refreshed = refreshed + 1
            else:
                pending_refresh = true
        wi = wi + 1

    let visible = []
    let ox = center_chunk["x"] - chunk_radius
    while ox <= center_chunk["x"] + chunk_radius:
        let oy = center_chunk["y"] - chunk_radius
        while oy <= center_chunk["y"] + chunk_radius:
            let oz = center_chunk["z"] - chunk_radius
            while oz <= center_chunk["z"] + chunk_radius:
                if _voxel_chunk_valid(vw, ox, oy, oz):
                    let key = voxel_chunk_key(ox, oy, oz)
                    if dict_has(vw["stream_chunks"], key):
                        let draws = vw["stream_chunks"][key]
                        let di = 0
                        while di < len(draws):
                            push(visible, draws[di])
                            di = di + 1
                oz = oz + 1
            oy = oy + 1
        ox = ox + 1

    vw["stream_draws"] = visible
    vw["stream_center_chunk"] = center_chunk
    vw["stream_chunk_radius"] = chunk_radius
    vw["dirty"] = pending_refresh or len(dict_keys(vw["dirty_chunks"])) > 0
    return visible

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
