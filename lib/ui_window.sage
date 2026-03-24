gc_disable()
# -----------------------------------------
# ui_window.sage - Floating window/panel system for Forge Engine
# Draggable, resizable, stackable panels with title bars
# Each window is a self-contained UI element that renders independently
# -----------------------------------------

import gpu
import ui_core
import ui_widgets

let _next_window_id = [1]
let _windows = []
let _drag_window = [nil]
let _drag_offset_x = [0.0]
let _drag_offset_y = [0.0]
let _resize_window = [nil]
let _resize_edge = ["none"]

# Theme
let WIN_TITLE_H = 26.0
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
    # Simple insertion sort by z_order
    let sorted = []
    let i = 0
    while i < len(_windows):
        push(sorted, _windows[i])
        i = i + 1
    # Bubble sort (small N)
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
    # Check back-to-front, return topmost hit
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
# Returns true if mouse was consumed by a window
# ============================================================================
proc update_windows(mx, my, left_pressed, left_held, left_released):
    # Start drag
    if left_pressed:
        let hit = window_at(mx, my)
        if hit != nil:
            bring_to_front(hit)
            # Check resize edge first
            let edge = is_on_resize_edge(hit, mx, my)
            if edge != "none":
                _resize_window[0] = hit
                _resize_edge[0] = edge
                return true
            # Check title bar for drag
            if is_in_title_bar(hit, mx, my):
                _drag_window[0] = hit
                _drag_offset_x[0] = mx - hit["x"]
                _drag_offset_y[0] = my - hit["y"]
                return true
            return true
    # Continue drag
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
    # End drag
    if left_released:
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
# Build quads for a window (panels + title bar + borders)
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

    # Drop shadow (offset down-right, layered for soft effect)
    push(quads, {"x": x + 4.0, "y": y + 4.0, "w": w, "h": h, "color": [0.0, 0.0, 0.0, 0.35]})
    push(quads, {"x": x + 2.0, "y": y + 2.0, "w": w, "h": h, "color": [0.0, 0.0, 0.0, 0.2]})

    # Window body
    push(quads, {"x": x, "y": y, "w": w, "h": h, "color": ui_widgets.THEME_PANEL})

    # Title bar (slightly elevated)
    push(quads, {"x": x, "y": y, "w": w, "h": WIN_TITLE_H, "color": ui_widgets.THEME_HEADER})

    # Title bar accent underline
    let acc = ui_widgets.THEME_ACCENT
    push(quads, {"x": x, "y": y + WIN_TITLE_H - 1.0, "w": w, "h": 1.0, "color": [acc[0], acc[1], acc[2], 0.4]})

    # Border (subtle)
    let bc = ui_widgets.THEME_BORDER
    push(quads, {"x": x, "y": y, "w": w, "h": WIN_BORDER, "color": bc})
    push(quads, {"x": x, "y": y + h - WIN_BORDER, "w": w, "h": WIN_BORDER, "color": bc})
    push(quads, {"x": x, "y": y, "w": WIN_BORDER, "h": h, "color": bc})
    push(quads, {"x": x + w - WIN_BORDER, "y": y, "w": WIN_BORDER, "h": h, "color": bc})

    # Resize grip (bottom-right corner, amber tinted)
    if win["collapsed"] == false:
        let gs = 10.0
        push(quads, {"x": x + w - gs, "y": y + h - gs, "w": gs, "h": gs, "color": [acc[0], acc[1], acc[2], 0.2]})
        push(quads, {"x": x + w - gs + 2.0, "y": y + h - 1.0, "w": gs - 2.0, "h": 1.0, "color": [acc[0], acc[1], acc[2], 0.4]})
        push(quads, {"x": x + w - 1.0, "y": y + h - gs + 2.0, "w": 1.0, "h": gs - 2.0, "color": [acc[0], acc[1], acc[2], 0.4]})

    return quads

# ============================================================================
# Content area bounds (inside the window, below title bar)
# ============================================================================
proc window_content_area(win):
    let ca = {}
    ca["x"] = win["x"] + 4.0
    ca["y"] = win["y"] + WIN_TITLE_H + 4.0
    ca["w"] = win["width"] - 8.0
    ca["h"] = win["height"] - WIN_TITLE_H - 8.0
    return ca

# ============================================================================
# Simple menu system
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

proc build_menu_quads():
    if _menu_open[0] == nil:
        return []
    let items = _menu_items[0]
    let x = _menu_x[0]
    let y = _menu_y[0]
    let w = 180.0
    let item_h = 24.0
    let h = len(items) * item_h + 8.0
    let quads = []
    # Shadow
    push(quads, {"x": x + 3.0, "y": y + 3.0, "w": w, "h": h, "color": [0.0, 0.0, 0.0, 0.45]})
    # Background
    push(quads, {"x": x, "y": y, "w": w, "h": h, "color": ui_widgets.THEME_HEADER})
    # Accent top edge
    let macc = ui_widgets.THEME_ACCENT
    push(quads, {"x": x, "y": y, "w": w, "h": 1.0, "color": [macc[0], macc[1], macc[2], 0.4]})
    # Border
    let mbc = ui_widgets.THEME_BORDER
    push(quads, {"x": x, "y": y + h - 1.0, "w": w, "h": 1.0, "color": mbc})
    push(quads, {"x": x, "y": y, "w": 1.0, "h": h, "color": mbc})
    push(quads, {"x": x + w - 1.0, "y": y, "w": 1.0, "h": h, "color": mbc})
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
    let w = 180.0
    let item_h = 24.0
    if mx < x or mx > x + w:
        return -1
    let idx = math.floor((my - y - 4.0) / item_h)
    if idx < 0 or idx >= len(items):
        return -1
    return idx
