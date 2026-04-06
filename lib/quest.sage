gc_disable()
# quest.sage — Quest and Dialog System
# Supports: quest chains, objectives, rewards, dialog trees, NPC interactions
#
# Usage:
#   let qm = create_quest_manager()
#   register_quest(qm, "find_sword", "Find the Lost Sword", [
#       objective("collect", "sword", 1, "Find the sword"),
#       objective("talk", "blacksmith", 1, "Return to the blacksmith")
#   ], [{"id": "gold", "count": 50}])
#
#   start_quest(qm, "find_sword")
#   advance_objective(qm, "find_sword", "collect", "sword", 1)

# ============================================================================
# Quest States
# ============================================================================

let QUEST_INACTIVE = 0
let QUEST_ACTIVE = 1
let QUEST_COMPLETE = 2
let QUEST_FAILED = 3
let QUEST_TURNED_IN = 4

# ============================================================================
# Objective Types
# ============================================================================

proc objective(obj_type, target, required, description):
    return {
        "type": obj_type,        # "collect", "kill", "talk", "reach", "defend", "escort"
        "target": target,         # Item ID, NPC name, location name, etc.
        "required": required,     # How many needed
        "current": 0,
        "description": description,
        "complete": false
    }

# ============================================================================
# Quest Manager
# ============================================================================

proc create_quest_manager():
    return {
        "quests": {},
        "active": [],
        "completed": [],
        "failed": [],
        "journal": []
    }

proc register_quest(qm, quest_id, name, objectives, rewards):
    qm["quests"][quest_id] = {
        "id": quest_id,
        "name": name,
        "objectives": objectives,
        "rewards": rewards,
        "state": QUEST_INACTIVE,
        "prereqs": [],
        "description": name
    }

proc register_quest_chain(qm, quest_id, name, objectives, rewards, prereqs, description):
    qm["quests"][quest_id] = {
        "id": quest_id,
        "name": name,
        "objectives": objectives,
        "rewards": rewards,
        "state": QUEST_INACTIVE,
        "prereqs": prereqs,
        "description": description
    }

proc start_quest(qm, quest_id):
    if not dict_has(qm["quests"], quest_id):
        return false
    let quest = qm["quests"][quest_id]
    if quest["state"] != QUEST_INACTIVE:
        return false
    # Check prerequisites
    let pi = 0
    while pi < len(quest["prereqs"]):
        let prereq = quest["prereqs"][pi]
        if not dict_has(qm["quests"], prereq):
            return false
        if qm["quests"][prereq]["state"] != QUEST_TURNED_IN:
            return false
        pi = pi + 1
    quest["state"] = QUEST_ACTIVE
    push(qm["active"], quest_id)
    push(qm["journal"], {"type": "started", "quest": quest_id, "name": quest["name"]})
    return true

proc advance_objective(qm, quest_id, obj_type, target, amount):
    if not dict_has(qm["quests"], quest_id):
        return false
    let quest = qm["quests"][quest_id]
    if quest["state"] != QUEST_ACTIVE:
        return false
    let advanced = false
    let oi = 0
    while oi < len(quest["objectives"]):
        let obj = quest["objectives"][oi]
        if obj["type"] == obj_type and obj["target"] == target and not obj["complete"]:
            obj["current"] = obj["current"] + amount
            if obj["current"] >= obj["required"]:
                obj["current"] = obj["required"]
                obj["complete"] = true
            advanced = true
        oi = oi + 1
    # Check if all objectives complete
    if advanced:
        let all_complete = true
        oi = 0
        while oi < len(quest["objectives"]):
            if not quest["objectives"][oi]["complete"]:
                all_complete = false
            oi = oi + 1
        if all_complete:
            quest["state"] = QUEST_COMPLETE
            push(qm["journal"], {"type": "completed", "quest": quest_id, "name": quest["name"]})
    return advanced

proc turn_in_quest(qm, quest_id):
    if not dict_has(qm["quests"], quest_id):
        return nil
    let quest = qm["quests"][quest_id]
    if quest["state"] != QUEST_COMPLETE:
        return nil
    quest["state"] = QUEST_TURNED_IN
    # Remove from active, add to completed
    let new_active = []
    let ai = 0
    while ai < len(qm["active"]):
        if qm["active"][ai] != quest_id:
            push(new_active, qm["active"][ai])
        ai = ai + 1
    qm["active"] = new_active
    push(qm["completed"], quest_id)
    push(qm["journal"], {"type": "turned_in", "quest": quest_id, "name": quest["name"]})
    return quest["rewards"]

proc fail_quest(qm, quest_id):
    if not dict_has(qm["quests"], quest_id):
        return false
    let quest = qm["quests"][quest_id]
    quest["state"] = QUEST_FAILED
    push(qm["failed"], quest_id)
    push(qm["journal"], {"type": "failed", "quest": quest_id, "name": quest["name"]})
    return true

proc quest_state(qm, quest_id):
    if dict_has(qm["quests"], quest_id):
        return qm["quests"][quest_id]["state"]
    return QUEST_INACTIVE

proc active_quests(qm):
    return qm["active"]

proc quest_progress(qm, quest_id):
    if not dict_has(qm["quests"], quest_id):
        return nil
    let quest = qm["quests"][quest_id]
    let done = 0
    let total = len(quest["objectives"])
    let oi = 0
    while oi < total:
        if quest["objectives"][oi]["complete"]:
            done = done + 1
        oi = oi + 1
    return {"done": done, "total": total, "percent": done * 100 / total}

# ============================================================================
# Dialog System — branching conversations with conditions
# ============================================================================

proc create_dialog_tree(npc_name):
    return {
        "npc": npc_name,
        "nodes": {},
        "start": "root",
        "current": nil,
        "history": []
    }

proc add_dialog_node(tree, node_id, text, choices):
    # choices: [{"text": "option text", "next": "node_id", "action": nil_or_proc}]
    tree["nodes"][node_id] = {
        "id": node_id,
        "text": text,
        "choices": choices
    }

proc start_dialog(tree):
    tree["current"] = tree["start"]
    tree["history"] = []
    return get_current_dialog(tree)

proc get_current_dialog(tree):
    if tree["current"] == nil:
        return nil
    if dict_has(tree["nodes"], tree["current"]):
        return tree["nodes"][tree["current"]]
    return nil

proc choose_dialog(tree, choice_index):
    let node = get_current_dialog(tree)
    if node == nil:
        return nil
    if choice_index < 0 or choice_index >= len(node["choices"]):
        return nil
    let choice = node["choices"][choice_index]
    push(tree["history"], {"node": tree["current"], "choice": choice_index})

    # Execute action if present
    if dict_has(choice, "action") and choice["action"] != nil:
        choice["action"]()

    # Advance to next node
    if dict_has(choice, "next") and choice["next"] != nil:
        tree["current"] = choice["next"]
        return get_current_dialog(tree)
    # End of dialog
    tree["current"] = nil
    return nil

proc is_dialog_active(tree):
    return tree["current"] != nil

# ============================================================================
# Character Stats — RPG-style stat system
# ============================================================================

proc create_character_stats(name, level):
    return {
        "name": name,
        "level": level,
        "xp": 0,
        "xp_to_next": level * 100,
        "hp": 100,
        "hp_max": 100,
        "mp": 50,
        "mp_max": 50,
        "stamina": 100,
        "stamina_max": 100,
        "strength": 10,
        "dexterity": 10,
        "intelligence": 10,
        "vitality": 10,
        "defense": 5,
        "speed": 1.0,
        "critical_chance": 0.05,
        "status_effects": []
    }

proc add_xp(stats, amount):
    stats["xp"] = stats["xp"] + amount
    let leveled = false
    while stats["xp"] >= stats["xp_to_next"]:
        stats["xp"] = stats["xp"] - stats["xp_to_next"]
        stats["level"] = stats["level"] + 1
        stats["xp_to_next"] = stats["level"] * 100
        stats["hp_max"] = stats["hp_max"] + 10
        stats["mp_max"] = stats["mp_max"] + 5
        stats["hp"] = stats["hp_max"]
        stats["mp"] = stats["mp_max"]
        leveled = true
    return leveled

proc take_damage(stats, amount, defense_bonus):
    let reduced = amount - stats["defense"] - defense_bonus
    if reduced < 1:
        reduced = 1
    stats["hp"] = stats["hp"] - reduced
    if stats["hp"] < 0:
        stats["hp"] = 0
    return reduced

proc heal(stats, amount):
    stats["hp"] = stats["hp"] + amount
    if stats["hp"] > stats["hp_max"]:
        stats["hp"] = stats["hp_max"]

proc is_alive(stats):
    return stats["hp"] > 0

proc use_mana(stats, cost):
    if stats["mp"] >= cost:
        stats["mp"] = stats["mp"] - cost
        return true
    return false

proc use_stamina(stats, cost):
    if stats["stamina"] >= cost:
        stats["stamina"] = stats["stamina"] - cost
        return true
    return false

proc regen_stamina(stats, dt):
    stats["stamina"] = stats["stamina"] + 20.0 * dt
    if stats["stamina"] > stats["stamina_max"]:
        stats["stamina"] = stats["stamina_max"]
