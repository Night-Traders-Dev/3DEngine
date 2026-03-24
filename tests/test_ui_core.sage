# test_ui_core.sage - Sanity checks for UI core widget system
# Run: ./run.sh tests/test_ui_core.sage

from ui_core import create_widget, create_panel, create_rect, create_label
from ui_core import create_button, create_progress_bar
from ui_core import add_child, remove_child, compute_layout, collect_quads
from ui_core import point_in_widget, compute_anchor_offset
from ui_core import update_hover_state, dispatch_click, process_ui_input
from ui_core import rgba, rgb, COLOR_WHITE, COLOR_RED, COLOR_TRANSPARENT
from ui_core import ANCHOR_TOP_LEFT, ANCHOR_CENTER, ANCHOR_BOTTOM_RIGHT

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
    return math.abs(a - b) < 1.0

print "=== UI Core Sanity Checks ==="

# --- Colors ---
let c = rgba(0.5, 0.6, 0.7, 0.8)
check("rgba r", math.abs(c[0] - 0.5) < 0.01)
check("rgba a", math.abs(c[3] - 0.8) < 0.01)
let c2 = rgb(1.0, 0.0, 0.0)
check("rgb alpha = 1", math.abs(c2[3] - 1.0) < 0.01)

# --- Base widget ---
let w = create_widget("test")
check("widget type", w["type"] == "test")
check("widget visible", w["visible"] == true)
check("widget default anchor", w["anchor"] == ANCHOR_TOP_LEFT)
check("no children", len(w["children"]) == 0)

# --- Panel ---
let p = create_panel(10.0, 20.0, 200.0, 100.0, COLOR_RED)
check("panel type", p["type"] == "panel")
check("panel x", approx(p["x"], 10.0))
check("panel width", approx(p["width"], 200.0))
check("panel bg color", p["bg_color"][0] > 0.5)

# --- Rect ---
let r = create_rect(5.0, 5.0, 50.0, 50.0, COLOR_WHITE)
check("rect type", r["type"] == "rect")
check("rect color set", r["color"][0] > 0.9)

# --- Label ---
let lbl = create_label(0.0, 0.0, "Hello", COLOR_WHITE)
check("label type", lbl["type"] == "label")
check("label text", lbl["text"] == "Hello")
check("label has width", lbl["width"] > 0.0)

# --- Button ---
let clicked = [false]
proc on_click():
    clicked[0] = true
let btn = create_button(0.0, 0.0, 120.0, 40.0, "Click Me", COLOR_RED, on_click)
check("button type", btn["type"] == "button")
check("button text", btn["text"] == "Click Me")
check("button has on_click", btn["on_click"] != nil)

# --- Progress bar ---
let pb = create_progress_bar(0.0, 0.0, 200.0, 20.0, 0.75, COLOR_RED, COLOR_WHITE)
check("progress type", pb["type"] == "progress")
check("progress value", math.abs(pb["value"] - 0.75) < 0.01)

# --- Hierarchy ---
let parent = create_panel(0.0, 0.0, 400.0, 300.0, COLOR_TRANSPARENT)
let child1 = create_rect(10.0, 10.0, 50.0, 50.0, COLOR_RED)
let child2 = create_rect(70.0, 10.0, 50.0, 50.0, COLOR_WHITE)
add_child(parent, child1)
add_child(parent, child2)
check("parent has 2 children", len(parent["children"]) == 2)
check("child1 parent set", child1["parent"] != nil)

remove_child(parent, child1)
check("parent has 1 child after remove", len(parent["children"]) == 1)
check("child1 parent cleared", child1["parent"] == nil)


# --- Anchor offset ---
let off_tl = compute_anchor_offset(ANCHOR_TOP_LEFT, 800.0, 600.0, 100.0, 50.0)
check("top_left offset x=0", approx(off_tl[0], 0.0))
check("top_left offset y=0", approx(off_tl[1], 0.0))

let off_c = compute_anchor_offset(ANCHOR_CENTER, 800.0, 600.0, 100.0, 50.0)
check("center offset x", approx(off_c[0], 350.0))
check("center offset y", approx(off_c[1], 275.0))

let off_br = compute_anchor_offset(ANCHOR_BOTTOM_RIGHT, 800.0, 600.0, 100.0, 50.0)
check("bottom_right offset x", approx(off_br[0], 700.0))
check("bottom_right offset y", approx(off_br[1], 550.0))

# --- Layout computation ---
let root = create_widget("root")
root["width"] = 800.0
root["height"] = 600.0
let box = create_rect(10.0, 20.0, 100.0, 50.0, COLOR_RED)
add_child(root, box)
compute_layout(root, 0.0, 0.0, 800.0, 600.0)
check("layout root x=0", approx(root["computed_x"], 0.0))
check("layout child x", approx(box["computed_x"], 10.0))
check("layout child y", approx(box["computed_y"], 20.0))

# Centered child
let centered = create_rect(0.0, 0.0, 100.0, 50.0, COLOR_RED)
centered["anchor"] = ANCHOR_CENTER
add_child(root, centered)
compute_layout(root, 0.0, 0.0, 800.0, 600.0)
check("centered child x", approx(centered["computed_x"], 350.0))
check("centered child y", approx(centered["computed_y"], 275.0))

# --- Hit testing ---
compute_layout(root, 0.0, 0.0, 800.0, 600.0)
check("hit inside box", point_in_widget(box, 15.0, 25.0))
check("hit outside box", point_in_widget(box, 200.0, 200.0) == false)

# --- Hover + click dispatch ---
let ui_root = create_panel(0.0, 0.0, 300.0, 200.0, COLOR_TRANSPARENT)
let ui_btn = create_button(20.0, 20.0, 120.0, 40.0, "Dispatch", COLOR_RED, on_click)
add_child(ui_root, ui_btn)
compute_layout(ui_root, 0.0, 0.0, 800.0, 600.0)
clicked[0] = false
update_hover_state(ui_root, 30.0, 30.0)
check("hovered button true", ui_btn["hovered"] == true)
let consumed = dispatch_click(ui_root, 30.0, 30.0)
check("dispatch_click consumed", consumed == true)
check("dispatch_click fired callback", clicked[0] == true)
clicked[0] = false
let consumed2 = process_ui_input(ui_root, 400.0, 400.0, true)
check("process click outside not consumed", consumed2 == false)
check("outside click did not fire callback", clicked[0] == false)

# --- Quad collection ---
let quads = []
collect_quads(root, quads)
check("collected quads > 0", len(quads) > 0)

# Hidden widget produces no quads
let hidden = create_rect(0.0, 0.0, 50.0, 50.0, COLOR_RED)
hidden["visible"] = false
let hq = []
collect_quads(hidden, hq)
check("hidden widget no quads", len(hq) == 0)

# Progress bar produces fill quad
let pb2 = create_progress_bar(0.0, 0.0, 200.0, 20.0, 0.5, rgba(0.2, 0.2, 0.2, 0.8), COLOR_RED)
compute_layout(pb2, 0.0, 0.0, 800.0, 600.0)
let pq = []
collect_quads(pb2, pq)
check("progress bar has fill quad", len(pq) >= 1)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "UI core sanity checks failed!"
else:
    print "All UI core sanity checks passed!"
