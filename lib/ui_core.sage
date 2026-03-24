gc_disable()
# -----------------------------------------
# ui_core.sage - Core UI widget system for Sage Engine
# Screen-space widgets with anchoring, colors, hierarchy
# Renders colored quads via a batched vertex buffer
# -----------------------------------------

import gpu
from engine_math import clamp

# ============================================================================
# Anchor presets
# ============================================================================
let ANCHOR_TOP_LEFT = "top_left"
let ANCHOR_TOP_CENTER = "top_center"
let ANCHOR_TOP_RIGHT = "top_right"
let ANCHOR_CENTER_LEFT = "center_left"
let ANCHOR_CENTER = "center"
let ANCHOR_CENTER_RIGHT = "center_right"
let ANCHOR_BOTTOM_LEFT = "bottom_left"
let ANCHOR_BOTTOM_CENTER = "bottom_center"
let ANCHOR_BOTTOM_RIGHT = "bottom_right"

# ============================================================================
# Color helpers
# ============================================================================
proc rgba(r, g, b, a):
    return [r, g, b, a]

proc rgb(r, g, b):
    return [r, g, b, 1.0]

let COLOR_WHITE = rgba(1.0, 1.0, 1.0, 1.0)
let COLOR_BLACK = rgba(0.0, 0.0, 0.0, 1.0)
let COLOR_RED = rgba(1.0, 0.2, 0.2, 1.0)
let COLOR_GREEN = rgba(0.2, 1.0, 0.2, 1.0)
let COLOR_BLUE = rgba(0.2, 0.2, 1.0, 1.0)
let COLOR_YELLOW = rgba(1.0, 1.0, 0.2, 1.0)
let COLOR_GRAY = rgba(0.5, 0.5, 0.5, 1.0)
let COLOR_DARK = rgba(0.15, 0.15, 0.15, 0.85)
let COLOR_TRANSPARENT = rgba(0.0, 0.0, 0.0, 0.0)

# ============================================================================
# Base Widget
# ============================================================================
let _widget_next_id = [1]

proc create_widget(widget_type):
    let w = {}
    w["_id"] = _widget_next_id[0]
    _widget_next_id[0] = _widget_next_id[0] + 1
    w["type"] = widget_type
    w["x"] = 0.0
    w["y"] = 0.0
    w["width"] = 100.0
    w["height"] = 30.0
    w["anchor"] = ANCHOR_TOP_LEFT
    w["margin_x"] = 0.0
    w["margin_y"] = 0.0
    w["visible"] = true
    w["color"] = COLOR_WHITE
    w["bg_color"] = COLOR_TRANSPARENT
    w["children"] = []
    w["parent"] = nil
    w["computed_x"] = 0.0
    w["computed_y"] = 0.0
    w["tag"] = ""
    w["on_click"] = nil
    w["hovered"] = false
    w["data"] = nil
    return w

# ============================================================================
# Widget types
# ============================================================================
proc create_panel(x, y, w, h, bg_color):
    let widget = create_widget("panel")
    widget["x"] = x
    widget["y"] = y
    widget["width"] = w
    widget["height"] = h
    widget["bg_color"] = bg_color
    return widget

proc create_rect(x, y, w, h, color):
    let widget = create_widget("rect")
    widget["x"] = x
    widget["y"] = y
    widget["width"] = w
    widget["height"] = h
    widget["color"] = color
    widget["bg_color"] = color
    return widget

proc create_label(x, y, text, color):
    let widget = create_widget("label")
    widget["x"] = x
    widget["y"] = y
    widget["text"] = text
    widget["color"] = color
    widget["font_size"] = 16.0
    widget["width"] = len(text) * 8.0
    widget["height"] = 16.0
    return widget

proc create_button(x, y, w, h, label, bg_color, on_click):
    let widget = create_widget("button")
    widget["x"] = x
    widget["y"] = y
    widget["width"] = w
    widget["height"] = h
    widget["text"] = label
    widget["bg_color"] = bg_color
    widget["hover_color"] = [bg_color[0] * 1.3, bg_color[1] * 1.3, bg_color[2] * 1.3, bg_color[3]]
    widget["on_click"] = on_click
    return widget

proc create_progress_bar(x, y, w, h, value, bg_color, fill_color):
    let widget = create_widget("progress")
    widget["x"] = x
    widget["y"] = y
    widget["width"] = w
    widget["height"] = h
    widget["value"] = value
    widget["bg_color"] = bg_color
    widget["fill_color"] = fill_color
    return widget

proc create_image_rect(x, y, w, h):
    let widget = create_widget("image")
    widget["x"] = x
    widget["y"] = y
    widget["width"] = w
    widget["height"] = h
    return widget

# ============================================================================
# Hierarchy
# ============================================================================
proc add_child(parent, child):
    push(parent["children"], child)
    child["parent"] = parent

proc remove_child(parent, child):
    let child_id = child["_id"]
    let new_children = []
    let i = 0
    while i < len(parent["children"]):
        if parent["children"][i]["_id"] != child_id:
            push(new_children, parent["children"][i])
        i = i + 1
    parent["children"] = new_children
    child["parent"] = nil

# ============================================================================
# Layout computation
# ============================================================================
proc compute_anchor_offset(anchor, parent_w, parent_h, child_w, child_h):
    let ox = 0.0
    let oy = 0.0
    if anchor == ANCHOR_TOP_LEFT:
        ox = 0.0
        oy = 0.0
    if anchor == ANCHOR_TOP_CENTER:
        ox = (parent_w - child_w) / 2.0
        oy = 0.0
    if anchor == ANCHOR_TOP_RIGHT:
        ox = parent_w - child_w
        oy = 0.0
    if anchor == ANCHOR_CENTER_LEFT:
        ox = 0.0
        oy = (parent_h - child_h) / 2.0
    if anchor == ANCHOR_CENTER:
        ox = (parent_w - child_w) / 2.0
        oy = (parent_h - child_h) / 2.0
    if anchor == ANCHOR_CENTER_RIGHT:
        ox = parent_w - child_w
        oy = (parent_h - child_h) / 2.0
    if anchor == ANCHOR_BOTTOM_LEFT:
        ox = 0.0
        oy = parent_h - child_h
    if anchor == ANCHOR_BOTTOM_CENTER:
        ox = (parent_w - child_w) / 2.0
        oy = parent_h - child_h
    if anchor == ANCHOR_BOTTOM_RIGHT:
        ox = parent_w - child_w
        oy = parent_h - child_h
    return [ox, oy]

proc compute_layout(widget, parent_x, parent_y, parent_w, parent_h):
    let anchor_off = compute_anchor_offset(widget["anchor"], parent_w, parent_h, widget["width"], widget["height"])
    widget["computed_x"] = parent_x + anchor_off[0] + widget["x"] + widget["margin_x"]
    widget["computed_y"] = parent_y + anchor_off[1] + widget["y"] + widget["margin_y"]
    # Compute children
    let i = 0
    while i < len(widget["children"]):
        compute_layout(widget["children"][i], widget["computed_x"], widget["computed_y"], widget["width"], widget["height"])
        i = i + 1

# ============================================================================
# Hit testing
# ============================================================================
proc point_in_widget(widget, mx, my):
    let x = widget["computed_x"]
    let y = widget["computed_y"]
    return mx >= x and mx <= x + widget["width"] and my >= y and my <= y + widget["height"]

# ============================================================================
# Collect visible quads for rendering
# ============================================================================
proc collect_quads(widget, quads):
    if widget["visible"] == false:
        return nil
    let x = widget["computed_x"]
    let y = widget["computed_y"]
    let w = widget["width"]
    let h = widget["height"]
    let wtype = widget["type"]
    # Background quad
    let bg = widget["bg_color"]
    if wtype == "button" and widget["hovered"]:
        bg = widget["hover_color"]
    if bg[3] > 0.001:
        push(quads, {"x": x, "y": y, "w": w, "h": h, "color": bg})
    # Progress bar fill
    if wtype == "progress":
        let fill_w = w * clamp(widget["value"], 0.0, 1.0)
        if fill_w > 0.0:
            push(quads, {"x": x, "y": y, "w": fill_w, "h": h, "color": widget["fill_color"]})
    # Colored rect
    if wtype == "rect":
        let c = widget["color"]
        if c[3] > 0.001:
            push(quads, {"x": x, "y": y, "w": w, "h": h, "color": c})
    # Children
    let i = 0
    while i < len(widget["children"]):
        collect_quads(widget["children"][i], quads)
        i = i + 1

# ============================================================================
# Input dispatch (hover + click)
# ============================================================================
proc _update_hover_recursive(widget, mx, my):
    if widget["visible"] == false:
        widget["hovered"] = false
        return false
    let inside = point_in_widget(widget, mx, my)
    widget["hovered"] = inside
    let i = 0
    while i < len(widget["children"]):
        _update_hover_recursive(widget["children"][i], mx, my)
        i = i + 1
    return inside

proc update_hover_state(root, mx, my):
    return _update_hover_recursive(root, mx, my)

proc _hit_test_top(widget, mx, my):
    if widget["visible"] == false:
        return nil
    # Children are considered top-most in insertion order; scan in reverse.
    let i = len(widget["children"]) - 1
    while i >= 0:
        let hit = _hit_test_top(widget["children"][i], mx, my)
        if hit != nil:
            return hit
        i = i - 1
    if point_in_widget(widget, mx, my):
        return widget
    return nil

proc dispatch_click(root, mx, my):
    let hit = _hit_test_top(root, mx, my)
    if hit == nil:
        return false
    if hit["on_click"] != nil:
        hit["on_click"]()
    return true

proc process_ui_input(root, mx, my, left_pressed):
    update_hover_state(root, mx, my)
    if left_pressed:
        return dispatch_click(root, mx, my)
    return false
