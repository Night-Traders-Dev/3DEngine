gc_disable()
# procedural_planet.sage — Procedural Planet Generation
# Perlin noise-based terrain with biomes, oceans, mountains, weather.
# Generates heightmaps, color maps, and normal maps for each planet.

import math

# ============================================================================
# Perlin Noise (2D and 3D)
# ============================================================================

# Permutation table (hash-based pseudo-random)
let _perm = []
let _pi = 0
while _pi < 512:
    let v = (_pi * 1103515245 + 12345) / 65536
    v = v - int(v / 256) * 256
    if v < 0:
        v = 0 - v
    push(_perm, int(v))
    _pi = _pi + 1

proc _fade(t):
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

proc _lerp(a, b, t):
    return a + t * (b - a)

proc _grad2d(hash, x, y):
    let h = hash & 3
    if h == 0:
        return x + y
    if h == 1:
        return 0.0 - x + y
    if h == 2:
        return x - y
    return 0.0 - x - y

proc perlin2d(x, y):
    let xi = int(x) & 255
    let yi = int(y) & 255
    if xi < 0:
        xi = xi + 256
    if yi < 0:
        yi = yi + 256
    let xf = x - int(x)
    let yf = y - int(y)
    if xf < 0:
        xf = xf + 1.0
    if yf < 0:
        yf = yf + 1.0
    let u = _fade(xf)
    let v = _fade(yf)

    let aa = _perm[_perm[xi] + yi]
    let ab = _perm[_perm[xi] + yi + 1]
    let ba = _perm[_perm[xi + 1] + yi]
    let bb = _perm[_perm[xi + 1] + yi + 1]

    let x1 = _lerp(_grad2d(aa, xf, yf), _grad2d(ba, xf - 1.0, yf), u)
    let x2 = _lerp(_grad2d(ab, xf, yf - 1.0), _grad2d(bb, xf - 1.0, yf - 1.0), u)
    return _lerp(x1, x2, v)

proc fbm2d(x, y, octaves, lacunarity, gain):
    let value = 0.0
    let amplitude = 1.0
    let frequency = 1.0
    let max_val = 0.0
    let i = 0
    while i < octaves:
        value = value + perlin2d(x * frequency, y * frequency) * amplitude
        max_val = max_val + amplitude
        amplitude = amplitude * gain
        frequency = frequency * lacunarity
        i = i + 1
    return value / max_val

# Ridged noise — for mountain ridges and canyons
proc ridged_noise(x, y, octaves, lacunarity, gain):
    let value = 0.0
    let amplitude = 1.0
    let frequency = 1.0
    let weight = 1.0
    let i = 0
    while i < octaves:
        let n = perlin2d(x * frequency, y * frequency)
        if n < 0:
            n = 0.0 - n
        n = 1.0 - n
        n = n * n * weight
        value = value + n * amplitude
        weight = n
        if weight > 1.0:
            weight = 1.0
        amplitude = amplitude * gain
        frequency = frequency * lacunarity
        i = i + 1
    return value

# Domain warping — distort coordinates for organic shapes
proc warped_noise(x, y, octaves, warp_strength):
    let wx = fbm2d(x + 5.2, y + 1.3, octaves, 2.0, 0.5) * warp_strength
    let wy = fbm2d(x + 1.7, y + 9.2, octaves, 2.0, 0.5) * warp_strength
    return fbm2d(x + wx, y + wy, octaves, 2.0, 0.5)

# ============================================================================
# Planet Surface Generation
# ============================================================================

proc create_planet_surface(seed, resolution):
    return {
        "seed": seed,
        "resolution": resolution,     # Grid size (e.g., 256)
        "heightmap": nil,              # Generated heights
        "colormap": nil,               # Generated colors
        "ocean_level": 0.4,            # Sea level (0-1)
        "mountain_scale": 1.0,
        "temperature_offset": 0.0,     # -1 (frozen) to +1 (hot)
        "moisture_scale": 1.0,
        "terrain_frequency": 3.0,
        "continent_frequency": 0.8,
        "generated": false
    }

proc generate_planet_heightmap(surface):
    let res = surface["resolution"]
    let seed = surface["seed"]
    let heightmap = []
    let colormap = []

    let y = 0
    while y < res:
        let x = 0
        while x < res:
            # Spherical UV mapping
            let u = x / res
            let v = y / res
            let nx = u * surface["terrain_frequency"] + seed
            let ny = v * surface["terrain_frequency"] + seed * 0.7

            # Continental shapes (low frequency)
            let continent = fbm2d(nx * surface["continent_frequency"], ny * surface["continent_frequency"], 4, 2.0, 0.5)
            continent = (continent + 1.0) * 0.5  # Normalize to 0-1

            # Terrain detail (high frequency)
            let detail = fbm2d(nx * 4.0, ny * 4.0, 6, 2.0, 0.5)

            # Mountain ridges
            let ridges = ridged_noise(nx * 2.0, ny * 2.0, 4, 2.0, 0.5) * surface["mountain_scale"]

            # Combine: continent base + detail + ridges
            let height = continent * 0.6 + detail * 0.2 + ridges * 0.2

            # Clamp
            if height < 0.0:
                height = 0.0
            if height > 1.0:
                height = 1.0

            push(heightmap, height)

            # Color based on height and biome
            let color = _height_to_color(height, surface["ocean_level"], u, v, surface["temperature_offset"], surface["moisture_scale"], seed)
            push(colormap, color)

            x = x + 1
        y = y + 1

    surface["heightmap"] = heightmap
    surface["colormap"] = colormap
    surface["generated"] = true
    return surface

proc _height_to_color(height, ocean_level, u, v, temp_offset, moisture, seed):
    # Temperature: hotter at equator, colder at poles
    let latitude = (v - 0.5) * 2.0  # -1 to +1
    if latitude < 0:
        latitude = 0.0 - latitude
    let temperature = 1.0 - latitude + temp_offset

    # Moisture varies with noise
    let moisture_val = (fbm2d(u * 5.0 + seed * 2.0, v * 5.0, 3, 2.0, 0.5) + 1.0) * 0.5 * moisture

    if height < ocean_level:
        # Ocean — deeper = darker blue
        let depth = (ocean_level - height) / ocean_level
        return [0.05 + 0.1 * (1.0 - depth), 0.15 + 0.2 * (1.0 - depth), 0.4 + 0.3 * (1.0 - depth)]

    # Normalize land height above ocean
    let land_h = (height - ocean_level) / (1.0 - ocean_level)

    # Beach
    if land_h < 0.05:
        return [0.76, 0.70, 0.50]

    # Ice caps (poles + high altitude)
    if temperature < 0.15 or (land_h > 0.7 and temperature < 0.4):
        return [0.9, 0.92, 0.95]

    # Desert (hot + dry)
    if temperature > 0.7 and moisture_val < 0.3:
        return [0.82, 0.75, 0.55]

    # Savanna (warm + moderate moisture)
    if temperature > 0.5 and moisture_val < 0.5:
        return [0.6, 0.65, 0.3]

    # Tropical forest (hot + wet)
    if temperature > 0.6 and moisture_val > 0.6:
        return [0.1, 0.45, 0.15]

    # Temperate forest
    if moisture_val > 0.4 and land_h < 0.4:
        return [0.2, 0.5, 0.2]

    # Grassland
    if land_h < 0.3:
        return [0.35, 0.6, 0.25]

    # Highland
    if land_h < 0.5:
        return [0.45, 0.42, 0.35]

    # Mountain rock
    if land_h < 0.7:
        return [0.5, 0.48, 0.45]

    # Mountain peak snow
    return [0.85, 0.87, 0.9]

# ============================================================================
# Weather System — clouds, storms, wind patterns
# ============================================================================

proc create_planet_weather(seed):
    return {
        "seed": seed,
        "time": 0.0,
        "wind_speed": 1.0,
        "cloud_coverage": 0.5,
        "storm_intensity": 0.0,
        "cloud_frequency": 4.0
    }

proc update_planet_weather(weather, dt):
    weather["time"] = weather["time"] + dt * weather["wind_speed"]
    # Storm cycles
    weather["storm_intensity"] = (math.sin(weather["time"] * 0.1) + 1.0) * 0.3

proc sample_clouds(weather, u, v):
    let t = weather["time"]
    let freq = weather["cloud_frequency"]
    # Animated cloud noise
    let cloud = fbm2d(u * freq + t * 0.02, v * freq + t * 0.01, 4, 2.0, 0.5)
    cloud = (cloud + 1.0) * 0.5
    # Apply coverage threshold
    let threshold = 1.0 - weather["cloud_coverage"] - weather["storm_intensity"] * 0.3
    if cloud < threshold:
        return 0.0
    return (cloud - threshold) / (1.0 - threshold)

proc sample_wind(weather, u, v):
    let t = weather["time"]
    let wx = perlin2d(u * 3.0 + t * 0.05, v * 3.0)
    let wy = perlin2d(u * 3.0 + 100.0, v * 3.0 + t * 0.05)
    return [wx, wy]

# ============================================================================
# Gas Giant Generation
# ============================================================================

proc create_gas_giant_surface(seed, band_count, storm_count):
    let bands = []
    let i = 0
    while i < band_count:
        let hue = math.random() * 0.3 + 0.05  # Warm hues
        let sat = 0.3 + math.random() * 0.4
        let val = 0.5 + math.random() * 0.4
        let speed = (math.random() - 0.5) * 2.0
        push(bands, {"hue": hue, "saturation": sat, "value": val, "speed": speed, "width": 0.5 + math.random() * 1.5})
        i = i + 1

    let storms = []
    i = 0
    while i < storm_count:
        push(storms, {
            "lat": (math.random() - 0.5) * 0.8,
            "lon": math.random(),
            "size": 0.02 + math.random() * 0.06,
            "intensity": 0.5 + math.random() * 0.5,
            "rotation_speed": (math.random() - 0.5) * 5.0
        })
        i = i + 1

    return {
        "seed": seed,
        "bands": bands,
        "storms": storms,
        "time": 0.0
    }

proc sample_gas_giant(giant, u, v, time):
    # Band color based on latitude
    let lat = v * len(giant["bands"])
    let band_idx = int(lat) % len(giant["bands"])
    let band = giant["bands"][band_idx]

    # Base color from band
    let r = band["value"] * (1.0 - band["saturation"] + band["saturation"] * band["hue"])
    let g = band["value"] * (1.0 - band["saturation"] + band["saturation"] * (1.0 - band["hue"]))
    let b = band["value"] * (1.0 - band["saturation"] * 0.5)

    # Add turbulence
    let turb = perlin2d(u * 20.0 + time * band["speed"], v * 20.0 + giant["seed"]) * 0.1
    r = r + turb
    g = g + turb * 0.8
    b = b + turb * 0.5

    # Storm spots
    let si = 0
    while si < len(giant["storms"]):
        let storm = giant["storms"][si]
        let du = u - storm["lon"]
        let dv = v - 0.5 - storm["lat"]
        let dist = math.sqrt(du * du + dv * dv)
        if dist < storm["size"]:
            let factor = 1.0 - dist / storm["size"]
            let swirl = perlin2d(u * 50.0 + time * storm["rotation_speed"], v * 50.0) * factor
            r = r + swirl * 0.15 * storm["intensity"]
            g = g - swirl * 0.05 * storm["intensity"]
            b = b - swirl * 0.1 * storm["intensity"]
        si = si + 1

    if r < 0.0:
        r = 0.0
    if r > 1.0:
        r = 1.0
    if g < 0.0:
        g = 0.0
    if g > 1.0:
        g = 1.0
    if b < 0.0:
        b = 0.0
    if b > 1.0:
        b = 1.0
    return [r, g, b]

# ============================================================================
# Query helpers
# ============================================================================

proc get_height_at(surface, u, v):
    if not surface["generated"] or surface["heightmap"] == nil:
        return 0.0
    let res = surface["resolution"]
    let x = int(u * res) % res
    let y = int(v * res) % res
    if x < 0:
        x = x + res
    if y < 0:
        y = y + res
    let idx = y * res + x
    if idx >= 0 and idx < len(surface["heightmap"]):
        return surface["heightmap"][idx]
    return 0.0

proc get_color_at(surface, u, v):
    if not surface["generated"] or surface["colormap"] == nil:
        return [0.5, 0.5, 0.5]
    let res = surface["resolution"]
    let x = int(u * res) % res
    let y = int(v * res) % res
    if x < 0:
        x = x + res
    if y < 0:
        y = y + res
    let idx = y * res + x
    if idx >= 0 and idx < len(surface["colormap"]):
        return surface["colormap"][idx]
    return [0.5, 0.5, 0.5]
