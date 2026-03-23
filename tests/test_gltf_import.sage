# test_gltf_import.sage - Sanity checks for glTF importer (parsing only)
import io
from gltf_import import load_gltf, create_gltf_result

let p = 0
let f = 0
proc check(n, c):
    if c:
        p = p + 1
    else:
        print "  FAIL: " + n
        f = f + 1

print "=== glTF Import Sanity Checks ==="

# --- Result structure ---
let r = create_gltf_result()
check("result created", r != nil)
check("meshes empty", len(r["meshes"]) == 0)
check("materials empty", len(r["materials"]) == 0)

# --- Parse minimal glTF JSON ---
from json import cJSON_CreateObject, cJSON_CreateArray, cJSON_CreateNumber, cJSON_CreateString
from json import cJSON_AddItemToObject, cJSON_AddItemToArray, cJSON_AddNumberToObject, cJSON_AddStringToObject
from json import cJSON_Print, cJSON_Delete

let root = cJSON_CreateObject()
let asset = cJSON_CreateObject()
cJSON_AddStringToObject(asset, "version", "2.0")
cJSON_AddStringToObject(asset, "generator", "TestGen")
cJSON_AddItemToObject(root, "asset", asset)
let meshes_arr = cJSON_CreateArray()
let mesh_obj = cJSON_CreateObject()
cJSON_AddStringToObject(mesh_obj, "name", "Cube")
let prims_arr = cJSON_CreateArray()
let prim_obj = cJSON_CreateObject()
cJSON_AddNumberToObject(prim_obj, "material", 0)
cJSON_AddItemToArray(prims_arr, prim_obj)
cJSON_AddItemToObject(mesh_obj, "primitives", prims_arr)
cJSON_AddItemToArray(meshes_arr, mesh_obj)
cJSON_AddItemToObject(root, "meshes", meshes_arr)
let mats_arr = cJSON_CreateArray()
let mat_obj = cJSON_CreateObject()
cJSON_AddStringToObject(mat_obj, "name", "Default")
let pbr_obj = cJSON_CreateObject()
let bcf_arr = cJSON_CreateArray()
cJSON_AddItemToArray(bcf_arr, cJSON_CreateNumber(1.0))
cJSON_AddItemToArray(bcf_arr, cJSON_CreateNumber(0.5))
cJSON_AddItemToArray(bcf_arr, cJSON_CreateNumber(0.2))
cJSON_AddItemToArray(bcf_arr, cJSON_CreateNumber(1.0))
cJSON_AddItemToObject(pbr_obj, "baseColorFactor", bcf_arr)
cJSON_AddNumberToObject(pbr_obj, "metallicFactor", 0.3)
cJSON_AddNumberToObject(pbr_obj, "roughnessFactor", 0.7)
cJSON_AddItemToObject(mat_obj, "pbrMetallicRoughness", pbr_obj)
cJSON_AddItemToArray(mats_arr, mat_obj)
cJSON_AddItemToObject(root, "materials", mats_arr)
let nodes_arr = cJSON_CreateArray()
let node_obj = cJSON_CreateObject()
cJSON_AddStringToObject(node_obj, "name", "CubeNode")
cJSON_AddNumberToObject(node_obj, "mesh", 0)
let trans_arr = cJSON_CreateArray()
cJSON_AddItemToArray(trans_arr, cJSON_CreateNumber(1.0))
cJSON_AddItemToArray(trans_arr, cJSON_CreateNumber(2.0))
cJSON_AddItemToArray(trans_arr, cJSON_CreateNumber(3.0))
cJSON_AddItemToObject(node_obj, "translation", trans_arr)
cJSON_AddItemToArray(nodes_arr, node_obj)
cJSON_AddItemToObject(root, "nodes", nodes_arr)
let minimal = cJSON_Print(root)
cJSON_Delete(root)
io.writefile("/tmp/sage_test.gltf", minimal)

let result = load_gltf("/tmp/sage_test.gltf")
check("loaded not nil", result != nil)
if result != nil:
    check("1 mesh", len(result["meshes"]) == 1)
    check("mesh name", result["meshes"][0]["name"] == "Cube")
    check("1 material", len(result["materials"]) == 1)
    check("material name", result["materials"][0]["name"] == "Default")
    check("albedo color r", result["materials"][0]["albedo_color"][0] > 0.9)
    check("albedo color g", result["materials"][0]["albedo_color"][1] > 0.4)
    check("metallic", result["materials"][0]["metallic"] > 0.2)
    check("roughness", result["materials"][0]["roughness"] > 0.6)
    check("1 node", len(result["nodes"]) == 1)
    check("node name", result["nodes"][0]["name"] == "CubeNode")
    check("node mesh ref", result["nodes"][0]["mesh"] == 0)
    check("node translation x", result["nodes"][0]["translation"][0] > 0.9)

# --- Bad file ---
let bad = load_gltf("/tmp/nonexistent.gltf")
check("bad file returns nil", bad == nil)

# --- Invalid JSON ---
io.writefile("/tmp/sage_bad.gltf", "not json at all")
let bad2 = load_gltf("/tmp/sage_bad.gltf")
check("invalid json returns nil", bad2 == nil)

# Cleanup
io.remove("/tmp/sage_test.gltf")
io.remove("/tmp/sage_bad.gltf")

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "glTF import sanity checks failed!"
else:
    print "All glTF import sanity checks passed!"
