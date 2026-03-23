# test_ui_text.sage - Sanity checks for bitmap text rendering
from ui_text import build_text_quads, measure_text

import math

let p = 0
let f = 0
proc check(n, c):
    if c:
        p = p + 1
    else:
        print "  FAIL: " + n
        f = f + 1

print "=== UI Text Sanity Checks ==="

# --- Measure ---
let size = measure_text("Hello", 2.0)
check("measure width > 0", size[0] > 0.0)
check("measure height > 0", size[1] > 0.0)

let size2 = measure_text("Hi", 2.0)
check("shorter text = smaller width", size2[0] < size[0])

let size3 = measure_text("A", 4.0)
let size4 = measure_text("A", 2.0)
check("bigger pixel = bigger size", size3[0] > size4[0])

# Multiline
let ml_size = measure_text("AB" + chr(10) + "CD", 2.0)
check("multiline taller", ml_size[1] > size[1])

# Empty
let empty_size = measure_text("", 2.0)
check("empty text zero width", empty_size[0] == 0.0)

# --- Build quads ---
let quads = build_text_quads("A", 10.0, 20.0, 2.0, [1.0, 1.0, 1.0, 1.0])
check("A produces quads", len(quads) > 0)
# 'A' glyph = [6,9,15,9,9,0] -> should have multiple pixels
check("A has multiple pixels", len(quads) > 3)

# Check quad properties
let q = quads[0]
check("quad has x", dict_has(q, "x"))
check("quad has y", dict_has(q, "y"))
check("quad has w", dict_has(q, "w"))
check("quad has h", dict_has(q, "h"))
check("quad has color", dict_has(q, "color"))
check("quad x >= start_x", q["x"] >= 10.0)
check("quad y >= start_y", q["y"] >= 20.0)
check("quad w = pixel_size", math.abs(q["w"] - 2.0) < 0.01)

# Color propagation
let red_quads = build_text_quads("X", 0.0, 0.0, 2.0, [1.0, 0.0, 0.0, 1.0])
if len(red_quads) > 0:
    check("color r propagated", red_quads[0]["color"][0] > 0.9)
    check("color g propagated", red_quads[0]["color"][1] < 0.1)

# Space produces no quads
let space_quads = build_text_quads(" ", 0.0, 0.0, 2.0, [1.0, 1.0, 1.0, 1.0])
check("space = no quads", len(space_quads) == 0)

# Multiple chars
let multi = build_text_quads("AB", 0.0, 0.0, 2.0, [1.0, 1.0, 1.0, 1.0])
let single = build_text_quads("A", 0.0, 0.0, 2.0, [1.0, 1.0, 1.0, 1.0])
check("2 chars more quads than 1", len(multi) > len(single))

# Numbers
let num_quads = build_text_quads("0123", 0.0, 0.0, 2.0, [1.0, 1.0, 1.0, 1.0])
check("numbers produce quads", len(num_quads) > 0)

# Special chars
let spec_quads = build_text_quads(".:+-", 0.0, 0.0, 2.0, [1.0, 1.0, 1.0, 1.0])
check("special chars work", len(spec_quads) > 0)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "UI text sanity checks failed!"
else:
    print "All UI text sanity checks passed!"
