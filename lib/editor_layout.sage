gc_disable()
# -----------------------------------------
# editor_layout.sage - Forge Engine editor panel layout
# Symmetrical dark layout with accent borders
# -----------------------------------------

from ui_core import create_widget, create_panel, create_rect, add_child
import ui_widgets
let THEME_BG = ui_widgets.THEME_BG
let THEME_PANEL = ui_widgets.THEME_PANEL
let THEME_HEADER = ui_widgets.THEME_HEADER
let THEME_BORDER = ui_widgets.THEME_BORDER

# ============================================================================
# Editor Layout
# ============================================================================
proc create_editor_layout(screen_w, screen_h):
    let layout = {}
    layout["screen_w"] = screen_w
    layout["screen_h"] = screen_h
    # Symmetrical panel dimensions
    layout["toolbar_h"] = 34.0
    layout["statusbar_h"] = 22.0
    layout["left_panel_w"] = 240.0
    layout["right_panel_w"] = 240.0
    layout["bottom_panel_h"] = 120.0
    # Root
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
    let rp_x = sw - rw
    let mid_y = tb
    let mid_h = sh - tb - bh - sb
    let bp_y = sh - bh - sb

    # --- Toolbar ---
    add_child(layout["root"], create_rect(0.0, 0.0, sw, tb, THEME_HEADER))
    # Toolbar bottom border (accent line)
    add_child(layout["root"], create_rect(0.0, tb - 1.0, sw, 1.0, [0.537, 0.863, 0.922, 0.4]))

    # --- Left panel (Outliner) ---
    add_child(layout["root"], create_rect(0.0, mid_y, lw, mid_h, THEME_PANEL))
    add_child(layout["root"], create_rect(0.0, mid_y, lw, 24.0, THEME_HEADER))
    # Right border
    add_child(layout["root"], create_rect(lw - 1.0, mid_y, 1.0, mid_h, THEME_BORDER))

    # --- Right panel (Details) ---
    add_child(layout["root"], create_rect(rp_x, mid_y, rw, mid_h, THEME_PANEL))
    add_child(layout["root"], create_rect(rp_x, mid_y, rw, 24.0, THEME_HEADER))
    # Left border
    add_child(layout["root"], create_rect(rp_x, mid_y, 1.0, mid_h, THEME_BORDER))

    # --- Bottom panel (Content Browser) ---
    add_child(layout["root"], create_rect(lw, bp_y, sw - lw - rw, bh, THEME_PANEL))
    add_child(layout["root"], create_rect(lw, bp_y, sw - lw - rw, 24.0, THEME_HEADER))
    # Top border
    add_child(layout["root"], create_rect(lw, bp_y, sw - lw - rw, 1.0, THEME_BORDER))

    # --- Status bar ---
    add_child(layout["root"], create_rect(0.0, sh - sb, sw, sb, THEME_HEADER))

    # Store viewport bounds
    layout["viewport_x"] = lw
    layout["viewport_y"] = mid_y
    layout["viewport_w"] = sw - lw - rw
    layout["viewport_h"] = mid_h

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
