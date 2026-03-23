gc_disable()
# -----------------------------------------
# day_night.sage - Day/night cycle for Sage Engine
# Animates sun position, sky colors, ambient light, fog
# -----------------------------------------

import math
from math3d import vec3, v3_normalize, v3_lerp
from engine_math import clamp, smoothstep

let PI = 3.14159265358979323846

# ============================================================================
# Day/Night Cycle Controller
# ============================================================================
proc create_day_cycle(day_length_seconds):
    let dc = {}
    dc["day_length"] = day_length_seconds
    dc["time_of_day"] = 0.25
    dc["speed"] = 1.0
    dc["paused"] = false
    # Sun
    dc["sun_dir"] = vec3(0.3, 0.8, 0.5)
    dc["sun_color"] = vec3(1.0, 0.95, 0.85)
    dc["sun_intensity"] = 1.0
    # Sky colors
    dc["sky_top"] = vec3(0.15, 0.3, 0.65)
    dc["sky_horizon"] = vec3(0.6, 0.75, 0.9)
    dc["ground_color"] = vec3(0.2, 0.18, 0.15)
    # Ambient
    dc["ambient_color"] = vec3(0.15, 0.15, 0.2)
    dc["ambient_intensity"] = 0.3
    # Fog
    dc["fog_color"] = vec3(0.6, 0.65, 0.7)
    dc["fog_density"] = 0.0
    return dc

# ============================================================================
# Time presets (0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset)
# ============================================================================
proc set_time_of_day(dc, t):
    dc["time_of_day"] = t - math.floor(t)

proc get_time_of_day(dc):
    return dc["time_of_day"]

proc get_hour(dc):
    return dc["time_of_day"] * 24.0

# ============================================================================
# Update cycle
# ============================================================================
proc update_day_cycle(dc, dt):
    if dc["paused"]:
        return nil
    dc["time_of_day"] = dc["time_of_day"] + (dt * dc["speed"]) / dc["day_length"]
    if dc["time_of_day"] >= 1.0:
        dc["time_of_day"] = dc["time_of_day"] - 1.0

    let t = dc["time_of_day"]
    # Sun angle (0.25=sunrise east, 0.5=noon overhead, 0.75=sunset west)
    let sun_angle = (t - 0.25) * PI * 2.0
    let sun_y = math.sin(sun_angle)
    let sun_x = math.cos(sun_angle) * 0.5
    let sun_z = 0.3
    dc["sun_dir"] = v3_normalize(vec3(sun_x, sun_y, sun_z))

    # Sun below horizon factor (0=night, 1=day)
    let day_factor = clamp(sun_y * 3.0 + 0.5, 0.0, 1.0)
    let dawn_factor = smoothstep(0.0, 0.3, sun_y)
    let dusk_factor = smoothstep(-0.1, 0.1, sun_y)

    # Sky colors
    let day_top = vec3(0.15, 0.3, 0.65)
    let night_top = vec3(0.01, 0.01, 0.05)
    let dawn_top = vec3(0.15, 0.2, 0.45)

    let day_horiz = vec3(0.6, 0.75, 0.9)
    let night_horiz = vec3(0.03, 0.04, 0.08)
    let dawn_horiz = vec3(0.8, 0.45, 0.2)

    # Blend based on sun height
    if sun_y > 0.15:
        dc["sky_top"] = v3_lerp(dawn_top, day_top, clamp((sun_y - 0.15) * 4.0, 0.0, 1.0))
        dc["sky_horizon"] = v3_lerp(dawn_horiz, day_horiz, clamp((sun_y - 0.15) * 4.0, 0.0, 1.0))
    else:
        if sun_y > -0.1:
            let dawn_t = clamp((sun_y + 0.1) * 4.0, 0.0, 1.0)
            dc["sky_top"] = v3_lerp(night_top, dawn_top, dawn_t)
            dc["sky_horizon"] = v3_lerp(night_horiz, dawn_horiz, dawn_t)
        else:
            dc["sky_top"] = night_top
            dc["sky_horizon"] = night_horiz

    dc["ground_color"] = v3_lerp(vec3(0.02, 0.02, 0.02), vec3(0.2, 0.18, 0.15), day_factor)

    # Sun color (warm at dawn/dusk, white at noon)
    if sun_y > 0.3:
        dc["sun_color"] = vec3(1.0, 0.97, 0.9)
    else:
        if sun_y > 0.0:
            let warm_t = sun_y / 0.3
            dc["sun_color"] = v3_lerp(vec3(1.0, 0.5, 0.2), vec3(1.0, 0.97, 0.9), warm_t)
        else:
            dc["sun_color"] = vec3(0.3, 0.3, 0.5)

    dc["sun_intensity"] = clamp(sun_y * 2.0, 0.05, 1.2)

    # Ambient
    dc["ambient_color"] = v3_lerp(vec3(0.02, 0.02, 0.06), vec3(0.15, 0.15, 0.2), day_factor)
    dc["ambient_intensity"] = 0.1 + day_factor * 0.25

    # Fog
    dc["fog_color"] = v3_lerp(vec3(0.05, 0.05, 0.08), vec3(0.6, 0.65, 0.7), day_factor)

# ============================================================================
# Apply to sky and lighting systems
# ============================================================================
proc apply_day_cycle_to_sky(dc, sky):
    sky["sun_dir"] = dc["sun_dir"]
    sky["sun_intensity"] = dc["sun_intensity"]
    sky["sky_top"] = dc["sky_top"]
    sky["sky_horizon"] = dc["sky_horizon"]
    sky["ground_color"] = dc["ground_color"]

proc apply_day_cycle_to_lighting(dc, light_scene, sun_light_index):
    from lighting import set_ambient
    set_ambient(light_scene, dc["ambient_color"][0], dc["ambient_color"][1], dc["ambient_color"][2], dc["ambient_intensity"])
    if sun_light_index >= 0 and sun_light_index < len(light_scene["lights"]):
        let sun = light_scene["lights"][sun_light_index]
        sun["position"] = dc["sun_dir"]
        sun["color"] = dc["sun_color"]
        sun["intensity"] = dc["sun_intensity"]
    light_scene["dirty"] = true
