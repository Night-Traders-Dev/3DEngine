gc_disable()
# star_renderer.sage — Realistic Star Rendering
# Temperature-based color (black body radiation), corona glow,
# lens flare, size pulsation, spectral classification.

import math

# ============================================================================
# Black Body Color — temperature to RGB (Kelvin)
# ============================================================================

proc temperature_to_color(kelvin):
    # Attempt accurate black body radiation curve approximation
    let temp = kelvin / 100.0
    let r = 0.0
    let g = 0.0
    let b = 0.0

    # Red channel
    if temp <= 66.0:
        r = 1.0
    else:
        r = temp - 60.0
        r = 329.698727446 * math.pow(r, -0.1332047592) / 255.0
        if r < 0.0:
            r = 0.0
        if r > 1.0:
            r = 1.0

    # Green channel
    if temp <= 66.0:
        g = temp
        g = (99.4708025861 * math.log(g) - 161.1195681661) / 255.0
        if g < 0.0:
            g = 0.0
        if g > 1.0:
            g = 1.0
    else:
        g = temp - 60.0
        g = 288.1221695283 * math.pow(g, -0.0755148492) / 255.0
        if g < 0.0:
            g = 0.0
        if g > 1.0:
            g = 1.0

    # Blue channel
    if temp >= 66.0:
        b = 1.0
    elif temp <= 19.0:
        b = 0.0
    else:
        b = temp - 10.0
        b = (138.5177312231 * math.log(b) - 305.0447927307) / 255.0
        if b < 0.0:
            b = 0.0
        if b > 1.0:
            b = 1.0

    return [r, g, b]

# ============================================================================
# Spectral Classification
# ============================================================================

proc spectral_class(temperature):
    if temperature > 30000:
        return "O"
    if temperature > 10000:
        return "B"
    if temperature > 7500:
        return "A"
    if temperature > 6000:
        return "F"
    if temperature > 5200:
        return "G"
    if temperature > 3700:
        return "K"
    return "M"

proc star_color_from_type(star_type):
    if star_type == "O":
        return temperature_to_color(35000)
    if star_type == "B":
        return temperature_to_color(20000)
    if star_type == "A":
        return temperature_to_color(8500)
    if star_type == "F":
        return temperature_to_color(6500)
    if star_type == "G":
        return temperature_to_color(5500)
    if star_type == "K":
        return temperature_to_color(4500)
    if star_type == "M":
        return temperature_to_color(3000)
    return [1.0, 1.0, 1.0]

# ============================================================================
# Star Visual Properties
# ============================================================================

proc create_star_visuals(temperature, luminosity, radius_km):
    let base_color = temperature_to_color(temperature)
    let spec = spectral_class(temperature)

    # Brightness multiplier based on luminosity
    let brightness = 1.0 + math.log(luminosity + 1.0) * 0.5

    return {
        "temperature": temperature,
        "luminosity": luminosity,
        "radius": radius_km,
        "base_color": base_color,
        "spectral_class": spec,
        "brightness": brightness,
        "corona_color": [base_color[0] * 0.8, base_color[1] * 0.7, base_color[2] * 0.5],
        "corona_size": 1.3 + luminosity * 0.1,
        "pulse_amplitude": 0.02,
        "pulse_speed": 0.5 + math.random() * 1.0,
        "flare_intensity": 0.3 + luminosity * 0.2,
        "surface_detail_seed": math.random() * 1000.0
    }

proc update_star_visuals(vis, time):
    # Gentle size pulsation
    let pulse = math.sin(time * vis["pulse_speed"]) * vis["pulse_amplitude"]
    return {
        "scale_factor": 1.0 + pulse,
        "brightness_factor": vis["brightness"] * (1.0 + pulse * 0.5),
        "corona_alpha": 0.15 + math.sin(time * vis["pulse_speed"] * 1.7) * 0.05
    }

proc star_surface_color(vis, u, v, time):
    # Animated surface detail (sunspots, granulation)
    let seed = vis["surface_detail_seed"]
    let freq = 15.0
    let detail = perlin2d(u * freq + seed, v * freq + seed * 0.5 + time * 0.1)

    # Granulation (small-scale convection cells)
    let gran = perlin2d(u * 40.0 + seed * 2.0 + time * 0.3, v * 40.0)
    gran = (gran + 1.0) * 0.5

    # Sunspot darkening
    let spot = perlin2d(u * 8.0 + seed * 3.0, v * 8.0 + time * 0.02)
    let spot_factor = 1.0
    if spot > 0.65:
        spot_factor = 0.4 + (1.0 - (spot - 0.65) / 0.35) * 0.6

    let base = vis["base_color"]
    let r = base[0] * vis["brightness"] * spot_factor * (0.9 + gran * 0.1)
    let g = base[1] * vis["brightness"] * spot_factor * (0.9 + gran * 0.08)
    let b = base[2] * vis["brightness"] * spot_factor * (0.85 + gran * 0.05)

    # Limb darkening (edges of star appear darker)
    let limb = math.sin(v * 3.14159)
    r = r * (0.7 + 0.3 * limb)
    g = g * (0.7 + 0.3 * limb)
    b = b * (0.65 + 0.35 * limb)

    if r > 1.0:
        r = 1.0
    if g > 1.0:
        g = 1.0
    if b > 1.0:
        b = 1.0
    return [r, g, b]

# Import perlin noise from procedural_planet
from procedural_planet import perlin2d

# ============================================================================
# Atmosphere Rendering (for planets)
# ============================================================================

proc atmosphere_color(planet_color, view_angle, atmosphere_thickness, scatter_color):
    # Rayleigh-like scattering at limb (edges glow with atmosphere color)
    let limb_factor = 1.0 - view_angle  # 0 at center, 1 at edge
    let scatter_strength = limb_factor * limb_factor * atmosphere_thickness

    let r = planet_color[0] * (1.0 - scatter_strength) + scatter_color[0] * scatter_strength
    let g = planet_color[1] * (1.0 - scatter_strength) + scatter_color[1] * scatter_strength
    let b = planet_color[2] * (1.0 - scatter_strength) + scatter_color[2] * scatter_strength
    return [r, g, b]

proc earth_atmosphere():
    return {"thickness": 0.3, "scatter": [0.3, 0.5, 0.9]}

proc mars_atmosphere():
    return {"thickness": 0.1, "scatter": [0.8, 0.5, 0.3]}

proc venus_atmosphere():
    return {"thickness": 0.8, "scatter": [0.9, 0.8, 0.5]}

proc titan_atmosphere():
    return {"thickness": 0.6, "scatter": [0.7, 0.5, 0.2]}
