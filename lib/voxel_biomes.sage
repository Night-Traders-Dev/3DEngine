# voxel_biomes.sage - Biome system with terrain variation
# Creates distinct biomes with different block distributions and generation parameters

import math
from math3d import vec3

# =====================================================
# Biome Definitions
# =====================================================

proc create_biome(name, temperate, precipitation, grass_color, foliage_color):
    let biome = {}
    biome["name"] = name
    biome["temperate"] = temperate
    biome["precipitation"] = precipitation
    biome["grass_color"] = grass_color
    biome["foliage_color"] = foliage_color
    biome["top_block"] = 1  # Default grass
    biome["bottom_block"] = 2  # Default dirt
    biome["secondary_block"] = 3  # Default stone
    biome["ore_density"] = 1.0
    biome["tree_density"] = 0.5
    biome["water_level"] = 32
    biome["max_elevation"] = 64
    return biome

proc default_biomes():
    let biomes = []
    
    # Plains - temperate, dry
    let plains = create_biome("Plains", 0.8, 0.4, vec3(0.34, 0.76, 0.22), vec3(0.34, 0.70, 0.28))
    plains["tree_density"] = 0.1
    plains["max_elevation"] = 48
    push(biomes, plains)
    
    # Forest - temperate, wet
    let forest = create_biome("Forest", 0.7, 0.8, vec3(0.20, 0.60, 0.15), vec3(0.20, 0.58, 0.15))
    forest["tree_density"] = 0.8
    forest["max_elevation"] = 56
    push(biomes, forest)
    
    # Desert - hot, very dry
    let desert = create_biome("Desert", 2.0, 0.0, vec3(0.92, 0.88, 0.70), vec3(0.88, 0.80, 0.55))
    desert["top_block"] = 12  # Sand
    desert["bottom_block"] = 12
    desert["tree_density"] = 0.02
    desert["water_level"] = 28
    desert["max_elevation"] = 52
    push(biomes, desert)
    
    # Mountains - cold, wet
    let mountains = create_biome("Mountains", 0.2, 0.9, vec3(0.40, 0.65, 0.25), vec3(0.35, 0.60, 0.25))
    mountains["tree_density"] = 0.3
    mountains["max_elevation"] = 96
    mountains["ore_density"] = 1.5
    push(biomes, mountains)
    
    # Swamp - temperate, very wet
    let swamp = create_biome("Swamp", 0.8, 1.0, vec3(0.33, 0.60, 0.28), vec3(0.30, 0.55, 0.25))
    swamp["tree_density"] = 0.4
    swamp["water_level"] = 48
    swamp["max_elevation"] = 40
    push(biomes, swamp)
    
    return biomes

# =====================================================
# Biome Sampling and Selection
# =====================================================

proc select_biome_at(biome_list, world_x, world_z, seed):
    # Use smooth Perlin-like noise to select biome
    let noise_val = _biome_noise(world_x * 0.05, world_z * 0.05, seed)
    let idx = int(math.abs(noise_val) * len(biome_list)) % len(biome_list)
    return biome_list[idx]

proc _biome_noise(x, y, seed):
    # Pseudo-random biome selection
    let val1 = math.sin(x * 12.9898 + y * 78.233 + seed) * 43758.5453
    let val2 = val1 - math.floor(val1)
    let val3 = math.sin(val2 * 10.0) * 10000.0
    return val3 - math.floor(val3)

proc get_biome_surface_block(biome):
    return biome["top_block"]

proc get_biome_subsurface_block(biome):
    return biome["bottom_block"]

proc get_biome_stone_block(biome):
    return biome["secondary_block"]

# =====================================================
# Biome-Based Generation Modifiers
# =====================================================

proc biome_ore_modifier(biome):
    return biome["ore_density"]

proc biome_tree_density(biome):
    return biome["tree_density"]

proc biome_elevation_scale(biome):
    return biome["max_elevation"] / 64.0

proc biome_water_level(biome):
    return biome["water_level"]

proc apply_biome_colors(biome, base_color):
    # Biome affects grass/foliage coloring
    let mix_amount = 0.3
    return vec3(
        base_color[0] * (1.0 - mix_amount) + biome["grass_color"][0] * mix_amount,
        base_color[1] * (1.0 - mix_amount) + biome["grass_color"][1] * mix_amount,
        base_color[2] * (1.0 - mix_amount) + biome["grass_color"][2] * mix_amount
    )

# =====================================================
# Biome-Aware Cave Generation
# =====================================================

proc biome_cave_frequency(biome, temperature_altitude):
    # Cold mountains get more caves
    if temperature_altitude < 0.2:
        return 2.0  # Doubled frequency
    if biome["name"] == "Swamp":
        return 0.5  # Fewer caves in swamps
    return 1.0

proc biome_cave_size_modifier(biome):
    # Desert caves tend to be smaller
    if biome["name"] == "Desert":
        return 0.7
    # Mountain caves are larger
    if biome["name"] == "Mountains":
        return 1.4
    return 1.0

# =====================================================
# Biome Structure Generation
# =====================================================

proc should_spawn_tree_in_biome(biome, local_noise):
    let density = biome["tree_density"]
    return local_noise < density

proc biome_vegetation_height(biome):
    # Tree/vegetation height by biome
    if biome["name"] == "Mountains":
        return 8
    if biome["name"] == "Desert":
        return 2
    if biome["name"] == "Forest":
        return 10
    return 6

proc biome_unique_features(biome):
    # Biome-specific blocks and structures
    let features = {}
    
    if biome["name"] == "Desert":
        features["special_block"] = 0  # Sand
        features["structure"] = "temples"
    elif biome["name"] == "Mountains":
        features["special_block"] = 0  # Stone variations
        features["structure"] = "caves"
    elif biome["name"] == "Swamp":
        features["special_block"] = 14  # Water
        features["structure"] = "lily_pads"
    
    return features
