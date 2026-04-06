gc_disable()
# vehicle.sage — Vehicle Physics System
# Supports: wheeled vehicles, suspension, steering, acceleration,
# braking, drift, chase camera, speedometer HUD
#
# Usage:
#   let car = create_vehicle(vec3(0, 1, 0), 1200.0)
#   add_wheel(car, vec3(-0.8, -0.3, 1.2), 0.3)  # FL
#   add_wheel(car, vec3(0.8, -0.3, 1.2), 0.3)    # FR
#   add_wheel(car, vec3(-0.8, -0.3, -1.2), 0.3)  # RL
#   add_wheel(car, vec3(0.8, -0.3, -1.2), 0.3)   # RR
#   update_vehicle(car, throttle, brake, steer, dt)

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot

# ============================================================================
# Vehicle Creation
# ============================================================================

proc create_vehicle(position, mass):
    return {
        "position": position,
        "velocity": vec3(0.0, 0.0, 0.0),
        "rotation": 0.0,             # Yaw angle (radians)
        "angular_velocity": 0.0,
        "mass": mass,
        "wheels": [],
        "speed": 0.0,               # Current speed (m/s)
        "rpm": 0.0,
        "gear": 1,
        "max_speed": 50.0,          # m/s (~180 km/h)
        "engine_power": 8000.0,     # Newtons
        "brake_force": 12000.0,
        "drag": 0.4,
        "rolling_resistance": 0.02,
        "steering_angle": 0.0,
        "max_steering": 0.6,        # ~35 degrees
        "steering_speed": 2.5,      # How fast steering responds
        "wheelbase": 2.4,           # Distance between front and rear axle
        "grounded": true,
        "drift_factor": 0.0,
        "handbrake": false,
        # Suspension
        "suspension_stiffness": 15000.0,
        "suspension_damping": 1500.0,
        "suspension_travel": 0.15,
        # State
        "throttle": 0.0,
        "brake": 0.0,
        "steer_input": 0.0
    }

proc add_wheel(car, local_offset, radius):
    let wheel = {
        "offset": local_offset,
        "radius": radius,
        "compression": 0.0,     # Suspension compression [0..travel]
        "spin_angle": 0.0,      # Visual wheel rotation
        "grounded": true,
        "slip": 0.0             # Lateral slip for drift
    }
    push(car["wheels"], wheel)
    return wheel

# ============================================================================
# Vehicle Update — simplified Pacejka-inspired tire model
# ============================================================================

proc update_vehicle(car, throttle, brake, steer_input, dt):
    car["throttle"] = throttle
    car["brake"] = brake
    car["steer_input"] = steer_input

    # Steering
    let target_steer = steer_input * car["max_steering"]
    let steer_diff = target_steer - car["steering_angle"]
    let steer_step = car["steering_speed"] * dt
    if steer_diff > steer_step:
        car["steering_angle"] = car["steering_angle"] + steer_step
    elif steer_diff < 0 - steer_step:
        car["steering_angle"] = car["steering_angle"] - steer_step
    else:
        car["steering_angle"] = target_steer

    # Forward direction
    let fwd_x = math.sin(car["rotation"])
    let fwd_z = math.cos(car["rotation"])
    let forward = vec3(fwd_x, 0.0, fwd_z)

    # Speed along forward axis
    car["speed"] = v3_dot(car["velocity"], forward)

    # Engine force
    let engine_force = 0.0
    if throttle > 0.0:
        engine_force = car["engine_power"] * throttle
        # Speed limiter
        let speed_ratio = car["speed"] / car["max_speed"]
        if speed_ratio > 0.95:
            engine_force = engine_force * (1.0 - speed_ratio) * 20.0
    elif throttle < 0.0:
        engine_force = car["engine_power"] * throttle * 0.5  # Reverse is slower

    # Braking force
    let brake_f = 0.0
    if brake > 0.0:
        brake_f = car["brake_force"] * brake
        if car["speed"] > 0.1:
            brake_f = 0.0 - brake_f
        elif car["speed"] < -0.1:
            brake_f = brake_f
        else:
            brake_f = 0.0
            car["velocity"] = vec3(0.0, car["velocity"][1], 0.0)

    # Drag and rolling resistance
    let drag = 0.0 - car["drag"] * car["speed"] * car["speed"]
    if car["speed"] < 0:
        drag = 0.0 - drag
    let rolling = 0.0 - car["rolling_resistance"] * car["speed"]

    # Total longitudinal force
    let total_force = engine_force + brake_f + drag + rolling

    # Acceleration
    let accel = total_force / car["mass"]
    car["speed"] = car["speed"] + accel * dt

    # Turning (Ackermann-like steering)
    if car["speed"] > 0.5 or car["speed"] < -0.5:
        let turn_radius = car["wheelbase"] / math.sin(car["steering_angle"] + 0.001)
        car["angular_velocity"] = car["speed"] / turn_radius
    else:
        car["angular_velocity"] = 0.0

    car["rotation"] = car["rotation"] + car["angular_velocity"] * dt

    # Update velocity vector
    let new_fwd_x = math.sin(car["rotation"])
    let new_fwd_z = math.cos(car["rotation"])
    car["velocity"] = vec3(new_fwd_x * car["speed"], car["velocity"][1], new_fwd_z * car["speed"])

    # Gravity
    if not car["grounded"]:
        car["velocity"] = v3_add(car["velocity"], vec3(0.0, -9.81 * dt, 0.0))

    # Update position
    car["position"] = v3_add(car["position"], v3_scale(car["velocity"], dt))

    # Ground collision (simple flat ground at y=0)
    if car["position"][1] < 0.5:
        car["position"][1] = 0.5
        car["velocity"][1] = 0.0
        car["grounded"] = true
    else:
        car["grounded"] = false

    # RPM approximation
    car["rpm"] = car["speed"] * 60.0 / (2.0 * math.PI * 0.3)
    if car["rpm"] < 800:
        car["rpm"] = 800

    # Update wheel spin
    let wi = 0
    while wi < len(car["wheels"]):
        let wheel = car["wheels"][wi]
        wheel["spin_angle"] = wheel["spin_angle"] + (car["speed"] / wheel["radius"]) * dt
        wi = wi + 1

proc vehicle_speed_kmh(car):
    return car["speed"] * 3.6

proc vehicle_speed_mph(car):
    return car["speed"] * 2.237

# ============================================================================
# Chase Camera
# ============================================================================

proc create_chase_camera(distance, height, look_height):
    return {
        "distance": distance,
        "height": height,
        "look_height": look_height,
        "position": vec3(0.0, 5.0, -10.0),
        "smoothing": 5.0
    }

proc update_chase_camera(cam, car, dt):
    let behind_x = 0.0 - math.sin(car["rotation"]) * cam["distance"]
    let behind_z = 0.0 - math.cos(car["rotation"]) * cam["distance"]
    let target_pos = vec3(
        car["position"][0] + behind_x,
        car["position"][1] + cam["height"],
        car["position"][2] + behind_z
    )
    # Smooth follow
    let t = cam["smoothing"] * dt
    if t > 1.0:
        t = 1.0
    cam["position"] = v3_add(
        v3_scale(cam["position"], 1.0 - t),
        v3_scale(target_pos, t)
    )
    return cam["position"]

proc chase_camera_target(cam, car):
    return vec3(car["position"][0], car["position"][1] + cam["look_height"], car["position"][2])
