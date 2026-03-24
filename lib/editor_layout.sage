gc_disable()
# -----------------------------------------
# editor_layout.sage - Forge Engine editor panel layout
# Multi-layered panels with depth, shadows, and accent highlights
# -----------------------------------------

from ui_core import create_widget, create_panel, create_rect, add_child
import ui_widgets
import ui_core

let THEME_BG = ui_widgets.THEME_BG
let THEME_PANEL = ui_widgets.THEME_PANEL
let THEME_HEADER = ui_widgets.THEME_HEADER
let THEME_BORDER = ui_widgets.THEME_BORDER
let THEME_ACCENT = ui_widgets.THEME_ACCENT

# Depth colors
let COL_SHADOW = ui_core.rgba(0.02, 0.02, 0.035, 1.0)
let COL_ACCENT_LINE = ui_core.rgba(THEME_ACCENT[0], THEME_ACCENT[1], THEME_ACCENT[2], 0.30)
let COL_VP_BORDER = ui_core.rgba(THEME_ACCENT[0], THEME_ACCENT[1], THEME_ACCENT[2], 0.10)
let COL_INNER = ui_core.rgba(0.055, 0.059, 0.078, 1.0)

proc create_editor_layout(screen_w, screen_h):
    let layout = {}
    layout["screen_w"] = screen_w
    layout["screen_h"] = screen_h
    layout["toolbar_h"] = 36.0
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
    let tb = layout["toolbar_h"]
    let sb = layout["statusbar_h"]
    let lw = layout["left_panel_w"]
    let rw = layout["right_panel_w"]
    let bh = layout["bottom_panel_h"]
    let rx = sw - rw
    let my = tb
    let mh = sh - tb - bh - sb
    let by = sh - bh - sb

    # --- Toolbar ---
    add_child(layout["root"], create_rect(0.0, 0.0, sw, tb, THEME_HEADER))
    add_child(layout["root"], create_rect(0.0, tb - 2.0, sw, 2.0, COL_SHADOW))
    add_child(layout["root"], create_rect(0.0, tb - 1.0, sw, 1.0, COL_ACCENT_LINE))

    # --- Left panel ---
    add_child(layout["root"], create_rect(0.0, my, lw, mh, THEME_PANEL))
    add_child(layout["root"], create_rect(0.0, my, lw, 26.0, THEME_HEADER))
    add_child(layout["root"], create_rect(0.0, my + 25.0, lw, 1.0, COL_ACCENT_LINE))
    add_child(layout["root"], create_rect(0.0, my + 26.0, lw, 2.0, COL_INNER))
    add_child(layout["root"], create_rect(lw, my, 1.0, mh, COL_SHADOW))

    # --- Right panel ---
    add_child(layout["root"], create_rect(rx, my, rw, mh, THEME_PANEL))
    add_child(layout["root"], create_rect(rx, my, rw, 26.0, THEME_HEADER))
    add_child(layout["root"], create_rect(rx, my + 25.0, rw, 1.0, COL_ACCENT_LINE))
    add_child(layout["root"], create_rect(rx, my + 26.0, rw, 2.0, COL_INNER))
    add_child(layout["root"], create_rect(rx - 1.0, my, 1.0, mh, COL_SHADOW))

    # --- Viewport border glow ---
    let vx = lw + 1.0
    let vy = my
    let vw = sw - lw - rw - 2.0
    let vh = mh
    add_child(layout["root"], create_rect(vx, vy, vw, 1.0, COL_VP_BORDER))
    add_child(layout["root"], create_rect(vx, vy + vh - 1.0, vw, 1.0, COL_VP_BORDER))

    # --- Bottom panel ---
    add_child(layout["root"], create_rect(lw, by - 1.0, sw - lw - rw, 1.0, COL_SHADOW))
    add_child(layout["root"], create_rect(lw, by, sw - lw - rw, bh, THEME_PANEL))
    add_child(layout["root"], create_rect(lw, by, sw - lw - rw, 26.0, THEME_HEADER))
    add_child(layout["root"], create_rect(lw, by + 25.0, sw - lw - rw, 1.0, COL_ACCENT_LINE))
    add_child(layout["root"], create_rect(lw, by + 26.0, sw - lw - rw, 2.0, COL_INNER))
    # Corner fills
    add_child(layout["root"], create_rect(0.0, by, lw, bh, THEME_PANEL))
    add_child(layout["root"], create_rect(0.0, by, lw, 1.0, COL_SHADOW))
    add_child(layout["root"], create_rect(rx, by, rw, bh, THEME_PANEL))
    add_child(layout["root"], create_rect(rx, by, rw, 1.0, COL_SHADOW))

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
