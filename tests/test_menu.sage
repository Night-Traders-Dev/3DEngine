# test_menu.sage - Sanity checks for menu system
# Run: ./run.sh tests/test_menu.sage

from menu import create_menu_system, register_menu, show_menu, hide_menu
from menu import is_menu_visible, update_menu_system
from menu import create_pause_menu, create_main_menu, create_game_over_menu
from menu import MENU_HIDDEN, MENU_VISIBLE, MENU_FADE_IN, MENU_FADE_OUT
from ui_core import create_panel, rgba, ANCHOR_CENTER

import math

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

proc approx(a, b):
    return math.abs(a - b) < 0.05

print "=== Menu System Sanity Checks ==="

# --- Menu system creation ---
let ms = create_menu_system()
check("menu system created", ms != nil)
check("no active menu", ms["active_menu"] == nil)
check("state hidden", ms["state"] == MENU_HIDDEN)
check("not visible", is_menu_visible(ms) == false)

# --- Register menus ---
let test_menu = create_panel(0.0, 0.0, 300.0, 200.0, rgba(0.1, 0.1, 0.1, 0.9))
test_menu["anchor"] = ANCHOR_CENTER
register_menu(ms, "test", test_menu)
check("menu registered", dict_has(ms["menus"], "test"))
check("menu starts hidden", test_menu["visible"] == false)

# --- Show menu ---
show_menu(ms, "test")
check("active menu set", ms["active_menu"] == "test")
check("state is fade_in", ms["state"] == MENU_FADE_IN)
check("menu visible", test_menu["visible"] == true)
check("is_menu_visible true", is_menu_visible(ms))

# --- Fade in ---
update_menu_system(ms, 0.1)
check("fade alpha increasing", ms["fade_alpha"] > 0.0)

# Complete fade in
update_menu_system(ms, 1.0)
check("fade in complete", ms["state"] == MENU_VISIBLE)
check("alpha at 1", approx(ms["fade_alpha"], 1.0))

# --- Hide menu ---
hide_menu(ms)
check("state is fade_out", ms["state"] == MENU_FADE_OUT)

update_menu_system(ms, 0.1)
check("fade out alpha decreasing", ms["fade_alpha"] < 1.0)

# Complete fade out
update_menu_system(ms, 1.0)
check("fade out complete", ms["state"] == MENU_HIDDEN)
check("no active menu after hide", ms["active_menu"] == nil)
check("not visible after hide", is_menu_visible(ms) == false)

# --- Menu switching ---
let menu_a = create_panel(0.0, 0.0, 200.0, 150.0, rgba(0.2, 0.0, 0.0, 0.9))
let menu_b = create_panel(0.0, 0.0, 200.0, 150.0, rgba(0.0, 0.2, 0.0, 0.9))
register_menu(ms, "a", menu_a)
register_menu(ms, "b", menu_b)

show_menu(ms, "a")
check("menu a visible", menu_a["visible"] == true)

show_menu(ms, "b")
check("menu a hidden on switch", menu_a["visible"] == false)
check("menu b visible", menu_b["visible"] == true)

# --- Pre-built: Pause menu ---
let resume_called = [false]
let quit_called = [false]
proc on_resume():
    resume_called[0] = true
proc on_quit():
    quit_called[0] = true

let pause = create_pause_menu(on_resume, on_quit)
check("pause menu created", pause != nil)
check("pause menu type panel", pause["type"] == "panel")
check("pause has children", len(pause["children"]) > 0)
check("pause centered", pause["anchor"] == ANCHOR_CENTER)

# --- Pre-built: Main menu ---
let main = create_main_menu(on_resume, on_quit)
check("main menu created", main != nil)
check("main has children", len(main["children"]) > 0)

# --- Pre-built: Game over ---
let gameover = create_game_over_menu(1500, on_resume, on_quit)
check("game over menu created", gameover != nil)
check("game over has children", len(gameover["children"]) > 0)

# --- Show non-existent menu (no crash) ---
show_menu(ms, "nonexistent")
check("show nonexistent no crash", true)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Menu system sanity checks failed!"
else:
    print "All menu system sanity checks passed!"
