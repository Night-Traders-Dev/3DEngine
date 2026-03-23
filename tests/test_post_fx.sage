# test_post_fx.sage - Sanity checks for post-processing effects
# Run: ./run.sh tests/test_post_fx.sage

from post_fx import create_postfx, pfx_default, pfx_cinematic, pfx_warm, pfx_cold
from post_fx import pfx_horror, pfx_dream
from post_fx import fade_to_black, fade_from_black, fade_to_white
from post_fx import apply_color_grade, vignette_alpha_at
from post_fx import build_fade_quad, build_vignette_quads

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

print "=== Post-FX Sanity Checks ==="

# --- Creation ---
let pp = create_postfx()
check("postfx created", pp != nil)
check("default brightness 1", approx(pp["brightness"], 1.0))
check("default contrast 1", approx(pp["contrast"], 1.0))
check("default saturation 1", approx(pp["saturation"], 1.0))
check("no vignette", pp["vignette_enabled"] == false)
check("no bloom", pp["bloom_enabled"] == false)
check("no fade", approx(pp["fade_alpha"], 0.0))

# --- Presets ---
pfx_cinematic(pp)
check("cinematic vignette", pp["vignette_enabled"] == true)
check("cinematic contrast", pp["contrast"] > 1.0)

pfx_warm(pp)
check("warm tint red", pp["tint_color"][0] > pp["tint_color"][2])
check("warm brightness up", pp["brightness"] > 1.0)

pfx_cold(pp)
check("cold tint blue", pp["tint_color"][2] > pp["tint_color"][0])
check("cold brightness down", pp["brightness"] < 1.0)

pfx_horror(pp)
check("horror vignette strong", pp["vignette_intensity"] > 0.5)
check("horror desaturated", pp["saturation"] < 0.5)

pfx_dream(pp)
check("dream bloom", pp["bloom_enabled"] == true)
check("dream vignette", pp["vignette_enabled"] == true)

pfx_default(pp)
check("default reset brightness", approx(pp["brightness"], 1.0))
check("default reset bloom off", pp["bloom_enabled"] == false)

# --- Color grading ---
let graded = apply_color_grade(pp, 0.5, 0.5, 0.5)
check("neutral grade unchanged", approx(graded[0], 0.5))

pp["brightness"] = 2.0
let bright = apply_color_grade(pp, 0.3, 0.3, 0.3)
check("brightness doubles", approx(bright[0], 0.6))
pp["brightness"] = 1.0

pp["contrast"] = 2.0
let high_c = apply_color_grade(pp, 0.75, 0.75, 0.75)
check("high contrast pushes away from 0.5", high_c[0] > 0.75)
let low_c = apply_color_grade(pp, 0.25, 0.25, 0.25)
check("high contrast darkens darks", low_c[0] < 0.25)
pp["contrast"] = 1.0

pp["saturation"] = 0.0
let desat = apply_color_grade(pp, 1.0, 0.0, 0.0)
check("zero saturation = gray", approx(desat[0], desat[1]))
pp["saturation"] = 1.0

# Clamp
let clamped = apply_color_grade(pp, 2.0, -1.0, 0.5)
check("clamped high", approx(clamped[0], 1.0))
check("clamped low", approx(clamped[1], 0.0))

# --- Vignette ---
pp["vignette_enabled"] = false
check("vignette off returns 0", approx(vignette_alpha_at(pp, 0.0, 0.0, 800.0, 600.0), 0.0))

pp["vignette_enabled"] = true
pp["vignette_intensity"] = 0.5
pp["vignette_radius"] = 0.5
pp["vignette_softness"] = 0.3
let vig_center = vignette_alpha_at(pp, 400.0, 300.0, 800.0, 600.0)
let vig_corner = vignette_alpha_at(pp, 0.0, 0.0, 800.0, 600.0)
check("vignette center light", vig_center < vig_corner)
check("vignette corner dark", vig_corner > 0.0)

# --- Vignette quads ---
let vq = build_vignette_quads(pp, 800.0, 600.0)
check("vignette quads generated", len(vq) == 4)
pp["vignette_enabled"] = false
let vq2 = build_vignette_quads(pp, 800.0, 600.0)
check("no vignette quads when off", len(vq2) == 0)

# --- Fade ---
pp["fade_alpha"] = 0.0
let done1 = fade_to_black(pp, 2.0, 0.3)
check("fading in progress", done1 == false)
check("fade alpha increased", pp["fade_alpha"] > 0.0)

fade_to_black(pp, 2.0, 2.0)
check("fade complete", approx(pp["fade_alpha"], 1.0))

let done2 = fade_from_black(pp, 2.0, 0.3)
check("fade out in progress", done2 == false)
check("fade alpha decreased", pp["fade_alpha"] < 1.0)

fade_from_black(pp, 2.0, 2.0)
check("fade out complete", approx(pp["fade_alpha"], 0.0))

# Fade quad
pp["fade_alpha"] = 0.5
let fq = build_fade_quad(pp, 800.0, 600.0)
check("fade quad exists", fq != nil)
check("fade quad full screen", approx(fq["w"], 800.0))
check("fade quad alpha", approx(fq["color"][3], 0.5))

pp["fade_alpha"] = 0.0
let fq2 = build_fade_quad(pp, 800.0, 600.0)
check("no fade quad at 0", fq2 == nil)

# White fade
pp["fade_alpha"] = 0.0
fade_to_white(pp, 5.0, 1.0)
check("white fade color", approx(pp["fade_color"][0], 1.0))

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Post-FX sanity checks failed!"
else:
    print "All post-FX sanity checks passed!"
