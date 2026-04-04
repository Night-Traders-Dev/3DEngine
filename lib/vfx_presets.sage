gc_disable()
# -----------------------------------------
# vfx_presets.sage - Pre-built particle effect presets
# Fire, smoke, sparks, explosion, rain, dust, magic
# -----------------------------------------

from particles import create_emitter, emitter_point, emitter_sphere, emitter_box, emitter_cone
from math3d import vec3

# ============================================================================
# Fire
# ============================================================================
proc vfx_fire(position, intensity):
    let e = create_emitter(200)
    e["position"] = position
    e["shape"] = emitter_cone(0.3, 0.3)
    e["rate"] = 40.0 * intensity
    e["life_min"] = 0.3
    e["life_max"] = 0.8
    e["speed_min"] = 1.5
    e["speed_max"] = 3.5
    e["direction"] = vec3(0.0, 1.0, 0.0)
    e["spread"] = 0.2
    e["gravity"] = vec3(0.0, 1.0, 0.0)
    e["drag"] = 0.05
    e["size_start"] = 0.3 * intensity
    e["size_end"] = 0.05
    e["color_start"] = [1.0, 0.7, 0.1, 1.0]
    e["color_end"] = [1.0, 0.1, 0.0, 0.0]
    return e

# ============================================================================
# Smoke
# ============================================================================
proc vfx_smoke(position, density):
    let e = create_emitter(150)
    e["position"] = position
    e["shape"] = emitter_sphere(0.2)
    e["rate"] = 15.0 * density
    e["life_min"] = 1.5
    e["life_max"] = 3.0
    e["speed_min"] = 0.5
    e["speed_max"] = 1.5
    e["direction"] = vec3(0.0, 1.0, 0.0)
    e["spread"] = 0.4
    e["gravity"] = vec3(0.0, 0.3, 0.0)
    e["drag"] = 0.02
    e["size_start"] = 0.2
    e["size_end"] = 1.0
    e["color_start"] = [0.4, 0.4, 0.4, 0.5]
    e["color_end"] = [0.6, 0.6, 0.6, 0.0]
    e["angular_vel_min"] = -1.0
    e["angular_vel_max"] = 1.0
    return e

# ============================================================================
# Sparks
# ============================================================================
proc vfx_sparks(position, count):
    let e = create_emitter(count)
    e["position"] = position
    e["shape"] = emitter_point()
    e["burst"] = count
    e["one_shot"] = true
    e["life_min"] = 0.3
    e["life_max"] = 1.0
    e["speed_min"] = 3.0
    e["speed_max"] = 8.0
    e["direction"] = vec3(0.0, 1.0, 0.0)
    e["spread"] = 1.0
    e["gravity"] = vec3(0.0, -9.0, 0.0)
    e["drag"] = 0.01
    e["size_start"] = 0.08
    e["size_end"] = 0.02
    e["color_start"] = [1.0, 0.9, 0.3, 1.0]
    e["color_end"] = [1.0, 0.3, 0.0, 0.0]
    return e

# ============================================================================
# Explosion
# ============================================================================
proc vfx_explosion(position, size):
    let e = create_emitter(300)
    e["position"] = position
    e["shape"] = emitter_sphere(0.1)
    e["burst"] = 200
    e["one_shot"] = true
    e["life_min"] = 0.5
    e["life_max"] = 1.5
    e["speed_min"] = 5.0 * size
    e["speed_max"] = 12.0 * size
    e["direction"] = vec3(0.0, 0.5, 0.0)
    e["spread"] = 1.0
    e["gravity"] = vec3(0.0, -4.0, 0.0)
    e["drag"] = 0.03
    e["size_start"] = 0.4 * size
    e["size_end"] = 0.1
    e["color_start"] = [1.0, 0.8, 0.2, 1.0]
    e["color_end"] = [0.3, 0.1, 0.0, 0.0]
    return e

# ============================================================================
# Rain
# ============================================================================
proc vfx_rain(area_size, intensity):
    let e = create_emitter(500)
    e["position"] = vec3(0.0, 20.0, 0.0)
    e["shape"] = emitter_box(area_size / 2.0, 0.0, area_size / 2.0)
    e["rate"] = 100.0 * intensity
    e["life_min"] = 1.0
    e["life_max"] = 2.0
    e["speed_min"] = 8.0
    e["speed_max"] = 12.0
    e["direction"] = vec3(0.0, -1.0, 0.0)
    e["spread"] = 0.05
    e["gravity"] = vec3(0.0, -5.0, 0.0)
    e["drag"] = 0.0
    e["size_start"] = 0.02
    e["size_end"] = 0.02
    e["color_start"] = [0.6, 0.7, 0.9, 0.6]
    e["color_end"] = [0.6, 0.7, 0.9, 0.2]
    return e

# ============================================================================
# Dust
# ============================================================================
proc vfx_dust(position):
    let e = create_emitter(80)
    e["position"] = position
    e["shape"] = emitter_sphere(0.5)
    e["rate"] = 8.0
    e["life_min"] = 2.0
    e["life_max"] = 4.0
    e["speed_min"] = 0.2
    e["speed_max"] = 0.8
    e["direction"] = vec3(0.3, 0.5, 0.1)
    e["spread"] = 0.8
    e["gravity"] = vec3(0.0, 0.1, 0.0)
    e["drag"] = 0.02
    e["size_start"] = 0.1
    e["size_end"] = 0.3
    e["color_start"] = [0.7, 0.65, 0.5, 0.3]
    e["color_end"] = [0.7, 0.65, 0.5, 0.0]
    e["angular_vel_min"] = -0.5
    e["angular_vel_max"] = 0.5
    return e

# ============================================================================
# Magic / heal
# ============================================================================
proc vfx_magic(position, color_r, color_g, color_b):
    let e = create_emitter(100)
    e["position"] = position
    e["shape"] = emitter_sphere(0.5)
    e["rate"] = 25.0
    e["life_min"] = 0.5
    e["life_max"] = 1.2
    e["speed_min"] = 0.5
    e["speed_max"] = 2.0
    e["direction"] = vec3(0.0, 1.0, 0.0)
    e["spread"] = 0.6
    e["gravity"] = vec3(0.0, 0.5, 0.0)
    e["drag"] = 0.03
    e["size_start"] = 0.15
    e["size_end"] = 0.0
    e["color_start"] = [color_r, color_g, color_b, 1.0]
    e["color_end"] = [color_r, color_g, color_b, 0.0]
    return e
