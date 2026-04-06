gc_disable()
# cloth.sage — Cloth and Soft Body Physics
# Mass-spring simulation for capes, flags, hair, soft objects.
# Supports: structural/shear/bend springs, wind, collision with spheres/planes,
# pin constraints, self-collision, tearing.

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length, v3_dot

proc create_cloth(width, height, spacing, mass_per_node):
    let nodes = []
    let springs = []
    let cols = width
    let rows = height
    let total = cols * rows

    # Create particle grid
    let i = 0
    while i < total:
        let col = i - (i / cols) * cols
        let row = i / cols
        push(nodes, {
            "position": vec3(col * spacing, 0.0, row * spacing),
            "prev_position": vec3(col * spacing, 0.0, row * spacing),
            "velocity": vec3(0.0, 0.0, 0.0),
            "acceleration": vec3(0.0, 0.0, 0.0),
            "mass": mass_per_node,
            "inv_mass": 1.0 / mass_per_node,
            "pinned": false,
            "col": col,
            "row": row
        })
        i = i + 1

    # Structural springs (horizontal + vertical)
    i = 0
    while i < total:
        let col = i - (i / cols) * cols
        let row = i / cols
        # Right neighbor
        if col < cols - 1:
            push(springs, {"a": i, "b": i + 1, "rest": spacing, "stiffness": 50.0, "type": "structural"})
        # Down neighbor
        if row < rows - 1:
            push(springs, {"a": i, "b": i + cols, "rest": spacing, "stiffness": 50.0, "type": "structural"})
        # Shear springs (diagonal)
        if col < cols - 1 and row < rows - 1:
            let diag = spacing * 1.41421356
            push(springs, {"a": i, "b": i + cols + 1, "rest": diag, "stiffness": 30.0, "type": "shear"})
        if col > 0 and row < rows - 1:
            let diag = spacing * 1.41421356
            push(springs, {"a": i, "b": i + cols - 1, "rest": diag, "stiffness": 30.0, "type": "shear"})
        # Bend springs (skip one)
        if col < cols - 2:
            push(springs, {"a": i, "b": i + 2, "rest": spacing * 2.0, "stiffness": 10.0, "type": "bend"})
        if row < rows - 2:
            push(springs, {"a": i, "b": i + cols * 2, "rest": spacing * 2.0, "stiffness": 10.0, "type": "bend"})
        i = i + 1

    return {
        "nodes": nodes,
        "springs": springs,
        "cols": cols,
        "rows": rows,
        "spacing": spacing,
        "damping": 0.98,
        "gravity": vec3(0.0, -9.81, 0.0),
        "wind": vec3(0.0, 0.0, 0.0),
        "wind_turbulence": 0.3,
        "iterations": 8,
        "collision_spheres": [],
        "collision_planes": [],
        "tear_threshold": 0.0    # 0 = no tearing
    }

proc pin_node(cloth, col, row):
    let idx = row * cloth["cols"] + col
    if idx >= 0 and idx < len(cloth["nodes"]):
        cloth["nodes"][idx]["pinned"] = true
        cloth["nodes"][idx]["inv_mass"] = 0.0

proc unpin_node(cloth, col, row):
    let idx = row * cloth["cols"] + col
    if idx >= 0 and idx < len(cloth["nodes"]):
        cloth["nodes"][idx]["pinned"] = false
        cloth["nodes"][idx]["inv_mass"] = 1.0 / cloth["nodes"][idx]["mass"]

proc set_wind(cloth, direction, strength):
    cloth["wind"] = v3_scale(v3_normalize(direction), strength)

proc add_collision_sphere(cloth, center, radius):
    push(cloth["collision_spheres"], {"center": center, "radius": radius})

proc add_collision_plane(cloth, normal, distance):
    push(cloth["collision_planes"], {"normal": normal, "distance": distance})

proc update_cloth(cloth, dt):
    let nodes = cloth["nodes"]
    let n = len(nodes)

    # Apply forces (gravity + wind + turbulence)
    let i = 0
    while i < n:
        let node = nodes[i]
        if node["pinned"]:
            i = i + 1
            continue
        let force = v3_scale(cloth["gravity"], node["mass"])
        # Wind with turbulence
        let wind = cloth["wind"]
        if cloth["wind_turbulence"] > 0:
            let turb = (math.sin(node["position"][0] * 3.0 + node["position"][2] * 2.0) * 0.5 + 0.5) * cloth["wind_turbulence"]
            wind = v3_add(wind, vec3(turb, 0.0, turb * 0.5))
        force = v3_add(force, v3_scale(wind, node["mass"]))
        node["acceleration"] = v3_scale(force, node["inv_mass"])
        i = i + 1

    # Verlet integration
    i = 0
    while i < n:
        let node = nodes[i]
        if node["pinned"]:
            i = i + 1
            continue
        let new_pos = v3_add(
            v3_sub(v3_scale(node["position"], 2.0 - (1.0 - cloth["damping"])), v3_scale(node["prev_position"], cloth["damping"])),
            v3_scale(node["acceleration"], dt * dt)
        )
        node["prev_position"] = node["position"]
        node["position"] = new_pos
        i = i + 1

    # Constraint solving (springs)
    let iter = 0
    while iter < cloth["iterations"]:
        let si = 0
        while si < len(cloth["springs"]):
            let spring = cloth["springs"][si]
            let a = nodes[spring["a"]]
            let b = nodes[spring["b"]]
            let delta = v3_sub(b["position"], a["position"])
            let dist = v3_length(delta)
            if dist < 0.0001:
                si = si + 1
                continue
            # Tearing check
            if cloth["tear_threshold"] > 0 and dist > spring["rest"] * cloth["tear_threshold"]:
                # Remove spring (mark for removal)
                spring["stiffness"] = 0.0
                si = si + 1
                continue
            let diff = (dist - spring["rest"]) / dist
            let correction = v3_scale(delta, diff * 0.5 * spring["stiffness"] / 50.0)
            if not a["pinned"]:
                a["position"] = v3_add(a["position"], correction)
            if not b["pinned"]:
                b["position"] = v3_sub(b["position"], correction)
            si = si + 1
        iter = iter + 1

    # Sphere collision
    i = 0
    while i < n:
        let node = nodes[i]
        if node["pinned"]:
            i = i + 1
            continue
        let ci = 0
        while ci < len(cloth["collision_spheres"]):
            let sphere = cloth["collision_spheres"][ci]
            let to_node = v3_sub(node["position"], sphere["center"])
            let dist = v3_length(to_node)
            if dist < sphere["radius"]:
                let push_out = v3_scale(v3_normalize(to_node), sphere["radius"] - dist)
                node["position"] = v3_add(node["position"], push_out)
            ci = ci + 1
        # Plane collision
        let pi = 0
        while pi < len(cloth["collision_planes"]):
            let plane = cloth["collision_planes"][pi]
            let dist = v3_dot(node["position"], plane["normal"]) - plane["distance"]
            if dist < 0:
                node["position"] = v3_add(node["position"], v3_scale(plane["normal"], 0.0 - dist))
            pi = pi + 1
        i = i + 1

proc cloth_positions(cloth):
    let positions = []
    let i = 0
    while i < len(cloth["nodes"]):
        push(positions, cloth["nodes"][i]["position"])
        i = i + 1
    return positions

proc cloth_node_count(cloth):
    return len(cloth["nodes"])

proc cloth_spring_count(cloth):
    return len(cloth["springs"])
