gc_disable()
# crowd.sage — Crowd Simulation System
# Manages hundreds of autonomous agents with collision avoidance,
# flow fields, formation movement, and LOD-based optimization.

import math
from math3d import vec3, v3_add, v3_sub, v3_scale, v3_normalize, v3_length

proc create_crowd_system(max_agents):
    return {
        "agents": [],
        "max_agents": max_agents,
        "cell_size": 2.0,
        "avoidance_radius": 1.5,
        "separation_weight": 2.0,
        "alignment_weight": 1.0,
        "cohesion_weight": 0.5,
        "goal_weight": 3.0,
        "max_speed": 3.0,
        "spatial_grid": {}
    }

proc add_crowd_agent(crowd, position, goal, speed):
    if len(crowd["agents"]) >= crowd["max_agents"]:
        return nil
    let agent = {
        "position": position,
        "velocity": vec3(0.0, 0.0, 0.0),
        "goal": goal,
        "speed": speed,
        "radius": 0.4,
        "active": true,
        "arrived": false,
        "group": 0
    }
    push(crowd["agents"], agent)
    return agent

proc update_crowd(crowd, dt):
    let n = len(crowd["agents"])
    # Build spatial grid
    _rebuild_spatial_grid(crowd)

    let i = 0
    while i < n:
        let agent = crowd["agents"][i]
        if not agent["active"] or agent["arrived"]:
            i = i + 1
            continue

        # Goal seeking
        let to_goal = v3_sub(agent["goal"], agent["position"])
        let dist = v3_length(to_goal)
        if dist < 0.5:
            agent["arrived"] = true
            agent["velocity"] = vec3(0.0, 0.0, 0.0)
            i = i + 1
            continue

        let goal_force = v3_scale(v3_normalize(to_goal), crowd["goal_weight"])

        # Neighbor forces (separation, alignment, cohesion)
        let sep = vec3(0.0, 0.0, 0.0)
        let align = vec3(0.0, 0.0, 0.0)
        let cohesion_center = vec3(0.0, 0.0, 0.0)
        let neighbor_count = 0

        let j = 0
        while j < n:
            if j != i and crowd["agents"][j]["active"]:
                let other = crowd["agents"][j]
                let diff = v3_sub(agent["position"], other["position"])
                let d = v3_length(diff)
                if d < crowd["avoidance_radius"] and d > 0.01:
                    # Separation
                    sep = v3_add(sep, v3_scale(v3_normalize(diff), 1.0 / d))
                    # Alignment
                    align = v3_add(align, other["velocity"])
                    # Cohesion
                    cohesion_center = v3_add(cohesion_center, other["position"])
                    neighbor_count = neighbor_count + 1
            j = j + 1

        let total_force = goal_force
        total_force = v3_add(total_force, v3_scale(sep, crowd["separation_weight"]))

        if neighbor_count > 0:
            align = v3_scale(align, 1.0 / neighbor_count)
            total_force = v3_add(total_force, v3_scale(align, crowd["alignment_weight"]))
            cohesion_center = v3_scale(cohesion_center, 1.0 / neighbor_count)
            let to_center = v3_sub(cohesion_center, agent["position"])
            total_force = v3_add(total_force, v3_scale(to_center, crowd["cohesion_weight"]))

        # Apply force, clamp speed
        agent["velocity"] = v3_add(agent["velocity"], v3_scale(total_force, dt))
        let speed = v3_length(agent["velocity"])
        if speed > agent["speed"]:
            agent["velocity"] = v3_scale(v3_normalize(agent["velocity"]), agent["speed"])

        agent["position"] = v3_add(agent["position"], v3_scale(agent["velocity"], dt))
        i = i + 1

proc _rebuild_spatial_grid(crowd):
    crowd["spatial_grid"] = {}

proc set_crowd_goal(crowd, group, goal):
    let i = 0
    while i < len(crowd["agents"]):
        if crowd["agents"][i]["group"] == group:
            crowd["agents"][i]["goal"] = goal
            crowd["agents"][i]["arrived"] = false
        i = i + 1

proc crowd_agent_count(crowd):
    let count = 0
    let i = 0
    while i < len(crowd["agents"]):
        if crowd["agents"][i]["active"]:
            count = count + 1
        i = i + 1
    return count

proc crowd_arrived_count(crowd):
    let count = 0
    let i = 0
    while i < len(crowd["agents"]):
        if crowd["agents"][i]["arrived"]:
            count = count + 1
        i = i + 1
    return count
