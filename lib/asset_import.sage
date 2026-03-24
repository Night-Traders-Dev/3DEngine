gc_disable()
# -----------------------------------------
# asset_import.sage - Asset import pipeline for Forge Engine
# Loads glTF models, textures, and creates GPU-ready resources
# -----------------------------------------

import gpu
import io
from mesh import upload_mesh
from math3d import vec3

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
    let nodes = gltf["nodes"]
    let node_list = []
    let ni = 0
    while ni < len(nodes):
        let node = nodes[ni]
        let node_info = {}
        node_info["name"] = node["name"]
        node_info["mesh_index"] = node["mesh"]
        node_info["position"] = vec3(node["tx"], node["ty"], node["tz"])
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
