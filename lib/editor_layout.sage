gc_disable()
# -----------------------------------------
# editor_layout.sage - Forge Engine editor panel layout
# Multi-layered panels with depth, shadows, and accent highlights
# -----------------------------------------

from ui_core import create_widget, create_panel, create_rect, add_child
import ui_widgets
import ui_core

let THEME_BG = ui_core.THEME_BG
let THEME_PANEL = ui_core.THEME_PANEL
let THEME_HEADER = ui_core.THEME_HEADER
let THEME_BORDER = ui_core.THEME_BORDER
let THEME_ACCENT = ui_core.THEME_ACCENT

# Depth colors (derived from theme)
let COL_SHADOW = ui_core.THEME_SHADOW_SOFT
let COL_ACCENT_LINE = ui_core.color_with_alpha(THEME_ACCENT, 0.35)
let COL_VP_BORDER = ui_core.color_with_alpha(THEME_ACCENT, 0.08)
let COL_INNER = ui_core.THEME_SURFACE

proc create_editor_layout(screen_w, screen_h):
    let layout = {}
    layout["screen_w"] = screen_w
    layout["screen_h"] = screen_h
    layout["menubar_h"] = 26.0
    layout["toolbar_h"] = 34.0
    layout["statusbar_h"] = 24.0
    layout["left_panel_w"] = 220.0
    layout["right_panel_w"] = 260.0
    layout["bottom_panel_h"] = 120.0
    layout["root"] = create_widget("editor_root")
    layout["root"]["width"] = screen_w
    layout["root"]["height"] = screen_h
    layout["root"]["bg_color"] = THEME_BG
    _build_all(layout)
    return layout

proc _build_all(layout):
    let sw = layout["screen_w"]
    let sh = layout["screen_h"]
    let mb = layout["menubar_h"]
    let tb = layout["toolbar_h"]
    let sb = layout["statusbar_h"]
    let top_h = mb + tb

    # --- Menu bar (topmost row — elevated header) ---
    add_child(layout["root"], create_rect(0.0, 0.0, sw, mb, ui_core.THEME_ELEVATED))
    add_child(layout["root"], create_rect(0.0, mb - 1.0, sw, 1.0, ui_core.THEME_BORDER))

    # --- Toolbar (below menu bar, panel-level) ---
    add_child(layout["root"], create_rect(0.0, mb, sw, tb, ui_core.THEME_HEADER))
    add_child(layout["root"], create_rect(0.0, mb + tb - 1.0, sw, 1.0, ui_core.THEME_BORDER))
    add_child(layout["root"], create_rect(0.0, mb + tb - 1.0, sw, 1.0, COL_ACCENT_LINE))

    # Viewport fills area between toolbar and statusbar
    let vx = 0.0
    let vy = top_h
    let vw = sw
    let vh = sh - top_h - sb

    # --- Status bar ---
    add_child(layout["root"], create_rect(0.0, sh - sb, sw, sb, COL_INNER))
    add_child(layout["root"], create_rect(0.0, sh - sb, sw, 1.0, COL_SHADOW))

    layout["viewport_x"] = vx
    layout["viewport_y"] = vy
    layout["viewport_w"] = vw
    layout["viewport_h"] = vh

proc get_viewport_bounds(layout):
    let b = {}
    b["x"] = layout["viewport_x"]
    b["y"] = layout["viewport_y"]
    b["w"] = layout["viewport_w"]
    b["h"] = layout["viewport_h"]
    return b

proc resize_editor_layout(layout, new_w, new_h):
    layout["screen_w"] = new_w
    layout["screen_h"] = new_h
    layout["root"]["children"] = []
    layout["root"]["width"] = new_w
    layout["root"]["height"] = new_h
    _build_all(layout)
