gc_disable()
# -----------------------------------------
# hud.sage - Pre-built HUD components for Sage Engine
# Health bar, crosshair, score display, FPS counter, minimap
# All components use the centralized theme from ui_core
# -----------------------------------------

import ui_core
from ui_core import create_widget, create_panel, create_rect, create_progress_bar
from ui_core import create_label, add_child
from ui_core import rgba, rgb, color_with_alpha, color_lerp, clamp
from ui_core import _push_border_quads, _push_inset_quads

# Re-export anchors for convenience
let ANCHOR_TOP_LEFT = ui_core.ANCHOR_TOP_LEFT
let ANCHOR_TOP_CENTER = ui_core.ANCHOR_TOP_CENTER
let ANCHOR_TOP_RIGHT = ui_core.ANCHOR_TOP_RIGHT
let ANCHOR_BOTTOM_LEFT = ui_core.ANCHOR_BOTTOM_LEFT
let ANCHOR_BOTTOM_CENTER = ui_core.ANCHOR_BOTTOM_CENTER
let ANCHOR_BOTTOM_RIGHT = ui_core.ANCHOR_BOTTOM_RIGHT
let ANCHOR_CENTER = ui_core.ANCHOR_CENTER

# ============================================================================
# HUD color palette (derived from theme)
# ============================================================================
let HUD_PANEL_BG = rgba(0.06, 0.06, 0.075, 0.75)
let HUD_PANEL_BORDER = color_with_alpha(ui_core.THEME_BORDER_LIGHT, 0.35)

let HUD_HEALTH_BG = rgba(0.08, 0.04, 0.04, 0.8)
let HUD_HEALTH_HIGH = rgba(0.25, 0.78, 0.35, 0.95)
let HUD_HEALTH_MED = rgba(0.92, 0.76, 0.18, 0.95)
let HUD_HEALTH_LOW = rgba(0.88, 0.22, 0.22, 0.95)
let HUD_HEALTH_CRITICAL = rgba(1.0, 0.15, 0.15, 1.0)

let HUD_CROSSHAIR = rgba(0.92, 0.94, 0.96, 0.65)
let HUD_CROSSHAIR_DOT = rgba(1.0, 1.0, 1.0, 0.85)

let HUD_MINIMAP_BG = rgba(0.05, 0.055, 0.07, 0.80)
let HUD_MINIMAP_BORDER = color_with_alpha(ui_core.THEME_ACCENT, 0.25)
let HUD_MINIMAP_PLAYER = rgba(0.30, 0.75, 0.95, 1.0)
let HUD_MINIMAP_ENEMY = rgba(0.92, 0.30, 0.25, 0.9)

# ============================================================================
# Health Bar
# ============================================================================
proc create_health_bar(x, y, width, height):
    let hb = {}
    # Outer container with border
    hb["bg"] = create_rect(x, y, width, height, HUD_HEALTH_BG)
    hb["bg"]["border_color"] = HUD_PANEL_BORDER
    hb["bg"]["border_width"] = ui_core.BORDER_THIN
    # Fill bar
    hb["fill"] = create_progress_bar(x, y, width, height, 1.0, ui_core.COLOR_TRANSPARENT, HUD_HEALTH_HIGH)
    hb["fill"]["border_color"] = ui_core.COLOR_TRANSPARENT
    hb["fill"]["border_width"] = 0.0
    # Sheen overlay (top highlight)
    hb["sheen"] = create_rect(x, y, width, 1.0, rgba(1.0, 1.0, 1.0, 0.06))
    hb["width"] = width
    hb["height"] = height
    return hb

proc update_health_bar(hb, percent):
    hb["fill"]["value"] = percent
    # Smooth color transition: green -> yellow -> red -> pulsing critical
    if percent > 0.6:
        hb["fill"]["fill_color"] = HUD_HEALTH_HIGH
    else:
        if percent > 0.3:
            let t = (percent - 0.3) / 0.3
            hb["fill"]["fill_color"] = color_lerp(HUD_HEALTH_MED, HUD_HEALTH_HIGH, t)
        else:
            if percent > 0.15:
                let t = (percent - 0.15) / 0.15
                hb["fill"]["fill_color"] = color_lerp(HUD_HEALTH_LOW, HUD_HEALTH_MED, t)
            else:
                hb["fill"]["fill_color"] = HUD_HEALTH_CRITICAL

proc add_health_bar_to(parent, hb):
    add_child(parent, hb["bg"])
    add_child(parent, hb["fill"])
    add_child(parent, hb["sheen"])

# ============================================================================
# Crosshair (modern thin-line style)
# ============================================================================
proc create_crosshair(size, thickness, color):
    let ch = {}
    let half = size / 2.0
    let gap = 3.0
    let ht = thickness / 2.0
    # Horizontal lines (left + right with gap)
    ch["h_left"] = create_rect(0.0 - half, 0.0 - ht, half - gap, thickness, HUD_CROSSHAIR)
    ch["h_left"]["anchor"] = ANCHOR_CENTER
    ch["h_right"] = create_rect(gap, 0.0 - ht, half - gap, thickness, HUD_CROSSHAIR)
    ch["h_right"]["anchor"] = ANCHOR_CENTER
    # Vertical lines (top + bottom with gap)
    ch["v_top"] = create_rect(0.0 - ht, 0.0 - half, thickness, half - gap, HUD_CROSSHAIR)
    ch["v_top"]["anchor"] = ANCHOR_CENTER
    ch["v_bottom"] = create_rect(0.0 - ht, gap, thickness, half - gap, HUD_CROSSHAIR)
    ch["v_bottom"]["anchor"] = ANCHOR_CENTER
    # Center dot (slightly brighter)
    let dot_size = thickness + 1.0
    ch["dot"] = create_rect(0.0 - dot_size / 2.0, 0.0 - dot_size / 2.0, dot_size, dot_size, HUD_CROSSHAIR_DOT)
    ch["dot"]["anchor"] = ANCHOR_CENTER
    return ch

proc add_crosshair_to(parent, ch):
    add_child(parent, ch["h_left"])
    add_child(parent, ch["h_right"])
    add_child(parent, ch["v_top"])
    add_child(parent, ch["v_bottom"])
    add_child(parent, ch["dot"])

# ============================================================================
# Score Display
# ============================================================================
proc create_score_display():
    let sd = {}
    sd["panel"] = create_panel(0.0, 0.0, 200.0, 44.0, HUD_PANEL_BG)
    sd["panel"]["anchor"] = ANCHOR_TOP_RIGHT
    sd["panel"]["x"] = -210.0
    sd["panel"]["y"] = ui_core.SP_LG
    sd["panel"]["border_color"] = HUD_PANEL_BORDER
    sd["panel"]["border_width"] = ui_core.BORDER_THIN
    sd["points"] = 0
    sd["combo"] = 0
    return sd

proc update_score_display(sd, points, combo):
    sd["points"] = points
    sd["combo"] = combo

# ============================================================================
# Info Panel (FPS, entity count)
# ============================================================================
proc create_info_panel():
    let ip = {}
    ip["panel"] = create_panel(0.0, 0.0, 180.0, 52.0, HUD_PANEL_BG)
    ip["panel"]["anchor"] = ANCHOR_TOP_LEFT
    ip["panel"]["x"] = ui_core.SP_LG
    ip["panel"]["y"] = ui_core.SP_LG
    ip["panel"]["border_color"] = HUD_PANEL_BORDER
    ip["panel"]["border_width"] = ui_core.BORDER_THIN
    ip["fps"] = 0.0
    ip["entity_count"] = 0
    ip["visible"] = true
    return ip

proc update_info_panel(ip, fps, entities):
    ip["fps"] = fps
    ip["entity_count"] = entities

# ============================================================================
# Minimap (top-down view with styled frame)
# ============================================================================
proc create_minimap(size):
    let mm = {}
    # Main panel
    mm["panel"] = create_panel(0.0, 0.0, size, size, HUD_MINIMAP_BG)
    mm["panel"]["anchor"] = ANCHOR_BOTTOM_RIGHT
    mm["panel"]["x"] = 0.0 - size - ui_core.SP_LG
    mm["panel"]["y"] = 0.0 - size - ui_core.SP_LG
    mm["panel"]["border_color"] = HUD_MINIMAP_BORDER
    mm["panel"]["border_width"] = ui_core.BORDER_THIN
    mm["size"] = size
    mm["dots"] = []
    mm["world_range"] = 30.0
    return mm

proc update_minimap_dots(mm, player_pos, entity_positions):
    mm["dots"] = []
    let half = mm["size"] / 2.0
    let scale = mm["size"] / (mm["world_range"] * 2.0)
    let i = 0
    while i < len(entity_positions):
        let ep = entity_positions[i]
        let dx = (ep[0] - player_pos[0]) * scale
        let dz = (ep[2] - player_pos[2]) * scale
        if dx > 0.0 - half and dx < half and dz > 0.0 - half and dz < half:
            let dot = create_rect(half + dx - 2.0, half + dz - 2.0, 4.0, 4.0, HUD_MINIMAP_ENEMY)
            push(mm["dots"], dot)
        i = i + 1
    # Player dot (center, larger, distinct color)
    let player_dot = create_rect(half - 3.0, half - 3.0, 6.0, 6.0, HUD_MINIMAP_PLAYER)
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

    # Health bar (bottom left, wider with padding)
    hud["health_bar"] = create_health_bar(ui_core.SP_XL, 0.0 - 40.0, 260.0, 16.0)
    hud["health_bar"]["bg"]["anchor"] = ANCHOR_BOTTOM_LEFT
    hud["health_bar"]["fill"]["anchor"] = ANCHOR_BOTTOM_LEFT
    hud["health_bar"]["sheen"]["anchor"] = ANCHOR_BOTTOM_LEFT
    add_health_bar_to(hud["root"], hud["health_bar"])

    # Crosshair (center, modern gapped style)
    hud["crosshair"] = create_crosshair(22.0, 1.5, HUD_CROSSHAIR)
    add_crosshair_to(hud["root"], hud["crosshair"])

    # Score (top right)
    hud["score"] = create_score_display()
    add_child(hud["root"], hud["score"]["panel"])

    # Info panel (top left)
    hud["info"] = create_info_panel()
    add_child(hud["root"], hud["info"]["panel"])

    # Minimap (bottom right)
    hud["minimap"] = create_minimap(128.0)
    add_child(hud["root"], hud["minimap"]["panel"])

    return hud

proc update_game_hud(hud, health_pct, score_pts, score_combo, fps, entity_count):
    update_health_bar(hud["health_bar"], health_pct)
    update_score_display(hud["score"], score_pts, score_combo)
    update_info_panel(hud["info"], fps, entity_count)
