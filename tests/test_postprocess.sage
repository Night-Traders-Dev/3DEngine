# test_postprocess.sage - Sanity checks for HDR/bloom postprocess helpers
# Run: ./run.sh tests/test_postprocess.sage

from postprocess import bloom_dimensions, build_bloom_extract_push_data, build_bloom_blur_push_data
from postprocess import build_tonemap_push_data, pfx_shaderpack_day, pfx_editor_preview
from postprocess import scene_pass_clear_values, scene_pass_load_values
from postprocess import TONEMAP_ACES

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Postprocess Sanity Checks ==="

let dims = bloom_dimensions(1280, 720)
check("bloom dimensions halve render size", dims[0] == 640 and dims[1] == 360)

let dims_small = bloom_dimensions(1, 1)
check("bloom dimensions clamp to minimum 1", dims_small[0] == 1 and dims_small[1] == 1)

let pp = {}
pp["bloom_threshold"] = 0.88
pp["bloom_soft_knee"] = 0.18
pp["highlight_saturation"] = 1.10
pp["bloom_width"] = 640.0
pp["bloom_height"] = 360.0
pp["bloom_radius"] = 1.1
pp["exposure"] = 0.84
pp["bloom_intensity"] = 0.18
pp["tonemap_mode"] = TONEMAP_ACES
pp["gamma"] = 2.2
pp["contrast"] = 1.18
pp["saturation"] = 1.28
pp["warmth"] = 0.05
pp["vignette_strength"] = 0.08

let extract = build_bloom_extract_push_data(pp)
check("extract push has 4 floats", len(extract) == 4)
check("extract push stores threshold and knee", extract[0] == 0.88 and extract[1] == 0.18)

let blur_h = build_bloom_blur_push_data(pp, true)
check("blur push has 4 floats", len(blur_h) == 4)
check("blur push stores texel sizes", blur_h[0] == 1.0 / 640.0 and blur_h[1] == 1.0 / 360.0)
check("blur push encodes horizontal pass", blur_h[2] == 1.0)

let tonemap = build_tonemap_push_data(pp)
check("tonemap push has 8 floats", len(tonemap) == 8)
check("tonemap push stores exposure and bloom", tonemap[0] == 0.84 and tonemap[1] == 0.18)
check("tonemap push stores grading params", tonemap[4] == 1.18 and tonemap[7] == 0.08)

let clear_values = scene_pass_clear_values(nil)
check("scene clear values include color and depth", len(clear_values) == 2 and len(clear_values[0]) == 4 and len(clear_values[1]) == 4)
check("scene clear values use default sky-ish color", clear_values[0][0] == 0.02 and clear_values[0][3] == 1.0)

let custom_clear = scene_pass_clear_values([0.3, 0.4, 0.5, 1.0])
check("scene clear values accept overrides", custom_clear[0][0] == 0.3 and custom_clear[0][2] == 0.5)

let load_values = scene_pass_load_values()
check("scene load values keep color and depth attachments", len(load_values) == 2 and load_values[1][0] == 1.0)

let preset = {}
pfx_shaderpack_day(preset)
check("shaderpack preset enables bloom", preset["bloom_enabled"])
check("shaderpack preset uses ACES", preset["tonemap_mode"] == TONEMAP_ACES)
check("shaderpack preset boosts saturation", preset["saturation"] > 1.0)
check("shaderpack preset uses restrained exposure", preset["exposure"] < 0.9 and preset["bloom_threshold"] >= 0.94)

pfx_editor_preview(preset)
check("editor preset keeps bloom enabled", preset["bloom_enabled"])
check("editor preset is milder than shaderpack", preset["bloom_intensity"] < 0.18 and preset["exposure"] < 0.84)

print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Postprocess sanity checks failed!"
else:
    print "All postprocess sanity checks passed!"
