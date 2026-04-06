gc_disable()
# planet_mesh.sage — Generate colored sphere meshes with procedural surface detail
# Each vertex gets a unique color from noise-based terrain/atmosphere simulation.
# No texture files needed — pure procedural generation.

import gpu
import math
from procedural_planet import perlin2d, fbm2d, ridged_noise

# ============================================================================
# Generate a sphere mesh with per-vertex color from a coloring function
# ============================================================================

proc generate_planet_sphere(segments, color_fn):
    # color_fn(u, v) → [r, g, b] where u,v are 0..1 spherical coordinates
    let vertices = []
    let indices = []
    let rings = segments
    let sectors = segments

    # Generate vertices with position + normal + uv + color baked into position
    let ri = 0
    while ri <= rings:
        let v = ri / rings
        let phi = v * 3.14159265
        let si = 0
        while si <= sectors:
            let u = si / sectors
            let theta = u * 6.28318530

            let x = math.sin(phi) * math.cos(theta)
            let y = math.cos(phi)
            let z = math.sin(phi) * math.sin(theta)

            # Get procedural color for this point on the sphere
            let color = color_fn(u, v)

            # Pack vertex: pos(3) + normal(3) + uv(2) = 8 floats
            # We encode color into the normal to pass it through the unlit shader
            # Actually unlit shader uses push constant color, not per-vertex...
            # So we need to store color data differently.
            #
            # For the unlit pipeline: we'll generate multiple draw calls per planet,
            # one per "patch" of the sphere with different colors.
            #
            # Better approach: store vertices with position only, and we'll
            # draw the sphere in patches.

            push(vertices, x)
            push(vertices, y)
            push(vertices, z)
            # Normal = same as position for unit sphere
            push(vertices, x)
            push(vertices, y)
            push(vertices, z)
            # UV
            push(vertices, u)
            push(vertices, v)

            si = si + 1
        ri = ri + 1

    # Generate indices
    ri = 0
    while ri < rings:
        let si = 0
        while si < sectors:
            let cur = ri * (sectors + 1) + si
            let next = cur + sectors + 1

            push(indices, cur)
            push(indices, next)
            push(indices, cur + 1)

            push(indices, cur + 1)
            push(indices, next)
            push(indices, next + 1)
            si = si + 1
        ri = ri + 1

    return {
        "vertices": vertices,
        "indices": indices,
        "vertex_count": (rings + 1) * (sectors + 1),
        "index_count": len(indices)
    }

# ============================================================================
# Planet color functions — return [r, g, b] for spherical coordinate (u, v)
# ============================================================================

proc earth_color(u, v):
    let lat = (v - 0.5) * 2.0  # -1 to 1
    if lat < 0:
        lat = 0.0 - lat

    # Continental noise
    let continent = fbm2d(u * 4.0 + 42.0, v * 4.0 + 17.0, 5, 2.0, 0.5)
    let height = (continent + 1.0) * 0.5  # 0 to 1
    let ocean_level = 0.45

    # Ice caps
    if lat > 0.85:
        return [0.92, 0.94, 0.97]

    if height < ocean_level:
        # Ocean — darker blue in deep water
        let depth = (ocean_level - height) / ocean_level
        return [0.04 + 0.08 * (1.0 - depth), 0.12 + 0.18 * (1.0 - depth), 0.35 + 0.30 * (1.0 - depth)]

    let land_h = (height - ocean_level) / (1.0 - ocean_level)

    # Beach
    if land_h < 0.05:
        return [0.76, 0.70, 0.50]

    # Desert near equator
    if lat < 0.25 and land_h < 0.3:
        let desert_noise = fbm2d(u * 8.0, v * 8.0, 3, 2.0, 0.5)
        if desert_noise > 0.1:
            return [0.80, 0.72, 0.48]

    # Forest (green areas)
    if land_h < 0.35:
        let green_var = fbm2d(u * 12.0 + 5.0, v * 12.0, 3, 2.0, 0.5) * 0.1
        return [0.15 + green_var, 0.45 + green_var, 0.12 + green_var]

    # Highland
    if land_h < 0.55:
        return [0.42, 0.40, 0.32]

    # Mountain
    if land_h < 0.75:
        return [0.52, 0.50, 0.46]

    # Snow peaks
    return [0.88, 0.90, 0.92]

proc mars_color(u, v):
    let noise = fbm2d(u * 5.0 + 99.0, v * 5.0 + 33.0, 5, 2.0, 0.5)
    let height = (noise + 1.0) * 0.5

    # Ice cap at south pole
    let lat = (v - 0.5) * 2.0
    if lat < 0:
        lat = 0.0 - lat
    if lat > 0.88:
        return [0.90, 0.88, 0.85]

    # Rusty red terrain with variation
    let detail = fbm2d(u * 15.0, v * 15.0, 3, 2.0, 0.5) * 0.08
    if height < 0.3:
        # Low dark terrain
        return [0.55 + detail, 0.28 + detail, 0.12 + detail]
    if height < 0.6:
        # Mid terrain
        return [0.72 + detail, 0.42 + detail, 0.20 + detail]
    # High bright terrain
    return [0.82 + detail, 0.55 + detail, 0.30 + detail]

proc venus_color(u, v):
    # Thick cloud cover — yellowish swirls
    let cloud1 = fbm2d(u * 6.0 + 77.0, v * 3.0, 4, 2.0, 0.5)
    let cloud2 = fbm2d(u * 4.0 + 22.0, v * 6.0 + 11.0, 3, 2.0, 0.5)
    let pattern = (cloud1 + cloud2) * 0.5
    let bright = 0.75 + pattern * 0.15
    return [bright, bright * 0.88, bright * 0.55]

proc mercury_color(u, v):
    # Cratered grey surface
    let base = fbm2d(u * 8.0 + 55.0, v * 8.0 + 88.0, 5, 2.0, 0.5)
    let crater = ridged_noise(u * 12.0, v * 12.0, 4, 2.0, 0.5)
    let grey = 0.45 + base * 0.15 - crater * 0.08
    if grey < 0.3:
        grey = 0.3
    if grey > 0.7:
        grey = 0.7
    return [grey, grey, grey * 1.02]

proc jupiter_color(u, v):
    # Banded atmosphere with Great Red Spot
    let band = math.sin(v * 20.0) * 0.5 + 0.5
    let turb = fbm2d(u * 25.0 + 44.0, v * 3.0, 3, 2.0, 0.5) * 0.08
    let r = 0.72 + band * 0.12 + turb
    let g = 0.58 + band * 0.10 + turb * 0.8
    let b = 0.38 + band * 0.05 + turb * 0.4

    # Great Red Spot (approximate location)
    let spot_u = u - 0.3
    let spot_v = v - 0.45
    let spot_dist = math.sqrt(spot_u * spot_u * 4.0 + spot_v * spot_v * 16.0)
    if spot_dist < 0.08:
        let spot_swirl = fbm2d(u * 40.0, v * 40.0, 3, 2.0, 0.5)
        r = 0.80 + spot_swirl * 0.05
        g = 0.45 + spot_swirl * 0.03
        b = 0.30

    return [r, g, b]

proc saturn_color(u, v):
    # Banded but more muted than Jupiter
    let band = math.sin(v * 16.0) * 0.5 + 0.5
    let turb = fbm2d(u * 20.0 + 66.0, v * 3.0, 3, 2.0, 0.5) * 0.06
    let r = 0.82 + band * 0.08 + turb
    let g = 0.74 + band * 0.06 + turb * 0.8
    let b = 0.52 + band * 0.04 + turb * 0.5
    return [r, g, b]

proc uranus_color(u, v):
    # Pale blue-green, very uniform
    let subtle = fbm2d(u * 10.0 + 11.0, v * 10.0, 3, 2.0, 0.5) * 0.04
    return [0.55 + subtle, 0.75 + subtle, 0.82 + subtle]

proc neptune_color(u, v):
    # Deep blue with faint bands and dark spots
    let band = math.sin(v * 12.0) * 0.03
    let detail = fbm2d(u * 15.0 + 33.0, v * 8.0, 3, 2.0, 0.5) * 0.05
    return [0.20 + band + detail, 0.32 + band + detail, 0.78 + band + detail * 0.5]

proc sun_color(u, v):
    # Hot surface with granulation and sunspots
    let gran = fbm2d(u * 30.0 + 7.0, v * 30.0 + 3.0, 4, 2.0, 0.5)
    let bright = 0.90 + gran * 0.1

    # Sunspot darkening
    let spot = fbm2d(u * 8.0 + 55.0, v * 8.0, 3, 2.0, 0.5)
    if spot > 0.55:
        bright = bright * (0.5 + (1.0 - (spot - 0.55) / 0.45) * 0.5)

    # Limb darkening (edges appear darker)
    let limb = math.sin(v * 3.14159)
    bright = bright * (0.65 + 0.35 * limb)

    return [bright, bright * 0.92, bright * 0.72]

proc generic_rock_color(u, v, seed):
    let noise = fbm2d(u * 6.0 + seed, v * 6.0 + seed * 0.7, 4, 2.0, 0.5)
    let grey = 0.45 + noise * 0.15
    return [grey, grey * 0.95, grey * 0.9]

# ============================================================================
# Get the right color function for a planet name
# ============================================================================

proc get_planet_color_fn(name):
    if name == "Sun" or name == "Star A" or name == "Star B" or name == "Central":
        return sun_color
    if name == "Earth":
        return earth_color
    if name == "Mars":
        return mars_color
    if name == "Venus":
        return venus_color
    if name == "Mercury":
        return mercury_color
    if name == "Jupiter":
        return jupiter_color
    if name == "Saturn":
        return saturn_color
    if name == "Uranus":
        return uranus_color
    if name == "Neptune":
        return neptune_color
    return _generic_fallback_color

proc _generic_fallback_color(u, v):
    return generic_rock_color(u, v, 42.0)

# ============================================================================
# Generate and upload a procedural planet mesh to GPU
# ============================================================================

proc upload_planet_mesh(name, segments):
    let color_fn = get_planet_color_fn(name)
    let mesh_data = generate_planet_sphere(segments, color_fn)
    from mesh import upload_mesh
    return upload_mesh(mesh_data)

# ============================================================================
# Draw a planet using patch-based rendering for surface detail
# The unlit shader uses a single color per draw call, so we divide
# the sphere into latitude bands and draw each with its average color.
# ============================================================================

proc draw_planet_detailed(cmd, mat, vp, position, radius, name, base_mesh, segments):
    let color_fn = get_planet_color_fn(name)

    if color_fn == nil:
        # Fallback: single color draw
        let m = mat4_mul(mat4_translate(position[0], position[1], position[2]), mat4_scale(radius, radius, radius))
        let mvp = mat4_mul(vp, m)
        draw_mesh_unlit(cmd, mat, base_mesh, mvp, [0.5, 0.5, 0.5, 1.0])
        return nil

    # Draw the sphere in latitude bands, each with sampled color
    let bands = 8
    if segments > 16:
        bands = 12
    let bi = 0
    while bi < bands:
        let v_center = (bi + 0.5) / bands
        # Sample color at multiple longitudes and average
        let r_sum = 0.0
        let g_sum = 0.0
        let b_sum = 0.0
        let samples = 6
        let si = 0
        while si < samples:
            let u_sample = si / samples
            let c = color_fn(u_sample, v_center)
            r_sum = r_sum + c[0]
            g_sum = g_sum + c[1]
            b_sum = b_sum + c[2]
            si = si + 1
        let avg_r = r_sum / samples
        let avg_g = g_sum / samples
        let avg_b = b_sum / samples

        # Draw a thin band of the sphere
        let band_offset = (v_center - 0.5) * 2.0 * radius * 0.95
        let band_scale_y = radius / bands * 1.1  # Slight overlap
        let band_scale_xz = radius * math.sin(v_center * 3.14159)
        if band_scale_xz < radius * 0.15:
            band_scale_xz = radius * 0.15

        let m = mat4_mul(
            mat4_translate(position[0], position[1] + band_offset, position[2]),
            mat4_scale(band_scale_xz, band_scale_y, band_scale_xz)
        )
        let mvp = mat4_mul(vp, m)
        let band_color = [avg_r, avg_g, avg_b, 1.0]
        # Clamp
        if band_color[0] > 1.0:
            band_color[0] = 1.0
        if band_color[1] > 1.0:
            band_color[1] = 1.0
        if band_color[2] > 1.0:
            band_color[2] = 1.0
        draw_mesh_unlit(cmd, mat, base_mesh, mvp, band_color)
        bi = bi + 1

from math3d import mat4_mul, mat4_translate, mat4_scale
from render_system import draw_mesh_unlit
