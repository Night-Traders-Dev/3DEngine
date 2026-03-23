gc_disable()
# -----------------------------------------
# inspector.sage - Property inspector for Sage Engine Editor
# View and edit entity components via UI panels
# -----------------------------------------

from ecs import get_component, has_component
from math3d import vec3
import ui_core
from ui_core import create_widget, create_panel, create_rect, create_label
from ui_core import add_child

let rgba = ui_core.rgba
let COLOR_WHITE = ui_core.COLOR_WHITE
let COLOR_DARK = ui_core.COLOR_DARK
let ANCHOR_TOP_RIGHT = ui_core.ANCHOR_TOP_RIGHT

# ============================================================================
# Inspector
# ============================================================================
proc create_inspector():
    let ins = {}
    ins["selected_entity"] = -1
    ins["selected_world"] = nil
    ins["panel"] = create_panel(0.0, 0.0, 260.0, 500.0, rgba(0.08, 0.08, 0.12, 0.9))
    ins["panel"]["anchor"] = ANCHOR_TOP_RIGHT
    ins["panel"]["x"] = -270.0
    ins["panel"]["y"] = 10.0
    ins["visible"] = true
    ins["entries"] = []
    ins["component_types"] = ["transform", "name", "velocity", "health", "rigidbody", "collider", "camera", "mesh_id", "ai_data"]
    return ins

# ============================================================================
# Select entity for inspection
# ============================================================================
proc inspect_entity(ins, world, entity_id):
    ins["selected_entity"] = entity_id
    ins["selected_world"] = world
    _rebuild_entries(ins)

proc clear_inspection(ins):
    ins["selected_entity"] = -1
    ins["selected_world"] = nil
    ins["entries"] = []
    ins["panel"]["children"] = []

# ============================================================================
# Rebuild inspector entries from selected entity
# ============================================================================
proc _rebuild_entries(ins):
    ins["entries"] = []
    ins["panel"]["children"] = []
    let eid = ins["selected_entity"]
    let w = ins["selected_world"]
    if eid < 0 or w == nil:
        return nil
    let y_offset = 10.0
    # Header
    let header = create_label(10.0, y_offset, "Entity #" + str(eid), COLOR_WHITE)
    add_child(ins["panel"], header)
    y_offset = y_offset + 22.0
    # Separator
    let sep = create_rect(10.0, y_offset, 240.0, 1.0, rgba(0.4, 0.4, 0.4, 0.5))
    add_child(ins["panel"], sep)
    y_offset = y_offset + 8.0
    # Components
    let types = ins["component_types"]
    let i = 0
    while i < len(types):
        let ct = types[i]
        if has_component(w, eid, ct):
            let comp = get_component(w, eid, ct)
            y_offset = _add_component_section(ins, ct, comp, y_offset)
        i = i + 1
    ins["panel"]["height"] = y_offset + 10.0

proc _add_component_section(ins, comp_type, comp, y_offset):
    # Component header
    let hdr = create_rect(10.0, y_offset, 240.0, 18.0, rgba(0.2, 0.25, 0.35, 0.8))
    add_child(ins["panel"], hdr)
    let lbl = create_label(14.0, y_offset + 2.0, comp_type, rgba(0.8, 0.9, 1.0, 1.0))
    add_child(ins["panel"], lbl)
    y_offset = y_offset + 22.0
    # Component fields
    if comp_type == "transform":
        y_offset = _add_vec3_entry(ins, "position", comp["position"], y_offset)
        y_offset = _add_vec3_entry(ins, "rotation", comp["rotation"], y_offset)
        y_offset = _add_vec3_entry(ins, "scale", comp["scale"], y_offset)
    if comp_type == "name":
        y_offset = _add_text_entry(ins, "name", comp["name"], y_offset)
    if comp_type == "velocity":
        y_offset = _add_vec3_entry(ins, "linear", comp["linear"], y_offset)
        y_offset = _add_vec3_entry(ins, "angular", comp["angular"], y_offset)
    if comp_type == "health":
        y_offset = _add_number_entry(ins, "current", comp["current"], y_offset)
        y_offset = _add_number_entry(ins, "max", comp["max"], y_offset)
        y_offset = _add_bool_entry(ins, "alive", comp["alive"], y_offset)
    if comp_type == "rigidbody":
        y_offset = _add_number_entry(ins, "mass", comp["mass"], y_offset)
        y_offset = _add_bool_entry(ins, "use_gravity", comp["use_gravity"], y_offset)
        y_offset = _add_bool_entry(ins, "kinematic", comp["is_kinematic"], y_offset)
    if comp_type == "collider":
        y_offset = _add_text_entry(ins, "type", comp["type"], y_offset)
    if comp_type == "camera":
        y_offset = _add_number_entry(ins, "fov", comp["fov"], y_offset)
        y_offset = _add_number_entry(ins, "near", comp["near"], y_offset)
        y_offset = _add_number_entry(ins, "far", comp["far"], y_offset)
    y_offset = y_offset + 6.0
    return y_offset

proc _add_vec3_entry(ins, label, vec, y_offset):
    let x_str = _fmt_num(vec[0])
    let y_str = _fmt_num(vec[1])
    let z_str = _fmt_num(vec[2])
    let text = label + ": " + x_str + ", " + y_str + ", " + z_str
    let lbl = create_label(18.0, y_offset, text, rgba(0.7, 0.7, 0.7, 1.0))
    add_child(ins["panel"], lbl)
    let entry = {"type": "vec3", "label": label, "value": vec}
    push(ins["entries"], entry)
    return y_offset + 16.0

proc _add_number_entry(ins, label, value, y_offset):
    let text = label + ": " + _fmt_num(value)
    let lbl = create_label(18.0, y_offset, text, rgba(0.7, 0.7, 0.7, 1.0))
    add_child(ins["panel"], lbl)
    let entry = {"type": "number", "label": label, "value": value}
    push(ins["entries"], entry)
    return y_offset + 16.0

proc _add_text_entry(ins, label, value, y_offset):
    let text = label + ": " + str(value)
    let lbl = create_label(18.0, y_offset, text, rgba(0.7, 0.7, 0.7, 1.0))
    add_child(ins["panel"], lbl)
    let entry = {"type": "text", "label": label, "value": value}
    push(ins["entries"], entry)
    return y_offset + 16.0

proc _add_bool_entry(ins, label, value, y_offset):
    let text = label + ": "
    if value:
        text = text + "true"
    else:
        text = text + "false"
    let lbl = create_label(18.0, y_offset, text, rgba(0.7, 0.7, 0.7, 1.0))
    add_child(ins["panel"], lbl)
    let entry = {"type": "bool", "label": label, "value": value}
    push(ins["entries"], entry)
    return y_offset + 16.0

proc _fmt_num(n):
    import math
    let rounded = math.floor(n * 100.0 + 0.5) / 100.0
    return str(rounded)

# ============================================================================
# Refresh (re-read values from entity)
# ============================================================================
proc refresh_inspector(ins):
    if ins["selected_entity"] >= 0 and ins["selected_world"] != nil:
        _rebuild_entries(ins)
