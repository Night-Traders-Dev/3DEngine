gc_disable()
# motion_blur.sage — Motion Blur Post-Processing
# Camera motion blur and per-object motion blur via velocity buffer.

import math
from math3d import vec3, v3_sub, v3_length

proc create_motion_blur_settings():
    return {
        "enabled": true,
        "intensity": 0.5,           # 0-1 blur strength
        "samples": 8,               # Number of blur samples
        "max_blur_pixels": 16,      # Maximum blur in pixels
        "camera_blur": true,        # Blur from camera rotation
        "object_blur": true,        # Blur from object movement
        "prev_view_proj": nil,      # Previous frame's VP matrix
        "velocity_scale": 1.0
    }

proc update_motion_blur(mb, current_vp, dt):
    if mb["prev_view_proj"] == nil:
        mb["prev_view_proj"] = current_vp
    # Compute per-pixel velocity from current vs previous VP
    mb["velocity_scale"] = mb["intensity"] / (dt + 0.001)
    mb["prev_view_proj"] = current_vp

proc compute_pixel_velocity(mb, current_vp, prev_vp, world_pos):
    # Project world position with current and previous VP
    # Returns screen-space velocity vector
    return [0.0, 0.0]  # Simplified — actual impl uses matrix projection

proc set_motion_blur_intensity(mb, intensity):
    mb["intensity"] = intensity
    if intensity <= 0:
        mb["enabled"] = false
    else:
        mb["enabled"] = true
