gc_disable()
# montage.sage — Animation Montages and Retargeting
# Play one-shot animation sequences over the base blend tree.
# Supports: sections, branching, notify events, slot-based layering,
# animation retargeting between different skeletons.

# ============================================================================
# Animation Montage — one-shot sequences that override blend tree
# ============================================================================

proc create_montage(name, clip, play_rate):
    return {
        "name": name,
        "clip": clip,
        "play_rate": play_rate,
        "sections": [{"name": "default", "start": 0.0, "end": -1.0}],
        "notifies": [],
        "current_time": 0.0,
        "playing": false,
        "looping": false,
        "blend_in": 0.15,
        "blend_out": 0.15,
        "blend_weight": 0.0,
        "slot": "full_body",     # Which body part this affects
        "on_complete": nil,
        "on_notify": nil,
        "current_section": 0
    }

proc add_montage_section(montage, name, start_time, end_time):
    push(montage["sections"], {"name": name, "start": start_time, "end": end_time})

proc add_montage_notify(montage, time, event_name, data):
    push(montage["notifies"], {"time": time, "event": event_name, "data": data, "fired": false})

proc play_montage(montage):
    montage["playing"] = true
    montage["current_time"] = 0.0
    montage["blend_weight"] = 0.0
    montage["current_section"] = 0
    let i = 0
    while i < len(montage["notifies"]):
        montage["notifies"][i]["fired"] = false
        i = i + 1

proc stop_montage(montage):
    montage["playing"] = false

proc jump_to_section(montage, section_name):
    let i = 0
    while i < len(montage["sections"]):
        if montage["sections"][i]["name"] == section_name:
            montage["current_section"] = i
            montage["current_time"] = montage["sections"][i]["start"]
            return true
        i = i + 1
    return false

proc update_montage(montage, dt):
    if not montage["playing"]:
        return nil

    montage["current_time"] = montage["current_time"] + dt * montage["play_rate"]

    # Blend in
    if montage["blend_weight"] < 1.0:
        montage["blend_weight"] = montage["blend_weight"] + dt / montage["blend_in"]
        if montage["blend_weight"] > 1.0:
            montage["blend_weight"] = 1.0

    # Check notifies
    let events = []
    let ni = 0
    while ni < len(montage["notifies"]):
        let notify = montage["notifies"][ni]
        if not notify["fired"] and montage["current_time"] >= notify["time"]:
            notify["fired"] = true
            push(events, notify)
            if montage["on_notify"] != nil:
                montage["on_notify"](notify["event"], notify["data"])
        ni = ni + 1

    # Check section end
    let section = montage["sections"][montage["current_section"]]
    let section_end = section["end"]
    if section_end < 0 and montage["clip"] != nil and dict_has(montage["clip"], "duration"):
        section_end = montage["clip"]["duration"]
    if section_end > 0 and montage["current_time"] >= section_end:
        if montage["current_section"] < len(montage["sections"]) - 1:
            montage["current_section"] = montage["current_section"] + 1
            montage["current_time"] = montage["sections"][montage["current_section"]]["start"]
        elif montage["looping"]:
            montage["current_time"] = montage["sections"][0]["start"]
            montage["current_section"] = 0
        else:
            montage["playing"] = false
            if montage["on_complete"] != nil:
                montage["on_complete"]()

    return {"time": montage["current_time"], "weight": montage["blend_weight"], "events": events}

proc is_montage_playing(montage):
    return montage["playing"]

# ============================================================================
# Montage Slots — layer montages on different body parts
# ============================================================================

proc create_montage_system():
    return {
        "slots": {},         # slot_name → active montage
        "queue": []          # Pending montages
    }

proc play_montage_in_slot(sys, montage, slot_name):
    montage["slot"] = slot_name
    sys["slots"][slot_name] = montage
    play_montage(montage)

proc update_montage_system(sys, dt):
    let results = {}
    let keys = dict_keys(sys["slots"])
    let i = 0
    while i < len(keys):
        let slot = keys[i]
        let montage = sys["slots"][slot]
        if montage != nil and montage["playing"]:
            let result = update_montage(montage, dt)
            results[slot] = result
        elif montage != nil and not montage["playing"]:
            sys["slots"][slot] = nil
        i = i + 1
    return results

proc get_active_montage(sys, slot_name):
    if dict_has(sys["slots"], slot_name):
        return sys["slots"][slot_name]
    return nil

# ============================================================================
# Animation Retargeting — map animations between different skeletons
# ============================================================================

proc create_retarget_map(source_skeleton, target_skeleton, bone_mapping):
    # bone_mapping: {"source_bone_name": "target_bone_name", ...}
    return {
        "source": source_skeleton,
        "target": target_skeleton,
        "mapping": bone_mapping,
        "scale_factor": 1.0
    }

proc retarget_pose(retarget, source_pose):
    let target_pose = {}
    let keys = dict_keys(retarget["mapping"])
    let i = 0
    while i < len(keys):
        let src_bone = keys[i]
        let tgt_bone = retarget["mapping"][src_bone]
        if dict_has(source_pose, src_bone):
            target_pose[tgt_bone] = source_pose[src_bone]
            # Scale translations by scale_factor
            if dict_has(target_pose[tgt_bone], "translation"):
                let t = target_pose[tgt_bone]["translation"]
                target_pose[tgt_bone]["translation"] = [
                    t[0] * retarget["scale_factor"],
                    t[1] * retarget["scale_factor"],
                    t[2] * retarget["scale_factor"]
                ]
        i = i + 1
    return target_pose

proc create_humanoid_retarget():
    # Standard humanoid bone mapping
    return {
        "Hips": "Hips", "Spine": "Spine", "Spine1": "Spine1", "Spine2": "Spine2",
        "Neck": "Neck", "Head": "Head",
        "LeftShoulder": "LeftShoulder", "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
        "RightShoulder": "RightShoulder", "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
        "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToeBase",
        "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToeBase"
    }
