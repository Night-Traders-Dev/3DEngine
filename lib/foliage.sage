gc_disable()
# -----------------------------------------
# foliage.sage - Foliage scattering for Sage Engine
# Places objects (trees, rocks, grass) on terrain via rules
# -----------------------------------------

import math
from math3d import vec3

# ============================================================================
# Scatter rule
# ============================================================================
proc create_scatter_rule(name, density, min_height, max_height, min_slope, max_slope):
    let sr = {}
    sr["name"] = name
    sr["density"] = density
    sr["min_height"] = min_height
    sr["max_height"] = max_height
    sr["min_slope"] = min_slope
    sr["max_slope"] = max_slope
    sr["scale_min"] = 0.8
    sr["scale_max"] = 1.2
    sr["rotation_random"] = true
    sr["mesh_name"] = ""
    sr["align_to_normal"] = false
    return sr

# ============================================================================
# Hash-based deterministic scatter (no random() needed)
# ============================================================================
proc _scatter_hash(x, z, seed):
    let n = x * 374761393 + z * 668265263 + seed * 1103515245
    n = (n ^ (n >> 13)) * 1274126177
    n = n ^ (n >> 16)
    if n < 0:
        n = 0 - n
    return (n - math.floor(n / 10000000) * 10000000) / 10000000.0

# ============================================================================
# Generate foliage instances from terrain + rules
# Returns array of {position, scale, rotation, rule_name}
# ============================================================================
proc scatter_foliage(terrain, rules, seed):
    let instances = []
    let ri = 0
    while ri < len(rules):
        let rule = rules[ri]
        let spacing = 1.0 / math.sqrt(rule["density"])
        let ox = terrain["origin_x"]
        let oz = terrain["origin_z"]
        let sx = terrain["size_x"]
        let sz = terrain["size_z"]
        let step = spacing
        let wx = ox + step * 0.5
        while wx < ox + sx:
            let wz = oz + step * 0.5
            while wz < oz + sz:
                # Hash to decide if this cell gets an instance
                let h = _scatter_hash(math.floor(wx * 100), math.floor(wz * 100), seed + ri)
                if h < rule["density"] * step * step:
                    # Jitter position
                    let jx = (_scatter_hash(math.floor(wx * 50 + 1), math.floor(wz * 50), seed) - 0.5) * step
                    let jz = (_scatter_hash(math.floor(wx * 50), math.floor(wz * 50 + 1), seed) - 0.5) * step
                    let px = wx + jx
                    let pz = wz + jz
                    # Sample terrain height
                    from terrain import sample_height, terrain_normal
                    let py = sample_height(terrain, px, pz)
                    # Height filter
                    if py >= rule["min_height"] and py <= rule["max_height"]:
                        # Slope filter (using normal.y as slope measure)
                        let gx = math.floor((px - ox) / terrain["cell_x"])
                        let gz = math.floor((pz - oz) / terrain["cell_z"])
                        let n = terrain_normal(terrain, gx, gz)
                        let slope = 1.0 - n[1]
                        if slope >= rule["min_slope"] and slope <= rule["max_slope"]:
                            let inst = {}
                            inst["position"] = vec3(px, py, pz)
                            let sh = _scatter_hash(math.floor(px * 77), math.floor(pz * 77), seed + 42)
                            let s = rule["scale_min"] + sh * (rule["scale_max"] - rule["scale_min"])
                            inst["scale"] = vec3(s, s, s)
                            let rot_y = 0.0
                            if rule["rotation_random"]:
                                rot_y = _scatter_hash(math.floor(px * 33), math.floor(pz * 33), seed + 99) * 6.28
                            inst["rotation"] = vec3(0.0, rot_y, 0.0)
                            inst["rule_name"] = rule["name"]
                            push(instances, inst)
                wz = wz + step
            wx = wx + step
        ri = ri + 1
    return instances

# ============================================================================
# Foliage instance count
# ============================================================================
proc foliage_count(instances):
    return len(instances)

proc foliage_count_by_rule(instances, rule_name):
    let count = 0
    let i = 0
    while i < len(instances):
        if instances[i]["rule_name"] == rule_name:
            count = count + 1
        i = i + 1
    return count
