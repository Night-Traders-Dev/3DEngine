# voxel_weather.sage - Advanced weather system with dynamic effects
# Rain, thunderstorms, wind effects, and visibility changes

import math
from math3d import vec3

# =====================================================
# Weather System
# =====================================================

proc create_weather_system():
    let ws = {}
    ws["current_weather"] = "clear"
    ws["weather_time"] = 0.0
    ws["weather_duration"] = 0.0
    ws["transition_time"] = 0.0
    ws["next_weather"] = "clear"
    ws["wind_direction"] = vec3(1.0, 0.0, 0.0)
    ws["wind_strength"] = 0.0
    ws["wind_change_rate"] = 0.0
    ws["rain_intensity"] = 0.0
    ws["thunder_queue"] = []
    ws["last_lightning"] = 0.0
    return ws

proc weather_types():
    return ["clear", "rain", "thunderstorm", "snow"]

# =====================================================
# Weather Transitions
# =====================================================

proc select_next_weather(current_weather):
    let rand = math.random()
    
    if current_weather == "clear":
        if rand < 0.2:
            return "rain"
        if rand < 0.25:
            return "thunderstorm"
        return "clear"
    
    if current_weather == "rain":
        if rand < 0.3:
            return "clear"
        if rand < 0.15:
            return "thunderstorm"
        return "rain"
    
    if current_weather == "thunderstorm":
        if rand < 0.4:
            return "rain"
        if rand < 0.1:
            return "clear"
        return "thunderstorm"
    
    if current_weather == "snow":
        if rand < 0.3:
            return "clear"
        return "snow"
    
    return "clear"

proc update_weather_system(ws, dt):
    ws["weather_time"] = ws["weather_time"] + dt
    ws["transition_time"] = ws["transition_time"] - dt
    
    # Handle transitions
    if ws["transition_time"] <= 0.0:
        ws["current_weather"] = ws["next_weather"]
        ws["next_weather"] = select_next_weather(ws["current_weather"])
        ws["weather_duration"] = 120.0 + math.random() * 480.0  # 2-10 minutes
        ws["transition_time"] = ws["weather_duration"]
        ws["weather_time"] = 0.0
    
    # Update weather-specific effects
    if ws["current_weather"] == "clear":
        ws["rain_intensity"] = math.max(0.0, ws["rain_intensity"] - dt * 0.5)
        ws["wind_strength"] = math.max(0.0, ws["wind_strength"] - dt * 0.1)
    
    elif ws["current_weather"] == "rain":
        ws["rain_intensity"] = math.min(0.8, ws["rain_intensity"] + dt * 0.3)
        ws["wind_strength"] = 0.3 + math.sin(ws["weather_time"] * 0.5) * 0.2
    
    elif ws["current_weather"] == "thunderstorm":
        ws["rain_intensity"] = math.min(1.0, ws["rain_intensity"] + dt * 0.5)
        ws["wind_strength"] = 0.6 + math.sin(ws["weather_time"] * 1.5) * 0.4
        
        # Thunder strikes
        if math.random() < dt * 0.02:  # 2% chance per second
            push(ws["thunder_queue"], {"delay": 0.5 + math.random() * 1.0})
        
        ws["last_lightning"] = ws["last_lightning"] - dt
    
    # Update wind
    ws["wind_change_rate"] = ws["wind_change_rate"] - dt * 0.1
    if ws["wind_change_rate"] <= 0.0:
        let angle = math.random() * 6.28  # 2π
        ws["wind_direction"] = vec3(math.cos(angle), 0.0, math.sin(angle))
        ws["wind_change_rate"] = 5.0 + math.random() * 15.0

# =====================================================
# Weather Effects
# =====================================================

proc get_weather_fog_modifier(ws):
    # Reduce visibility in bad weather
    if ws["current_weather"] == "clear":
        return 1.0
    if ws["current_weather"] == "rain":
        return 0.8
    if ws["current_weather"] == "thunderstorm":
        return 0.6
    return 0.9

proc get_weather_light_modifier(ws):
    # Darken sky in storms
    if ws["current_weather"] == "clear":
        return 1.0
    if ws["current_weather"] == "rain":
        return 0.85
    if ws["current_weather"] == "thunderstorm":
        return 0.6
    return 0.95

proc get_weather_ambient_color(ws):
    # Shift ambient color based on weather
    if ws["current_weather"] == "clear":
        return vec3(0.10, 0.13, 0.18)  # Normal
    if ws["current_weather"] == "rain":
        return vec3(0.08, 0.10, 0.14)  # Slightly darker, cooler
    if ws["current_weather"] == "thunderstorm":
        return vec3(0.05, 0.06, 0.10)  # Very dark, very cool
    return vec3(0.10, 0.13, 0.18)

proc apply_rain_to_particle_system(particles, intensity, wind):
    if particles == nil or intensity <= 0.0:
        return
    # Rain particle effects would be added here
    return

proc apply_wind_force(entity, wind_direction, wind_strength, dt):
    if entity == nil or not dict_has(entity, "velocity"):
        return
    let wind_force = vec3(wind_direction[0] * wind_strength * 0.5,
                          0.0,  # Wind doesn't push up
                          wind_direction[2] * wind_strength * 0.5)
    entity["velocity"] = vec3(entity["velocity"][0] + wind_force[0] * dt,
                               entity["velocity"][1],
                               entity["velocity"][2] + wind_force[2] * dt)

# =====================================================
# Weather State
# =====================================================

proc weather_to_sage(ws):
    let data = {}
    data["current_weather"] = ws["current_weather"]
    data["weather_time"] = ws["weather_time"]
    return data

proc weather_from_sage(data):
    let ws = create_weather_system()
    if dict_has(data, "current_weather"):
        ws["current_weather"] = data["current_weather"]
    if dict_has(data, "weather_time"):
        ws["weather_time"] = data["weather_time"]
    return ws
