gc_disable()
# -----------------------------------------
# editor_layout.sage - Unreal-style editor panel layout
# Manages dockable panels: viewport, hierarchy, inspector, assets, console
# -----------------------------------------

from ui_core import create_widget, create_panel, create_rect, add_child
import ui_widgets
let THEME_BG = ui_widgets.THEME_BG
let THEME_PANEL = ui_widgets.THEME_PANEL
let THEME_HEADER = ui_widgets.THEME_HEADER
let THEME_BORDER = ui_widgets.THEME_BORDER
let THEME_BUTTON = ui_widgets.THEME_BUTTON
let THEME_ACCENT = ui_widgets.THEME_ACCENT
let THEME_TEXT = ui_widgets.THEME_TEXT
let THEME_TEXT_DIM = ui_widgets.THEME_TEXT_DIM

# ============================================================================
# Editor Layout
# ============================================================================
proc create_editor_layout(screen_w, screen_h):
    let layout = {}
    layout["screen_w"] = screen_w
    layout["screen_h"] = screen_h
    # Panel dimensions (Unreal-like proportions)
    layout["toolbar_h"] = 32.0
    layout["statusbar_h"] = 24.0
    layout["left_panel_w"] = 220.0
    layout["right_panel_w"] = 280.0
    layout["bottom_panel_h"] = 180.0
    # Root widget
    layout["root"] = create_widget("editor_root")
    layout["root"]["width"] = screen_w
    layout["root"]["height"] = screen_h
    layout["root"]["bg_color"] = THEME_BG
    # Create panels
    _build_toolbar(layout)
    _build_left_panel(layout)
    _build_right_panel(layout)
    _build_bottom_panel(layout)
    _build_viewport_area(layout)
    _build_statusbar(layout)
    return layout

# ============================================================================
# Toolbar (top bar with mode buttons)
# ============================================================================
proc _build_toolbar(layout):
    let w = layout["screen_w"]
    let h = layout["toolbar_h"]
    let bar = create_rect(0.0, 0.0, w, h, THEME_HEADER)
    layout["toolbar"] = bar
    add_child(layout["root"], bar)
    # Mode buttons will be added by the editor

# ============================================================================
# Left panel (Scene Hierarchy)
# ============================================================================
proc _build_left_panel(layout):
    let pw = layout["left_panel_w"]
    let y = layout["toolbar_h"]
    let h = layout["screen_h"] - layout["toolbar_h"] - layout["bottom_panel_h"] - layout["statusbar_h"]
    let panel = create_rect(0.0, y, pw, h, THEME_PANEL)
    layout["left_panel"] = panel
    add_child(layout["root"], panel)
    # Header
    let hdr = create_rect(0.0, y, pw, 24.0, THEME_HEADER)
    add_child(layout["root"], hdr)
    layout["left_header"] = hdr
    # Border
    let border = create_rect(pw - 1.0, y, 1.0, h, THEME_BORDER)
    add_child(layout["root"], border)

# ============================================================================
# Right panel (Inspector / Details)
# ============================================================================
proc _build_right_panel(layout):
    let pw = layout["right_panel_w"]
    let x = layout["screen_w"] - pw
    let y = layout["toolbar_h"]
    let h = layout["screen_h"] - layout["toolbar_h"] - layout["statusbar_h"]
    let panel = create_rect(x, y, pw, h, THEME_PANEL)
    layout["right_panel"] = panel
    add_child(layout["root"], panel)
    # Header
    let hdr = create_rect(x, y, pw, 24.0, THEME_HEADER)
    add_child(layout["root"], hdr)
    layout["right_header"] = hdr
    # Border
    let border = create_rect(x, y, 1.0, h, THEME_BORDER)
    add_child(layout["root"], border)

# ============================================================================
# Bottom panel (Asset browser / Console)
# ============================================================================
proc _build_bottom_panel(layout):
    let lw = layout["left_panel_w"]
    let rw = layout["right_panel_w"]
    let bh = layout["bottom_panel_h"]
    let x = lw
    let y = layout["screen_h"] - bh - layout["statusbar_h"]
    let w = layout["screen_w"] - lw - rw
    let panel = create_rect(x, y, w, bh, THEME_PANEL)
    layout["bottom_panel"] = panel
    add_child(layout["root"], panel)
    # Header
    let hdr = create_rect(x, y, w, 24.0, THEME_HEADER)
    add_child(layout["root"], hdr)
    layout["bottom_header"] = hdr
    # Border
    let border = create_rect(x, y, w, 1.0, THEME_BORDER)
    add_child(layout["root"], border)

# ============================================================================
# Viewport area (3D scene view)
# ============================================================================
proc _build_viewport_area(layout):
    let lw = layout["left_panel_w"]
    let rw = layout["right_panel_w"]
    let bh = layout["bottom_panel_h"]
    let x = lw
    let y = layout["toolbar_h"]
    let w = layout["screen_w"] - lw - rw
    let h = layout["screen_h"] - layout["toolbar_h"] - bh - layout["statusbar_h"]
    layout["viewport_x"] = x
    layout["viewport_y"] = y
    layout["viewport_w"] = w
    layout["viewport_h"] = h

# ============================================================================
# Status bar (bottom)
# ============================================================================
proc _build_statusbar(layout):
    let y = layout["screen_h"] - layout["statusbar_h"]
    let w = layout["screen_w"]
    let h = layout["statusbar_h"]
    let bar = create_rect(0.0, y, w, h, THEME_HEADER)
    layout["statusbar"] = bar
    add_child(layout["root"], bar)

# ============================================================================
# Get viewport bounds (for 3D rendering)
# ============================================================================
proc get_viewport_bounds(layout):
    let b = {}
    b["x"] = layout["viewport_x"]
    b["y"] = layout["viewport_y"]
    b["w"] = layout["viewport_w"]
    b["h"] = layout["viewport_h"]
    return b

# ============================================================================
# Resize handling
# ============================================================================
proc resize_editor_layout(layout, new_w, new_h):
    layout["screen_w"] = new_w
    layout["screen_h"] = new_h
    # Rebuild all panels
    layout["root"]["children"] = []
    layout["root"]["width"] = new_w
    layout["root"]["height"] = new_h
    _build_toolbar(layout)
    _build_left_panel(layout)
    _build_right_panel(layout)
    _build_bottom_panel(layout)
    _build_viewport_area(layout)
    _build_statusbar(layout)
