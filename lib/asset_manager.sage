gc_disable()
# -----------------------------------------
# asset_manager.sage - Asset management for Sage Engine
# Caches loaded resources, tracks references, supports reload
# -----------------------------------------

import gpu
import io
from mesh import cube_mesh, plane_mesh, sphere_mesh, upload_mesh, load_obj

# ============================================================================
# Asset Manager
# ============================================================================
proc create_asset_manager():
    let am = {}
    am["meshes"] = {}
    am["shaders"] = {}
    am["textures"] = {}
    am["files"] = {}
    am["stats"] = {}
    am["stats"]["loads"] = 0
    am["stats"]["cache_hits"] = 0
    am["stats"]["total_bytes"] = 0
    return am

# ============================================================================
# Mesh loading with caching
# ============================================================================
proc load_mesh(am, name, path):
    if dict_has(am["meshes"], name):
        am["stats"]["cache_hits"] = am["stats"]["cache_hits"] + 1
        return am["meshes"][name]
    let mesh_data = nil
    # Built-in primitives
    if path == "primitive:cube":
        mesh_data = cube_mesh()
    if path == "primitive:plane":
        mesh_data = plane_mesh(1.0)
    if path == "primitive:plane_large":
        mesh_data = plane_mesh(40.0)
    if path == "primitive:sphere":
        mesh_data = sphere_mesh(24, 24)
    if path == "primitive:sphere_low":
        mesh_data = sphere_mesh(12, 12)
    # OBJ files
    if mesh_data == nil:
        mesh_data = load_obj(path)
    if mesh_data == nil:
        print "ASSET ERROR: Failed to load mesh '" + name + "' from " + path
        return nil
    let gpu_mesh = upload_mesh(mesh_data)
    am["meshes"][name] = gpu_mesh
    am["stats"]["loads"] = am["stats"]["loads"] + 1
    return gpu_mesh

proc get_mesh(am, name):
    if dict_has(am["meshes"], name) == false:
        return nil
    am["stats"]["cache_hits"] = am["stats"]["cache_hits"] + 1
    return am["meshes"][name]

proc has_mesh(am, name):
    return dict_has(am["meshes"], name)

# ============================================================================
# Shader loading with caching
# ============================================================================
proc load_shader_asset(am, name, path, stage):
    if dict_has(am["shaders"], name):
        am["stats"]["cache_hits"] = am["stats"]["cache_hits"] + 1
        return am["shaders"][name]
    let stage_flag = gpu.STAGE_VERTEX
    if stage == "fragment":
        stage_flag = gpu.STAGE_FRAGMENT
    if stage == "compute":
        stage_flag = gpu.STAGE_COMPUTE
    let handle = gpu.load_shader(path, stage_flag)
    if handle < 0:
        print "ASSET ERROR: Failed to load shader '" + name + "' from " + path
        return -1
    am["shaders"][name] = handle
    am["stats"]["loads"] = am["stats"]["loads"] + 1
    return handle

proc get_shader(am, name):
    if dict_has(am["shaders"], name) == false:
        return -1
    return am["shaders"][name]

# ============================================================================
# Raw file loading with caching
# ============================================================================
proc load_file(am, path):
    if dict_has(am["files"], path):
        am["stats"]["cache_hits"] = am["stats"]["cache_hits"] + 1
        return am["files"][path]
    let content = io.readfile(path)
    if content == nil:
        return nil
    am["files"][path] = content
    am["stats"]["loads"] = am["stats"]["loads"] + 1
    return content

# ============================================================================
# Cache management
# ============================================================================
proc invalidate_mesh(am, name):
    if dict_has(am["meshes"], name):
        dict_delete(am["meshes"], name)

proc invalidate_all(am):
    am["meshes"] = {}
    am["shaders"] = {}
    am["textures"] = {}
    am["files"] = {}

proc asset_stats(am):
    let s = {}
    s["meshes"] = len(dict_keys(am["meshes"]))
    s["shaders"] = len(dict_keys(am["shaders"]))
    s["files"] = len(dict_keys(am["files"]))
    s["loads"] = am["stats"]["loads"]
    s["cache_hits"] = am["stats"]["cache_hits"]
    return s

proc print_asset_stats(am):
    let s = asset_stats(am)
    print "Assets: " + str(s["meshes"]) + " meshes, " + str(s["shaders"]) + " shaders, " + str(s["files"]) + " files"
    print "  Loads: " + str(s["loads"]) + "  Cache hits: " + str(s["cache_hits"])
