gc_disable()
# -----------------------------------------
# inspector.sage - Property inspector for Sage Engine Editor
# View and edit entity components via UI panels
# Uses centralized theme from ui_core
# -----------------------------------------

from ecs import get_component, has_component
from math3d import vec3
import ui_core
from ui_core import create_widget, create_panel, create_rect, create_label
from ui_core import add_child, rgba, color_with_alpha

# ============================================================================
# Inspector
# ============================================================================
proc create_inspector():
    let ins = {}
    ins["selected_entity"] = -1
    ins["selected_world"] = nil
    ins["panel"] = create_panel(0.0, 0.0, 260.0, 500.0, ui_core.THEME_PANEL)
    ins["panel"]["anchor"] = ui_core.ANCHOR_TOP_RIGHT
    ins["panel"]["x"] = -270.0
    ins["panel"]["y"] = ui_core.SP_LG
    ins["panel"]["border_color"] = ui_core.THEME_BORDER
    ins["panel"]["border_width"] = ui_core.BORDER_THIN
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
    let y_offset = ui_core.SP_MD

    # Header with accent left bar
    let header_bg = create_rect(0.0, y_offset, 260.0, 28.0, ui_core.THEME_HEADER)
    add_child(ins["panel"], header_bg)
    let header_accent = create_rect(0.0, y_offset, 3.0, 28.0, color_with_alpha(ui_core.THEME_ACCENT, 0.7))
    add_child(ins["panel"], header_accent)
    let header = create_label(ui_core.SP_LG, y_offset + 6.0, "Entity #" + str(eid), ui_core.THEME_TEXT_BRIGHT)
    add_child(ins["panel"], header)
    y_offset = y_offset + 34.0

    # Separator
    let sep = create_rect(ui_core.SP_MD, y_offset, 244.0, 1.0, ui_core.THEME_SEPARATOR)
    add_child(ins["panel"], sep)
    y_offset = y_offset + ui_core.SP_MD

    # Components
    let types = ins["component_types"]
    let i = 0
    while i < len(types):
        let ct = types[i]
        if has_component(w, eid, ct):
            let comp = get_component(w, eid, ct)
            y_offset = _add_component_section(ins, ct, comp, y_offset)
        i = i + 1
    ins["panel"]["height"] = y_offset + ui_core.SP_LG

proc _add_component_section(ins, comp_type, comp, y_offset):
    # Section header with accent left bar
    let hdr = create_rect(ui_core.SP_MD, y_offset, 244.0, 22.0, ui_core.THEME_HEADER)
    hdr["border_color"] = ui_core.THEME_BORDER
    hdr["border_width"] = ui_core.BORDER_THIN
    add_child(ins["panel"], hdr)
    let accent = create_rect(ui_core.SP_MD, y_offset, 3.0, 22.0, color_with_alpha(ui_core.THEME_ACCENT, 0.5))
    add_child(ins["panel"], accent)
    let lbl = create_label(ui_core.SP_XL + ui_core.SP_SM, y_offset + 3.0, comp_type, ui_core.THEME_TEXT)
    add_child(ins["panel"], lbl)
    y_offset = y_offset + 26.0

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
    y_offset = y_offset + ui_core.SP_MD
    return y_offset

proc _add_vec3_entry(ins, label, vec, y_offset):
    let x_str = _fmt_num(vec[0])
    let y_str = _fmt_num(vec[1])
    let z_str = _fmt_num(vec[2])
    # Label
    let name_lbl = create_label(ui_core.SP_XL, y_offset + 1.0, label, ui_core.THEME_TEXT_SECONDARY)
    add_child(ins["panel"], name_lbl)
    # Value (offset right)
    let val_text = x_str + ", " + y_str + ", " + z_str
    let val_lbl = create_label(90.0, y_offset + 1.0, val_text, ui_core.THEME_TEXT)
    add_child(ins["panel"], val_lbl)
    let entry = {"type": "vec3", "label": label, "value": vec}
    push(ins["entries"], entry)
    return y_offset + 18.0

proc _add_number_entry(ins, label, value, y_offset):
    let name_lbl = create_label(ui_core.SP_XL, y_offset + 1.0, label, ui_core.THEME_TEXT_SECONDARY)
    add_child(ins["panel"], name_lbl)
    let val_lbl = create_label(90.0, y_offset + 1.0, _fmt_num(value), ui_core.THEME_TEXT)
    add_child(ins["panel"], val_lbl)
    let entry = {"type": "number", "label": label, "value": value}
    push(ins["entries"], entry)
    return y_offset + 18.0

proc _add_text_entry(ins, label, value, y_offset):
    let name_lbl = create_label(ui_core.SP_XL, y_offset + 1.0, label, ui_core.THEME_TEXT_SECONDARY)
    add_child(ins["panel"], name_lbl)
    let val_lbl = create_label(90.0, y_offset + 1.0, str(value), ui_core.THEME_TEXT)
    add_child(ins["panel"], val_lbl)
    let entry = {"type": "text", "label": label, "value": value}
    push(ins["entries"], entry)
    return y_offset + 18.0

proc _add_bool_entry(ins, label, value, y_offset):
    let name_lbl = create_label(ui_core.SP_XL, y_offset + 1.0, label, ui_core.THEME_TEXT_SECONDARY)
    add_child(ins["panel"], name_lbl)
    let val_text = "false"
    let val_color = ui_core.THEME_DANGER
    if value:
        val_text = "true"
        val_color = ui_core.THEME_SUCCESS
    let val_lbl = create_label(90.0, y_offset + 1.0, val_text, val_color)
    add_child(ins["panel"], val_lbl)
    let entry = {"type": "bool", "label": label, "value": value}
    push(ins["entries"], entry)
    return y_offset + 18.0

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
