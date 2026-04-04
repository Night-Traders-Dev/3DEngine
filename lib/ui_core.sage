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

proc color_lerp(a, b, t):
    if t < 0.0:
        t = 0.0
    if t > 1.0:
        t = 1.0
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t]

proc color_brighten(c, factor):
    let r = c[0] * factor
    let g = c[1] * factor
    let b = c[2] * factor
    if r > 1.0:
        r = 1.0
    if g > 1.0:
        g = 1.0
    if b > 1.0:
        b = 1.0
    return [r, g, b, c[3]]

proc color_with_alpha(c, a):
    return [c[0], c[1], c[2], a]

# ============================================================================
# Theme — Forge Engine (UE5-inspired dark neutral + blue accent)
# Centralized: every UI file should reference these instead of hardcoding
# ============================================================================

# --- Spacing & sizing ---
let SP_XS = 2.0
let SP_SM = 4.0
let SP_MD = 8.0
let SP_LG = 12.0
let SP_XL = 16.0
let SP_XXL = 24.0

let BORDER_THIN = 1.0
let BORDER_NORMAL = 2.0

let RADIUS_SM = 3.0
let RADIUS_MD = 6.0

# --- Panel & surface colors (wider spread for contrast) ---
let THEME_BG = rgba(0.098, 0.098, 0.106, 1.0)
let THEME_SURFACE = rgba(0.137, 0.137, 0.149, 1.0)
let THEME_PANEL = rgba(0.161, 0.165, 0.176, 1.0)
let THEME_HEADER = rgba(0.208, 0.212, 0.224, 1.0)
let THEME_ELEVATED = rgba(0.243, 0.247, 0.259, 1.0)

# --- Interactive element colors ---
let THEME_BUTTON = rgba(0.239, 0.243, 0.263, 1.0)
let THEME_BUTTON_HOVER = rgba(0.298, 0.306, 0.329, 1.0)
let THEME_BUTTON_ACTIVE = rgba(0.200, 0.204, 0.224, 1.0)
let THEME_BUTTON_DISABLED = rgba(0.180, 0.180, 0.192, 0.6)

# --- Accent colors ---
let THEME_ACCENT = rgba(0.302, 0.573, 0.859, 1.0)
let THEME_ACCENT_HOVER = rgba(0.369, 0.639, 0.929, 1.0)
let THEME_ACCENT_ACTIVE = rgba(0.243, 0.494, 0.769, 1.0)
let THEME_ACCENT_DIM = rgba(0.302, 0.573, 0.859, 0.35)

# --- Semantic colors ---
let THEME_SUCCESS = rgba(0.306, 0.718, 0.376, 1.0)
let THEME_SUCCESS_DIM = rgba(0.306, 0.718, 0.376, 0.15)
let THEME_WARNING = rgba(0.918, 0.741, 0.216, 1.0)
let THEME_WARNING_DIM = rgba(0.918, 0.741, 0.216, 0.15)
let THEME_DANGER = rgba(0.859, 0.278, 0.278, 1.0)
let THEME_DANGER_DIM = rgba(0.859, 0.278, 0.278, 0.15)
let THEME_INFO = rgba(0.302, 0.573, 0.859, 1.0)

# --- Text colors ---
let THEME_TEXT = rgba(0.843, 0.851, 0.871, 1.0)
let THEME_TEXT_SECONDARY = rgba(0.557, 0.569, 0.600, 1.0)
let THEME_TEXT_DIM = rgba(0.400, 0.408, 0.435, 1.0)
let THEME_TEXT_BRIGHT = rgba(0.949, 0.953, 0.961, 1.0)

# --- Borders & dividers ---
let THEME_BORDER = rgba(0.118, 0.122, 0.133, 1.0)
let THEME_BORDER_LIGHT = rgba(0.220, 0.224, 0.243, 1.0)
let THEME_BORDER_FOCUS = rgba(0.302, 0.573, 0.859, 0.7)

# --- Input fields ---
let THEME_INPUT_BG = rgba(0.082, 0.082, 0.094, 1.0)
let THEME_INPUT_HOVER = rgba(0.098, 0.098, 0.110, 1.0)
let THEME_INPUT_FOCUS = rgba(0.090, 0.090, 0.106, 1.0)

# --- Selection & highlights ---
let THEME_SELECT = rgba(0.302, 0.573, 0.859, 0.20)
let THEME_HIGHLIGHT = rgba(1.0, 1.0, 1.0, 0.04)

# --- Shadows ---
let THEME_SHADOW = rgba(0.0, 0.0, 0.0, 0.40)
let THEME_SHADOW_SOFT = rgba(0.0, 0.0, 0.0, 0.20)

# --- Separator ---
let THEME_SEPARATOR = rgba(0.188, 0.192, 0.208, 0.6)

# --- Overlay ---
let THEME_OVERLAY = rgba(0.0, 0.0, 0.02, 0.65)

# --- Basic named colors ---
let COLOR_WHITE = rgba(1.0, 1.0, 1.0, 1.0)
let COLOR_BLACK = rgba(0.0, 0.0, 0.0, 1.0)
let COLOR_RED = rgba(1.0, 0.2, 0.2, 1.0)
let COLOR_GREEN = rgba(0.2, 1.0, 0.2, 1.0)
let COLOR_BLUE = rgba(0.2, 0.2, 1.0, 1.0)
let COLOR_YELLOW = rgba(1.0, 1.0, 0.2, 1.0)
let COLOR_GRAY = rgba(0.5, 0.5, 0.5, 1.0)
let COLOR_DARK = rgba(0.15, 0.15, 0.15, 0.85)
let COLOR_TRANSPARENT = rgba(0.0, 0.0, 0.0, 0.0)

# --- Font sizing ---
let FONT_SM = 1.8
let FONT_MD = 2.2
let FONT_LG = 2.8
let FONT_XL = 3.5
let FONT_TITLE = 4.5

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
    w["enabled"] = true
    w["color"] = THEME_TEXT
    w["bg_color"] = COLOR_TRANSPARENT
    w["border_color"] = COLOR_TRANSPARENT
    w["border_width"] = 0.0
    w["children"] = []
    w["parent"] = nil
    w["computed_x"] = 0.0
    w["computed_y"] = 0.0
    w["tag"] = ""
    w["on_click"] = nil
    w["hovered"] = false
    w["pressed"] = false
    w["data"] = nil
    w["opacity"] = 1.0
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
    widget["border_color"] = THEME_BORDER
    widget["border_width"] = BORDER_THIN
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
    widget["hover_color"] = color_brighten(bg_color, 1.25)
    widget["active_color"] = color_brighten(bg_color, 0.8)
    widget["disabled_color"] = color_with_alpha(bg_color, 0.4)
    widget["border_color"] = color_with_alpha(THEME_BORDER_LIGHT, 0.5)
    widget["border_width"] = BORDER_THIN
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
    widget["border_color"] = THEME_BORDER_LIGHT
    widget["border_width"] = BORDER_THIN
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
# Quad helpers for borders and shadows
# ============================================================================
proc _push_border_quads(quads, x, y, w, h, bw, color):
    if bw < 0.5 or color[3] < 0.01:
        return nil
    # Top
    push(quads, {"x": x, "y": y, "w": w, "h": bw, "color": color})
    # Bottom
    push(quads, {"x": x, "y": y + h - bw, "w": w, "h": bw, "color": color})
    # Left
    push(quads, {"x": x, "y": y + bw, "w": bw, "h": h - bw * 2.0, "color": color})
    # Right
    push(quads, {"x": x + w - bw, "y": y + bw, "w": bw, "h": h - bw * 2.0, "color": color})

proc _push_shadow_quads(quads, x, y, w, h):
    push(quads, {"x": x + 3.0, "y": y + 3.0, "w": w, "h": h, "color": [0.0, 0.0, 0.0, 0.30]})
    push(quads, {"x": x + 1.5, "y": y + 1.5, "w": w, "h": h, "color": [0.0, 0.0, 0.0, 0.15]})

proc _push_inset_quads(quads, x, y, w, h):
    # Subtle inner shadow for recessed elements (inputs, progress bars)
    push(quads, {"x": x, "y": y, "w": w, "h": 1.0, "color": [0.0, 0.0, 0.0, 0.25]})
    push(quads, {"x": x, "y": y, "w": 1.0, "h": h, "color": [0.0, 0.0, 0.0, 0.15]})

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
    let is_enabled = true
    if dict_has(widget, "enabled"):
        is_enabled = widget["enabled"]

    # Resolve background color based on state
    let bg = widget["bg_color"]
    if wtype == "button":
        if is_enabled == false:
            if dict_has(widget, "disabled_color"):
                bg = widget["disabled_color"]
        else:
            if widget["pressed"] and dict_has(widget, "active_color"):
                bg = widget["active_color"]
            else:
                if widget["hovered"] and dict_has(widget, "hover_color"):
                    bg = widget["hover_color"]
    if wtype == "toolbar_btn":
        if dict_has(widget, "is_active") and widget["is_active"]:
            bg = widget["active_color"]
        else:
            if widget["hovered"] and dict_has(widget, "hover_color"):
                bg = widget["hover_color"]

    # Apply widget opacity
    let op = 1.0
    if dict_has(widget, "opacity"):
        op = widget["opacity"]

    # Draw background
    if bg[3] * op > 0.001:
        let draw_bg = [bg[0], bg[1], bg[2], bg[3] * op]
        push(quads, {"x": x, "y": y, "w": w, "h": h, "color": draw_bg})

    # Hover highlight (subtle luminance overlay)
    if wtype == "button" and widget["hovered"] and is_enabled and widget["pressed"] == false:
        push(quads, {"x": x, "y": y, "w": w, "h": 1.0, "color": [1.0, 1.0, 1.0, 0.06]})

    # Progress bar fill
    if wtype == "progress":
        let fill_w = w * clamp(widget["value"], 0.0, 1.0)
        if fill_w > 0.0:
            push(quads, {"x": x, "y": y, "w": fill_w, "h": h, "color": widget["fill_color"]})
            # Sheen on progress fill
            push(quads, {"x": x, "y": y, "w": fill_w, "h": 1.0, "color": [1.0, 1.0, 1.0, 0.1]})
        _push_inset_quads(quads, x, y, w, h)

    # Colored rect
    if wtype == "rect":
        let c = widget["color"]
        if c[3] * op > 0.001:
            push(quads, {"x": x, "y": y, "w": w, "h": h, "color": [c[0], c[1], c[2], c[3] * op]})

    # Border
    let bc = widget["border_color"]
    let bw = widget["border_width"]
    if bw > 0.0 and bc[3] * op > 0.01:
        let draw_bc = [bc[0], bc[1], bc[2], bc[3] * op]
        _push_border_quads(quads, x, y, w, h, bw, draw_bc)

    # Focus ring for buttons/inputs when hovered
    if wtype == "button" and widget["hovered"] and is_enabled:
        let fc = THEME_BORDER_FOCUS
        _push_border_quads(quads, x - 1.0, y - 1.0, w + 2.0, h + 2.0, 1.0, [fc[0], fc[1], fc[2], fc[3] * 0.5])

    # Children
    let i = 0
    while i < len(widget["children"]):
        collect_quads(widget["children"][i], quads)
        i = i + 1

# ============================================================================
# Input dispatch (hover + click + pressed state)
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

proc _update_pressed_recursive(widget, mx, my, left_held):
    if widget["visible"] == false:
        widget["pressed"] = false
        return nil
    widget["pressed"] = widget["hovered"] and left_held
    let i = 0
    while i < len(widget["children"]):
        _update_pressed_recursive(widget["children"][i], mx, my, left_held)
        i = i + 1

proc _hit_test_top(widget, mx, my):
    if widget["visible"] == false:
        return nil
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
    let is_enabled = true
    if dict_has(hit, "enabled"):
        is_enabled = hit["enabled"]
    if hit["on_click"] != nil and is_enabled:
        hit["on_click"]()
    return true

proc process_ui_input(root, mx, my, left_pressed, left_held):
    update_hover_state(root, mx, my)
    _update_pressed_recursive(root, mx, my, left_held)
    if left_pressed:
        return dispatch_click(root, mx, my)
    return false
