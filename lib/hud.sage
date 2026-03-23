gc_disable()
# -----------------------------------------
# hud.sage - Pre-built HUD components for Sage Engine
# Health bar, crosshair, score display, FPS counter, minimap
# -----------------------------------------

import ui_core
from ui_core import create_widget, create_panel, create_rect, create_progress_bar
from ui_core import create_label, add_child

let rgba = ui_core.rgba
let rgb = ui_core.rgb
let COLOR_WHITE = ui_core.COLOR_WHITE
let COLOR_BLACK = ui_core.COLOR_BLACK
let COLOR_RED = ui_core.COLOR_RED
let COLOR_GREEN = ui_core.COLOR_GREEN
let COLOR_DARK = ui_core.COLOR_DARK
let COLOR_YELLOW = ui_core.COLOR_YELLOW
let COLOR_TRANSPARENT = ui_core.COLOR_TRANSPARENT
let ANCHOR_TOP_LEFT = ui_core.ANCHOR_TOP_LEFT
let ANCHOR_TOP_CENTER = ui_core.ANCHOR_TOP_CENTER
let ANCHOR_TOP_RIGHT = ui_core.ANCHOR_TOP_RIGHT
let ANCHOR_BOTTOM_LEFT = ui_core.ANCHOR_BOTTOM_LEFT
let ANCHOR_BOTTOM_CENTER = ui_core.ANCHOR_BOTTOM_CENTER
let ANCHOR_BOTTOM_RIGHT = ui_core.ANCHOR_BOTTOM_RIGHT
let ANCHOR_CENTER = ui_core.ANCHOR_CENTER

# ============================================================================
# Health Bar
# ============================================================================
proc create_health_bar(x, y, width, height):
    let hb = {}
    hb["bg"] = create_rect(x, y, width, height, rgba(0.2, 0.0, 0.0, 0.7))
    hb["fill"] = create_progress_bar(x, y, width, height, 1.0, COLOR_TRANSPARENT, rgba(0.8, 0.15, 0.15, 0.9))
    hb["border"] = create_rect(x, y, width, height, COLOR_TRANSPARENT)
    hb["border"]["bg_color"] = rgba(0.9, 0.9, 0.9, 0.3)
    # Overlay border as slightly larger
    hb["width"] = width
    hb["height"] = height
    return hb

proc update_health_bar(hb, percent):
    hb["fill"]["value"] = percent
    # Color shift: green->yellow->red
    if percent > 0.6:
        hb["fill"]["fill_color"] = rgba(0.2, 0.8, 0.2, 0.9)
    else:
        if percent > 0.3:
            hb["fill"]["fill_color"] = rgba(0.9, 0.8, 0.1, 0.9)
        else:
            hb["fill"]["fill_color"] = rgba(0.9, 0.15, 0.15, 0.9)

proc add_health_bar_to(parent, hb):
    add_child(parent, hb["bg"])
    add_child(parent, hb["fill"])

# ============================================================================
# Crosshair
# ============================================================================
proc create_crosshair(size, thickness, color):
    let ch = {}
    let half = size / 2.0
    let ht = thickness / 2.0
    # Horizontal line
    ch["h_bar"] = create_rect(0.0 - half, 0.0 - ht, size, thickness, color)
    ch["h_bar"]["anchor"] = ANCHOR_CENTER
    # Vertical line
    ch["v_bar"] = create_rect(0.0 - ht, 0.0 - half, thickness, size, color)
    ch["v_bar"]["anchor"] = ANCHOR_CENTER
    # Center dot
    ch["dot"] = create_rect(0.0 - ht, 0.0 - ht, thickness, thickness, color)
    ch["dot"]["anchor"] = ANCHOR_CENTER
    return ch

proc add_crosshair_to(parent, ch):
    add_child(parent, ch["h_bar"])
    add_child(parent, ch["v_bar"])
    add_child(parent, ch["dot"])

# ============================================================================
# Score Display
# ============================================================================
proc create_score_display():
    let sd = {}
    sd["panel"] = create_panel(10.0, 10.0, 200.0, 40.0, rgba(0.0, 0.0, 0.0, 0.5))
    sd["panel"]["anchor"] = ANCHOR_TOP_RIGHT
    sd["panel"]["x"] = -210.0
    sd["panel"]["y"] = 10.0
    sd["points"] = 0
    sd["combo"] = 0
    return sd

proc update_score_display(sd, points, combo):
    sd["points"] = points
    sd["combo"] = combo

# ============================================================================
# Info Panel (for debug/FPS info)
# ============================================================================
proc create_info_panel():
    let ip = {}
    ip["panel"] = create_panel(0.0, 0.0, 180.0, 80.0, rgba(0.0, 0.0, 0.0, 0.5))
    ip["panel"]["anchor"] = ANCHOR_TOP_LEFT
    ip["panel"]["x"] = 10.0
    ip["panel"]["y"] = 10.0
    ip["fps"] = 0.0
    ip["entity_count"] = 0
    ip["visible"] = true
    return ip

proc update_info_panel(ip, fps, entities):
    ip["fps"] = fps
    ip["entity_count"] = entities

# ============================================================================
# Minimap (simple top-down view)
# ============================================================================
proc create_minimap(size):
    let mm = {}
    mm["panel"] = create_panel(0.0, 0.0, size, size, rgba(0.1, 0.1, 0.1, 0.7))
    mm["panel"]["anchor"] = ANCHOR_BOTTOM_RIGHT
    mm["panel"]["x"] = 0.0 - size - 10.0
    mm["panel"]["y"] = 0.0 - size - 10.0
    mm["border"] = create_rect(0.0, 0.0, size, size, COLOR_TRANSPARENT)
    mm["border"]["bg_color"] = rgba(0.5, 0.5, 0.5, 0.5)
    mm["border"]["anchor"] = ANCHOR_BOTTOM_RIGHT
    mm["border"]["x"] = 0.0 - size - 10.0
    mm["border"]["y"] = 0.0 - size - 10.0
    mm["size"] = size
    mm["dots"] = []
    mm["world_range"] = 30.0
    return mm

proc update_minimap_dots(mm, player_pos, entity_positions):
    # Clear old dots
    mm["dots"] = []
    let half = mm["size"] / 2.0
    let scale = mm["size"] / (mm["world_range"] * 2.0)
    # Add entities as dots
    let i = 0
    while i < len(entity_positions):
        let ep = entity_positions[i]
        let dx = (ep[0] - player_pos[0]) * scale
        let dz = (ep[2] - player_pos[2]) * scale
        if dx > 0.0 - half and dx < half and dz > 0.0 - half and dz < half:
            let dot = create_rect(half + dx - 2.0, half + dz - 2.0, 4.0, 4.0, COLOR_RED)
            push(mm["dots"], dot)
        i = i + 1
    # Player dot (center)
    let player_dot = create_rect(half - 3.0, half - 3.0, 6.0, 6.0, COLOR_GREEN)
    push(mm["dots"], player_dot)

# ============================================================================
# Build complete game HUD
# ============================================================================
proc create_game_hud():
    let hud = {}
    hud["root"] = create_widget("root")
    hud["root"]["width"] = 1280.0
    hud["root"]["height"] = 720.0
    hud["root"]["visible"] = true

    # Health bar (bottom left)
    hud["health_bar"] = create_health_bar(20.0, -50.0, 250.0, 20.0)
    hud["health_bar"]["bg"]["anchor"] = ANCHOR_BOTTOM_LEFT
    hud["health_bar"]["fill"]["anchor"] = ANCHOR_BOTTOM_LEFT
    add_health_bar_to(hud["root"], hud["health_bar"])

    # Crosshair (center)
    hud["crosshair"] = create_crosshair(20.0, 2.0, rgba(1.0, 1.0, 1.0, 0.7))
    add_crosshair_to(hud["root"], hud["crosshair"])

    # Score (top right)
    hud["score"] = create_score_display()
    add_child(hud["root"], hud["score"]["panel"])

    # Info panel (top left)
    hud["info"] = create_info_panel()
    add_child(hud["root"], hud["info"]["panel"])

    # Minimap (bottom right)
    hud["minimap"] = create_minimap(120.0)
    add_child(hud["root"], hud["minimap"]["panel"])

    return hud

proc update_game_hud(hud, health_pct, score_pts, score_combo, fps, entity_count):
    update_health_bar(hud["health_bar"], health_pct)
    update_score_display(hud["score"], score_pts, score_combo)
    update_info_panel(hud["info"], fps, entity_count)
