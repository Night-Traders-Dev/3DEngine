gc_disable()
# volumetric.sage — Volumetric Effects (Fog, Light Shafts, Clouds)
# Supports: distance fog, height fog, volumetric light shafts (god rays),
# procedural clouds, atmospheric scattering
#
# Usage:
#   let vfx = create_volumetric_system()
#   set_distance_fog(vfx, 50.0, 200.0, [0.6, 0.65, 0.7])
#   set_height_fog(vfx, 0.0, 20.0, 0.3, [0.5, 0.55, 0.6])
#   set_god_rays(vfx, sun_direction, 0.8, 0.5)
#   let fog_color = sample_fog(vfx, position, camera_pos)

import math
from math3d import vec3, v3_sub, v3_length, v3_dot, v3_normalize

# ============================================================================
# Volumetric System
# ============================================================================

proc create_volumetric_system():
    return {
        # Distance fog
        "dist_fog_enabled": false,
        "dist_fog_near": 50.0,
        "dist_fog_far": 200.0,
        "dist_fog_color": [0.6, 0.65, 0.7],
        "dist_fog_density": 1.0,

        # Height fog
        "height_fog_enabled": false,
        "height_fog_base": 0.0,
        "height_fog_top": 20.0,
        "height_fog_density": 0.3,
        "height_fog_color": [0.5, 0.55, 0.6],

        # God rays
        "god_rays_enabled": false,
        "god_rays_direction": vec3(0.3, -0.8, 0.5),
        "god_rays_intensity": 0.5,
        "god_rays_decay": 0.95,
        "god_rays_samples": 64,
        "god_rays_color": [1.0, 0.95, 0.8],

        # Clouds
        "clouds_enabled": false,
        "cloud_height": 100.0,
        "cloud_thickness": 30.0,
        "cloud_coverage": 0.5,
        "cloud_speed": 2.0,
        "cloud_color": [1.0, 1.0, 1.0],
        "cloud_time": 0.0,

        # Atmospheric scattering
        "scatter_enabled": false,
        "scatter_rayleigh": [0.0058, 0.0135, 0.0331],
        "scatter_mie": 0.004,
        "scatter_sun_intensity": 20.0
    }

# ============================================================================
# Configuration
# ============================================================================

proc set_distance_fog(vfx, near, far, color):
    vfx["dist_fog_enabled"] = true
    vfx["dist_fog_near"] = near
    vfx["dist_fog_far"] = far
    vfx["dist_fog_color"] = color

proc set_height_fog(vfx, base, top, density, color):
    vfx["height_fog_enabled"] = true
    vfx["height_fog_base"] = base
    vfx["height_fog_top"] = top
    vfx["height_fog_density"] = density
    vfx["height_fog_color"] = color

proc set_god_rays(vfx, direction, intensity, decay):
    vfx["god_rays_enabled"] = true
    vfx["god_rays_direction"] = v3_normalize(direction)
    vfx["god_rays_intensity"] = intensity
    vfx["god_rays_decay"] = decay

proc set_clouds(vfx, height, thickness, coverage, speed):
    vfx["clouds_enabled"] = true
    vfx["cloud_height"] = height
    vfx["cloud_thickness"] = thickness
    vfx["cloud_coverage"] = coverage
    vfx["cloud_speed"] = speed

proc set_atmospheric_scattering(vfx, sun_intensity):
    vfx["scatter_enabled"] = true
    vfx["scatter_sun_intensity"] = sun_intensity

# ============================================================================
# Fog Sampling — compute fog factor and color for a world position
# ============================================================================

proc sample_distance_fog(vfx, world_pos, camera_pos):
    if not vfx["dist_fog_enabled"]:
        return {"factor": 0.0, "color": [0.0, 0.0, 0.0]}

    let dist = v3_length(v3_sub(world_pos, camera_pos))
    let factor = (dist - vfx["dist_fog_near"]) / (vfx["dist_fog_far"] - vfx["dist_fog_near"])
    if factor < 0.0:
        factor = 0.0
    if factor > 1.0:
        factor = 1.0
    factor = factor * vfx["dist_fog_density"]
    return {"factor": factor, "color": vfx["dist_fog_color"]}

proc sample_height_fog(vfx, world_pos, camera_pos):
    if not vfx["height_fog_enabled"]:
        return {"factor": 0.0, "color": [0.0, 0.0, 0.0]}

    let y = world_pos[1]
    let factor = 0.0
    if y < vfx["height_fog_top"]:
        if y < vfx["height_fog_base"]:
            factor = vfx["height_fog_density"]
        else:
            let range = vfx["height_fog_top"] - vfx["height_fog_base"]
            factor = vfx["height_fog_density"] * (1.0 - (y - vfx["height_fog_base"]) / range)

    # Also factor in distance
    let dist = v3_length(v3_sub(world_pos, camera_pos))
    factor = factor * (1.0 - math.exp(0.0 - dist * 0.01))

    return {"factor": factor, "color": vfx["height_fog_color"]}

proc sample_fog(vfx, world_pos, camera_pos):
    let dist_fog = sample_distance_fog(vfx, world_pos, camera_pos)
    let height_fog = sample_height_fog(vfx, world_pos, camera_pos)
    let total = dist_fog["factor"] + height_fog["factor"]
    if total > 1.0:
        total = 1.0

    let color = [0.0, 0.0, 0.0]
    if total > 0.0:
        let dw = dist_fog["factor"] / (total + 0.001)
        let hw = height_fog["factor"] / (total + 0.001)
        color[0] = dist_fog["color"][0] * dw + height_fog["color"][0] * hw
        color[1] = dist_fog["color"][1] * dw + height_fog["color"][1] * hw
        color[2] = dist_fog["color"][2] * dw + height_fog["color"][2] * hw
    return {"factor": total, "color": color}

# ============================================================================
# God Rays — screen-space light shaft sampling
# ============================================================================

proc compute_god_rays_screen_pos(vfx, view_proj_matrix):
    # Project sun direction to screen space
    # Simplified: return a fixed screen position based on sun direction
    let dir = vfx["god_rays_direction"]
    let sx = 0.5 + dir[0] * 0.4
    let sy = 0.5 + dir[1] * 0.4
    return [sx, sy]

proc god_rays_sample(vfx, screen_uv, sun_screen_pos):
    if not vfx["god_rays_enabled"]:
        return 0.0

    # March from pixel toward sun
    let delta_x = (sun_screen_pos[0] - screen_uv[0]) / vfx["god_rays_samples"]
    let delta_y = (sun_screen_pos[1] - screen_uv[1]) / vfx["god_rays_samples"]

    let illumination = 0.0
    let decay = 1.0
    let ux = screen_uv[0]
    let uy = screen_uv[1]

    let i = 0
    while i < vfx["god_rays_samples"]:
        ux = ux + delta_x
        uy = uy + delta_y
        # Sample depth buffer at (ux, uy) — simplified: always contribute
        illumination = illumination + decay * 0.02
        decay = decay * vfx["god_rays_decay"]
        i = i + 1

    return illumination * vfx["god_rays_intensity"]

# ============================================================================
# Procedural Clouds — noise-based cloud density
# ============================================================================

proc update_clouds(vfx, dt):
    if vfx["clouds_enabled"]:
        vfx["cloud_time"] = vfx["cloud_time"] + dt * vfx["cloud_speed"]

proc sample_cloud_density(vfx, world_x, world_z):
    if not vfx["clouds_enabled"]:
        return 0.0

    # Simple hash-based noise (no Perlin — approximate)
    let t = vfx["cloud_time"]
    let nx = (world_x + t) * 0.01
    let nz = world_z * 0.01
    let hash = math.sin(nx * 127.1 + nz * 311.7) * 43758.5453
    hash = hash - math.floor(hash)

    let density = hash - (1.0 - vfx["cloud_coverage"])
    if density < 0.0:
        density = 0.0
    if density > 1.0:
        density = 1.0
    return density

proc cloud_shadow_at(vfx, world_pos, sun_dir):
    if not vfx["clouds_enabled"]:
        return 1.0  # No shadow

    # Project position to cloud plane along sun direction
    let t = (vfx["cloud_height"] - world_pos[1]) / (sun_dir[1] - 0.001)
    let cloud_x = world_pos[0] + sun_dir[0] * t
    let cloud_z = world_pos[2] + sun_dir[2] * t
    let density = sample_cloud_density(vfx, cloud_x, cloud_z)
    return 1.0 - density * 0.6  # Soft cloud shadows
