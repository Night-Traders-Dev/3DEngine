gc_disable()
# reverb_zones.sage — Spatial Audio Reverb Zones
# Apply reverb, echo, and occlusion effects based on listener position.

from math3d import vec3, v3_sub, v3_length

proc create_reverb_zone(position, radius, preset):
    return {
        "position": position,
        "radius": radius,
        "inner_radius": radius * 0.5,
        "preset": preset,
        "priority": 0,
        "active": true
    }

proc reverb_preset_cave():
    return {"reverb_time": 3.0, "decay": 0.8, "wet": 0.7, "dry": 0.4, "name": "cave"}

proc reverb_preset_hall():
    return {"reverb_time": 2.0, "decay": 0.6, "wet": 0.5, "dry": 0.6, "name": "hall"}

proc reverb_preset_outdoor():
    return {"reverb_time": 0.3, "decay": 0.2, "wet": 0.1, "dry": 0.95, "name": "outdoor"}

proc reverb_preset_bathroom():
    return {"reverb_time": 1.5, "decay": 0.7, "wet": 0.6, "dry": 0.5, "name": "bathroom"}

proc reverb_preset_underwater():
    return {"reverb_time": 4.0, "decay": 0.9, "wet": 0.8, "dry": 0.2, "name": "underwater"}

proc create_reverb_system():
    return {"zones": [], "current_preset": reverb_preset_outdoor(), "blend": 0.0}

proc add_reverb_zone(sys, zone):
    push(sys["zones"], zone)

proc update_reverb(sys, listener_pos):
    let best_zone = nil
    let best_weight = 0.0
    let i = 0
    while i < len(sys["zones"]):
        let z = sys["zones"][i]
        if not z["active"]:
            i = i + 1
            continue
        let dist = v3_length(v3_sub(listener_pos, z["position"]))
        if dist < z["radius"]:
            let weight = 1.0
            if dist > z["inner_radius"]:
                weight = 1.0 - (dist - z["inner_radius"]) / (z["radius"] - z["inner_radius"])
            if weight > best_weight:
                best_weight = weight
                best_zone = z
        i = i + 1
    if best_zone != nil:
        sys["current_preset"] = best_zone["preset"]
        sys["blend"] = best_weight
    else:
        sys["current_preset"] = reverb_preset_outdoor()
        sys["blend"] = 0.0

proc get_current_reverb(sys):
    return sys["current_preset"]

# ============================================================================
# Audio Occlusion — reduce volume behind walls
# ============================================================================

proc compute_audio_occlusion(source_pos, listener_pos, occluders):
    let dir = v3_sub(listener_pos, source_pos)
    let dist = v3_length(dir)
    let occlusion = 0.0
    let i = 0
    while i < len(occluders):
        let occ = occluders[i]
        # Simple: check if occluder is between source and listener
        let to_occ = v3_sub(occ["position"], source_pos)
        let occ_dist = v3_length(to_occ)
        if occ_dist < dist and occ_dist > 0.5:
            occlusion = occlusion + occ["thickness"] * 0.3
        i = i + 1
    if occlusion > 0.9:
        occlusion = 0.9
    return 1.0 - occlusion

# ============================================================================
# Client Prediction for Networking
# ============================================================================

proc create_prediction_state():
    return {
        "pending_inputs": [],
        "server_state": nil,
        "predicted_state": nil,
        "reconcile_threshold": 0.1,
        "input_sequence": 0
    }

proc record_input(pred, input_data):
    pred["input_sequence"] = pred["input_sequence"] + 1
    push(pred["pending_inputs"], {
        "sequence": pred["input_sequence"],
        "input": input_data
    })

proc apply_server_state(pred, server_state, last_processed_input):
    pred["server_state"] = server_state
    # Remove acknowledged inputs
    let remaining = []
    let i = 0
    while i < len(pred["pending_inputs"]):
        if pred["pending_inputs"][i]["sequence"] > last_processed_input:
            push(remaining, pred["pending_inputs"][i])
        i = i + 1
    pred["pending_inputs"] = remaining

proc get_predicted_position(pred, apply_input_fn):
    if pred["server_state"] == nil:
        return nil
    let state = pred["server_state"]
    # Re-apply unacknowledged inputs
    let i = 0
    while i < len(pred["pending_inputs"]):
        state = apply_input_fn(state, pred["pending_inputs"][i]["input"])
        i = i + 1
    pred["predicted_state"] = state
    return state
