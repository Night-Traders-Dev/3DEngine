gc_disable()
# -----------------------------------------
# asset_import.sage - Asset import pipeline for Forge Engine
# Loads glTF models, textures, and creates GPU-ready resources
# -----------------------------------------

import gpu
import io
import gltf_import
from mesh import upload_mesh
from math3d import vec3, quat_to_matrix, mat4_identity, mat4_translate, mat4_scale, mat4_mul

# ============================================================================
# Import a glTF file (mesh + materials + animations)
# Returns a complete asset dict ready for rendering
# ============================================================================
proc import_gltf(path):
    let gltf = gpu.load_gltf(path)
    if gltf == nil:
        print "IMPORT ERROR: Failed to load " + path
        return nil

    let asset = {}
    asset["name"] = path
    asset["source"] = path

    # Extract base directory for texture paths
    let base_dir = _extract_dir(path)

    # Upload meshes to GPU
    let gpu_meshes = []
    let meshes = gltf["meshes"]
    let mi = 0
    while mi < len(meshes):
        let mesh = meshes[mi]
        let prims = mesh["primitives"]
        let pi = 0
        while pi < len(prims):
            let prim = prims[pi]
            let mesh_data = {}
            mesh_data["vertices"] = prim["vertices"]
            mesh_data["indices"] = prim["indices"]
            mesh_data["vertex_count"] = prim["vertex_count"]
            mesh_data["index_count"] = prim["index_count"]
            mesh_data["has_normals"] = true
            mesh_data["has_uvs"] = true
            let gpu_mesh = upload_mesh(mesh_data)
            let entry = {}
            entry["gpu_mesh"] = gpu_mesh
            entry["mesh_name"] = mesh["name"]
            entry["mesh_index"] = mi
            entry["primitive_index"] = pi
            if dict_has(prim, "material"):
                entry["material_index"] = prim["material"]
            else:
                entry["material_index"] = -1
            push(gpu_meshes, entry)
            pi = pi + 1
        mi = mi + 1
    asset["gpu_meshes"] = gpu_meshes

    # Load textures referenced by materials
    let materials = gltf["materials"]
    let mat_list = []
    let mati = 0
    while mati < len(materials):
        let mat = materials[mati]
        let mat_info = {}
        mat_info["name"] = mat["name"]
        mat_info["albedo_color"] = [1.0, 1.0, 1.0, 1.0]
        if dict_has(mat, "albedo_r"):
            mat_info["albedo_color"] = [mat["albedo_r"], mat["albedo_g"], mat["albedo_b"], mat["albedo_a"]]
        mat_info["metallic"] = 0.0
        mat_info["roughness"] = 0.5
        if dict_has(mat, "metallic"):
            mat_info["metallic"] = mat["metallic"]
        if dict_has(mat, "roughness"):
            mat_info["roughness"] = mat["roughness"]
        # Load textures
        mat_info["albedo_tex"] = -1
        mat_info["normal_tex"] = -1
        mat_info["mr_tex"] = -1
        if dict_has(mat, "albedo_texture"):
            let tex_path = base_dir + "/" + mat["albedo_texture"]
            if io.exists(tex_path):
                mat_info["albedo_tex"] = gpu.load_texture(tex_path)
        if dict_has(mat, "normal_texture"):
            let tex_path = base_dir + "/" + mat["normal_texture"]
            if io.exists(tex_path):
                mat_info["normal_tex"] = gpu.load_texture(tex_path)
        if dict_has(mat, "mr_texture"):
            let tex_path = base_dir + "/" + mat["mr_texture"]
            if io.exists(tex_path):
                mat_info["mr_tex"] = gpu.load_texture(tex_path)
        push(mat_list, mat_info)
        mati = mati + 1
    asset["materials"] = mat_list

    # Nodes (scene hierarchy with transforms)
    let node_list = []
    let scene_gltf = gltf_import.load_gltf(path)
    if scene_gltf != nil and dict_has(scene_gltf, "nodes"):
        let nodes = scene_gltf["nodes"]
        let parent_map = {}
        let pi = 0
        while pi < len(nodes):
            let child_list = nodes[pi]["children"]
            let ci = 0
            while ci < len(child_list):
                parent_map[str(child_list[ci])] = pi
                ci = ci + 1
            pi = pi + 1
        let ni = 0
        while ni < len(nodes):
            let node = nodes[ni]
            let node_info = {}
            node_info["name"] = node["name"]
            node_info["mesh_index"] = node["mesh"]
            node_info["position"] = node["translation"]
            node_info["rotation"] = node["rotation"]
            node_info["scale"] = node["scale"]
            node_info["children"] = node["children"]
            node_info["parent"] = -1
            let sid = str(ni)
            if dict_has(parent_map, sid):
                node_info["parent"] = parent_map[sid]
            if dict_has(node, "matrix") and node["matrix"] != nil:
                node_info["matrix"] = node["matrix"]
            push(node_list, node_info)
            ni = ni + 1
    else:
        let nodes = gltf["nodes"]
        let ni = 0
        while ni < len(nodes):
            let node = nodes[ni]
            let node_info = {}
            node_info["name"] = node["name"]
            node_info["mesh_index"] = node["mesh"]
            node_info["position"] = vec3(node["tx"], node["ty"], node["tz"])
            node_info["rotation"] = [1.0, 0.0, 0.0, 0.0]
            node_info["scale"] = vec3(1.0, 1.0, 1.0)
            node_info["children"] = []
            node_info["parent"] = -1
            push(node_list, node_info)
            ni = ni + 1
    asset["nodes"] = node_list

    # Animations
    asset["animations"] = gltf["animations"]
    asset["animation_count"] = gltf["animation_count"]

    # Stats
    asset["mesh_count"] = len(gpu_meshes)
    asset["material_count"] = len(mat_list)
    asset["node_count"] = len(node_list)

    print "Imported: " + path + " (" + str(len(gpu_meshes)) + " meshes, " + str(len(mat_list)) + " materials)"
    return asset

proc imported_node_local_matrix(node):
    if node == nil:
        return mat4_identity()
    if dict_has(node, "matrix") and node["matrix"] != nil and len(node["matrix"]) == 16:
        return node["matrix"]
    let pos = vec3(0.0, 0.0, 0.0)
    let scl = vec3(1.0, 1.0, 1.0)
    let rot = [1.0, 0.0, 0.0, 0.0]
    if dict_has(node, "position"):
        pos = node["position"]
    if dict_has(node, "scale"):
        scl = node["scale"]
    if dict_has(node, "rotation"):
        rot = node["rotation"]
    return mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_mul(quat_to_matrix(rot), mat4_scale(scl[0], scl[1], scl[2])))

proc _imported_node_world(asset, node_index, cache):
    let key = str(node_index)
    if dict_has(cache, key):
        return cache[key]
    let node = asset["nodes"][node_index]
    let local = imported_node_local_matrix(node)
    let world = local
    if dict_has(node, "parent") and node["parent"] >= 0:
        let parent_world = _imported_node_world(asset, node["parent"], cache)
        world = mat4_mul(parent_world, local)
    cache[key] = world
    return world

proc imported_asset_draws(asset):
    if asset == nil:
        return []
    let draws = []
    if dict_has(asset, "nodes") == false or len(asset["nodes"]) == 0:
        let gi = 0
        while gi < len(asset["gpu_meshes"]):
            let gm = asset["gpu_meshes"][gi]
            push(draws, {"gpu_mesh": gm["gpu_mesh"], "material_index": gm["material_index"], "model": mat4_identity()})
            gi = gi + 1
        return draws
    let cache = {}
    let ni = 0
    while ni < len(asset["nodes"]):
        let node = asset["nodes"][ni]
        if dict_has(node, "mesh_index") and node["mesh_index"] >= 0:
            let node_model = _imported_node_world(asset, ni, cache)
            let gi = 0
            while gi < len(asset["gpu_meshes"]):
                let gm = asset["gpu_meshes"][gi]
                if dict_has(gm, "mesh_index") and gm["mesh_index"] == node["mesh_index"]:
                    push(draws, {"gpu_mesh": gm["gpu_mesh"], "material_index": gm["material_index"], "model": node_model, "node_index": ni, "node_name": node["name"]})
                gi = gi + 1
        ni = ni + 1
    if len(draws) == 0:
        let gi = 0
        while gi < len(asset["gpu_meshes"]):
            let gm = asset["gpu_meshes"][gi]
            push(draws, {"gpu_mesh": gm["gpu_mesh"], "material_index": gm["material_index"], "model": mat4_identity()})
            gi = gi + 1
    return draws

# ============================================================================
# Get the base directory from a file path
# ============================================================================
proc _extract_dir(path):
    let last_slash = -1
    let i = 0
    while i < len(path):
        if path[i] == "/":
            last_slash = i
        i = i + 1
    if last_slash < 0:
        return "."
    let result = ""
    i = 0
    while i < last_slash:
        result = result + path[i]
        i = i + 1
    return result

# ============================================================================
# Scan a directory for importable assets
# ============================================================================
proc scan_importable_assets(dir_path):
    let files = io.listdir(dir_path)
    if files == nil:
        return []
    let assets = []
    let i = 0
    while i < len(files):
        let f = files[i]
        let flen = len(f)
        if flen > 5:
            if endswith(f, ".gltf") or endswith(f, ".glb"):
                push(assets, {"name": f, "type": "model", "path": dir_path + "/" + f})
        if flen > 4:
            if endswith(f, ".png") or endswith(f, ".jpg"):
                push(assets, {"name": f, "type": "texture", "path": dir_path + "/" + f})
            if endswith(f, ".obj"):
                push(assets, {"name": f, "type": "model", "path": dir_path + "/" + f})
            if endswith(f, ".ttf"):
                push(assets, {"name": f, "type": "font", "path": dir_path + "/" + f})
        i = i + 1
    return assets

# ============================================================================
# Async asset loading (non-blocking)
# ============================================================================
let _async_load_queue = []
let _async_load_results = []

proc request_async_load(path, asset_type):
    push(_async_load_queue, {"path": path, "type": asset_type, "status": "pending"})

proc process_async_loads():
    # Process one load per frame to avoid blocking
    if len(_async_load_queue) == 0:
        return nil
    let req = _async_load_queue[0]
    # Remove from queue
    let new_queue = []
    let i = 1
    while i < len(_async_load_queue):
        push(new_queue, _async_load_queue[i])
        i = i + 1
    _async_load_queue = new_queue
    # Process the load
    let result = nil
    if req["type"] == "gltf":
        result = import_gltf(req["path"])
    if req["type"] == "texture":
        result = gpu.load_texture(req["path"])
    if result != nil:
        push(_async_load_results, {"path": req["path"], "type": req["type"], "result": result})
        print "Async loaded: " + req["path"]
    return result

proc get_async_results():
    let results = _async_load_results
    _async_load_results = []
    return results

proc has_pending_loads():
    return len(_async_load_queue) > 0

# ============================================================================
# Remote asset downloading
# ============================================================================
proc download_asset(url, local_path):
    # Uses SageLang's http module if available
    try:
        import http
        let result = http.download(url, local_path)
        if result:
            print "Downloaded: " + url + " -> " + local_path
            return true
        else:
            print "Download failed: " + url
            return false
    catch e:
        print "HTTP not available: " + str(e)
        return false
