import math
from voxel_gameplay import create_voxel_gameplay_state, ensure_voxel_mob_population
from math3d import vec3
print("Gameplay import successful")
let gameplay = create_voxel_gameplay_state()
print("Gameplay created:", gameplay != nil)
let pos = vec3(32.0, 30.0, 32.0)
ensure_voxel_mob_population(gameplay, pos, 64)
print("Mob population ensured")