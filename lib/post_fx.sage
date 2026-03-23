gc_disable()
# -----------------------------------------
# post_fx.sage - Screen-space post-processing for Sage Engine
# Effect parameters, color grading, vignette, fade, presets
# -----------------------------------------

import math
from engine_math import clamp

# ============================================================================
# Post-process settings
# ============================================================================
proc create_postfx():
    let pp = {}
    pp["bloom_enabled"] = false
    pp["bloom_threshold"] = 0.8
    pp["bloom_intensity"] = 0.5
    pp["vignette_enabled"] = false
    pp["vignette_intensity"] = 0.4
    pp["vignette_radius"] = 0.8
    pp["vignette_softness"] = 0.3
    pp["vignette_color"] = [0.0, 0.0, 0.0]
    pp["brightness"] = 1.0
    pp["contrast"] = 1.0
    pp["saturation"] = 1.0
    pp["gamma"] = 2.2
    pp["tint_color"] = [1.0, 1.0, 1.0]
    pp["tint_strength"] = 0.0
    pp["fade_color"] = [0.0, 0.0, 0.0]
    pp["fade_alpha"] = 0.0
    return pp

# ============================================================================
# Presets
# ============================================================================
proc pfx_default(pp):
    pp["bloom_enabled"] = false
    pp["vignette_enabled"] = false
    pp["brightness"] = 1.0
    pp["contrast"] = 1.0
    pp["saturation"] = 1.0
    pp["tint_strength"] = 0.0
    pp["fade_alpha"] = 0.0

proc pfx_cinematic(pp):
    pp["vignette_enabled"] = true
    pp["vignette_intensity"] = 0.5
    pp["contrast"] = 1.1
    pp["saturation"] = 0.9
    pp["tint_color"] = [0.95, 0.95, 1.0]
    pp["tint_strength"] = 0.1

proc pfx_warm(pp):
    pp["tint_color"] = [1.0, 0.9, 0.8]
    pp["tint_strength"] = 0.15
    pp["brightness"] = 1.05
    pp["saturation"] = 1.1

proc pfx_cold(pp):
    pp["tint_color"] = [0.8, 0.9, 1.0]
    pp["tint_strength"] = 0.15
    pp["brightness"] = 0.95
    pp["saturation"] = 0.85

proc pfx_horror(pp):
    pp["vignette_enabled"] = true
    pp["vignette_intensity"] = 0.7
    pp["vignette_radius"] = 0.6
    pp["saturation"] = 0.4
    pp["contrast"] = 1.3

proc pfx_dream(pp):
    pp["bloom_enabled"] = true
    pp["bloom_intensity"] = 0.7
    pp["brightness"] = 1.1
    pp["saturation"] = 0.7
    pp["vignette_enabled"] = true
    pp["vignette_intensity"] = 0.3

# ============================================================================
# Fade helpers
# ============================================================================
proc fade_to_black(pp, speed, dt):
    pp["fade_color"] = [0.0, 0.0, 0.0]
    pp["fade_alpha"] = clamp(pp["fade_alpha"] + speed * dt, 0.0, 1.0)
    return pp["fade_alpha"] >= 1.0

proc fade_from_black(pp, speed, dt):
    pp["fade_color"] = [0.0, 0.0, 0.0]
    pp["fade_alpha"] = clamp(pp["fade_alpha"] - speed * dt, 0.0, 1.0)
    return pp["fade_alpha"] <= 0.0

proc fade_to_white(pp, speed, dt):
    pp["fade_color"] = [1.0, 1.0, 1.0]
    pp["fade_alpha"] = clamp(pp["fade_alpha"] + speed * dt, 0.0, 1.0)
    return pp["fade_alpha"] >= 1.0

# ============================================================================
# Software color grading (per-pixel)
# ============================================================================
proc apply_color_grade(pp, r, g, b):
    r = r * pp["brightness"]
    g = g * pp["brightness"]
    b = b * pp["brightness"]
    let c = pp["contrast"]
    r = (r - 0.5) * c + 0.5
    g = (g - 0.5) * c + 0.5
    b = (b - 0.5) * c + 0.5
    let lum = r * 0.299 + g * 0.587 + b * 0.114
    let s = pp["saturation"]
    r = lum + (r - lum) * s
    g = lum + (g - lum) * s
    b = lum + (b - lum) * s
    if pp["tint_strength"] > 0.0:
        let ts = pp["tint_strength"]
        r = r * (1.0 - ts) + r * pp["tint_color"][0] * ts
        g = g * (1.0 - ts) + g * pp["tint_color"][1] * ts
        b = b * (1.0 - ts) + b * pp["tint_color"][2] * ts
    return [clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0)]

# ============================================================================
# Vignette alpha at screen position
# ============================================================================
proc vignette_alpha_at(pp, sx, sy, sw, sh):
    if pp["vignette_enabled"] == false:
        return 0.0
    let cx = sx / sw - 0.5
    let cy = sy / sh - 0.5
    let dist = math.sqrt(cx * cx + cy * cy) * 2.0
    let edge = pp["vignette_radius"]
    let soft = pp["vignette_softness"]
    let vig = clamp((dist - edge) / soft, 0.0, 1.0)
    return vig * pp["vignette_intensity"]

# ============================================================================
# Build fade overlay quad data for UI rendering
# ============================================================================
proc build_fade_quad(pp, screen_w, screen_h):
    if pp["fade_alpha"] <= 0.001:
        return nil
    let q = {}
    q["x"] = 0.0
    q["y"] = 0.0
    q["w"] = screen_w
    q["h"] = screen_h
    let fc = pp["fade_color"]
    q["color"] = [fc[0], fc[1], fc[2], pp["fade_alpha"]]
    return q

# ============================================================================
# Build vignette overlay quads (4 corner darkening rects)
# ============================================================================
proc build_vignette_quads(pp, screen_w, screen_h):
    if pp["vignette_enabled"] == false:
        return []
    let quads = []
    let intensity = pp["vignette_intensity"]
    let bw = screen_w * 0.25
    let bh = screen_h * 0.25
    let a = intensity * 0.5
    # Top
    push(quads, {"x": 0.0, "y": 0.0, "w": screen_w, "h": bh, "color": [0.0, 0.0, 0.0, a]})
    # Bottom
    push(quads, {"x": 0.0, "y": screen_h - bh, "w": screen_w, "h": bh, "color": [0.0, 0.0, 0.0, a]})
    # Left
    push(quads, {"x": 0.0, "y": 0.0, "w": bw, "h": screen_h, "color": [0.0, 0.0, 0.0, a * 0.7]})
    # Right
    push(quads, {"x": screen_w - bw, "y": 0.0, "w": bw, "h": screen_h, "color": [0.0, 0.0, 0.0, a * 0.7]})
    return quads
