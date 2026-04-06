gc_disable()
# -----------------------------------------
# ui_window.sage - Floating window/panel system for Forge Engine
# Draggable, resizable, stackable panels with title bars
# Uses centralized theme from ui_core
# -----------------------------------------

import gpu
import math
import ui_core
from ui_core import rgba, color_with_alpha, _push_border_quads, _push_elevation_shadow

let _next_window_id = [1]
let _windows = []
let _drag_window = [nil]
let _drag_offset_x = [0.0]
let _drag_offset_y = [0.0]
let _resize_window = [nil]
let _resize_edge = ["none"]

# Window constants
let WIN_TITLE_H = 28.0
let WIN_MIN_W = 120.0
let WIN_MIN_H = 60.0
let WIN_BORDER = 1.0

# ============================================================================
# Create a floating window
# ============================================================================
proc create_ui_window(title, x, y, w, h):
    let win = {}
    win["id"] = _next_window_id[0]
    _next_window_id[0] = _next_window_id[0] + 1
    win["title"] = title
    win["x"] = x
    win["y"] = y
    win["width"] = w
    win["height"] = h
    win["visible"] = true
    win["collapsed"] = false
    win["pinned"] = false
    win["z_order"] = win["id"]
    win["content_quads"] = []
    win["content_text"] = []
    win["scroll_y"] = 0.0
    win["max_scroll"] = 0.0
    push(_windows, win)
    return win

# ============================================================================
# Get all windows sorted by z-order (back to front)
# ============================================================================
proc get_windows_sorted():
    let sorted = []
    let i = 0
    while i < len(_windows):
        push(sorted, _windows[i])
        i = i + 1
    let swapped = true
    while swapped:
        swapped = false
        i = 0
        while i < len(sorted) - 1:
            if sorted[i]["z_order"] > sorted[i + 1]["z_order"]:
                let tmp = sorted[i]
                sorted[i] = sorted[i + 1]
                sorted[i + 1] = tmp
                swapped = true
            i = i + 1
    return sorted

# ============================================================================
# Bring window to front
# ============================================================================
proc bring_to_front(win):
    let max_z = 0
    let i = 0
    while i < len(_windows):
        if _windows[i]["z_order"] > max_z:
            max_z = _windows[i]["z_order"]
        i = i + 1
    win["z_order"] = max_z + 1

# ============================================================================
# Hit test: which window is under the mouse?
# ============================================================================
proc window_at(mx, my):
    let sorted = get_windows_sorted()
    let result = nil
    let i = 0
    while i < len(sorted):
        let w = sorted[i]
        if w["visible"]:
            let h = w["height"]
            if w["collapsed"]:
                h = WIN_TITLE_H
            if mx >= w["x"] and mx < w["x"] + w["width"] and my >= w["y"] and my < w["y"] + h:
                result = w
        i = i + 1
    return result

proc is_in_title_bar(win, mx, my):
    return mx >= win["x"] and mx < win["x"] + win["width"] and my >= win["y"] and my < win["y"] + WIN_TITLE_H

proc is_on_resize_edge(win, mx, my):
    if win["collapsed"]:
        return "none"
    let r = win["x"] + win["width"]
    let b = win["y"] + win["height"]
    let edge_size = 6.0
    if mx > r - edge_size and mx < r + edge_size and my > b - edge_size and my < b + edge_size:
        return "corner"
    if mx > r - edge_size and mx < r + edge_size:
        return "right"
    if my > b - edge_size and my < b + edge_size:
        return "bottom"
    return "none"

# ============================================================================
# Handle mouse input for all windows
# ============================================================================
proc update_windows(mx, my, left_pressed, left_held, left_released):
    if left_pressed:
        let hit = window_at(mx, my)
        if hit != nil:
            bring_to_front(hit)
            let edge = is_on_resize_edge(hit, mx, my)
            if edge != "none":
                _resize_window[0] = hit
                _resize_edge[0] = edge
                return true
            if is_in_title_bar(hit, mx, my):
                _drag_window[0] = hit
                _drag_offset_x[0] = mx - hit["x"]
                _drag_offset_y[0] = my - hit["y"]
                return true
            return true
    if left_held:
        if _drag_window[0] != nil:
            _drag_window[0]["x"] = mx - _drag_offset_x[0]
            _drag_window[0]["y"] = my - _drag_offset_y[0]
            return true
        if _resize_window[0] != nil:
            let w = _resize_window[0]
            let edge = _resize_edge[0]
            if edge == "right" or edge == "corner":
                let new_w = mx - w["x"]
                if new_w > WIN_MIN_W:
                    w["width"] = new_w
            if edge == "bottom" or edge == "corner":
                let new_h = my - w["y"]
                if new_h > WIN_MIN_H:
                    w["height"] = new_h
            return true
    if left_released:
        if _drag_window[0] != nil:
            snap_window_to_edge(_drag_window[0])
        _drag_window[0] = nil
        _resize_window[0] = nil
        _resize_edge[0] = "none"
    return false

# ============================================================================
# Toggle collapse
# ============================================================================
proc toggle_collapse(win):
    win["collapsed"] = win["collapsed"] == false

# ============================================================================
# Build quads for a window (themed panels + title bar + borders + shadows)
# ============================================================================
proc build_window_quads(win):
    if win["visible"] == false:
        return []
    let quads = []
    let x = win["x"]
    let y = win["y"]
    let w = win["width"]
    let h = win["height"]
    if win["collapsed"]:
        h = WIN_TITLE_H

    # Professional elevation shadow (5-level depth system)
    _push_elevation_shadow(quads, x, y, w, h, 4)

    # Window body
    push(quads, {"x": x, "y": y, "w": w, "h": h, "color": ui_core.THEME_PANEL})

    # Title bar
    push(quads, {"x": x, "y": y, "w": w, "h": WIN_TITLE_H, "color": ui_core.THEME_HEADER})

    # Title bar accent underline
    let acc = ui_core.THEME_ACCENT
    push(quads, {"x": x, "y": y + WIN_TITLE_H - 1.0, "w": w, "h": 1.0, "color": color_with_alpha(acc, 0.45)})

    # Top highlight (subtle depth)
    push(quads, {"x": x, "y": y, "w": w, "h": 1.0, "color": [1.0, 1.0, 1.0, 0.04]})

    # Border
    _push_border_quads(quads, x, y, w, h, WIN_BORDER, ui_core.THEME_BORDER)

    # Resize grip (bottom-right corner)
    if win["collapsed"] == false:
        let gs = 12.0
        push(quads, {"x": x + w - gs, "y": y + h - gs, "w": gs, "h": gs, "color": color_with_alpha(acc, 0.12)})
        # Grip lines
        let gi = 0
        while gi < 3:
            let off = 3.0 + gi * 3.0
            push(quads, {"x": x + w - off - 1.0, "y": y + h - 1.0, "w": 1.0, "h": 1.0, "color": color_with_alpha(acc, 0.4)})
            push(quads, {"x": x + w - 1.0, "y": y + h - off - 1.0, "w": 1.0, "h": 1.0, "color": color_with_alpha(acc, 0.4)})
            gi = gi + 1

    return quads

# ============================================================================
# Content area bounds (inside the window, below title bar)
# ============================================================================
proc window_content_area(win):
    let ca = {}
    let pad = ui_core.SP_MD
    ca["x"] = win["x"] + pad
    ca["y"] = win["y"] + WIN_TITLE_H + pad
    ca["w"] = win["width"] - pad * 2.0
    ca["h"] = win["height"] - WIN_TITLE_H - pad * 2.0
    return ca

# ============================================================================
# Scroll support
# ============================================================================
proc scroll_window(win, delta):
    win["scroll_y"] = win["scroll_y"] + delta
    if win["scroll_y"] < 0.0:
        win["scroll_y"] = 0.0
    if win["scroll_y"] > win["max_scroll"]:
        win["scroll_y"] = win["max_scroll"]

proc update_window_content_height(win, content_height):
    let ca = window_content_area(win)
    let max_s = content_height - ca["h"]
    if max_s < 0.0:
        max_s = 0.0
    win["max_scroll"] = max_s
    if win["scroll_y"] > max_s:
        win["scroll_y"] = max_s

proc mouse_in_window_content(win, mx, my):
    if win["visible"] == false or win["collapsed"]:
        return false
    let ca = window_content_area(win)
    return mx >= ca["x"] and mx < ca["x"] + ca["w"] and my >= ca["y"] and my < ca["y"] + ca["h"]

# Screen dimensions for snap-to-edge
let _screen_dims = [1440.0, 900.0]

proc set_screen_dims(w, h):
    _screen_dims[0] = w
    _screen_dims[1] = h

proc snap_window_to_edge(win):
    let snap = 20.0
    let top_h = 60.0
    let sw = _screen_dims[0]
    let sh = _screen_dims[1]
    if win["x"] < snap:
        win["x"] = 0.0
    if win["x"] + win["width"] > sw - snap:
        win["x"] = sw - win["width"]
    if win["y"] < top_h + snap:
        win["y"] = top_h
    if win["y"] + win["height"] > sh - snap:
        win["y"] = sh - win["height"]

# ============================================================================
# Simple menu system (themed)
# ============================================================================
let _menu_open = [nil]
let _menu_items = [nil]
let _menu_x = [0.0]
let _menu_y = [0.0]

proc open_menu(x, y, items):
    _menu_open[0] = true
    _menu_items[0] = items
    _menu_x[0] = x
    _menu_y[0] = y

proc close_menu():
    _menu_open[0] = nil
    _menu_items[0] = nil

proc is_menu_open():
    return _menu_open[0] != nil

proc _menu_width():
    if _menu_open[0] == nil:
        return 180.0
    let items = _menu_items[0]
    let max_len = 0
    let i = 0
    while i < len(items):
        if items[i] != "---":
            if len(items[i]) > max_len:
                max_len = len(items[i])
        i = i + 1
    let w = max_len * 8.0 + 28.0
    if w < 180.0:
        w = 180.0
    if w > 420.0:
        w = 420.0
    return w

proc build_menu_quads():
    if _menu_open[0] == nil:
        return []
    let items = _menu_items[0]
    let x = _menu_x[0]
    let y = _menu_y[0]
    let w = _menu_width()
    let item_h = 26.0
    let h = len(items) * item_h + ui_core.SP_MD * 2.0
    let quads = []
    # Shadow
    push(quads, {"x": x + 5.0, "y": y + 5.0, "w": w, "h": h, "color": ui_core.THEME_SHADOW})
    push(quads, {"x": x + 2.0, "y": y + 2.0, "w": w, "h": h, "color": ui_core.THEME_SHADOW_SOFT})
    # Background
    push(quads, {"x": x, "y": y, "w": w, "h": h, "color": ui_core.THEME_ELEVATED})
    # Accent top edge
    let acc = ui_core.THEME_ACCENT
    push(quads, {"x": x, "y": y, "w": w, "h": 2.0, "color": color_with_alpha(acc, 0.55)})
    # Border
    _push_border_quads(quads, x, y, w, h, 1.0, ui_core.THEME_BORDER)
    # Separator items
    let si = 0
    while si < len(items):
        if items[si] == "---":
            let sy = y + ui_core.SP_MD + si * item_h + item_h / 2.0
            push(quads, {"x": x + ui_core.SP_MD, "y": sy, "w": w - ui_core.SP_MD * 2.0, "h": 1.0, "color": ui_core.THEME_SEPARATOR})
        si = si + 1
    return quads

proc get_menu_items():
    return _menu_items[0]

proc get_menu_pos():
    return [_menu_x[0], _menu_y[0]]

proc menu_item_at(mx, my):
    if _menu_open[0] == nil:
        return -1
    let items = _menu_items[0]
    let x = _menu_x[0]
    let y = _menu_y[0]
    let w = _menu_width()
    let item_h = 26.0
    if mx < x or mx > x + w:
        return -1
    let idx = math.floor((my - y - ui_core.SP_MD) / item_h)
    if idx < 0 or idx >= len(items):
        return -1
    return idx

# ============================================================================
# Modal dialog system (themed)
# ============================================================================
let _modal = [nil]

proc show_modal(title, message, on_yes, on_no):
    _modal[0] = {"title": title, "message": message, "on_yes": on_yes, "on_no": on_no}

proc close_modal():
    _modal[0] = nil

proc is_modal_open():
    return _modal[0] != nil

proc get_modal():
    return _modal[0]

proc build_modal_quads(sw, sh):
    if _modal[0] == nil:
        return []
    let quads = []
    # Dark overlay
    push(quads, {"x": 0.0, "y": 0.0, "w": sw, "h": sh, "color": ui_core.THEME_OVERLAY})
    # Centered dialog
    let dw = 360.0
    let dh = 160.0
    let dx = (sw - dw) / 2.0
    let dy = (sh - dh) / 2.0
    # Shadow
    push(quads, {"x": dx + 5.0, "y": dy + 5.0, "w": dw, "h": dh, "color": ui_core.THEME_SHADOW})
    push(quads, {"x": dx + 2.0, "y": dy + 2.0, "w": dw, "h": dh, "color": ui_core.THEME_SHADOW_SOFT})
    # Background
    push(quads, {"x": dx, "y": dy, "w": dw, "h": dh, "color": ui_core.THEME_PANEL})
    # Title bar
    push(quads, {"x": dx, "y": dy, "w": dw, "h": 30.0, "color": ui_core.THEME_HEADER})
    # Accent line
    let acc = ui_core.THEME_ACCENT
    push(quads, {"x": dx, "y": dy + 29.0, "w": dw, "h": 1.0, "color": color_with_alpha(acc, 0.45)})
    # Border
    _push_border_quads(quads, dx, dy, dw, dh, 1.0, ui_core.THEME_BORDER)
    # Yes button (accent)
    push(quads, {"x": dx + dw - 170.0, "y": dy + dh - 42.0, "w": 74.0, "h": 30.0, "color": ui_core.THEME_ACCENT})
    _push_border_quads(quads, dx + dw - 170.0, dy + dh - 42.0, 74.0, 30.0, 1.0, ui_core.THEME_BORDER_LIGHT)
    # No button (neutral)
    push(quads, {"x": dx + dw - 86.0, "y": dy + dh - 42.0, "w": 74.0, "h": 30.0, "color": ui_core.THEME_BUTTON})
    _push_border_quads(quads, dx + dw - 86.0, dy + dh - 42.0, 74.0, 30.0, 1.0, ui_core.THEME_BORDER_LIGHT)
    return quads

proc modal_click(mx, my, sw, sh):
    if _modal[0] == nil:
        return false
    let dw = 360.0
    let dh = 160.0
    let dx = (sw - dw) / 2.0
    let dy = (sh - dh) / 2.0
    if mx >= dx + dw - 170.0 and mx < dx + dw - 96.0 and my >= dy + dh - 42.0 and my < dy + dh - 12.0:
        if _modal[0]["on_yes"] != nil:
            _modal[0]["on_yes"]()
        close_modal()
        return true
    if mx >= dx + dw - 86.0 and mx < dx + dw - 12.0 and my >= dy + dh - 42.0 and my < dy + dh - 12.0:
        if _modal[0]["on_no"] != nil:
            _modal[0]["on_no"]()
        close_modal()
        return true
    return true
