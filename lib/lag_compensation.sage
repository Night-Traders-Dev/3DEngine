gc_disable()
# lag_compensation.sage — Network Lag Compensation
# Server-side hit validation by rewinding world state to client's perceived time.
# Supports: state history buffer, time rewind, hit verification, interpolation.

from math3d import vec3, v3_sub, v3_add, v3_scale, v3_length

proc create_lag_compensator(max_history_ms):
    return {
        "history": [],
        "max_history": max_history_ms,
        "tick_rate": 60,
        "current_tick": 0
    }

proc record_state(comp, tick, entity_states):
    # entity_states: [{"id": eid, "position": vec3, "bounds_min": vec3, "bounds_max": vec3}]
    push(comp["history"], {"tick": tick, "time": tick / comp["tick_rate"], "states": entity_states})
    # Trim old history
    let cutoff = tick - (comp["max_history"] * comp["tick_rate"] / 1000)
    let trimmed = []
    let i = 0
    while i < len(comp["history"]):
        if comp["history"][i]["tick"] >= cutoff:
            push(trimmed, comp["history"][i])
        i = i + 1
    comp["history"] = trimmed
    comp["current_tick"] = tick

proc rewind_to_tick(comp, target_tick):
    # Find the two surrounding snapshots
    let before = nil
    let after = nil
    let i = 0
    while i < len(comp["history"]):
        let snap = comp["history"][i]
        if snap["tick"] <= target_tick:
            before = snap
        if snap["tick"] >= target_tick and after == nil:
            after = snap
        i = i + 1
    if before == nil:
        return nil
    if after == nil or before["tick"] == after["tick"]:
        return before["states"]
    # Interpolate between snapshots
    let t = (target_tick - before["tick"]) / (after["tick"] - before["tick"])
    return _interpolate_states(before["states"], after["states"], t)

proc _interpolate_states(states_a, states_b, t):
    let result = []
    let i = 0
    while i < len(states_a):
        let a = states_a[i]
        let b = nil
        let j = 0
        while j < len(states_b):
            if states_b[j]["id"] == a["id"]:
                b = states_b[j]
                break
            j = j + 1
        if b != nil:
            push(result, {
                "id": a["id"],
                "position": v3_add(v3_scale(a["position"], 1.0 - t), v3_scale(b["position"], t))
            })
        else:
            push(result, a)
        i = i + 1
    return result

proc verify_hit(comp, client_tick, shooter_pos, shoot_dir, target_id, max_dist):
    let rewound = rewind_to_tick(comp, client_tick)
    if rewound == nil:
        return false
    let i = 0
    while i < len(rewound):
        if rewound[i]["id"] == target_id:
            let target_pos = rewound[i]["position"]
            let to_target = v3_sub(target_pos, shooter_pos)
            let dist = v3_length(to_target)
            if dist <= max_dist:
                return true
        i = i + 1
    return false

proc history_size(comp):
    return len(comp["history"])
