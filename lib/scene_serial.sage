gc_disable()
# -----------------------------------------
# scene_serial.sage - Scene serialization for Forge Engine
# Save/load ECS scenes to/from JSON files
# -----------------------------------------

import io
from forge_version import engine_name, engine_version, scene_format_version
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
    if dict_has(comp, "cast_shadows"):
        cJSON_AddItemToObject(obj, "cast_shadows", cJSON_CreateBool(comp["cast_shadows"]))
    return obj

proc serialize_mesh_renderer(comp):
    let obj = cJSON_CreateObject()
    let material = "default"
    if dict_has(comp, "material"):
        material = comp["material"]
    cJSON_AddStringToObject(obj, "material", material)
    let visible = true
    if dict_has(comp, "visible"):
        visible = comp["visible"]
    cJSON_AddItemToObject(obj, "visible", cJSON_CreateBool(visible))
    if dict_has(comp, "cast_shadows"):
        cJSON_AddItemToObject(obj, "cast_shadows", cJSON_CreateBool(comp["cast_shadows"]))
    if dict_has(comp, "receive_shadows"):
        cJSON_AddItemToObject(obj, "receive_shadows", cJSON_CreateBool(comp["receive_shadows"]))
    return obj

proc serialize_health(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddNumberToObject(obj, "current", comp["current"])
    cJSON_AddNumberToObject(obj, "max", comp["max"])
    return obj

# ============================================================================
# Component serializer registry
# ============================================================================
proc serialize_mesh_id(comp):
    let obj = cJSON_CreateObject()
    if dict_has(comp, "name"):
        cJSON_AddStringToObject(obj, "mesh_type", comp["name"])
    else:
        cJSON_AddStringToObject(obj, "mesh_type", "cube")
    return obj

proc serialize_rigidbody(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddNumberToObject(obj, "mass", comp["mass"])
    cJSON_AddItemToObject(obj, "use_gravity", cJSON_CreateBool(comp["use_gravity"]))
    cJSON_AddItemToObject(obj, "is_kinematic", cJSON_CreateBool(comp["is_kinematic"]))
    cJSON_AddNumberToObject(obj, "restitution", comp["restitution"])
    return obj

proc serialize_collider(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddStringToObject(obj, "type", comp["type"])
    if comp["type"] == "aabb":
        from scene_serial import vec3_to_json
        cJSON_AddItemToObject(obj, "half", vec3_to_json(comp["half"]))
    if comp["type"] == "sphere":
        cJSON_AddNumberToObject(obj, "radius", comp["radius"])
    return obj

proc serialize_material(comp):
    let obj = cJSON_CreateObject()
    cJSON_AddItemToObject(obj, "albedo", vec3_to_json(comp["albedo"]))
    cJSON_AddNumberToObject(obj, "metallic", comp["metallic"])
    cJSON_AddNumberToObject(obj, "roughness", comp["roughness"])
    cJSON_AddItemToObject(obj, "emission", vec3_to_json(comp["emission"]))
    cJSON_AddNumberToObject(obj, "emission_strength", comp["emission_strength"])
    cJSON_AddNumberToObject(obj, "alpha", comp["alpha"])
    return obj

proc serialize_imported_asset(comp):
    let obj = cJSON_CreateObject()
    let source = ""
    if dict_has(comp, "source"):
        source = comp["source"]
    cJSON_AddStringToObject(obj, "source", source)
    let name = source
    if dict_has(comp, "name"):
        name = comp["name"]
    cJSON_AddStringToObject(obj, "name", name)
    return obj

proc serialize_sage_dict(comp):
    return cJSON_FromSage(comp)

let _serializers = {}
_serializers["transform"] = serialize_transform
_serializers["name"] = serialize_name
_serializers["velocity"] = serialize_velocity
_serializers["camera"] = serialize_camera
_serializers["light"] = serialize_light
_serializers["mesh_id"] = serialize_mesh_id
_serializers["mesh_renderer"] = serialize_mesh_renderer
_serializers["health"] = serialize_health
_serializers["rigidbody"] = serialize_rigidbody
_serializers["collider"] = serialize_collider
_serializers["material"] = serialize_material
_serializers["imported_asset"] = serialize_imported_asset
_serializers["asset_ref"] = serialize_sage_dict
_serializers["animation_state"] = serialize_sage_dict

proc register_serializer(comp_type, serialize_fn):
    _serializers[comp_type] = serialize_fn

# ============================================================================
# Serialize a full scene (world) to JSON string
# ============================================================================
proc serialize_scene(world, scene_name):
    let root = cJSON_CreateObject()
    cJSON_AddStringToObject(root, "name", scene_name)
    cJSON_AddStringToObject(root, "engine", engine_name())
    cJSON_AddStringToObject(root, "engine_version", engine_version())
    cJSON_AddNumberToObject(root, "version", scene_format_version())

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

proc deserialize_light(node):
    from components import PointLightComponent, DirectionalLightComponent
    let ltype = cJSON_GetStringValue(cJSON_GetObjectItem(node, "type"))
    let color = json_to_vec3(cJSON_GetObjectItem(node, "color"))
    let intensity = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "intensity"))
    if ltype == "directional":
        let l = DirectionalLightComponent(color[0], color[1], color[2], intensity)
        let cs = cJSON_GetObjectItem(node, "cast_shadows")
        if cs != nil:
            l["cast_shadows"] = cJSON_IsTrue(cs)
        return l
    let radius = 20.0
    let rad_node = cJSON_GetObjectItem(node, "radius")
    if rad_node != nil:
        radius = cJSON_GetNumberValue(rad_node)
    let p = PointLightComponent(color[0], color[1], color[2], intensity, radius)
    return p

proc deserialize_mesh_renderer(node):
    from components import MeshRendererComponent
    let material = "default"
    let mat_node = cJSON_GetObjectItem(node, "material")
    if mat_node != nil:
        material = cJSON_GetStringValue(mat_node)
    let mr = MeshRendererComponent(nil, material)
    let vis = cJSON_GetObjectItem(node, "visible")
    if vis != nil:
        mr["visible"] = cJSON_IsTrue(vis)
    let cs = cJSON_GetObjectItem(node, "cast_shadows")
    if cs != nil:
        mr["cast_shadows"] = cJSON_IsTrue(cs)
    let rs = cJSON_GetObjectItem(node, "receive_shadows")
    if rs != nil:
        mr["receive_shadows"] = cJSON_IsTrue(rs)
    return mr

# ============================================================================
# Deserializer registry
# ============================================================================
proc deserialize_mesh_id(node):
    let mesh_type = "cube"
    let mt = cJSON_GetObjectItem(node, "mesh_type")
    if mt != nil:
        mesh_type = cJSON_GetStringValue(mt)
    return {"mesh": nil, "name": mesh_type}

proc deserialize_rigidbody(node):
    from physics import RigidbodyComponent, StaticBodyComponent
    let mass = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "mass"))
    if mass <= 0.0:
        return StaticBodyComponent()
    let rb = RigidbodyComponent(mass)
    let grav = cJSON_GetObjectItem(node, "use_gravity")
    if grav != nil:
        rb["use_gravity"] = cJSON_IsTrue(grav)
    let kin = cJSON_GetObjectItem(node, "is_kinematic")
    if kin != nil:
        rb["is_kinematic"] = cJSON_IsTrue(kin)
    let rest = cJSON_GetObjectItem(node, "restitution")
    if rest != nil:
        rb["restitution"] = cJSON_GetNumberValue(rest)
    return rb

proc deserialize_collider(node):
    from physics import BoxColliderComponent, SphereColliderComponent
    let ctype = cJSON_GetStringValue(cJSON_GetObjectItem(node, "type"))
    if ctype == "sphere":
        let rad = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "radius"))
        return SphereColliderComponent(rad)
    let half = json_to_vec3(cJSON_GetObjectItem(node, "half"))
    return BoxColliderComponent(half[0], half[1], half[2])

let _deserializers = {}
_deserializers["transform"] = deserialize_transform
_deserializers["name"] = deserialize_name
_deserializers["velocity"] = deserialize_velocity
_deserializers["camera"] = deserialize_camera
_deserializers["health"] = deserialize_health
_deserializers["light"] = deserialize_light
_deserializers["mesh_id"] = deserialize_mesh_id
_deserializers["mesh_renderer"] = deserialize_mesh_renderer
_deserializers["rigidbody"] = deserialize_rigidbody
_deserializers["collider"] = deserialize_collider

proc deserialize_material(node):
    from components import MaterialComponent
    let albedo = json_to_vec3(cJSON_GetObjectItem(node, "albedo"))
    let mc = MaterialComponent(albedo[0], albedo[1], albedo[2])
    mc["metallic"] = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "metallic"))
    mc["roughness"] = cJSON_GetNumberValue(cJSON_GetObjectItem(node, "roughness"))
    let em = cJSON_GetObjectItem(node, "emission")
    if em != nil:
        mc["emission"] = json_to_vec3(em)
    let es = cJSON_GetObjectItem(node, "emission_strength")
    if es != nil:
        mc["emission_strength"] = cJSON_GetNumberValue(es)
    let al = cJSON_GetObjectItem(node, "alpha")
    if al != nil:
        mc["alpha"] = cJSON_GetNumberValue(al)
    return mc
_deserializers["material"] = deserialize_material

proc deserialize_imported_asset(node):
    let asset = {}
    asset["source"] = cJSON_GetStringValue(cJSON_GetObjectItem(node, "source"))
    let name_node = cJSON_GetObjectItem(node, "name")
    if name_node != nil:
        asset["name"] = cJSON_GetStringValue(name_node)
    else:
        asset["name"] = asset["source"]
    asset["gpu_meshes"] = []
    asset["materials"] = []
    asset["nodes"] = []
    asset["animations"] = []
    asset["animation_count"] = 0
    asset["mesh_count"] = 0
    asset["material_count"] = 0
    asset["node_count"] = 0
    return asset
_deserializers["imported_asset"] = deserialize_imported_asset

proc deserialize_sage_dict(node):
    return cJSON_ToSage(node)
_deserializers["asset_ref"] = deserialize_sage_dict
_deserializers["animation_state"] = deserialize_sage_dict

proc register_deserializer(comp_type, deserialize_fn):
    _deserializers[comp_type] = deserialize_fn

# ============================================================================
# Prefab system — save/load entity templates
# ============================================================================
proc save_prefab(world, entity_id, name, filepath):
    # Serialize a single entity and all its components to a JSON file
    # Reuse the existing serializer infrastructure
    from json import cJSON_CreateObject, cJSON_AddStringToObject, cJSON_AddItemToObject, cJSON_Print
    from ecs import get_component, has_component
    let prefab = cJSON_CreateObject()
    cJSON_AddStringToObject(prefab, "name", name)
    cJSON_AddStringToObject(prefab, "type", "prefab")
    let comps = cJSON_CreateObject()
    # Iterate known component types
    let comp_types = dict_keys(_serializers)
    let ci = 0
    while ci < len(comp_types):
        let ct = comp_types[ci]
        if has_component(world, entity_id, ct):
            let comp = get_component(world, entity_id, ct)
            let serialized = _serializers[ct](comp)
            cJSON_AddItemToObject(comps, ct, serialized)
        ci = ci + 1
    cJSON_AddItemToObject(prefab, "components", comps)
    let json_str = cJSON_Print(prefab)
    io.writefile(filepath, json_str)
    return true

proc load_prefab(world, filepath):
    # Load a prefab from JSON and spawn a new entity with all components
    if io.exists(filepath) == false:
        return -1
    let json_str = io.readfile(filepath)
    from json import cJSON_Parse, cJSON_GetObjectItem, cJSON_GetStringValue
    let root = cJSON_Parse(json_str)
    if root == nil:
        return -1
    let comps_node = cJSON_GetObjectItem(root, "components")
    if comps_node == nil:
        return -1
    from ecs import spawn, add_component, add_tag
    let eid = spawn(world)
    add_tag(world, eid, "editable")
    let comp_types = dict_keys(_deserializers)
    let ci = 0
    while ci < len(comp_types):
        let ct = comp_types[ci]
        let comp_node = cJSON_GetObjectItem(comps_node, ct)
        if comp_node != nil:
            let comp = _deserializers[ct](comp_node)
            add_component(world, eid, ct, comp)
        ci = ci + 1
    return eid

proc list_prefabs(directory):
    # Scan a directory for .prefab.json files
    let files = io.listdir(directory)
    let prefabs = []
    let i = 0
    while i < len(files):
        if endswith(files[i], ".prefab.json"):
            push(prefabs, files[i])
        i = i + 1
    return prefabs

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
    let scene_engine = ""
    let engine_node = cJSON_GetObjectItem(root, "engine")
    if engine_node != nil:
        scene_engine = cJSON_GetStringValue(engine_node)
    let scene_engine_version = ""
    let engine_version_node = cJSON_GetObjectItem(root, "engine_version")
    if engine_version_node != nil:
        scene_engine_version = cJSON_GetStringValue(engine_version_node)
    let scene_version = 0
    let version_node = cJSON_GetObjectItem(root, "version")
    if version_node != nil:
        scene_version = cJSON_GetNumberValue(version_node)

    let entities_node = cJSON_GetObjectItem(root, "entities")
    if entities_node == nil:
        cJSON_Delete(root)
        let empty_result = {}
        empty_result["world"] = world
        empty_result["name"] = scene_name
        empty_result["engine"] = scene_engine
        empty_result["engine_version"] = scene_engine_version
        empty_result["scene_version"] = scene_version
        empty_result["entity_count"] = 0
        return empty_result

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
    result["engine"] = scene_engine
    result["engine_version"] = scene_engine_version
    result["scene_version"] = scene_version
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
