gc_disable()
# -----------------------------------------
# asset_import.sage - Asset import pipeline for Forge Engine
# Loads glTF models, textures, and creates GPU-ready resources
# -----------------------------------------

import gpu
import io
import math
import gltf_import
from mesh import upload_mesh
from math3d import vec3, v3_lerp, quat_to_matrix, quat_slerp
from math3d import mat4_identity, mat4_translate, mat4_scale, mat4_mul

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
    asset["animations"] = []
    asset["animation_count"] = 0
    if scene_gltf != nil and dict_has(scene_gltf, "animations"):
        asset["animations"] = scene_gltf["animations"]
        asset["animation_count"] = len(asset["animations"])
    else:
        asset["animations"] = gltf["animations"]
        asset["animation_count"] = gltf["animation_count"]

    # Stats
    asset["mesh_count"] = len(gpu_meshes)
    asset["material_count"] = len(mat_list)
    asset["node_count"] = len(node_list)

    print "Imported: " + path + " (" + str(len(gpu_meshes)) + " meshes, " + str(len(mat_list)) + " materials)"
    return asset

proc _imported_node_pose(node, override_pose):
    let pose = {}
    pose["position"] = vec3(0.0, 0.0, 0.0)
    pose["scale"] = vec3(1.0, 1.0, 1.0)
    pose["rotation"] = [1.0, 0.0, 0.0, 0.0]
    pose["matrix"] = nil
    if node != nil:
        if dict_has(node, "position"):
            pose["position"] = node["position"]
        if dict_has(node, "scale"):
            pose["scale"] = node["scale"]
        if dict_has(node, "rotation"):
            pose["rotation"] = node["rotation"]
        if dict_has(node, "matrix") and node["matrix"] != nil:
            pose["matrix"] = node["matrix"]
    if override_pose != nil:
        if dict_has(override_pose, "position"):
            pose["position"] = override_pose["position"]
        if dict_has(override_pose, "scale"):
            pose["scale"] = override_pose["scale"]
        if dict_has(override_pose, "rotation"):
            pose["rotation"] = override_pose["rotation"]
        if dict_has(override_pose, "matrix"):
            pose["matrix"] = override_pose["matrix"]
    return pose

proc imported_node_local_matrix(node, override_pose):
    if node == nil:
        return mat4_identity()
    let pose = _imported_node_pose(node, override_pose)
    if pose["matrix"] != nil and len(pose["matrix"]) == 16:
        return pose["matrix"]
    let pos = pose["position"]
    let scl = pose["scale"]
    let rot = pose["rotation"]
    return mat4_mul(mat4_translate(pos[0], pos[1], pos[2]), mat4_mul(quat_to_matrix(rot), mat4_scale(scl[0], scl[1], scl[2])))

proc _imported_node_world(asset, node_index, cache, overrides):
    let key = str(node_index)
    if dict_has(cache, key):
        return cache[key]
    let node = asset["nodes"][node_index]
    let override_pose = nil
    if overrides != nil and dict_has(overrides, key):
        override_pose = overrides[key]
    let local = imported_node_local_matrix(node, override_pose)
    let world = local
    if dict_has(node, "parent") and node["parent"] >= 0:
        let parent_world = _imported_node_world(asset, node["parent"], cache, overrides)
        world = mat4_mul(parent_world, local)
    cache[key] = world
    return world

proc _normalized_clip_name(clip_name):
    if clip_name == nil:
        return ""
    let sep = " :: "
    let last = -1
    let i = 0
    while i <= len(clip_name) - len(sep):
        if clip_name[i] == " " and clip_name[i + 1] == ":" and clip_name[i + 2] == ":" and clip_name[i + 3] == " ":
            last = i
        i = i + 1
    if last < 0:
        return clip_name
    let out = ""
    i = last + len(sep)
    while i < len(clip_name):
        out = out + clip_name[i]
        i = i + 1
    return out

proc imported_animation_clip_names(asset):
    let clip_names = []
    if asset == nil or dict_has(asset, "animations") == false:
        return clip_names
    let i = 0
    while i < len(asset["animations"]):
        let anim = asset["animations"][i]
        let name = "Animation_" + str(i)
        if dict_has(anim, "name") and anim["name"] != "":
            name = anim["name"]
        push(clip_names, name)
        i = i + 1
    return clip_names

proc imported_animation_index(asset, clip_name):
    let clip_names = imported_animation_clip_names(asset)
    if len(clip_names) == 0:
        return -1
    let requested = _normalized_clip_name(clip_name)
    if requested == "":
        return 0
    let i = 0
    while i < len(clip_names):
        if clip_names[i] == requested:
            return i
        i = i + 1
    return -1

proc imported_animation_duration(asset, clip_name):
    let anim = resolve_imported_animation(asset, clip_name)
    if anim == nil or dict_has(anim, "duration") == false:
        return 0.0
    return anim["duration"]

proc create_imported_animation_state(asset, clip_name):
    let state = {}
    state["clip"] = ""
    state["playing"] = true
    state["time"] = 0.0
    state["speed"] = 1.0
    state["looping"] = true
    let clip_names = imported_animation_clip_names(asset)
    if len(clip_names) == 0:
        return state
    let idx = imported_animation_index(asset, clip_name)
    if idx < 0:
        idx = 0
    state["clip"] = clip_names[idx]
    let anim = asset["animations"][idx]
    if dict_has(anim, "looping"):
        state["looping"] = anim["looping"]
    return state

proc sync_imported_animation_state(asset, animation_state):
    if animation_state == nil:
        return nil
    let clip_names = imported_animation_clip_names(asset)
    if len(clip_names) == 0:
        if dict_has(animation_state, "clip") == false:
            animation_state["clip"] = ""
        if dict_has(animation_state, "playing") == false:
            animation_state["playing"] = true
        if dict_has(animation_state, "time") == false:
            animation_state["time"] = 0.0
        if dict_has(animation_state, "speed") == false:
            animation_state["speed"] = 1.0
        if dict_has(animation_state, "looping") == false:
            animation_state["looping"] = true
        return animation_state
    let idx = 0
    if dict_has(animation_state, "clip"):
        idx = imported_animation_index(asset, animation_state["clip"])
        if idx < 0:
            idx = 0
    animation_state["clip"] = clip_names[idx]
    if dict_has(animation_state, "playing") == false:
        animation_state["playing"] = true
    if dict_has(animation_state, "time") == false:
        animation_state["time"] = 0.0
    if dict_has(animation_state, "speed") == false:
        animation_state["speed"] = 1.0
    if dict_has(animation_state, "looping") == false:
        let anim = asset["animations"][idx]
        if dict_has(anim, "looping"):
            animation_state["looping"] = anim["looping"]
        else:
            animation_state["looping"] = true
    return animation_state

proc cycle_imported_animation_clip(asset, animation_state, direction):
    if animation_state == nil:
        return false
    let clip_names = imported_animation_clip_names(asset)
    if len(clip_names) == 0:
        return false
    sync_imported_animation_state(asset, animation_state)
    let idx = imported_animation_index(asset, animation_state["clip"])
    if idx < 0:
        idx = 0
    let next_idx = idx + direction
    if next_idx < 0:
        next_idx = len(clip_names) - 1
    if next_idx >= len(clip_names):
        next_idx = 0
    animation_state["clip"] = clip_names[next_idx]
    animation_state["time"] = 0.0
    let anim = asset["animations"][next_idx]
    if dict_has(anim, "looping"):
        animation_state["looping"] = anim["looping"]
    return true

proc step_imported_animation_time(asset, animation_state, delta_time):
    if animation_state == nil:
        return 0.0
    sync_imported_animation_state(asset, animation_state)
    let time_value = animation_state["time"] + delta_time
    let duration = imported_animation_duration(asset, animation_state["clip"])
    let looping = true
    if dict_has(animation_state, "looping"):
        looping = animation_state["looping"]
    if duration > 0.0001:
        if looping:
            time_value = time_value - math.floor(time_value / duration) * duration
        else:
            if time_value < 0.0:
                time_value = 0.0
            if time_value > duration:
                time_value = duration
    else:
        if time_value < 0.0:
            time_value = 0.0
    animation_state["time"] = time_value
    return time_value

proc advance_imported_animation_state(asset, animation_state, dt):
    if animation_state == nil:
        return nil
    sync_imported_animation_state(asset, animation_state)
    let delta_time = 0.0
    if dict_has(animation_state, "playing") and animation_state["playing"]:
        let speed = 1.0
        if dict_has(animation_state, "speed"):
            speed = animation_state["speed"]
        delta_time = dt * speed
    step_imported_animation_time(asset, animation_state, delta_time)
    return animation_state

proc resolve_imported_animation(asset, clip_name):
    if asset == nil or dict_has(asset, "animations") == false or len(asset["animations"]) == 0:
        return nil
    let requested = _normalized_clip_name(clip_name)
    if requested != "":
        let i = 0
        while i < len(asset["animations"]):
            let anim = asset["animations"][i]
            if dict_has(anim, "name") and anim["name"] == requested:
                return anim
            i = i + 1
    return asset["animations"][0]

proc _animation_sample_time(anim, animation_state):
    let sample_time = 0.0
    if animation_state != nil and dict_has(animation_state, "time"):
        sample_time = animation_state["time"]
    let duration = 0.0
    if anim != nil and dict_has(anim, "duration"):
        duration = anim["duration"]
    let looping = true
    if anim != nil and dict_has(anim, "looping"):
        looping = anim["looping"]
    if animation_state != nil and dict_has(animation_state, "looping"):
        looping = animation_state["looping"]
    if duration > 0.0001:
        if looping:
            sample_time = sample_time - math.floor(sample_time / duration) * duration
        else:
            if sample_time < 0.0:
                sample_time = 0.0
            if sample_time > duration:
                sample_time = duration
    return sample_time

proc _sample_imported_channel(channel, sample_time):
    if channel == nil or dict_has(channel, "times") == false or dict_has(channel, "values") == false:
        return nil
    let times = channel["times"]
    let values = channel["values"]
    if len(times) == 0 or len(values) == 0:
        return nil
    if len(times) == 1 or sample_time <= times[0]:
        return values[0]
    let last_index = len(times) - 1
    if sample_time >= times[last_index]:
        if last_index < len(values):
            return values[last_index]
        return values[len(values) - 1]
    let i = 0
    while i < len(times) - 1:
        let ta = times[i]
        let tb = times[i + 1]
        if sample_time <= tb:
            let t = 0.0
            let dt = tb - ta
            if dt > 0.000001:
                t = (sample_time - ta) / dt
            if t < 0.0:
                t = 0.0
            if t > 1.0:
                t = 1.0
            if dict_has(channel, "interpolation") and channel["interpolation"] == "STEP":
                return values[i]
            if channel["path"] == "rotation":
                return quat_slerp(values[i], values[i + 1], t)
            return v3_lerp(values[i], values[i + 1], t)
        i = i + 1
    return values[len(values) - 1]

proc _sample_imported_animation_overrides(asset, animation_state):
    let overrides = {}
    if asset == nil or animation_state == nil:
        return overrides
    sync_imported_animation_state(asset, animation_state)
    let clip_name = ""
    if dict_has(animation_state, "clip"):
        clip_name = animation_state["clip"]
    let anim = resolve_imported_animation(asset, clip_name)
    if anim == nil:
        return overrides
    let sample_time = _animation_sample_time(anim, animation_state)
    let ci = 0
    while ci < len(anim["channels"]):
        let channel = anim["channels"][ci]
        let value = _sample_imported_channel(channel, sample_time)
        if value != nil:
            let key = str(channel["node"])
            let pose = {}
            if dict_has(overrides, key):
                pose = overrides[key]
            if channel["path"] == "translation":
                pose["position"] = value
            if channel["path"] == "rotation":
                pose["rotation"] = value
            if channel["path"] == "scale":
                pose["scale"] = value
            overrides[key] = pose
        ci = ci + 1
    return overrides

proc imported_asset_draws(asset, animation_state):
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
    let overrides = _sample_imported_animation_overrides(asset, animation_state)
    let ni = 0
    while ni < len(asset["nodes"]):
        let node = asset["nodes"][ni]
        if dict_has(node, "mesh_index") and node["mesh_index"] >= 0:
            let node_model = _imported_node_world(asset, ni, cache, overrides)
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
