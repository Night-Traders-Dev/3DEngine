gc_disable()
# -----------------------------------------
# scene_serial.sage - Scene serialization for Sage Engine
# Save/load ECS scenes to/from JSON files
# -----------------------------------------

import io
from json import cJSON_Parse, cJSON_Print, cJSON_Delete
from json import cJSON_CreateObject, cJSON_CreateArray, cJSON_CreateNumber, cJSON_CreateString
from json import cJSON_CreateBool, cJSON_CreateNull
from json import cJSON_AddItemToObject, cJSON_AddItemToArray
from json import cJSON_AddNumberToObject, cJSON_AddStringToObject
from json import cJSON_GetObjectItem, cJSON_GetArrayItem, cJSON_GetArraySize
from json import cJSON_GetStringValue, cJSON_GetNumberValue
from json import cJSON_IsObject, cJSON_IsArray, cJSON_IsNumber, cJSON_IsString, cJSON_IsBool
from json import cJSON_IsTrue, cJSON_ToSage, cJSON_FromSage
from ecs import create_world, spawn, add_component, get_component, has_component, query, add_tag
from math3d import vec3

# ============================================================================
# Serialize a vec3 to a JSON array
# ============================================================================
proc vec3_to_json(v):
    let arr = cJSON_CreateArray()
    cJSON_AddItemToArray(arr, cJSON_CreateNumber(v[0]))
    cJSON_AddItemToArray(arr, cJSON_CreateNumber(v[1]))
    cJSON_AddItemToArray(arr, cJSON_CreateNumber(v[2]))
    return arr

proc json_to_vec3(node):
    let x = cJSON_GetNumberValue(cJSON_GetArrayItem(node, 0))
    let y = cJSON_GetNumberValue(cJSON_GetArrayItem(node, 1))
    let z = cJSON_GetNumberValue(cJSON_GetArrayItem(node, 2))
    return vec3(x, y, z)

# ============================================================================
# Serialize components to JSON nodes
# ============================================================================
proc serialize_transform(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddItemToObject(obj, "position", vec3_to_json(comp["position"]))
    cJSON_AddItemToObject(obj, "rotation", vec3_to_json(comp["rotation"]))
    cJSON_AddItemToObject(obj, "scale", vec3_to_json(comp["scale"]))
    return obj

proc serialize_name(comp):
    return cJSON_CreateString(comp["name"])

proc serialize_velocity(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddItemToObject(obj, "linear", vec3_to_json(comp["linear"]))
    cJSON_AddItemToObject(obj, "angular", vec3_to_json(comp["angular"]))
    cJSON_AddNumberToObject(obj, "damping", comp["damping"])
    return obj

proc serialize_camera(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddNumberToObject(obj, "fov", comp["fov"])
    cJSON_AddNumberToObject(obj, "near", comp["near"])
    cJSON_AddNumberToObject(obj, "far", comp["far"])
    cJSON_AddNumberToObject(obj, "yaw", comp["yaw"])
    cJSON_AddNumberToObject(obj, "pitch", comp["pitch"])
    return obj

proc serialize_light(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddStringToObject(obj, "type", comp["type"])
    cJSON_AddItemToObject(obj, "color", vec3_to_json(comp["color"]))
    cJSON_AddNumberToObject(obj, "intensity", comp["intensity"])
    if dict_has(comp, "radius"):
        cJSON_AddNumberToObject(obj, "radius", comp["radius"])
    return obj

proc serialize_mesh_renderer(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddStringToObject(obj, "material", comp["material"])
    cJSON_AddItemToObject(obj, "visible", cJSON_CreateBool(comp["visible"]))
    return obj

proc serialize_health(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddNumberToObject(obj, "current", comp["current"])
    cJSON_AddNumberToObject(obj, "max", comp["max"])
    return obj

# ============================================================================
# Component serializer registry
# ============================================================================
let _serializers = {}
_serializers["transform"] = serialize_transform
_serializers["name"] = serialize_name
_serializers["velocity"] = serialize_velocity
_serializers["camera"] = serialize_camera
_serializers["light"] = serialize_light
_serializers["mesh_renderer"] = serialize_mesh_renderer
_serializers["health"] = serialize_health

proc register_serializer(comp_type, serialize_fn):
    _serializers[comp_type] = serialize_fn

# ============================================================================
# Serialize a full scene (world) to JSON string
# ============================================================================
proc serialize_scene(world, scene_name):
    let root = cJSON_CreateObject()
    cJSON_AddStringToObject(root, "name", scene_name)
    cJSON_AddStringToObject(root, "engine", "Sage Engine")
    cJSON_AddNumberToObject(root, "version", 1)

    let entities_arr = cJSON_CreateArray()

    # Iterate all component types to find entities
    let all_entities = {}
    let comp_types = dict_keys(world["components"])
    let ci = 0
    while ci < len(comp_types):
        let store = world["components"][comp_types[ci]]
        let eids = dict_keys(store)
        let ei = 0
        while ei < len(eids):
            let sid = eids[ei]
            if dict_has(world["entities"], sid):
                if world["entities"][sid] == true:
                    all_entities[sid] = true
            ei = ei + 1
        ci = ci + 1

    # Serialize each entity
    let entity_keys = dict_keys(all_entities)
    let i = 0
    while i < len(entity_keys):
        let sid = entity_keys[i]
        let eid = tonumber(sid)
        let ent_obj = cJSON_CreateObject()
        cJSON_AddNumberToObject(ent_obj, "id", eid)

        let comps_obj = cJSON_CreateObject()
        let ser_types = dict_keys(_serializers)
        let j = 0
        while j < len(ser_types):
            let ct = ser_types[j]
            if has_component(world, eid, ct):
                let comp = get_component(world, eid, ct)
                let serialized = _serializers[ct](comp)
                cJSON_AddItemToObject(comps_obj, ct, serialized)
            j = j + 1
        cJSON_AddItemToObject(ent_obj, "components", comps_obj)

        # Tags
        let tags_arr = cJSON_CreateArray()
        let tag_types = dict_keys(world["tags"])
        let ti = 0
        while ti < len(tag_types):
            let tag = tag_types[ti]
            let tstore = world["tags"][tag]
            if dict_has(tstore, sid):
                cJSON_AddItemToArray(tags_arr, cJSON_CreateString(tag))
            ti = ti + 1
        cJSON_AddItemToObject(ent_obj, "tags", tags_arr)

        cJSON_AddItemToArray(entities_arr, ent_obj)
        i = i + 1

    cJSON_AddItemToObject(root, "entities", entities_arr)
    let json_str = cJSON_Print(root)
    cJSON_Delete(root)
    return json_str

# ============================================================================
# Save scene to file
# ============================================================================
proc save_scene(world, scene_name, file_path):
    let json_str = serialize_scene(world, scene_name)
    if json_str == nil:
        print "SCENE ERROR: Failed to serialize scene"
        return false
    io.writefile(file_path, json_str)
    print "Scene saved: " + file_path
    return true

# ============================================================================
# Deserialize components from JSON nodes
# ============================================================================
proc deserialize_transform(node):
    from components import TransformComponentFull
    let pos = json_to_vec3(cJSON_GetObjectItem(node, "position"))
    let rot = json_to_vec3(cJSON_GetObjectItem(node, "rotation"))
    let scl = json_to_vec3(cJSON_GetObjectItem(node, "scale"))
    return TransformComponentFull(pos, rot, scl)

proc deserialize_name(node):
    from components import NameComponent
    return NameComponent(cJSON_GetStringValue(node))

proc deserialize_velocity(node):
    from components import VelocityComponent
    let v = VelocityComponent()
    v["linear"] = json_to_vec3(cJSON_GetObjectItem(node, "linear"))
    v["angular"] = json_to_vec3(cJSON_GetObjectItem(node, "angular"))
    let damp_node = cJSON_GetObjectItem(node, "damping")
    if damp_node != nil:
        v["damping"] = cJSON_GetNumberValue(damp_node)
    return v

proc deserialize_camera(node):
    from components import CameraComponent
    let fov = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "fov"))
    let near = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "near"))
    let far = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "far"))
    let c = CameraComponent(fov, near, far)
    let yaw_node = cJSON_GetObjectItem(node, "yaw")
    if yaw_node != nil:
        c["yaw"] = cJSON_GetNumberValue(yaw_node)
    let pitch_node = cJSON_GetObjectItem(node, "pitch")
    if pitch_node != nil:
        c["pitch"] = cJSON_GetNumberValue(pitch_node)
    return c

proc deserialize_health(node):
    from gameplay import HealthComponent
    let max_hp = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "max"))
    let h = HealthComponent(max_hp)
    h["current"] = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "current"))
    if h["current"] <= 0.0:
        h["alive"] = false
    return h

# ============================================================================
# Deserializer registry
# ============================================================================
let _deserializers = {}
_deserializers["transform"] = deserialize_transform
_deserializers["name"] = deserialize_name
_deserializers["velocity"] = deserialize_velocity
_deserializers["camera"] = deserialize_camera
_deserializers["health"] = deserialize_health

proc register_deserializer(comp_type, deserialize_fn):
    _deserializers[comp_type] = deserialize_fn

# ============================================================================
# Load scene from JSON string
# ============================================================================
proc load_scene_string(json_str):
    let root = cJSON_Parse(json_str)
    if root == nil:
        print "SCENE ERROR: Failed to parse scene JSON"
        return nil

    let world = create_world()
    let name_node = cJSON_GetObjectItem(root, "name")
    let scene_name = ""
    if name_node != nil:
        scene_name = cJSON_GetStringValue(name_node)

    let entities_node = cJSON_GetObjectItem(root, "entities")
    if entities_node == nil:
        cJSON_Delete(root)
        return world

    let count = cJSON_GetArraySize(entities_node)
    let i = 0
    while i < count:
        let ent_node = cJSON_GetArrayItem(entities_node, i)
        let eid = spawn(world)

        # Components
        let comps_node = cJSON_GetObjectItem(ent_node, "components")
        if comps_node != nil:
            let deser_types = dict_keys(_deserializers)
            let j = 0
            while j < len(deser_types):
                let ct = deser_types[j]
                let comp_node = cJSON_GetObjectItem(comps_node, ct)
                if comp_node != nil:
                    let comp = _deserializers[ct](comp_node)
                    add_component(world, eid, ct, comp)
                j = j + 1

        # Tags
        let tags_node = cJSON_GetObjectItem(ent_node, "tags")
        if tags_node != nil:
            let tc = cJSON_GetArraySize(tags_node)
            let ti = 0
            while ti < tc:
                let tag_node = cJSON_GetArrayItem(tags_node, ti)
                let tag = cJSON_GetStringValue(tag_node)
                add_tag(world, eid, tag)
                ti = ti + 1
        i = i + 1

    cJSON_Delete(root)
    let result = {}
    result["world"] = world
    result["name"] = scene_name
    result["entity_count"] = count
    return result

# ============================================================================
# Load scene from file
# ============================================================================
proc load_scene(file_path):
    let content = io.readfile(file_path)
    if content == nil:
        print "SCENE ERROR: Failed to read " + file_path
        return nil
    let result = load_scene_string(content)
    if result != nil:
        print "Scene loaded: " + file_path + " (" + str(result["entity_count"]) + " entities)"
    return result
