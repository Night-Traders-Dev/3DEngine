gc_disable()
# ability_system.sage — Gameplay Ability System (GAS-like)
# Tag-based ability activation, cooldowns, costs, effects, stacking.
# Supports: active/passive abilities, attribute modifiers, gameplay tags,
# effect duration, periodic ticks, stacking rules.

import math

proc create_ability_system():
    return {
        "abilities": {},
        "active_effects": [],
        "tags": {},              # Active gameplay tags
        "attributes": {},        # Base stats (health, mana, etc.)
        "modifiers": [],         # Active attribute modifiers
        "cooldowns": {}          # ability_id → remaining cooldown
    }

proc register_ability(sys, id, name, config):
    sys["abilities"][id] = {
        "id": id,
        "name": name,
        "cooldown": config["cooldown"],
        "cost_type": config["cost_type"],
        "cost_amount": config["cost_amount"],
        "cast_time": config["cast_time"],
        "duration": config["duration"],
        "tags_required": config["tags_required"],
        "tags_blocked": config["tags_blocked"],
        "tags_granted": config["tags_granted"],
        "effects": config["effects"],
        "passive": config["passive"]
    }

proc set_attribute(sys, name, base_value):
    sys["attributes"][name] = {"base": base_value, "current": base_value}

proc get_attribute(sys, name):
    if dict_has(sys["attributes"], name):
        return sys["attributes"][name]["current"]
    return 0

proc get_attribute_base(sys, name):
    if dict_has(sys["attributes"], name):
        return sys["attributes"][name]["base"]
    return 0

proc add_tag(sys, tag):
    sys["tags"][tag] = true

proc remove_tag(sys, tag):
    if dict_has(sys["tags"], tag):
        dict_delete(sys["tags"], tag)

proc has_tag(sys, tag):
    return dict_has(sys["tags"], tag)

proc can_activate_ability(sys, ability_id):
    if not dict_has(sys["abilities"], ability_id):
        return false
    let ability = sys["abilities"][ability_id]
    # Check cooldown
    if dict_has(sys["cooldowns"], ability_id):
        if sys["cooldowns"][ability_id] > 0:
            return false
    # Check cost
    if ability["cost_type"] != nil and ability["cost_amount"] > 0:
        if get_attribute(sys, ability["cost_type"]) < ability["cost_amount"]:
            return false
    # Check required tags
    if ability["tags_required"] != nil:
        let i = 0
        while i < len(ability["tags_required"]):
            if not has_tag(sys, ability["tags_required"][i]):
                return false
            i = i + 1
    # Check blocked tags
    if ability["tags_blocked"] != nil:
        let i = 0
        while i < len(ability["tags_blocked"]):
            if has_tag(sys, ability["tags_blocked"][i]):
                return false
            i = i + 1
    return true

proc activate_ability(sys, ability_id, target):
    if not can_activate_ability(sys, ability_id):
        return false
    let ability = sys["abilities"][ability_id]
    # Pay cost
    if ability["cost_type"] != nil and ability["cost_amount"] > 0:
        let attr = sys["attributes"][ability["cost_type"]]
        attr["current"] = attr["current"] - ability["cost_amount"]
    # Start cooldown
    sys["cooldowns"][ability_id] = ability["cooldown"]
    # Grant tags
    if ability["tags_granted"] != nil:
        let i = 0
        while i < len(ability["tags_granted"]):
            add_tag(sys, ability["tags_granted"][i])
            i = i + 1
    # Apply effects
    if ability["effects"] != nil:
        let i = 0
        while i < len(ability["effects"]):
            let effect = ability["effects"][i]
            _apply_effect(sys, effect, target, ability["duration"])
            i = i + 1
    return true

proc _apply_effect(sys, effect, target, duration):
    let active = {
        "effect": effect,
        "target": target,
        "remaining": duration,
        "tick_timer": 0.0,
        "stacks": 1
    }
    # Check stacking
    if dict_has(effect, "stacking"):
        let max_stacks = effect["stacking"]
        let existing = _find_effect(sys, effect["type"], target)
        if existing != nil:
            if existing["stacks"] < max_stacks:
                existing["stacks"] = existing["stacks"] + 1
                existing["remaining"] = duration
            return
    push(sys["active_effects"], active)
    # Immediate effects
    if effect["type"] == "instant_damage":
        _modify_attribute(sys, "health", 0.0 - effect["amount"] * active["stacks"])
    elif effect["type"] == "instant_heal":
        _modify_attribute(sys, "health", effect["amount"] * active["stacks"])
    elif effect["type"] == "attribute_modifier":
        push(sys["modifiers"], {
            "attribute": effect["attribute"],
            "value": effect["value"],
            "operation": effect["operation"],
            "source": effect
        })
        _recalculate_attributes(sys)

proc _find_effect(sys, effect_type, target):
    let i = 0
    while i < len(sys["active_effects"]):
        let e = sys["active_effects"][i]
        if e["effect"]["type"] == effect_type and e["target"] == target:
            return e
        i = i + 1
    return nil

proc _modify_attribute(sys, attr_name, amount):
    if dict_has(sys["attributes"], attr_name):
        sys["attributes"][attr_name]["current"] = sys["attributes"][attr_name]["current"] + amount
        let max_val = sys["attributes"][attr_name]["base"] * 2
        if sys["attributes"][attr_name]["current"] > max_val:
            sys["attributes"][attr_name]["current"] = max_val
        if sys["attributes"][attr_name]["current"] < 0:
            sys["attributes"][attr_name]["current"] = 0

proc _recalculate_attributes(sys):
    let keys = dict_keys(sys["attributes"])
    let ki = 0
    while ki < len(keys):
        let attr = sys["attributes"][keys[ki]]
        attr["current"] = attr["base"]
        ki = ki + 1
    let i = 0
    while i < len(sys["modifiers"]):
        let mod = sys["modifiers"][i]
        if dict_has(sys["attributes"], mod["attribute"]):
            let attr = sys["attributes"][mod["attribute"]]
            if mod["operation"] == "add":
                attr["current"] = attr["current"] + mod["value"]
            elif mod["operation"] == "multiply":
                attr["current"] = attr["current"] * mod["value"]
        i = i + 1

proc update_ability_system(sys, dt):
    # Update cooldowns
    let cd_keys = dict_keys(sys["cooldowns"])
    let i = 0
    while i < len(cd_keys):
        sys["cooldowns"][cd_keys[i]] = sys["cooldowns"][cd_keys[i]] - dt
        if sys["cooldowns"][cd_keys[i]] <= 0:
            dict_delete(sys["cooldowns"], cd_keys[i])
        i = i + 1

    # Update active effects
    let alive = []
    i = 0
    while i < len(sys["active_effects"]):
        let e = sys["active_effects"][i]
        e["remaining"] = e["remaining"] - dt
        # Periodic tick
        if dict_has(e["effect"], "tick_interval") and e["effect"]["tick_interval"] > 0:
            e["tick_timer"] = e["tick_timer"] + dt
            if e["tick_timer"] >= e["effect"]["tick_interval"]:
                e["tick_timer"] = 0.0
                if e["effect"]["type"] == "damage_over_time":
                    _modify_attribute(sys, "health", 0.0 - e["effect"]["tick_amount"] * e["stacks"])
                elif e["effect"]["type"] == "heal_over_time":
                    _modify_attribute(sys, "health", e["effect"]["tick_amount"] * e["stacks"])
        if e["remaining"] > 0:
            push(alive, e)
        else:
            # Remove granted tags and modifiers
            if dict_has(e["effect"], "tags_granted"):
                let ti = 0
                while ti < len(e["effect"]["tags_granted"]):
                    remove_tag(sys, e["effect"]["tags_granted"][ti])
                    ti = ti + 1
    sys["active_effects"] = alive

# ============================================================================
# Preset Abilities
# ============================================================================

proc register_default_abilities(sys):
    register_ability(sys, "fireball", "Fireball", {
        "cooldown": 3.0, "cost_type": "mana", "cost_amount": 20,
        "cast_time": 0.5, "duration": 0.0,
        "tags_required": nil, "tags_blocked": ["silenced", "stunned"],
        "tags_granted": nil, "passive": false,
        "effects": [{"type": "instant_damage", "amount": 40}]
    })
    register_ability(sys, "heal", "Heal", {
        "cooldown": 8.0, "cost_type": "mana", "cost_amount": 30,
        "cast_time": 1.0, "duration": 0.0,
        "tags_required": nil, "tags_blocked": ["silenced"],
        "tags_granted": nil, "passive": false,
        "effects": [{"type": "instant_heal", "amount": 60}]
    })
    register_ability(sys, "shield", "Shield", {
        "cooldown": 15.0, "cost_type": "mana", "cost_amount": 25,
        "cast_time": 0.0, "duration": 8.0,
        "tags_required": nil, "tags_blocked": nil,
        "tags_granted": ["shielded"], "passive": false,
        "effects": [{"type": "attribute_modifier", "attribute": "defense", "value": 20, "operation": "add"}]
    })
    register_ability(sys, "sprint", "Sprint", {
        "cooldown": 10.0, "cost_type": "stamina", "cost_amount": 30,
        "cast_time": 0.0, "duration": 5.0,
        "tags_required": nil, "tags_blocked": ["stunned", "rooted"],
        "tags_granted": ["sprinting"], "passive": false,
        "effects": [{"type": "attribute_modifier", "attribute": "speed", "value": 1.5, "operation": "multiply"}]
    })
    register_ability(sys, "poison", "Poison Strike", {
        "cooldown": 6.0, "cost_type": nil, "cost_amount": 0,
        "cast_time": 0.0, "duration": 6.0,
        "tags_required": nil, "tags_blocked": nil,
        "tags_granted": nil, "passive": false,
        "effects": [
            {"type": "instant_damage", "amount": 10},
            {"type": "damage_over_time", "tick_interval": 1.0, "tick_amount": 5, "stacking": 3}
        ]
    })
