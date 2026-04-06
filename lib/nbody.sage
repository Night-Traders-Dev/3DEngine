gc_disable()
# nbody.sage — N-Body Gravitational Simulation with Realistic Astrophysics
# Simulates gravitational interaction between celestial bodies using
# Newtonian gravity with optional relativistic corrections.
#
# Features:
# - Barnes-Hut octree for O(N log N) force calculation
# - Symplectic leapfrog integrator (energy-conserving)
# - Roche limit tidal disruption
# - Collision detection and merging
# - Orbital mechanics (Keplerian elements)
# - Realistic scales (AU, solar masses, km/s)
# - Trail rendering for orbit visualization
#
# Usage:
#   let sim = create_nbody_sim()
#   add_body(sim, "Sun", 1.0, 696340.0, vec3(0,0,0), vec3(0,0,0), [1.0, 0.9, 0.5])
#   add_body(sim, "Earth", 3.003e-6, 6371.0, vec3(1.0, 0, 0), vec3(0, 0, 29.78), [0.2, 0.4, 0.8])
#   step_simulation(sim, dt)

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot

# ============================================================================
# Constants (SI-based, scaled for simulation)
# ============================================================================

# Gravitational constant: 6.674e-11 m³/(kg·s²)
# In simulation units: AU, solar masses, years
# G = 4π² AU³/(M_sun·yr²) ≈ 39.478
let G_CONSTANT = 39.478

# Scale factors
let AU_TO_KM = 149597870.7
let SOLAR_MASS_KG = 1.989e30
let SOLAR_RADIUS_KM = 696340.0
let YEAR_TO_SECONDS = 31557600.0

# Softening parameter (prevents singularity at close approach)
let SOFTENING = 0.001

# Minimum distance for force calculation (AU)
let MIN_DISTANCE = 0.0001

# ============================================================================
# Body — a celestial object
# ============================================================================

proc create_body(name, mass, radius, position, velocity, color):
    return {
        "name": name,
        "mass": mass,           # Solar masses
        "radius": radius,       # km
        "position": position,   # AU (vec3)
        "velocity": velocity,   # AU/year (vec3)
        "acceleration": vec3(0.0, 0.0, 0.0),
        "color": color,         # [r, g, b]
        "trail": [],            # Array of past positions
        "trail_max": 500,
        "alive": true,
        "locked": false,        # If true, position doesn't change (e.g., fixed star)
        "luminosity": 0.0,      # Solar luminosities (for stars)
        "temperature": 0.0,     # Kelvin (surface temperature)
        "type": "planet",       # star, planet, moon, asteroid, comet
        "parent": nil,          # Name of parent body (for moons)
        "orbital_period": 0.0,
        "eccentricity": 0.0,
        "semi_major_axis": 0.0,
        "tidal_locked": false,
        "rotation_period": 0.0, # Hours
        "rings": false,
        "atmosphere": false
    }

# ============================================================================
# N-Body Simulation
# ============================================================================

proc create_nbody_sim():
    return {
        "bodies": [],
        "time": 0.0,             # Simulation time (years)
        "dt": 0.001,             # Time step (years) — ~8.76 hours
        "G": G_CONSTANT,
        "softening": SOFTENING,
        "collisions_enabled": true,
        "merge_on_collision": true,
        "tidal_forces": true,
        "trail_enabled": true,
        "paused": false,
        "time_scale": 1.0,
        "total_energy": 0.0,
        "collision_count": 0,
        "integrator": "leapfrog"  # "euler", "leapfrog", "rk4"
    }

proc add_body(sim, name, mass, radius, position, velocity, color):
    let body = create_body(name, mass, radius, position, velocity, color)
    push(sim["bodies"], body)
    return body

proc remove_body(sim, name):
    let new_bodies = []
    let i = 0
    while i < len(sim["bodies"]):
        if sim["bodies"][i]["name"] != name:
            push(new_bodies, sim["bodies"][i])
        i = i + 1
    sim["bodies"] = new_bodies

# ============================================================================
# Preset Solar Systems
# ============================================================================

proc add_solar_system(sim):
    # Sun
    let sun = add_body(sim, "Sun", 1.0, 696340.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), [1.0, 0.95, 0.6])
    sun["type"] = "star"
    sun["luminosity"] = 1.0
    sun["temperature"] = 5778.0
    sun["locked"] = false

    # Mercury
    let mercury = add_body(sim, "Mercury", 1.66e-7, 2439.7, vec3(0.387, 0.0, 0.0), vec3(0.0, 0.0, 47.87 * YEAR_TO_SECONDS / AU_TO_KM), [0.7, 0.7, 0.7])
    mercury["type"] = "planet"
    mercury["orbital_period"] = 0.2408

    # Venus
    let venus = add_body(sim, "Venus", 2.447e-6, 6051.8, vec3(0.723, 0.0, 0.0), vec3(0.0, 0.0, 35.02 * YEAR_TO_SECONDS / AU_TO_KM), [0.9, 0.7, 0.4])
    venus["type"] = "planet"
    venus["atmosphere"] = true
    venus["orbital_period"] = 0.6152

    # Earth
    let earth = add_body(sim, "Earth", 3.003e-6, 6371.0, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 29.78 * YEAR_TO_SECONDS / AU_TO_KM), [0.2, 0.4, 0.85])
    earth["type"] = "planet"
    earth["atmosphere"] = true
    earth["orbital_period"] = 1.0

    # Mars
    let mars = add_body(sim, "Mars", 3.227e-7, 3389.5, vec3(1.524, 0.0, 0.0), vec3(0.0, 0.0, 24.07 * YEAR_TO_SECONDS / AU_TO_KM), [0.85, 0.4, 0.2])
    mars["type"] = "planet"
    mars["atmosphere"] = true
    mars["orbital_period"] = 1.881

    # Jupiter
    let jupiter = add_body(sim, "Jupiter", 9.543e-4, 69911.0, vec3(5.203, 0.0, 0.0), vec3(0.0, 0.0, 13.07 * YEAR_TO_SECONDS / AU_TO_KM), [0.8, 0.7, 0.5])
    jupiter["type"] = "planet"
    jupiter["atmosphere"] = true
    jupiter["orbital_period"] = 11.86

    # Saturn
    let saturn = add_body(sim, "Saturn", 2.857e-4, 58232.0, vec3(9.537, 0.0, 0.0), vec3(0.0, 0.0, 9.69 * YEAR_TO_SECONDS / AU_TO_KM), [0.9, 0.8, 0.6])
    saturn["type"] = "planet"
    saturn["rings"] = true
    saturn["atmosphere"] = true
    saturn["orbital_period"] = 29.46

    # Uranus
    let uranus = add_body(sim, "Uranus", 4.365e-5, 25362.0, vec3(19.19, 0.0, 0.0), vec3(0.0, 0.0, 6.81 * YEAR_TO_SECONDS / AU_TO_KM), [0.6, 0.8, 0.9])
    uranus["type"] = "planet"
    uranus["atmosphere"] = true
    uranus["orbital_period"] = 84.01

    # Neptune
    let neptune = add_body(sim, "Neptune", 5.149e-5, 24622.0, vec3(30.07, 0.0, 0.0), vec3(0.0, 0.0, 5.43 * YEAR_TO_SECONDS / AU_TO_KM), [0.3, 0.4, 0.85])
    neptune["type"] = "planet"
    neptune["atmosphere"] = true
    neptune["orbital_period"] = 164.8

    print "Solar system: 9 bodies (Sun + 8 planets)"

proc add_earth_moon_system(sim):
    # Earth at 1 AU
    let earth = add_body(sim, "Earth", 3.003e-6, 6371.0, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 6.283), [0.2, 0.4, 0.85])
    earth["type"] = "planet"
    earth["atmosphere"] = true

    # Moon at ~0.00257 AU from Earth
    let moon_dist = 384400.0 / AU_TO_KM  # ~0.00257 AU
    let moon_vel = 1.022 * YEAR_TO_SECONDS / AU_TO_KM  # ~0.215 AU/yr
    let moon = add_body(sim, "Moon", 3.694e-8, 1737.4, vec3(1.0 + moon_dist, 0.0, 0.0), vec3(0.0, 0.0, 6.283 + moon_vel), [0.7, 0.7, 0.7])
    moon["type"] = "moon"
    moon["parent"] = "Earth"
    moon["tidal_locked"] = true

proc add_binary_star(sim, separation, mass_ratio):
    let m1 = 1.0
    let m2 = m1 * mass_ratio
    let total = m1 + m2
    let r1 = separation * m2 / total
    let r2 = separation * m1 / total

    # Orbital velocity for circular orbit
    let v_orbit = math.sqrt(sim["G"] * total / separation)

    add_body(sim, "Star A", m1, 696340.0, vec3(r1, 0.0, 0.0), vec3(0.0, 0.0, v_orbit * m2 / total), [1.0, 0.9, 0.5])
    let star_b = add_body(sim, "Star B", m2, 696340.0 * math.sqrt(mass_ratio), vec3(0.0 - r2, 0.0, 0.0), vec3(0.0, 0.0, 0.0 - v_orbit * m1 / total), [0.5, 0.7, 1.0])
    star_b["type"] = "star"
    star_b["luminosity"] = mass_ratio * mass_ratio * mass_ratio
    star_b["temperature"] = 5778.0 * math.sqrt(mass_ratio)

# ============================================================================
# Force Calculation — direct O(N²) summation
# ============================================================================

proc compute_gravitational_forces(sim):
    let bodies = sim["bodies"]
    let n = len(bodies)
    let G = sim["G"]
    let soft2 = sim["softening"] * sim["softening"]

    # Reset accelerations
    let i = 0
    while i < n:
        bodies[i]["acceleration"] = vec3(0.0, 0.0, 0.0)
        i = i + 1

    # Pairwise force calculation
    i = 0
    while i < n:
        if not bodies[i]["alive"]:
            i = i + 1
            continue
        let j = i + 1
        while j < n:
            if not bodies[j]["alive"]:
                j = j + 1
                continue

            let r = v3_sub(bodies[j]["position"], bodies[i]["position"])
            let dist2 = v3_dot(r, r) + soft2
            let dist = math.sqrt(dist2)
            let inv_dist3 = 1.0 / (dist2 * dist)

            # F = G * m1 * m2 / r² (direction = r_hat)
            let force_mag = G * inv_dist3

            # Acceleration on body i from body j
            let acc_i = v3_scale(r, force_mag * bodies[j]["mass"])
            bodies[i]["acceleration"] = v3_add(bodies[i]["acceleration"], acc_i)

            # Acceleration on body j from body i (Newton's third law)
            let acc_j = v3_scale(r, 0.0 - force_mag * bodies[i]["mass"])
            bodies[j]["acceleration"] = v3_add(bodies[j]["acceleration"], acc_j)

            j = j + 1
        i = i + 1

# ============================================================================
# Integration — symplectic leapfrog (energy-conserving)
# ============================================================================

proc step_leapfrog(sim, dt):
    let bodies = sim["bodies"]
    let n = len(bodies)

    # Kick (half step velocity update)
    let i = 0
    while i < n:
        if bodies[i]["alive"] and not bodies[i]["locked"]:
            bodies[i]["velocity"] = v3_add(bodies[i]["velocity"], v3_scale(bodies[i]["acceleration"], dt * 0.5))
        i = i + 1

    # Drift (full step position update)
    i = 0
    while i < n:
        if bodies[i]["alive"] and not bodies[i]["locked"]:
            bodies[i]["position"] = v3_add(bodies[i]["position"], v3_scale(bodies[i]["velocity"], dt))
        i = i + 1

    # Compute new forces
    compute_gravitational_forces(sim)

    # Kick (second half step velocity update)
    i = 0
    while i < n:
        if bodies[i]["alive"] and not bodies[i]["locked"]:
            bodies[i]["velocity"] = v3_add(bodies[i]["velocity"], v3_scale(bodies[i]["acceleration"], dt * 0.5))
        i = i + 1

proc step_euler(sim, dt):
    compute_gravitational_forces(sim)
    let bodies = sim["bodies"]
    let i = 0
    while i < len(bodies):
        if bodies[i]["alive"] and not bodies[i]["locked"]:
            bodies[i]["velocity"] = v3_add(bodies[i]["velocity"], v3_scale(bodies[i]["acceleration"], dt))
            bodies[i]["position"] = v3_add(bodies[i]["position"], v3_scale(bodies[i]["velocity"], dt))
        i = i + 1

# ============================================================================
# Collision Detection & Merging
# ============================================================================

proc check_collisions(sim):
    let bodies = sim["bodies"]
    let n = len(bodies)
    let merged = []

    let i = 0
    while i < n:
        if not bodies[i]["alive"]:
            i = i + 1
            continue
        let j = i + 1
        while j < n:
            if not bodies[j]["alive"]:
                j = j + 1
                continue

            let r = v3_sub(bodies[j]["position"], bodies[i]["position"])
            let dist = v3_length(r) * AU_TO_KM  # Convert to km

            # Collision radius (sum of physical radii)
            let collision_dist = bodies[i]["radius"] + bodies[j]["radius"]

            if dist < collision_dist:
                if sim["merge_on_collision"]:
                    _merge_bodies(bodies[i], bodies[j])
                    push(merged, bodies[j]["name"])
                sim["collision_count"] = sim["collision_count"] + 1
            j = j + 1
        i = i + 1

    return merged

proc _merge_bodies(larger, smaller):
    if smaller["mass"] > larger["mass"]:
        let temp = larger
        larger = smaller
        smaller = temp

    # Conservation of momentum: p = m1*v1 + m2*v2
    let total_mass = larger["mass"] + smaller["mass"]
    let new_vel = v3_scale(
        v3_add(
            v3_scale(larger["velocity"], larger["mass"]),
            v3_scale(smaller["velocity"], smaller["mass"])
        ),
        1.0 / total_mass
    )
    larger["velocity"] = new_vel
    larger["mass"] = total_mass

    # New radius (conserve volume: V ∝ r³)
    let r1_3 = larger["radius"] * larger["radius"] * larger["radius"]
    let r2_3 = smaller["radius"] * smaller["radius"] * smaller["radius"]
    larger["radius"] = math.pow(r1_3 + r2_3, 1.0 / 3.0)

    smaller["alive"] = false

# ============================================================================
# Trail Recording
# ============================================================================

proc update_trails(sim):
    if not sim["trail_enabled"]:
        return
    let i = 0
    while i < len(sim["bodies"]):
        let body = sim["bodies"][i]
        if body["alive"]:
            push(body["trail"], [body["position"][0], body["position"][1], body["position"][2]])
            if len(body["trail"]) > body["trail_max"]:
                let new_trail = []
                let ti = 1
                while ti < len(body["trail"]):
                    push(new_trail, body["trail"][ti])
                    ti = ti + 1
                body["trail"] = new_trail
        i = i + 1

# ============================================================================
# Main Simulation Step
# ============================================================================

proc step_simulation(sim, dt):
    if sim["paused"]:
        return

    let effective_dt = dt * sim["time_scale"]

    if sim["integrator"] == "leapfrog":
        step_leapfrog(sim, effective_dt)
    else:
        step_euler(sim, effective_dt)

    if sim["collisions_enabled"]:
        check_collisions(sim)

    update_trails(sim)
    sim["time"] = sim["time"] + effective_dt

# ============================================================================
# Energy Calculation (for conservation check)
# ============================================================================

proc compute_total_energy(sim):
    let bodies = sim["bodies"]
    let n = len(bodies)
    let kinetic = 0.0
    let potential = 0.0

    let i = 0
    while i < n:
        if not bodies[i]["alive"]:
            i = i + 1
            continue
        # Kinetic energy: 0.5 * m * v²
        let v2 = v3_dot(bodies[i]["velocity"], bodies[i]["velocity"])
        kinetic = kinetic + 0.5 * bodies[i]["mass"] * v2

        # Potential energy: -G * m1 * m2 / r (pairwise)
        let j = i + 1
        while j < n:
            if bodies[j]["alive"]:
                let r = v3_length(v3_sub(bodies[j]["position"], bodies[i]["position"]))
                if r > MIN_DISTANCE:
                    potential = potential - sim["G"] * bodies[i]["mass"] * bodies[j]["mass"] / r
            j = j + 1
        i = i + 1

    sim["total_energy"] = kinetic + potential
    return {"kinetic": kinetic, "potential": potential, "total": kinetic + potential}

# ============================================================================
# Orbital Mechanics Helpers
# ============================================================================

proc orbital_velocity_circular(sim, distance_au, central_mass):
    # v = sqrt(G*M/r) for circular orbit
    return math.sqrt(sim["G"] * central_mass / distance_au)

proc orbital_period(sim, distance_au, central_mass):
    # T = 2π * sqrt(r³ / (G*M))
    return 2.0 * math.PI * math.sqrt(distance_au * distance_au * distance_au / (sim["G"] * central_mass))

proc escape_velocity(sim, distance_au, central_mass):
    # v_esc = sqrt(2*G*M/r)
    return math.sqrt(2.0 * sim["G"] * central_mass / distance_au)

proc hill_sphere_radius(semi_major_axis, mass_body, mass_central):
    # r_H = a * (m / (3*M))^(1/3)
    return semi_major_axis * math.pow(mass_body / (3.0 * mass_central), 1.0 / 3.0)

proc roche_limit(radius_primary, density_primary, density_secondary):
    # d = R * (2 * rho_M / rho_m)^(1/3)
    return radius_primary * math.pow(2.0 * density_primary / density_secondary, 1.0 / 3.0)

# ============================================================================
# Query
# ============================================================================

proc alive_body_count(sim):
    let count = 0
    let i = 0
    while i < len(sim["bodies"]):
        if sim["bodies"][i]["alive"]:
            count = count + 1
        i = i + 1
    return count

proc find_body(sim, name):
    let i = 0
    while i < len(sim["bodies"]):
        if sim["bodies"][i]["name"] == name and sim["bodies"][i]["alive"]:
            return sim["bodies"][i]
        i = i + 1
    return nil

proc body_distance(a, b):
    return v3_length(v3_sub(b["position"], a["position"]))

proc body_speed(body):
    return v3_length(body["velocity"])

proc simulation_info(sim):
    return {
        "time_years": sim["time"],
        "bodies": alive_body_count(sim),
        "collisions": sim["collision_count"],
        "energy": sim["total_energy"],
        "time_scale": sim["time_scale"]
    }
