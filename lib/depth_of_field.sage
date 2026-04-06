gc_disable()
# depth_of_field.sage — Depth of Field Post-Processing Effect
# Simulates camera lens bokeh blur based on distance from focus plane.
# Supports: near/far blur, focal distance, aperture control, bokeh shapes.

import math

proc create_dof_settings():
    return {
        "enabled": true,
        "focal_distance": 10.0,    # Distance to focus plane (meters)
        "focal_range": 5.0,        # Range around focal distance that's sharp
        "near_blur": 0.5,          # Max blur for near objects (0-1)
        "far_blur": 1.0,           # Max blur for far objects (0-1)
        "aperture": 2.8,           # f-stop (lower = more blur)
        "bokeh_shape": "circle",   # circle, hexagon
        "quality": "medium",       # low, medium, high
        "max_blur_radius": 8       # Max blur kernel radius in pixels
    }

proc compute_coc(dof, depth):
    # Circle of Confusion — how blurry a pixel should be
    let dist_from_focus = depth - dof["focal_distance"]
    if dist_from_focus < 0:
        dist_from_focus = 0 - dist_from_focus
    let half_range = dof["focal_range"] * 0.5
    if dist_from_focus < half_range:
        return 0.0  # In focus
    let blur_factor = (dist_from_focus - half_range) / (dof["focal_distance"] * 0.5)
    if blur_factor > 1.0:
        blur_factor = 1.0
    if depth < dof["focal_distance"]:
        return blur_factor * dof["near_blur"]
    return blur_factor * dof["far_blur"]

proc compute_dof_weights(dof, depth_samples):
    let weights = []
    let i = 0
    while i < len(depth_samples):
        push(weights, compute_coc(dof, depth_samples[i]))
        i = i + 1
    return weights

proc set_focal_distance(dof, distance):
    dof["focal_distance"] = distance

proc set_aperture(dof, fstop):
    dof["aperture"] = fstop
    dof["near_blur"] = 1.0 / fstop
    dof["far_blur"] = 2.0 / fstop

proc auto_focus(dof, center_depth):
    dof["focal_distance"] = center_depth
