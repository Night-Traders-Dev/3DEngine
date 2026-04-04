import gpu
import math
from math3d import vec3
from voxel_weather import create_weather_system, update_weather_system, get_weather_light_modifier

let weather = create_weather_system()
print "Weather created"

update_weather_system(weather, 0.016)
print "Weather updated"

let weather_mod = get_weather_light_modifier(weather)
print "Weather mod: " + str(weather_mod)
print "Weather mod type: " + type(weather_mod)

let r = 0.52 * weather_mod
print "Multiplied: " + str(r)