gc_disable()
# perception.sage — AI Perception System + Environment Query System (EQS)
# Gives AI agents sight, hearing, and damage awareness.
# EQS finds optimal positions for cover, flanking, patrol routes.

import math
from math3d import vec3, v3_sub, v3_normalize, v3_length, v3_dot, v3_add, v3_scale

# ============================================================================
# Perception — sight, hearing, damage awareness
# ============================================================================

proc create_perception(sight_range, sight_angle, hearing_range):
    return {
        "sight_range": sight_range,
        "sight_angle": sight_angle,     # Half-angle in degrees
        "hearing_range": hearing_range,
        "damage_memory": 5.0,           # Remember damage source for N seconds
        "stimuli": [],                   # Active stimuli
        "known_targets": {},             # target_id → perception_data
        "dominant_target": nil
    }

proc add_sight_stimulus(perc, source_id, position, strength):
    push(perc["stimuli"], {"type": "sight", "source": source_id, "position": position, "strength": strength, "age": 0.0})

proc add_hearing_stimulus(perc, source_id, position, loudness):
    push(perc["stimuli"], {"type": "hearing", "source": source_id, "position": position, "strength": loudness, "age": 0.0})

proc add_damage_stimulus(perc, source_id, position, amount):
    push(perc["stimuli"], {"type": "damage", "source": source_id, "position": position, "strength": amount, "age": 0.0})

proc update_perception(perc, self_pos, self_forward, dt):
    # Age stimuli
    let alive = []
    let i = 0
    while i < len(perc["stimuli"]):
        let s = perc["stimuli"][i]
        s["age"] = s["age"] + dt
        if s["age"] < perc["damage_memory"]:
            push(alive, s)
        i = i + 1
    perc["stimuli"] = alive

    # Update known targets from stimuli
    i = 0
    while i < len(perc["stimuli"]):
        let s = perc["stimuli"][i]
        let visible = false
        if s["type"] == "sight":
            visible = _check_sight(perc, self_pos, self_forward, s["position"])
        elif s["type"] == "hearing":
            let dist = v3_length(v3_sub(s["position"], self_pos))
            visible = dist <= perc["hearing_range"]
        elif s["type"] == "damage":
            visible = true  # Always perceive damage source

        if visible:
            let key = str(s["source"])
            perc["known_targets"][key] = {
                "id": s["source"],
                "position": s["position"],
                "last_seen": 0.0,
                "threat": s["strength"],
                "type": s["type"]
            }
        i = i + 1

    # Age known targets
    let target_keys = dict_keys(perc["known_targets"])
    let best_threat = 0.0
    perc["dominant_target"] = nil
    i = 0
    while i < len(target_keys):
        let t = perc["known_targets"][target_keys[i]]
        t["last_seen"] = t["last_seen"] + dt
        if t["last_seen"] > perc["damage_memory"] * 2:
            dict_delete(perc["known_targets"], target_keys[i])
        elif t["threat"] > best_threat:
            best_threat = t["threat"]
            perc["dominant_target"] = t
        i = i + 1

proc _check_sight(perc, self_pos, self_forward, target_pos):
    let to_target = v3_sub(target_pos, self_pos)
    let dist = v3_length(to_target)
    if dist > perc["sight_range"]:
        return false
    let dir = v3_normalize(to_target)
    let dot = v3_dot(self_forward, dir)
    let angle_cos = math.cos(perc["sight_angle"] * 0.01745329)
    return dot >= angle_cos

proc get_dominant_target(perc):
    return perc["dominant_target"]

proc has_target(perc):
    return perc["dominant_target"] != nil

proc known_target_count(perc):
    return len(dict_keys(perc["known_targets"]))

# ============================================================================
# Environment Query System (EQS) — find optimal positions
# ============================================================================

proc create_eqs_query(center, radius, sample_count):
    return {
        "center": center,
        "radius": radius,
        "samples": sample_count,
        "tests": [],
        "results": []
    }

proc add_eqs_test(query, test_type, params):
    # test_type: "distance_to", "dot_product", "line_of_sight", "cover_from", "path_cost"
    push(query["tests"], {"type": test_type, "params": params, "weight": 1.0})

proc set_eqs_test_weight(query, test_index, weight):
    if test_index >= 0 and test_index < len(query["tests"]):
        query["tests"][test_index]["weight"] = weight

proc run_eqs_query(query):
    let results = []
    let i = 0
    while i < query["samples"]:
        let angle = (i * 6.2831853) / query["samples"]
        let r = query["radius"] * (0.3 + math.random() * 0.7)
        let pos = vec3(
            query["center"][0] + math.cos(angle) * r,
            query["center"][1],
            query["center"][2] + math.sin(angle) * r
        )
        let score = 0.0
        let ti = 0
        while ti < len(query["tests"]):
            let test = query["tests"][ti]
            let test_score = _evaluate_eqs_test(test, pos, query["center"])
            score = score + test_score * test["weight"]
            ti = ti + 1
        push(results, {"position": pos, "score": score})
        i = i + 1

    # Sort by score (descending) — simple bubble sort
    let si = 0
    while si < len(results) - 1:
        let sj = si + 1
        while sj < len(results):
            if results[sj]["score"] > results[si]["score"]:
                let tmp = results[si]
                results[si] = results[sj]
                results[sj] = tmp
            sj = sj + 1
        si = si + 1

    query["results"] = results
    return results

proc _evaluate_eqs_test(test, pos, center):
    if test["type"] == "distance_to":
        let target = test["params"]["target"]
        let dist = v3_length(v3_sub(pos, target))
        let preferred = test["params"]["preferred_distance"]
        let diff = dist - preferred
        if diff < 0:
            diff = 0 - diff
        return 1.0 - (diff / (preferred + 1.0))
    if test["type"] == "dot_product":
        let from_pos = test["params"]["from"]
        let to_pos = test["params"]["to"]
        let dir1 = v3_normalize(v3_sub(pos, from_pos))
        let dir2 = v3_normalize(v3_sub(to_pos, from_pos))
        return (v3_dot(dir1, dir2) + 1.0) * 0.5
    if test["type"] == "cover_from":
        let threat = test["params"]["threat_position"]
        let dist = v3_length(v3_sub(pos, threat))
        return dist / (dist + 5.0)  # Prefer positions far from threat
    return 0.5

proc eqs_best_position(query):
    if len(query["results"]) > 0:
        return query["results"][0]["position"]
    return query["center"]

proc eqs_top_n_positions(query, n):
    let results = []
    let i = 0
    while i < n and i < len(query["results"]):
        push(results, query["results"][i]["position"])
        i = i + 1
    return results
