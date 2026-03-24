gc_disable()
# -----------------------------------------
# menu.sage - Menu system for Sage Engine
# Pause menu, main menu, settings, transitions
# Uses centralized theme from ui_core for consistent styling
# -----------------------------------------

import ui_core
from ui_core import create_widget, create_panel, create_rect, create_button, create_label
from ui_core import add_child, rgba, color_with_alpha, color_brighten
from ui_core import _push_border_quads, _push_shadow_quads

let ANCHOR_CENTER = ui_core.ANCHOR_CENTER
let ANCHOR_TOP_CENTER = ui_core.ANCHOR_TOP_CENTER

# ============================================================================
# Menu state
# ============================================================================
let MENU_HIDDEN = "hidden"
let MENU_VISIBLE = "visible"
let MENU_FADE_IN = "fade_in"
let MENU_FADE_OUT = "fade_out"

# ============================================================================
# Menu button factory (themed, consistent)
# ============================================================================
proc _menu_button(x, y, w, h, label, style, on_click):
    let bg = ui_core.THEME_BUTTON
    if style == "primary":
        bg = ui_core.THEME_ACCENT
    if style == "danger":
        bg = rgba(0.55, 0.18, 0.18, 1.0)
    if style == "success":
        bg = rgba(0.18, 0.45, 0.22, 1.0)
    let btn = create_button(x, y, w, h, label, bg, on_click)
    btn["border_color"] = color_with_alpha(ui_core.THEME_BORDER_LIGHT, 0.6)
    btn["border_width"] = ui_core.BORDER_THIN
    return btn

# ============================================================================
# Menu system
# ============================================================================
proc create_menu_system():
    let ms = {}
    ms["menus"] = {}
    ms["active_menu"] = nil
    ms["state"] = MENU_HIDDEN
    ms["fade_alpha"] = 0.0
    ms["fade_speed"] = 5.0
    ms["overlay"] = create_rect(0.0, 0.0, 1280.0, 720.0, rgba(0.0, 0.0, 0.0, 0.0))
    ms["content_scale"] = 0.0
    return ms

proc register_menu(ms, name, root_widget):
    ms["menus"][name] = root_widget
    root_widget["visible"] = false

proc show_menu(ms, name):
    if dict_has(ms["menus"], name) == false:
        return nil
    if ms["active_menu"] != nil:
        if dict_has(ms["menus"], ms["active_menu"]):
            ms["menus"][ms["active_menu"]]["visible"] = false
    ms["active_menu"] = name
    ms["menus"][name]["visible"] = true
    ms["state"] = MENU_FADE_IN
    ms["fade_alpha"] = 0.0
    ms["content_scale"] = 0.0

proc hide_menu(ms):
    ms["state"] = MENU_FADE_OUT

proc is_menu_visible(ms):
    return ms["state"] != MENU_HIDDEN

proc update_menu_system(ms, dt):
    if ms["state"] == MENU_FADE_IN:
        ms["fade_alpha"] = ms["fade_alpha"] + dt * ms["fade_speed"]
        if ms["fade_alpha"] >= 1.0:
            ms["fade_alpha"] = 1.0
            ms["state"] = MENU_VISIBLE
        # Smooth ease-out for overlay
        let t = ms["fade_alpha"]
        let ease = t * (2.0 - t)
        ms["overlay"]["color"] = ui_core.THEME_OVERLAY
        ms["overlay"]["color"][3] = ease * 0.65
        ms["overlay"]["bg_color"] = ms["overlay"]["color"]
        # Content fade-in (slightly delayed)
        ms["content_scale"] = ease
        if ms["active_menu"] != nil:
            if dict_has(ms["menus"], ms["active_menu"]):
                ms["menus"][ms["active_menu"]]["opacity"] = ease

    if ms["state"] == MENU_FADE_OUT:
        ms["fade_alpha"] = ms["fade_alpha"] - dt * ms["fade_speed"]
        if ms["fade_alpha"] <= 0.0:
            ms["fade_alpha"] = 0.0
            ms["state"] = MENU_HIDDEN
            if ms["active_menu"] != nil:
                if dict_has(ms["menus"], ms["active_menu"]):
                    ms["menus"][ms["active_menu"]]["visible"] = false
                    ms["menus"][ms["active_menu"]]["opacity"] = 0.0
                ms["active_menu"] = nil
        let t = ms["fade_alpha"]
        ms["overlay"]["color"][3] = t * 0.65
        ms["overlay"]["bg_color"] = ms["overlay"]["color"]
        if ms["active_menu"] != nil:
            if dict_has(ms["menus"], ms["active_menu"]):
                ms["menus"][ms["active_menu"]]["opacity"] = t

# ============================================================================
# Pre-built menus (themed, with visual hierarchy)
# ============================================================================
proc create_pause_menu(on_resume, on_quit):
    let root = create_panel(0.0, 0.0, 320.0, 260.0, ui_core.THEME_PANEL)
    root["anchor"] = ANCHOR_CENTER
    root["border_color"] = ui_core.THEME_BORDER
    root["border_width"] = ui_core.BORDER_THIN

    # Title with accent underline
    let title_bg = create_rect(0.0, 0.0, 320.0, 48.0, ui_core.THEME_HEADER)
    add_child(root, title_bg)
    let title_accent = create_rect(0.0, 47.0, 320.0, 1.0, color_with_alpha(ui_core.THEME_ACCENT, 0.5))
    add_child(root, title_accent)

    let title = create_label(0.0, 14.0, "PAUSED", ui_core.THEME_TEXT_BRIGHT)
    title["anchor"] = ANCHOR_TOP_CENTER
    title["width"] = 80.0
    title["font_size"] = 24.0
    add_child(root, title)

    # Divider
    let div = create_rect(24.0, 60.0, 272.0, 1.0, ui_core.THEME_SEPARATOR)
    add_child(root, div)

    # Primary action: Resume (accent styled, larger)
    let resume_btn = _menu_button(40.0, 80.0, 240.0, 42.0, "Resume", "primary", on_resume)
    add_child(root, resume_btn)

    # Secondary action: Quit (danger styled, smaller)
    let quit_btn = _menu_button(40.0, 140.0, 240.0, 38.0, "Quit", "danger", on_quit)
    add_child(root, quit_btn)

    # Hint text
    let hint = create_label(0.0, 200.0, "Press ESC to resume", ui_core.THEME_TEXT_DIM)
    hint["anchor"] = ANCHOR_TOP_CENTER
    hint["width"] = 140.0
    add_child(root, hint)

    return root

proc create_main_menu(on_play, on_quit):
    let root = create_panel(0.0, 0.0, 420.0, 380.0, ui_core.THEME_PANEL)
    root["anchor"] = ANCHOR_CENTER
    root["border_color"] = ui_core.THEME_BORDER
    root["border_width"] = ui_core.BORDER_THIN

    # Title header area
    let title_bg = create_rect(0.0, 0.0, 420.0, 64.0, ui_core.THEME_HEADER)
    add_child(root, title_bg)
    let title_accent = create_rect(0.0, 63.0, 420.0, 2.0, color_with_alpha(ui_core.THEME_ACCENT, 0.6))
    add_child(root, title_accent)

    let title = create_label(0.0, 20.0, "SAGE ENGINE", ui_core.THEME_TEXT_BRIGHT)
    title["anchor"] = ANCHOR_TOP_CENTER
    title["width"] = 120.0
    title["font_size"] = 28.0
    add_child(root, title)

    # Subtitle
    let subtitle = create_label(0.0, 82.0, "3D Game Engine", ui_core.THEME_TEXT_SECONDARY)
    subtitle["anchor"] = ANCHOR_TOP_CENTER
    subtitle["width"] = 120.0
    add_child(root, subtitle)

    # Divider
    let div = create_rect(32.0, 112.0, 356.0, 1.0, ui_core.THEME_SEPARATOR)
    add_child(root, div)

    # Play button (primary, prominent)
    let play_btn = _menu_button(80.0, 140.0, 260.0, 48.0, "Play", "primary", on_play)
    add_child(root, play_btn)

    # Quit button (subtle danger)
    let quit_btn = _menu_button(80.0, 210.0, 260.0, 42.0, "Quit", "danger", on_quit)
    add_child(root, quit_btn)

    # Version/credit text
    let ver = create_label(0.0, 340.0, "Forge Engine v0.6", ui_core.THEME_TEXT_DIM)
    ver["anchor"] = ANCHOR_TOP_CENTER
    ver["width"] = 120.0
    add_child(root, ver)

    return root

proc create_game_over_menu(score, on_restart, on_quit):
    let root = create_panel(0.0, 0.0, 360.0, 320.0, ui_core.THEME_PANEL)
    root["anchor"] = ANCHOR_CENTER
    root["border_color"] = ui_core.THEME_BORDER
    root["border_width"] = ui_core.BORDER_THIN

    # Title header with danger tint
    let title_bg = create_rect(0.0, 0.0, 360.0, 52.0, rgba(0.20, 0.08, 0.08, 1.0))
    add_child(root, title_bg)
    let title_accent = create_rect(0.0, 51.0, 360.0, 2.0, color_with_alpha(ui_core.THEME_DANGER, 0.6))
    add_child(root, title_accent)

    let title = create_label(0.0, 16.0, "GAME OVER", ui_core.THEME_DANGER)
    title["anchor"] = ANCHOR_TOP_CENTER
    title["width"] = 100.0
    title["font_size"] = 24.0
    add_child(root, title)

    # Score display area
    let score_bg = create_rect(24.0, 68.0, 312.0, 50.0, ui_core.THEME_SURFACE)
    score_bg["border_color"] = ui_core.THEME_BORDER
    score_bg["border_width"] = ui_core.BORDER_THIN
    add_child(root, score_bg)

    let score_label = create_label(0.0, 72.0, "SCORE", ui_core.THEME_TEXT_SECONDARY)
    score_label["anchor"] = ANCHOR_TOP_CENTER
    score_label["width"] = 60.0
    add_child(root, score_label)

    let score_val = create_label(0.0, 92.0, str(score), ui_core.THEME_TEXT_BRIGHT)
    score_val["anchor"] = ANCHOR_TOP_CENTER
    score_val["width"] = 80.0
    score_val["font_size"] = 22.0
    add_child(root, score_val)

    # Divider
    let div = create_rect(24.0, 132.0, 312.0, 1.0, ui_core.THEME_SEPARATOR)
    add_child(root, div)

    # Restart (primary action)
    let restart_btn = _menu_button(60.0, 152.0, 240.0, 42.0, "Restart", "primary", on_restart)
    add_child(root, restart_btn)

    # Quit (secondary)
    let quit_btn = _menu_button(60.0, 210.0, 240.0, 38.0, "Quit", "danger", on_quit)
    add_child(root, quit_btn)

    # Hint
    let hint = create_label(0.0, 275.0, "Press R to restart", ui_core.THEME_TEXT_DIM)
    hint["anchor"] = ANCHOR_TOP_CENTER
    hint["width"] = 120.0
    add_child(root, hint)

    return root
