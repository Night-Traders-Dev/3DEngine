gc_disable()
# -----------------------------------------
# gltf_import.sage - glTF 2.0 importer for Sage Engine
# Loads meshes, materials, textures, skeleton from glTF JSON
# -----------------------------------------

import io
import math
import gpu
from json import cJSON_Parse, cJSON_Delete, cJSON_GetObjectItem, cJSON_GetArrayItem
from json import cJSON_GetArraySize, cJSON_GetStringValue, cJSON_GetNumberValue
from json import cJSON_IsArray, cJSON_IsString
from math3d import vec3, mat4_identity
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
    r["skins"] = []
    r["skin_count"] = 0
    r["animations"] = []
    r["animation_count"] = 0
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
    let buffers_node = cJSON_GetObjectItem(root, "buffers")
    let buffer_views_node = cJSON_GetObjectItem(root, "bufferViews")
    let accessors_node = cJSON_GetObjectItem(root, "accessors")
    let buffers = _load_gltf_buffers(buffers_node, base_dir)
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
    # Parse skins
    let skins_node = cJSON_GetObjectItem(root, "skins")
    if skins_node != nil:
        let sc = cJSON_GetArraySize(skins_node)
        let si = 0
        while si < sc:
            let skin_node = cJSON_GetArrayItem(skins_node, si)
            let skin_info = _parse_skin_node(skin_node, si, result["nodes"], accessors_node, buffer_views_node, buffers)
            push(result["skins"], skin_info)
            si = si + 1
    result["skin_count"] = len(result["skins"])
    result["animations"] = _parse_animations(path)
    result["animation_count"] = len(result["animations"])
    cJSON_Delete(root)
    print "glTF loaded: " + str(len(result["meshes"])) + " meshes, " + str(len(result["materials"])) + " materials, " + str(result["skin_count"]) + " skins, " + str(result["animation_count"]) + " animations"
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
    info["skin"] = -1
    let skin_node = cJSON_GetObjectItem(node, "skin")
    if skin_node != nil:
        info["skin"] = cJSON_GetNumberValue(skin_node)
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

proc _parse_skin_node(node, skin_index, nodes, accessors_node, buffer_views_node, buffers):
    let skin = {}
    skin["name"] = "Skin_" + str(skin_index)
    let name_node = cJSON_GetObjectItem(node, "name")
    if name_node != nil:
        skin["name"] = cJSON_GetStringValue(name_node)
    skin["skeleton"] = -1
    let skeleton_node = cJSON_GetObjectItem(node, "skeleton")
    if skeleton_node != nil:
        skin["skeleton"] = cJSON_GetNumberValue(skeleton_node)
    skin["joints"] = []
    skin["joint_names"] = []
    let joints_node = cJSON_GetObjectItem(node, "joints")
    if joints_node != nil:
        let jc = cJSON_GetArraySize(joints_node)
        let ji = 0
        while ji < jc:
            let joint_idx = cJSON_GetNumberValue(cJSON_GetArrayItem(joints_node, ji))
            push(skin["joints"], joint_idx)
            let joint_name = "Joint_" + str(joint_idx)
            if joint_idx >= 0 and joint_idx < len(nodes):
                if dict_has(nodes[joint_idx], "name"):
                    joint_name = nodes[joint_idx]["name"]
            push(skin["joint_names"], joint_name)
            ji = ji + 1
    skin["inverse_bind_matrices"] = []
    let ibm_node = cJSON_GetObjectItem(node, "inverseBindMatrices")
    if ibm_node != nil and accessors_node != nil and buffer_views_node != nil:
        let ibm_accessor = cJSON_GetNumberValue(ibm_node)
        let raw_mats = _decode_accessor_values(accessors_node, buffer_views_node, buffers, ibm_accessor)
        let mi = 0
        while mi < len(raw_mats):
            if len(raw_mats[mi]) == 16:
                push(skin["inverse_bind_matrices"], raw_mats[mi])
            mi = mi + 1
    while len(skin["inverse_bind_matrices"]) < len(skin["joints"]):
        push(skin["inverse_bind_matrices"], mat4_identity())
    skin["joint_count"] = len(skin["joints"])
    return skin

proc _parse_animations(path):
    let animations = []
    let gpu_gltf = gpu.load_gltf(path)
    if gpu_gltf == nil or dict_has(gpu_gltf, "animations") == false:
        return animations
    let source_animations = gpu_gltf["animations"]
    let ac = len(source_animations)
    let ai = 0
    while ai < ac:
        let anim_node = source_animations[ai]
        let anim = {}
        anim["name"] = "Animation_" + str(ai)
        if dict_has(anim_node, "name") and anim_node["name"] != "":
            anim["name"] = anim_node["name"]
        anim["channels"] = []
        anim["duration"] = 0.0
        anim["looping"] = true
        if dict_has(anim_node, "channels"):
            let ci = 0
            while ci < len(anim_node["channels"]):
                let source_channel = anim_node["channels"][ci]
                let channel = {}
                channel["node"] = source_channel["node"]
                channel["path"] = source_channel["path"]
                channel["interpolation"] = "LINEAR"
                channel["times"] = source_channel["times"]
                channel["values"] = _reshape_animation_values(channel["path"], source_channel["values"])
                if len(channel["times"]) > 0:
                    let last_time = channel["times"][len(channel["times"]) - 1]
                    if last_time > anim["duration"]:
                        anim["duration"] = last_time
                push(anim["channels"], channel)
                ci = ci + 1
        push(animations, anim)
        ai = ai + 1
    return animations

proc _reshape_animation_values(path, flat_values):
    let values = []
    let stride = 1
    if path == "translation" or path == "scale":
        stride = 3
    if path == "rotation":
        stride = 4
    let i = 0
    while i + stride - 1 < len(flat_values):
        if stride == 1:
            push(values, flat_values[i])
        if stride == 3:
            push(values, vec3(flat_values[i], flat_values[i + 1], flat_values[i + 2]))
        if stride == 4:
            push(values, [flat_values[i + 3], flat_values[i], flat_values[i + 1], flat_values[i + 2]])
        i = i + stride
    return values

proc _load_gltf_buffers(buffers_node, base_dir):
    let buffers = []
    if buffers_node == nil:
        return buffers
    let bc = cJSON_GetArraySize(buffers_node)
    let bi = 0
    while bi < bc:
        let buffer_node = cJSON_GetArrayItem(buffers_node, bi)
        let bytes = nil
        let uri_node = cJSON_GetObjectItem(buffer_node, "uri")
        if uri_node != nil:
            let uri = cJSON_GetStringValue(uri_node)
            if startswith(uri, "data:") == false:
                bytes = _read_binary_bytes(base_dir + "/" + uri)
        push(buffers, bytes)
        bi = bi + 1
    return buffers

proc _read_binary_bytes(path):
    let raw = io.readfile(path)
    if raw == nil:
        return nil
    let bytes = []
    let i = 0
    while i < len(raw):
        push(bytes, ord(raw[i]))
        i = i + 1
    return bytes

proc _decode_accessor_values(accessors_node, buffer_views_node, buffers, accessor_index):
    let values = []
    let accessor_node = cJSON_GetArrayItem(accessors_node, accessor_index)
    if accessor_node == nil:
        return values
    let view_ref = cJSON_GetObjectItem(accessor_node, "bufferView")
    if view_ref == nil:
        return values
    let view_idx = cJSON_GetNumberValue(view_ref)
    let view_node = cJSON_GetArrayItem(buffer_views_node, view_idx)
    if view_node == nil:
        return values
    let buffer_ref = cJSON_GetObjectItem(view_node, "buffer")
    if buffer_ref == nil:
        return values
    let buffer_idx = cJSON_GetNumberValue(buffer_ref)
    if buffer_idx < 0 or buffer_idx >= len(buffers):
        return values
    let bytes = buffers[buffer_idx]
    if bytes == nil:
        return values
    let count = cJSON_GetNumberValue(cJSON_GetObjectItem(accessor_node, "count"))
    let component_type = cJSON_GetNumberValue(cJSON_GetObjectItem(accessor_node, "componentType"))
    let type_name = cJSON_GetStringValue(cJSON_GetObjectItem(accessor_node, "type"))
    let component_count = _accessor_component_count(type_name)
    let component_size = _accessor_component_size(component_type)
    if component_count <= 0 or component_size <= 0:
        return values
    let view_offset = 0
    let view_offset_node = cJSON_GetObjectItem(view_node, "byteOffset")
    if view_offset_node != nil:
        view_offset = cJSON_GetNumberValue(view_offset_node)
    let accessor_offset = 0
    let accessor_offset_node = cJSON_GetObjectItem(accessor_node, "byteOffset")
    if accessor_offset_node != nil:
        accessor_offset = cJSON_GetNumberValue(accessor_offset_node)
    let stride = component_count * component_size
    let stride_node = cJSON_GetObjectItem(view_node, "byteStride")
    if stride_node != nil:
        stride = cJSON_GetNumberValue(stride_node)
    let start = view_offset + accessor_offset
    let i = 0
    while i < count:
        let elem_off = start + i * stride
        let value = _decode_accessor_value(bytes, elem_off, component_type, component_count)
        push(values, value)
        i = i + 1
    return values

proc _decode_accessor_value(bytes, offset, component_type, component_count):
    if component_count == 1:
        return _decode_accessor_component(bytes, offset, component_type)
    let result = []
    let comp_size = _accessor_component_size(component_type)
    let ci = 0
    while ci < component_count:
        push(result, _decode_accessor_component(bytes, offset + ci * comp_size, component_type))
        ci = ci + 1
    return result

proc _decode_accessor_component(bytes, offset, component_type):
    if component_type == 5126:
        return _read_f32_le(bytes, offset)
    if component_type == 5125:
        return _read_u32_le(bytes, offset)
    if component_type == 5123:
        return _read_u16_le(bytes, offset)
    return 0.0

proc _accessor_component_count(type_name):
    if type_name == "SCALAR":
        return 1
    if type_name == "VEC2":
        return 2
    if type_name == "VEC3":
        return 3
    if type_name == "VEC4":
        return 4
    if type_name == "MAT4":
        return 16
    return 0

proc _accessor_component_size(component_type):
    if component_type == 5123:
        return 2
    if component_type == 5125 or component_type == 5126:
        return 4
    return 0

proc _normalize_animation_values(path, values):
    if path != "rotation":
        return values
    let out = []
    let i = 0
    while i < len(values):
        let v = values[i]
        if len(v) >= 4:
            push(out, [v[3], v[0], v[1], v[2]])
        else:
            push(out, [1.0, 0.0, 0.0, 0.0])
        i = i + 1
    return out

proc _read_u16_le(bytes, offset):
    if offset + 2 > len(bytes):
        return 0
    return bytes[offset] + bytes[offset + 1] * 256

proc _read_u32_le(bytes, offset):
    if offset + 4 > len(bytes):
        return 0
    return bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536 + bytes[offset + 3] * 16777216

proc _read_f32_le(bytes, offset):
    if offset + 4 > len(bytes):
        return 0.0
    let bits = _read_u32_le(bytes, offset)
    let sign = 1.0
    if bits >= 2147483648:
        sign = -1.0
        bits = bits - 2147483648
    let exponent = (bits / 8388608) | 0
    let mantissa = bits - exponent * 8388608
    if exponent == 0:
        if mantissa == 0:
            return 0.0 * sign
        return sign * mantissa / 8388608.0 * 0.0000000000000000000000000000000000000117549435
    if exponent == 255:
        return 0.0
    return sign * (1.0 + mantissa / 8388608.0) * math.pow(2.0, exponent - 127)

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
