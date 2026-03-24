gc_disable()
# -----------------------------------------
# ui_widgets.sage - Advanced UI widgets for Sage Engine Editor
# Scroll panels, tree views, sliders, checkboxes, dropdowns, text fields
# -----------------------------------------

import ui_core
from ui_core import create_widget, create_panel, create_rect, create_label
from ui_core import add_child

# ============================================================================
# Color theme — Forge Engine (UE5-inspired neutral dark grey + blue accent)
# ============================================================================
# BG: #191919  Panel: #242424  Header: #2D2D2D  Accent: #4A90D9
let THEME_BG = ui_core.rgba(0.098, 0.098, 0.098, 1.0)
let THEME_PANEL = ui_core.rgba(0.141, 0.141, 0.141, 1.0)
let THEME_HEADER = ui_core.rgba(0.176, 0.176, 0.176, 1.0)
let THEME_BUTTON = ui_core.rgba(0.212, 0.212, 0.212, 1.0)
let THEME_BUTTON_HOVER = ui_core.rgba(0.259, 0.259, 0.259, 1.0)
let THEME_ACCENT = ui_core.rgba(0.290, 0.565, 0.851, 1.0)
let THEME_ACCENT_HOVER = ui_core.rgba(0.357, 0.627, 0.914, 1.0)
let THEME_TEXT = ui_core.rgba(0.784, 0.784, 0.784, 1.0)
let THEME_TEXT_DIM = ui_core.rgba(0.439, 0.439, 0.439, 1.0)
let THEME_BORDER = ui_core.rgba(0.082, 0.082, 0.082, 1.0)
let THEME_INPUT_BG = ui_core.rgba(0.110, 0.110, 0.110, 1.0)
let THEME_SELECT = ui_core.rgba(0.290, 0.565, 0.851, 0.25)
let THEME_SEPARATOR = ui_core.rgba(0.212, 0.212, 0.212, 1.0)

# ============================================================================
# Toolbar button
# ============================================================================
proc create_toolbar_button(x, y, width, label, tooltip, on_click):
    let btn = create_widget("toolbar_btn")
    btn["x"] = x
    btn["y"] = y
    btn["width"] = width
    btn["height"] = 28.0
    btn["bg_color"] = THEME_BUTTON
    btn["hover_color"] = THEME_BUTTON_HOVER
    btn["active_color"] = THEME_ACCENT
    btn["text"] = label
    btn["tooltip"] = tooltip
    btn["on_click"] = on_click
    btn["is_active"] = false
    return btn

# ============================================================================
# Scrollable panel
# ============================================================================
proc create_scroll_panel(x, y, w, h, content_height):
    let sp = create_widget("scroll_panel")
    sp["x"] = x
    sp["y"] = y
    sp["width"] = w
    sp["height"] = h
    sp["bg_color"] = THEME_PANEL
    sp["content_height"] = content_height
    sp["scroll_y"] = 0.0
    sp["max_scroll"] = 0.0
    if content_height > h:
        sp["max_scroll"] = content_height - h
    sp["scroll_speed"] = 20.0
    return sp

proc scroll_panel_scroll(sp, delta):
    sp["scroll_y"] = sp["scroll_y"] + delta
    if sp["scroll_y"] < 0.0:
        sp["scroll_y"] = 0.0
    if sp["scroll_y"] > sp["max_scroll"]:
        sp["scroll_y"] = sp["max_scroll"]

proc scroll_panel_update_content(sp, new_height):
    sp["content_height"] = new_height
    if new_height > sp["height"]:
        sp["max_scroll"] = new_height - sp["height"]
    else:
        sp["max_scroll"] = 0.0
    if sp["scroll_y"] > sp["max_scroll"]:
        sp["scroll_y"] = sp["max_scroll"]

# ============================================================================
# Tree view node
# ============================================================================
proc create_tree_node(label, data, depth):
    let tn = {}
    tn["label"] = label
    tn["data"] = data
    tn["depth"] = depth
    tn["expanded"] = true
    tn["selected"] = false
    tn["children"] = []
    tn["visible"] = true
    return tn

proc add_tree_child(parent, child):
    push(parent["children"], child)

proc toggle_tree_expand(node):
    node["expanded"] = node["expanded"] == false

proc flatten_tree(node, result, filter_text):
    if node["visible"] == false:
        return nil
    if filter_text != "" and filter_text != nil:
        if contains(node["label"], filter_text) == false:
            # Still check children
            let i = 0
            while i < len(node["children"]):
                flatten_tree(node["children"][i], result, filter_text)
                i = i + 1
            return nil
    push(result, node)
    if node["expanded"]:
        let i = 0
        while i < len(node["children"]):
            flatten_tree(node["children"][i], result, filter_text)
            i = i + 1

# ============================================================================
# Slider
# ============================================================================
proc create_slider(x, y, width, min_val, max_val, value):
    let sl = create_widget("slider")
    sl["x"] = x
    sl["y"] = y
    sl["width"] = width
    sl["height"] = 18.0
    sl["bg_color"] = THEME_INPUT_BG
    sl["min_val"] = min_val
    sl["max_val"] = max_val
    sl["value"] = value
    sl["dragging"] = false
    sl["label"] = ""
    return sl

proc slider_normalized(sl):
    let range = sl["max_val"] - sl["min_val"]
    if range < 0.0001:
        return 0.0
    return (sl["value"] - sl["min_val"]) / range

proc set_slider_from_normalized(sl, t):
    if t < 0.0:
        t = 0.0
    if t > 1.0:
        t = 1.0
    sl["value"] = sl["min_val"] + t * (sl["max_val"] - sl["min_val"])

# ============================================================================
# Checkbox
# ============================================================================
proc create_checkbox(x, y, label, checked):
    let cb = create_widget("checkbox")
    cb["x"] = x
    cb["y"] = y
    cb["width"] = 16.0
    cb["height"] = 16.0
    cb["bg_color"] = THEME_INPUT_BG
    cb["check_color"] = THEME_ACCENT
    cb["checked"] = checked
    cb["label_text"] = label
    cb["on_change"] = nil
    return cb

proc toggle_checkbox(cb):
    cb["checked"] = cb["checked"] == false
    if cb["on_change"] != nil:
        cb["on_change"](cb["checked"])

# ============================================================================
# Dropdown / combo box
# ============================================================================
proc create_dropdown(x, y, width, options, selected_index):
    let dd = create_widget("dropdown")
    dd["x"] = x
    dd["y"] = y
    dd["width"] = width
    dd["height"] = 22.0
    dd["bg_color"] = THEME_INPUT_BG
    dd["options"] = options
    dd["selected"] = selected_index
    dd["open"] = false
    dd["on_change"] = nil
    return dd

proc dropdown_value(dd):
    if dd["selected"] < 0 or dd["selected"] >= len(dd["options"]):
        return ""
    return dd["options"][dd["selected"]]

proc set_dropdown_index(dd, idx):
    dd["selected"] = idx
    dd["open"] = false
    if dd["on_change"] != nil:
        dd["on_change"](idx)

# ============================================================================
# Text input field (display only for now, value set programmatically)
# ============================================================================
proc create_text_field(x, y, width, value):
    let tf = create_widget("text_field")
    tf["x"] = x
    tf["y"] = y
    tf["width"] = width
    tf["height"] = 20.0
    tf["bg_color"] = THEME_INPUT_BG
    tf["text_value"] = value
    tf["focused"] = false
    tf["cursor_pos"] = len(value)
    tf["on_change"] = nil
    return tf

proc set_text_field_value(tf, value):
    tf["text_value"] = value
    tf["cursor_pos"] = len(value)

# ============================================================================
# Number input (value + drag to adjust)
# ============================================================================
proc create_number_field(x, y, width, value, step):
    let nf = create_widget("number_field")
    nf["x"] = x
    nf["y"] = y
    nf["width"] = width
    nf["height"] = 20.0
    nf["bg_color"] = THEME_INPUT_BG
    nf["value"] = value
    nf["step"] = step
    nf["min_val"] = -99999.0
    nf["max_val"] = 99999.0
    nf["dragging"] = false
    nf["on_change"] = nil
    return nf

proc adjust_number_field(nf, delta):
    nf["value"] = nf["value"] + delta * nf["step"]
    if nf["value"] < nf["min_val"]:
        nf["value"] = nf["min_val"]
    if nf["value"] > nf["max_val"]:
        nf["value"] = nf["max_val"]
    if nf["on_change"] != nil:
        nf["on_change"](nf["value"])

# ============================================================================
# Separator line
# ============================================================================
proc create_separator(x, y, width):
    return create_rect(x, y, width, 1.0, THEME_SEPARATOR)

# ============================================================================
# Section header (collapsible)
# ============================================================================
proc create_section_header(x, y, width, title):
    let sh = create_widget("section_header")
    sh["x"] = x
    sh["y"] = y
    sh["width"] = width
    sh["height"] = 22.0
    sh["bg_color"] = THEME_HEADER
    sh["text"] = title
    sh["expanded"] = true
    return sh

proc toggle_section(sh):
    sh["expanded"] = sh["expanded"] == false
