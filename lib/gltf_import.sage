gc_disable()
# -----------------------------------------
# gltf_import.sage - glTF 2.0 importer for Sage Engine
# Loads meshes, materials, textures, skeleton from glTF JSON
# -----------------------------------------

import io
import math
from json import cJSON_Parse, cJSON_Delete, cJSON_GetObjectItem, cJSON_GetArrayItem
from json import cJSON_GetArraySize, cJSON_GetStringValue, cJSON_GetNumberValue
from json import cJSON_IsArray, cJSON_IsString
from math3d import vec3
from mesh import upload_mesh

# ============================================================================
# glTF scene result
# ============================================================================
proc create_gltf_result():
    let r = {}
    r["meshes"] = []
    r["materials"] = []
    r["textures"] = []
    r["nodes"] = []
    r["name"] = ""
    return r

# ============================================================================
# Load glTF JSON file (embedded or separate binary)
# ============================================================================
proc load_gltf(path):
    let content = io.readfile(path)
    if content == nil:
        print "GLTF ERROR: Cannot read " + path
        return nil
    let root = cJSON_Parse(content)
    if root == nil:
        print "GLTF ERROR: Invalid JSON in " + path
        return nil
    let result = create_gltf_result()
    # Extract base directory for relative paths
    let base_dir = _extract_dir(path)
    # Parse asset info
    let asset = cJSON_GetObjectItem(root, "asset")
    if asset != nil:
        let gen = cJSON_GetObjectItem(asset, "generator")
        if gen != nil:
            result["name"] = cJSON_GetStringValue(gen)
    # Parse meshes
    let meshes_node = cJSON_GetObjectItem(root, "meshes")
    if meshes_node != nil:
        let mc = cJSON_GetArraySize(meshes_node)
        let mi = 0
        while mi < mc:
            let mesh_node = cJSON_GetArrayItem(meshes_node, mi)
            let mesh_info = _parse_mesh_node(mesh_node)
            push(result["meshes"], mesh_info)
            mi = mi + 1
    # Parse materials
    let mats_node = cJSON_GetObjectItem(root, "materials")
    if mats_node != nil:
        let matc = cJSON_GetArraySize(mats_node)
        let mati = 0
        while mati < matc:
            let mat_node = cJSON_GetArrayItem(mats_node, mati)
            let mat_info = _parse_material_node(mat_node)
            push(result["materials"], mat_info)
            mati = mati + 1
    # Parse textures
    let tex_node = cJSON_GetObjectItem(root, "textures")
    if tex_node != nil:
        let tc = cJSON_GetArraySize(tex_node)
        let ti = 0
        while ti < tc:
            let t = cJSON_GetArrayItem(tex_node, ti)
            let src_node = cJSON_GetObjectItem(t, "source")
            if src_node != nil:
                let img_idx = cJSON_GetNumberValue(src_node)
                push(result["textures"], {"image_index": img_idx})
            ti = ti + 1
    # Parse images (texture file paths)
    let images_node = cJSON_GetObjectItem(root, "images")
    let image_paths = []
    if images_node != nil:
        let ic = cJSON_GetArraySize(images_node)
        let ii = 0
        while ii < ic:
            let img = cJSON_GetArrayItem(images_node, ii)
            let uri = cJSON_GetObjectItem(img, "uri")
            if uri != nil:
                push(image_paths, base_dir + "/" + cJSON_GetStringValue(uri))
            else:
                push(image_paths, "")
            ii = ii + 1
    result["image_paths"] = image_paths
    # Parse nodes
    let nodes_node = cJSON_GetObjectItem(root, "nodes")
    if nodes_node != nil:
        let nc = cJSON_GetArraySize(nodes_node)
        let ni = 0
        while ni < nc:
            let n = cJSON_GetArrayItem(nodes_node, ni)
            let node_info = _parse_node(n)
            push(result["nodes"], node_info)
            ni = ni + 1
    cJSON_Delete(root)
    print "glTF loaded: " + str(len(result["meshes"])) + " meshes, " + str(len(result["materials"])) + " materials"
    return result

# ============================================================================
# Internal parsers
# ============================================================================
proc _parse_mesh_node(node):
    let info = {}
    let name_node = cJSON_GetObjectItem(node, "name")
    if name_node != nil:
        info["name"] = cJSON_GetStringValue(name_node)
    else:
        info["name"] = "unnamed"
    info["primitives"] = []
    let prims = cJSON_GetObjectItem(node, "primitives")
    if prims != nil:
        let pc = cJSON_GetArraySize(prims)
        let pi = 0
        while pi < pc:
            let prim = cJSON_GetArrayItem(prims, pi)
            let pinfo = {}
            let mat_node = cJSON_GetObjectItem(prim, "material")
            if mat_node != nil:
                pinfo["material"] = cJSON_GetNumberValue(mat_node)
            else:
                pinfo["material"] = -1
            push(info["primitives"], pinfo)
            pi = pi + 1
    return info

proc _parse_material_node(node):
    let mat = {}
    let name_node = cJSON_GetObjectItem(node, "name")
    if name_node != nil:
        mat["name"] = cJSON_GetStringValue(name_node)
    else:
        mat["name"] = "unnamed"
    mat["albedo_color"] = [1.0, 1.0, 1.0, 1.0]
    mat["metallic"] = 0.0
    mat["roughness"] = 0.5
    mat["albedo_texture_index"] = -1
    mat["normal_texture_index"] = -1
    mat["mr_texture_index"] = -1
    let pbr = cJSON_GetObjectItem(node, "pbrMetallicRoughness")
    if pbr != nil:
        let bcf = cJSON_GetObjectItem(pbr, "baseColorFactor")
        if bcf != nil:
            let r = cJSON_GetNumberValue(cJSON_GetArrayItem(bcf, 0))
            let g = cJSON_GetNumberValue(cJSON_GetArrayItem(bcf, 1))
            let b = cJSON_GetNumberValue(cJSON_GetArrayItem(bcf, 2))
            let a = cJSON_GetNumberValue(cJSON_GetArrayItem(bcf, 3))
            mat["albedo_color"] = [r, g, b, a]
        let mf = cJSON_GetObjectItem(pbr, "metallicFactor")
        if mf != nil:
            mat["metallic"] = cJSON_GetNumberValue(mf)
        let rf = cJSON_GetObjectItem(pbr, "roughnessFactor")
        if rf != nil:
            mat["roughness"] = cJSON_GetNumberValue(rf)
        let bct = cJSON_GetObjectItem(pbr, "baseColorTexture")
        if bct != nil:
            let idx = cJSON_GetObjectItem(bct, "index")
            if idx != nil:
                mat["albedo_texture_index"] = cJSON_GetNumberValue(idx)
        let mrt = cJSON_GetObjectItem(pbr, "metallicRoughnessTexture")
        if mrt != nil:
            let idx = cJSON_GetObjectItem(mrt, "index")
            if idx != nil:
                mat["mr_texture_index"] = cJSON_GetNumberValue(idx)
    let nt = cJSON_GetObjectItem(node, "normalTexture")
    if nt != nil:
        let idx = cJSON_GetObjectItem(nt, "index")
        if idx != nil:
            mat["normal_texture_index"] = cJSON_GetNumberValue(idx)
    return mat

proc _parse_node(node):
    let info = {}
    let name_node = cJSON_GetObjectItem(node, "name")
    if name_node != nil:
        info["name"] = cJSON_GetStringValue(name_node)
    else:
        info["name"] = "node"
    info["mesh"] = -1
    let mesh_node = cJSON_GetObjectItem(node, "mesh")
    if mesh_node != nil:
        info["mesh"] = cJSON_GetNumberValue(mesh_node)
    info["matrix"] = nil
    let matrix_node = cJSON_GetObjectItem(node, "matrix")
    if matrix_node != nil:
        let matrix = []
        let mi = 0
        while mi < 16:
            push(matrix, cJSON_GetNumberValue(cJSON_GetArrayItem(matrix_node, mi)))
            mi = mi + 1
        info["matrix"] = matrix
    info["translation"] = vec3(0.0, 0.0, 0.0)
    let trans = cJSON_GetObjectItem(node, "translation")
    if trans != nil:
        let tx = cJSON_GetNumberValue(cJSON_GetArrayItem(trans, 0))
        let ty = cJSON_GetNumberValue(cJSON_GetArrayItem(trans, 1))
        let tz = cJSON_GetNumberValue(cJSON_GetArrayItem(trans, 2))
        info["translation"] = vec3(tx, ty, tz)
    info["rotation"] = [1.0, 0.0, 0.0, 0.0]
    let rot = cJSON_GetObjectItem(node, "rotation")
    if rot != nil:
        let qx = cJSON_GetNumberValue(cJSON_GetArrayItem(rot, 0))
        let qy = cJSON_GetNumberValue(cJSON_GetArrayItem(rot, 1))
        let qz = cJSON_GetNumberValue(cJSON_GetArrayItem(rot, 2))
        let qw = cJSON_GetNumberValue(cJSON_GetArrayItem(rot, 3))
        info["rotation"] = [qw, qx, qy, qz]
    info["scale"] = vec3(1.0, 1.0, 1.0)
    let scl = cJSON_GetObjectItem(node, "scale")
    if scl != nil:
        let sx = cJSON_GetNumberValue(cJSON_GetArrayItem(scl, 0))
        let sy = cJSON_GetNumberValue(cJSON_GetArrayItem(scl, 1))
        let sz = cJSON_GetNumberValue(cJSON_GetArrayItem(scl, 2))
        info["scale"] = vec3(sx, sy, sz)
    info["children"] = []
    let ch = cJSON_GetObjectItem(node, "children")
    if ch != nil:
        let cc = cJSON_GetArraySize(ch)
        let ci = 0
        while ci < cc:
            push(info["children"], cJSON_GetNumberValue(cJSON_GetArrayItem(ch, ci)))
            ci = ci + 1
    return info

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
