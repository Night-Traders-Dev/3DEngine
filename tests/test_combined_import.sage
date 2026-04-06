import gpu
import math
from math3d import vec3
from renderer import create_renderer
from input import create_input, default_fps_bindings
from player_controller import create_player_controller
from voxel_world import create_voxel_world
from voxel_gameplay import create_voxel_gameplay_state
from voxel_fluids import create_fluid_system
from voxel_biomes import default_biomes
from voxel_weather import create_weather_system
print("All imports successful")
let r = create_renderer(800, 600, "Test")
print("Renderer created")
let inp = create_input()
default_fps_bindings(inp)
print("Input created")
let player = create_player_controller()
print("Player created")
let world = create_voxel_world(64, 48, 64)
print("World created")