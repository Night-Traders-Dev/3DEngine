# Ore and Cave Generation Enhancement
# Append to voxel_world.sage for Minecraft-like world generation

from voxel_world import voxel_in_bounds, get_voxel, set_voxel

# =====================================================
# Ore & Cave Generation
# =====================================================

proc _simple_noise_2d(x, y, seed):
    let n = math.sin(x * 12.9898 + y * 78.233 + seed) * 43758.5453
    return n - math.floor(n)

proc _simple_noise_3d(x, y, z, seed):
    let n = math.sin(x * 12.9898 + y * 78.233 + z * 45.164 + seed) * 43758.5453
    return n - math.floor(n)

proc _generate_ore_vein(vw, center_x, center_y, center_z, ore_block, vein_size, seed):
    let i = 0
    while i < vein_size:
        let offset_x = int(_simple_noise_3d(center_x + i, center_y, center_z, seed) * 4.0 - 2.0)
        let offset_y = int(_simple_noise_3d(center_x, center_y + i, center_z, seed) * 4.0 - 2.0)
        let offset_z = int(_simple_noise_3d(center_x, center_y, center_z + i, seed) * 4.0 - 2.0)
        let x = center_x + offset_x
        let y = center_y + offset_y
        let z = center_z + offset_z
        if voxel_in_bounds(vw, x, y, z) and get_voxel(vw, x, y, z) == 3:
            set_voxel(vw, x, y, z, ore_block)
        i = i + 1

proc _generate_ore_deposits(vw, seed):
    let coal_deposits = 20
    let i = 0
    while i < coal_deposits:
        let x = int(_simple_noise_2d(i, 0.0, seed) * vw["size_x"])
        let y = int(_simple_noise_2d(i, 1.0, seed) * vw["size_y"] * 0.8)
        let z = int(_simple_noise_2d(i, 2.0, seed) * vw["size_z"])
        _generate_ore_vein(vw, x, y, z, 7, 12, seed)
        i = i + 1
    
    let iron_deposits = 12
    let j = 0
    while j < iron_deposits:
        let x = int(_simple_noise_2d(100 + j, 0.0, seed) * vw["size_x"])
        let y = int(_simple_noise_2d(100 + j, 1.0, seed) * vw["size_y"] * 0.6)
        let z = int(_simple_noise_2d(100 + j, 2.0, seed) * vw["size_z"])
        _generate_ore_vein(vw, x, y, z, 8, 8, seed)
        j = j + 1
    
    let gold_deposits = 6
    let k = 0
    while k < gold_deposits:
        let x = int(_simple_noise_2d(200 + k, 0.0, seed) * vw["size_x"])
        let y = int(_simple_noise_2d(200 + k, 1.0, seed) * vw["size_y"] * 0.4)
        let z = int(_simple_noise_2d(200 + k, 2.0, seed) * vw["size_z"])
        _generate_ore_vein(vw, x, y, z, 9, 6, seed)
        k = k + 1
    
    let diamond_deposits = 3
    let m = 0
    while m < diamond_deposits:
        let x = int(_simple_noise_2d(300 + m, 0.0, seed) * vw["size_x"])
        let y = int(_simple_noise_2d(300 + m, 1.0, seed) * vw["size_y"] * 0.2)
        let z = int(_simple_noise_2d(300 + m, 2.0, seed) * vw["size_z"])
        _generate_ore_vein(vw, x, y, z, 10, 4, seed)
        m = m + 1

proc _generate_cave_tunnel(vw, start_x, start_y, start_z, length, seed):
    let x = start_x
    let y = start_y
    let z = start_z
    let i = 0
    while i < length:
        let radius = 2
        let cx = x - radius
        while cx <= x + radius:
            let cy = y - radius
            while cy <= y + radius:
                let cz = z - radius
                while cz <= z + radius:
                    if voxel_in_bounds(vw, cx, cy, cz):
                        let dist = (cx - x) * (cx - x) + (cy - y) * (cy - y) + (cz - z) * (cz - z)
                        if dist <= radius * radius:
                            let current = get_voxel(vw, cx, cy, cz)
                            if current == 3 or current == 2 or current == 11:
                                set_voxel(vw, cx, cy, cz, 0)
                    cz = cz + 1
                cy = cy + 1
            cx = cx + 1
        
        let angle = _simple_noise_3d(x, y, z, seed + i) * 2.0 * 3.14159265358979323846
        let pitch = (_simple_noise_3d(x + 100, y + 100, z + 100, seed + i) - 0.5) * 0.5
        x = x + int(math.cos(angle) * 3.0)
        z = z + int(math.sin(angle) * 3.0)
        y = y + int(math.sin(pitch) * 2.0)
        
        i = i + 1
        
        if y < 5 or y > vw["size_y"] - 5:
            i = length

proc _generate_caves(vw, seed):
    let cave_count = 8
    let i = 0
    while i < cave_count:
        let start_x = int(_simple_noise_2d(400 + i, 0.0, seed) * vw["size_x"])
        let start_y = int(_simple_noise_2d(400 + i, 1.0, seed) * vw["size_y"] * 0.6)
        let start_z = int(_simple_noise_2d(400 + i, 2.0, seed) * vw["size_z"])
        let length = int(40 + _simple_noise_2d(450 + i, 3.0, seed) * 30.0)
        _generate_cave_tunnel(vw, start_x, start_y, start_z, length, seed)
        i = i + 1

proc enhance_voxel_world_with_features(vw, seed):
    _generate_ore_deposits(vw, seed)
    _generate_caves(vw, seed)
