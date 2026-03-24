gc_disable()
# -----------------------------------------
# ui_widgets.sage - Advanced UI widgets for Sage Engine Editor
# Scroll panels, tree views, sliders, checkboxes, dropdowns, text fields
# All widgets use the centralized theme from ui_core
# -----------------------------------------

import gpu
import ui_core
from ui_core import create_widget, create_panel, create_rect, create_label
from ui_core import add_child
from ui_core import rgba, color_brighten, color_with_alpha, color_lerp
from ui_core import _push_border_quads, _push_inset_quads, _push_shadow_quads
from engine_math import clamp

# ============================================================================
# Re-export theme from ui_core for backward compat
# ============================================================================
let THEME_BG = ui_core.THEME_BG
let THEME_PANEL = ui_core.THEME_PANEL
let THEME_HEADER = ui_core.THEME_HEADER
let THEME_BUTTON = ui_core.THEME_BUTTON
let THEME_BUTTON_HOVER = ui_core.THEME_BUTTON_HOVER
let THEME_ACCENT = ui_core.THEME_ACCENT
let THEME_ACCENT_HOVER = ui_core.THEME_ACCENT_HOVER
let THEME_TEXT = ui_core.THEME_TEXT
let THEME_TEXT_DIM = ui_core.THEME_TEXT_SECONDARY
let THEME_BORDER = ui_core.THEME_BORDER
let THEME_INPUT_BG = ui_core.THEME_INPUT_BG
let THEME_SELECT = ui_core.THEME_SELECT
let THEME_SEPARATOR = ui_core.THEME_SEPARATOR

# ============================================================================
# Global focus state for text input
# ============================================================================
let _focused_widget = [nil]
let _focus_original_value = [""]

proc focus_text_field(tf):
    _focused_widget[0] = tf
    _focus_original_value[0] = tf["text_value"]
    tf["focused"] = true
    tf["cursor_pos"] = len(tf["text_value"])
    tf["blink_timer"] = 0.0

proc unfocus_text_field():
    if _focused_widget[0] != nil:
        _focused_widget[0]["focused"] = false
    _focused_widget[0] = nil

proc get_focused_widget():
    return _focused_widget[0]

proc is_any_field_focused():
    return _focused_widget[0] != nil

proc text_field_insert_char(tf, ch):
    let v = tf["text_value"]
    let cp = tf["cursor_pos"]
    if cp >= len(v):
        tf["text_value"] = v + ch
    else:
        let before = ""
        let bi = 0
        while bi < cp:
            before = before + char_at(v, bi)
            bi = bi + 1
        let after = ""
        let ai = cp
        while ai < len(v):
            after = after + char_at(v, ai)
            ai = ai + 1
        tf["text_value"] = before + ch + after
    tf["cursor_pos"] = cp + len(ch)

proc text_field_backspace(tf):
    if tf["cursor_pos"] > 0:
        let v = tf["text_value"]
        let cp = tf["cursor_pos"]
        let before = ""
        let bi = 0
        while bi < cp - 1:
            before = before + char_at(v, bi)
            bi = bi + 1
        let after = ""
        let ai = cp
        while ai < len(v):
            after = after + char_at(v, ai)
            ai = ai + 1
        tf["text_value"] = before + after
        tf["cursor_pos"] = cp - 1

proc text_field_delete_char(tf):
    let v = tf["text_value"]
    let cp = tf["cursor_pos"]
    if cp < len(v):
        let before = ""
        let bi = 0
        while bi < cp:
            before = before + char_at(v, bi)
            bi = bi + 1
        let after = ""
        let ai = cp + 1
        while ai < len(v):
            after = after + char_at(v, ai)
            ai = ai + 1
        tf["text_value"] = before + after

proc text_field_move_cursor(tf, delta):
    tf["cursor_pos"] = tf["cursor_pos"] + delta
    if tf["cursor_pos"] < 0:
        tf["cursor_pos"] = 0
    if tf["cursor_pos"] > len(tf["text_value"]):
        tf["cursor_pos"] = len(tf["text_value"])

proc text_field_commit(tf):
    if tf["on_commit"] != nil:
        tf["on_commit"](tf["text_value"])
    unfocus_text_field()

proc text_field_cancel(tf):
    tf["text_value"] = _focus_original_value[0]
    if tf["on_cancel"] != nil:
        tf["on_cancel"]()
    unfocus_text_field()

proc update_text_input(dt):
    let tf = _focused_widget[0]
    if tf == nil:
        return
    tf["blink_timer"] = tf["blink_timer"] + dt
    while gpu.text_input_available():
        let ch = gpu.text_input_read()
        if len(ch) > 0:
            text_field_insert_char(tf, ch)
    if gpu.key_just_pressed(gpu.KEY_BACKSPACE):
        text_field_backspace(tf)
    if gpu.key_just_pressed(gpu.KEY_DELETE):
        text_field_delete_char(tf)
    if gpu.key_just_pressed(gpu.KEY_LEFT):
        text_field_move_cursor(tf, 0 - 1)
    if gpu.key_just_pressed(gpu.KEY_RIGHT):
        text_field_move_cursor(tf, 1)
    if gpu.key_just_pressed(gpu.KEY_HOME):
        tf["cursor_pos"] = 0
    if gpu.key_just_pressed(gpu.KEY_END):
        tf["cursor_pos"] = len(tf["text_value"])
    if gpu.key_just_pressed(gpu.KEY_ENTER):
        text_field_commit(tf)
    if gpu.key_just_pressed(gpu.KEY_ESCAPE):
        text_field_cancel(tf)

proc parse_number(s):
    let result = tonumber(s)
    if result != nil:
        return result
    return 0.0

# ============================================================================
# Toolbar button
# ============================================================================
proc create_toolbar_button(x, y, width, label, tooltip, on_click):
    let btn = create_widget("toolbar_btn")
    btn["x"] = x
    btn["y"] = y
    btn["width"] = width
    btn["height"] = 28.0
    btn["bg_color"] = ui_core.THEME_BUTTON
    btn["hover_color"] = ui_core.THEME_BUTTON_HOVER
    btn["active_color"] = ui_core.THEME_ACCENT
    btn["text"] = label
    btn["tooltip"] = tooltip
    btn["on_click"] = on_click
    btn["is_active"] = false
    btn["border_color"] = ui_core.THEME_BORDER
    btn["border_width"] = ui_core.BORDER_THIN
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
    sp["bg_color"] = ui_core.THEME_PANEL
    sp["border_color"] = ui_core.THEME_BORDER
    sp["border_width"] = ui_core.BORDER_THIN
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
    sl["bg_color"] = ui_core.THEME_INPUT_BG
    sl["border_color"] = ui_core.THEME_BORDER
    sl["border_width"] = ui_core.BORDER_THIN
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
    cb["bg_color"] = ui_core.THEME_INPUT_BG
    cb["check_color"] = ui_core.THEME_ACCENT
    cb["border_color"] = ui_core.THEME_BORDER_LIGHT
    cb["border_width"] = ui_core.BORDER_THIN
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
    dd["height"] = 24.0
    dd["bg_color"] = ui_core.THEME_INPUT_BG
    dd["border_color"] = ui_core.THEME_BORDER_LIGHT
    dd["border_width"] = ui_core.BORDER_THIN
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
# Text input field
# ============================================================================
proc create_text_field(x, y, width, value):
    let tf = create_widget("text_field")
    tf["x"] = x
    tf["y"] = y
    tf["width"] = width
    tf["height"] = 22.0
    tf["bg_color"] = ui_core.THEME_INPUT_BG
    tf["border_color"] = ui_core.THEME_BORDER_LIGHT
    tf["border_width"] = ui_core.BORDER_THIN
    tf["text_value"] = value
    tf["focused"] = false
    tf["cursor_pos"] = len(value)
    tf["on_change"] = nil
    tf["on_commit"] = nil
    tf["on_cancel"] = nil
    tf["blink_timer"] = 0.0
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
    nf["height"] = 22.0
    nf["bg_color"] = ui_core.THEME_INPUT_BG
    nf["border_color"] = ui_core.THEME_BORDER_LIGHT
    nf["border_width"] = ui_core.BORDER_THIN
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
    return create_rect(x, y, width, 1.0, ui_core.THEME_SEPARATOR)

# ============================================================================
# Section header (collapsible)
# ============================================================================
proc create_section_header(x, y, width, title):
    let sh = create_widget("section_header")
    sh["x"] = x
    sh["y"] = y
    sh["width"] = width
    sh["height"] = 24.0
    sh["bg_color"] = ui_core.THEME_HEADER
    sh["border_color"] = ui_core.THEME_BORDER
    sh["border_width"] = ui_core.BORDER_THIN
    sh["text"] = title
    sh["expanded"] = true
    return sh

proc toggle_section(sh):
    sh["expanded"] = sh["expanded"] == false

# ============================================================================
# Collect quads for advanced widgets (called from ui_renderer or manually)
# These produce extra quads beyond what ui_core.collect_quads handles
# ============================================================================

proc collect_slider_quads(sl, quads):
    let x = sl["computed_x"]
    let y = sl["computed_y"]
    let w = sl["width"]
    let h = sl["height"]
    # Track background
    let track_h = 4.0
    let track_y = y + (h - track_h) / 2.0
    push(quads, {"x": x, "y": track_y, "w": w, "h": track_h, "color": ui_core.THEME_INPUT_BG})
    _push_inset_quads(quads, x, track_y, w, track_h)
    # Filled portion
    let t = slider_normalized(sl)
    let fill_w = w * t
    if fill_w > 0.0:
        push(quads, {"x": x, "y": track_y, "w": fill_w, "h": track_h, "color": ui_core.THEME_ACCENT})
    # Thumb handle
    let thumb_w = 12.0
    let thumb_h = h
    let thumb_x = x + fill_w - thumb_w / 2.0
    if thumb_x < x:
        thumb_x = x
    if thumb_x + thumb_w > x + w:
        thumb_x = x + w - thumb_w
    push(quads, {"x": thumb_x, "y": y, "w": thumb_w, "h": thumb_h, "color": ui_core.THEME_ELEVATED})
    _push_border_quads(quads, thumb_x, y, thumb_w, thumb_h, 1.0, ui_core.THEME_BORDER_LIGHT)
    # Thumb highlight on hover
    if sl["hovered"]:
        push(quads, {"x": thumb_x, "y": y, "w": thumb_w, "h": 1.0, "color": [1.0, 1.0, 1.0, 0.08]})

proc collect_checkbox_quads(cb, quads):
    let x = cb["computed_x"]
    let y = cb["computed_y"]
    let s = 16.0
    # Box background
    let bg = ui_core.THEME_INPUT_BG
    if cb["hovered"]:
        bg = ui_core.THEME_INPUT_HOVER
    push(quads, {"x": x, "y": y, "w": s, "h": s, "color": bg})
    _push_border_quads(quads, x, y, s, s, 1.0, ui_core.THEME_BORDER_LIGHT)
    # Check mark (filled inner square with accent color)
    if cb["checked"]:
        let pad = 3.0
        push(quads, {"x": x + pad, "y": y + pad, "w": s - pad * 2.0, "h": s - pad * 2.0, "color": ui_core.THEME_ACCENT})
        # Inner highlight
        push(quads, {"x": x + pad, "y": y + pad, "w": s - pad * 2.0, "h": 1.0, "color": [1.0, 1.0, 1.0, 0.15]})
    # Focus ring on hover
    if cb["hovered"]:
        let fc = ui_core.THEME_BORDER_FOCUS
        _push_border_quads(quads, x - 1.0, y - 1.0, s + 2.0, s + 2.0, 1.0, [fc[0], fc[1], fc[2], fc[3] * 0.4])

proc collect_dropdown_quads(dd, quads):
    let x = dd["computed_x"]
    let y = dd["computed_y"]
    let w = dd["width"]
    let h = dd["height"]
    # Background
    let bg = ui_core.THEME_INPUT_BG
    if dd["hovered"] or dd["open"]:
        bg = ui_core.THEME_INPUT_HOVER
    push(quads, {"x": x, "y": y, "w": w, "h": h, "color": bg})
    _push_border_quads(quads, x, y, w, h, 1.0, ui_core.THEME_BORDER_LIGHT)
    # Arrow indicator (small chevron on right side)
    let aw = 8.0
    let ah = 4.0
    let ax = x + w - aw - ui_core.SP_MD
    let ay = y + (h - ah) / 2.0
    push(quads, {"x": ax, "y": ay, "w": aw, "h": ah, "color": ui_core.THEME_TEXT_SECONDARY})
    # Focus ring
    if dd["hovered"]:
        let fc = ui_core.THEME_BORDER_FOCUS
        _push_border_quads(quads, x - 1.0, y - 1.0, w + 2.0, h + 2.0, 1.0, [fc[0], fc[1], fc[2], fc[3] * 0.4])
    # Open dropdown items
    if dd["open"]:
        let item_h = 26.0
        let opts = dd["options"]
        let dh = len(opts) * item_h + ui_core.SP_SM * 2.0
        let dy = y + h + 2.0
        # Shadow under dropdown
        _push_shadow_quads(quads, x, dy, w, dh)
        # Dropdown panel bg
        push(quads, {"x": x, "y": dy, "w": w, "h": dh, "color": ui_core.THEME_ELEVATED})
        _push_border_quads(quads, x, dy, w, dh, 1.0, ui_core.THEME_BORDER)
        # Accent top edge
        push(quads, {"x": x, "y": dy, "w": w, "h": 2.0, "color": color_with_alpha(ui_core.THEME_ACCENT, 0.5)})
        # Items
        let oi = 0
        while oi < len(opts):
            let iy = dy + ui_core.SP_SM + oi * item_h
            if oi == dd["selected"]:
                push(quads, {"x": x + 2.0, "y": iy, "w": w - 4.0, "h": item_h, "color": ui_core.THEME_SELECT})
            oi = oi + 1

proc collect_text_field_quads(tf, quads):
    let x = tf["computed_x"]
    let y = tf["computed_y"]
    let w = tf["width"]
    let h = tf["height"]
    # Background
    let bg = ui_core.THEME_INPUT_BG
    if tf["focused"]:
        bg = ui_core.THEME_INPUT_FOCUS
    else:
        if tf["hovered"]:
            bg = ui_core.THEME_INPUT_HOVER
    push(quads, {"x": x, "y": y, "w": w, "h": h, "color": bg})
    _push_inset_quads(quads, x, y, w, h)
    # Border (accent when focused)
    if tf["focused"]:
        _push_border_quads(quads, x, y, w, h, 1.0, ui_core.THEME_BORDER_FOCUS)
        # Cursor
        let blink = tf["blink_timer"]
        # Blink: visible for 0.5s, hidden for 0.3s
        let blink_phase = blink - math.floor(blink / 0.8) * 0.8
        if blink_phase < 0.5:
            let char_w = 7.0
            let cursor_x = x + ui_core.SP_SM + tf["cursor_pos"] * char_w
            if cursor_x > x + w - 2.0:
                cursor_x = x + w - 2.0
            push(quads, {"x": cursor_x, "y": y + 3.0, "w": 1.5, "h": h - 6.0, "color": ui_core.THEME_TEXT})
    else:
        _push_border_quads(quads, x, y, w, h, 1.0, ui_core.THEME_BORDER_LIGHT)
    # Focus glow
    if tf["focused"]:
        let fc = ui_core.THEME_ACCENT
        _push_border_quads(quads, x - 1.0, y - 1.0, w + 2.0, h + 2.0, 1.0, [fc[0], fc[1], fc[2], 0.25])

proc collect_section_header_quads(sh, quads):
    let x = sh["computed_x"]
    let y = sh["computed_y"]
    let w = sh["width"]
    let h = sh["height"]
    push(quads, {"x": x, "y": y, "w": w, "h": h, "color": ui_core.THEME_HEADER})
    # Accent left edge
    push(quads, {"x": x, "y": y, "w": 3.0, "h": h, "color": color_with_alpha(ui_core.THEME_ACCENT, 0.6)})
    # Bottom border
    push(quads, {"x": x, "y": y + h - 1.0, "w": w, "h": 1.0, "color": ui_core.THEME_BORDER})
    # Expand/collapse indicator
    let ind_size = 6.0
    let ind_x = x + ui_core.SP_MD
    let ind_y = y + (h - ind_size) / 2.0
    if sh["expanded"]:
        # Down arrow (triangle approx with small rect)
        push(quads, {"x": ind_x, "y": ind_y, "w": ind_size, "h": ind_size, "color": ui_core.THEME_TEXT_SECONDARY})
    else:
        # Right arrow
        push(quads, {"x": ind_x, "y": ind_y, "w": ind_size * 0.6, "h": ind_size, "color": ui_core.THEME_TEXT_SECONDARY})

proc collect_scrollbar_quads(sp, quads):
    if sp["max_scroll"] < 1.0:
        return nil
    let x = sp["computed_x"] + sp["width"] - 6.0
    let y = sp["computed_y"]
    let h = sp["height"]
    let sb_w = 4.0
    # Track
    push(quads, {"x": x, "y": y, "w": sb_w, "h": h, "color": color_with_alpha(ui_core.THEME_BG, 0.5)})
    # Thumb
    let visible_ratio = sp["height"] / sp["content_height"]
    let thumb_h = h * visible_ratio
    if thumb_h < 20.0:
        thumb_h = 20.0
    let scroll_ratio = sp["scroll_y"] / sp["max_scroll"]
    let thumb_y = y + scroll_ratio * (h - thumb_h)
    push(quads, {"x": x, "y": thumb_y, "w": sb_w, "h": thumb_h, "color": ui_core.THEME_ELEVATED})
    _push_border_quads(quads, x, thumb_y, sb_w, thumb_h, 0.5, ui_core.THEME_BORDER_LIGHT)

import math
