gc_disable()
# -----------------------------------------
# menu.sage - Menu system for Sage Engine
# Pause menu, main menu, settings, transitions
# -----------------------------------------

import ui_core
from ui_core import create_widget, create_panel, create_rect, create_button, create_label
from ui_core import add_child

let rgba = ui_core.rgba
let COLOR_WHITE = ui_core.COLOR_WHITE
let COLOR_DARK = ui_core.COLOR_DARK
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
# Menu system
# ============================================================================
proc create_menu_system():
    let ms = {}
    ms["menus"] = {}
    ms["active_menu"] = nil
    ms["state"] = MENU_HIDDEN
    ms["fade_alpha"] = 0.0
    ms["fade_speed"] = 4.0
    ms["overlay"] = create_rect(0.0, 0.0, 1280.0, 720.0, rgba(0.0, 0.0, 0.0, 0.0))
    return ms

proc register_menu(ms, name, root_widget):
    ms["menus"][name] = root_widget
    root_widget["visible"] = false

proc show_menu(ms, name):
    if dict_has(ms["menus"], name) == false:
        return nil
    # Hide current
    if ms["active_menu"] != nil:
        if dict_has(ms["menus"], ms["active_menu"]):
            ms["menus"][ms["active_menu"]]["visible"] = false
    ms["active_menu"] = name
    ms["menus"][name]["visible"] = true
    ms["state"] = MENU_FADE_IN
    ms["fade_alpha"] = 0.0

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
        ms["overlay"]["color"][3] = ms["fade_alpha"] * 0.6
        ms["overlay"]["bg_color"] = ms["overlay"]["color"]
    if ms["state"] == MENU_FADE_OUT:
        ms["fade_alpha"] = ms["fade_alpha"] - dt * ms["fade_speed"]
        if ms["fade_alpha"] <= 0.0:
            ms["fade_alpha"] = 0.0
            ms["state"] = MENU_HIDDEN
            if ms["active_menu"] != nil:
                if dict_has(ms["menus"], ms["active_menu"]):
                    ms["menus"][ms["active_menu"]]["visible"] = false
                ms["active_menu"] = nil
        ms["overlay"]["color"][3] = ms["fade_alpha"] * 0.6
        ms["overlay"]["bg_color"] = ms["overlay"]["color"]

# ============================================================================
# Pre-built menus
# ============================================================================
proc create_pause_menu(on_resume, on_quit):
    let root = create_panel(0.0, 0.0, 300.0, 250.0, rgba(0.1, 0.1, 0.15, 0.9))
    root["anchor"] = ANCHOR_CENTER

    let title = create_label(0.0, 20.0, "PAUSED", COLOR_WHITE)
    title["anchor"] = ANCHOR_TOP_CENTER
    title["width"] = 80.0
    add_child(root, title)

    let resume_btn = create_button(50.0, 80.0, 200.0, 40.0, "Resume", rgba(0.2, 0.5, 0.2, 1.0), on_resume)
    add_child(root, resume_btn)

    let quit_btn = create_button(50.0, 140.0, 200.0, 40.0, "Quit", rgba(0.5, 0.2, 0.2, 1.0), on_quit)
    add_child(root, quit_btn)

    return root

proc create_main_menu(on_play, on_quit):
    let root = create_panel(0.0, 0.0, 400.0, 350.0, rgba(0.05, 0.05, 0.1, 0.95))
    root["anchor"] = ANCHOR_CENTER

    let title = create_label(0.0, 30.0, "SAGE ENGINE", COLOR_WHITE)
    title["anchor"] = ANCHOR_TOP_CENTER
    title["width"] = 120.0
    title["font_size"] = 24.0
    add_child(root, title)

    let play_btn = create_button(100.0, 120.0, 200.0, 50.0, "Play", rgba(0.2, 0.6, 0.3, 1.0), on_play)
    add_child(root, play_btn)

    let quit_btn = create_button(100.0, 200.0, 200.0, 50.0, "Quit", rgba(0.6, 0.2, 0.2, 1.0), on_quit)
    add_child(root, quit_btn)

    return root

proc create_game_over_menu(score, on_restart, on_quit):
    let root = create_panel(0.0, 0.0, 350.0, 300.0, rgba(0.1, 0.0, 0.0, 0.9))
    root["anchor"] = ANCHOR_CENTER

    let title = create_label(0.0, 25.0, "GAME OVER", rgba(1.0, 0.3, 0.3, 1.0))
    title["anchor"] = ANCHOR_TOP_CENTER
    title["width"] = 100.0
    add_child(root, title)

    let score_lbl = create_label(0.0, 70.0, "Score: " + str(score), COLOR_WHITE)
    score_lbl["anchor"] = ANCHOR_TOP_CENTER
    score_lbl["width"] = 120.0
    add_child(root, score_lbl)

    let restart_btn = create_button(75.0, 130.0, 200.0, 40.0, "Restart", rgba(0.2, 0.5, 0.2, 1.0), on_restart)
    add_child(root, restart_btn)

    let quit_btn = create_button(75.0, 190.0, 200.0, 40.0, "Quit", rgba(0.5, 0.2, 0.2, 1.0), on_quit)
    add_child(root, quit_btn)

    return root
