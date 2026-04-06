gc_disable()
# inventory.sage — General-purpose inventory system
# Supports: items with stacks, equipment slots, drag-drop, weight limits,
# item categories, crafting recipes, and loot tables.
#
# Usage:
#   let inv = create_inventory(36)         # 36-slot backpack
#   add_item(inv, "sword", 1)
#   add_item(inv, "potion", 5)
#   let removed = remove_item(inv, "potion", 2)
#   let count = item_count(inv, "sword")

# ============================================================================
# Item Database — define items with properties
# ============================================================================

let _item_db = {}

proc register_item(id, name, category, max_stack, weight, properties):
    let item = {}
    item["id"] = id
    item["name"] = name
    item["category"] = category
    item["max_stack"] = max_stack
    item["weight"] = weight
    item["properties"] = properties
    _item_db[id] = item

proc get_item_def(id):
    if dict_has(_item_db, id):
        return _item_db[id]
    return nil

proc register_default_items():
    # Weapons
    register_item("sword", "Iron Sword", "weapon", 1, 3.0, {"damage": 10, "speed": 1.2})
    register_item("bow", "Wooden Bow", "weapon", 1, 2.0, {"damage": 7, "speed": 0.8, "range": 30})
    register_item("axe", "Steel Axe", "weapon", 1, 4.0, {"damage": 12, "speed": 0.9})
    register_item("staff", "Magic Staff", "weapon", 1, 2.5, {"damage": 15, "speed": 1.0, "mana_cost": 5})

    # Armor
    register_item("helmet", "Iron Helmet", "armor", 1, 2.0, {"defense": 3, "slot": "head"})
    register_item("chest", "Chain Mail", "armor", 1, 5.0, {"defense": 8, "slot": "chest"})
    register_item("boots", "Leather Boots", "armor", 1, 1.5, {"defense": 2, "slot": "feet"})
    register_item("shield", "Wooden Shield", "armor", 1, 3.0, {"defense": 5, "slot": "offhand"})

    # Consumables
    register_item("potion_hp", "Health Potion", "consumable", 10, 0.5, {"heal": 50})
    register_item("potion_mp", "Mana Potion", "consumable", 10, 0.5, {"restore_mana": 30})
    register_item("food", "Bread", "consumable", 20, 0.2, {"heal": 10, "hunger": 25})
    register_item("water", "Water Flask", "consumable", 5, 0.8, {"thirst": 40})

    # Resources
    register_item("wood", "Wood", "resource", 64, 1.0, {})
    register_item("stone", "Stone", "resource", 64, 2.0, {})
    register_item("iron", "Iron Ore", "resource", 32, 3.0, {})
    register_item("gold", "Gold Ore", "resource", 16, 4.0, {})
    register_item("gem", "Crystal Gem", "resource", 8, 0.5, {"value": 100})

    # Ammo
    register_item("arrow", "Arrow", "ammo", 64, 0.1, {"damage": 3})
    register_item("bolt", "Crossbow Bolt", "ammo", 32, 0.2, {"damage": 5})

    # Keys / Quest items
    register_item("key_gold", "Golden Key", "quest", 1, 0.1, {"opens": "gold_door"})
    register_item("map", "Treasure Map", "quest", 1, 0.1, {"reveals": "treasure_location"})

# ============================================================================
# Inventory — slot-based storage with stacks
# ============================================================================

proc create_inventory(size):
    let inv = {}
    inv["size"] = size
    inv["slots"] = []
    inv["weight_limit"] = 100.0
    inv["current_weight"] = 0.0
    let i = 0
    while i < size:
        push(inv["slots"], nil)
        i = i + 1
    return inv

proc add_item(inv, item_id, count):
    if count <= 0:
        return 0
    let def = get_item_def(item_id)
    let max_stack = 64
    if def != nil:
        max_stack = def["max_stack"]

    let remaining = count
    # First try to stack with existing slots
    let i = 0
    while i < inv["size"] and remaining > 0:
        let slot = inv["slots"][i]
        if slot != nil and slot["id"] == item_id:
            let space = max_stack - slot["count"]
            if space > 0:
                let to_add = remaining
                if to_add > space:
                    to_add = space
                slot["count"] = slot["count"] + to_add
                remaining = remaining - to_add
        i = i + 1

    # Then fill empty slots
    i = 0
    while i < inv["size"] and remaining > 0:
        if inv["slots"][i] == nil:
            let to_add = remaining
            if to_add > max_stack:
                to_add = max_stack
            inv["slots"][i] = {"id": item_id, "count": to_add}
            remaining = remaining - to_add
        i = i + 1

    return count - remaining

proc remove_item(inv, item_id, count):
    let remaining = count
    let i = inv["size"] - 1
    while i >= 0 and remaining > 0:
        let slot = inv["slots"][i]
        if slot != nil and slot["id"] == item_id:
            let to_remove = remaining
            if to_remove > slot["count"]:
                to_remove = slot["count"]
            slot["count"] = slot["count"] - to_remove
            remaining = remaining - to_remove
            if slot["count"] <= 0:
                inv["slots"][i] = nil
        i = i - 1
    return count - remaining

proc item_count(inv, item_id):
    let total = 0
    let i = 0
    while i < inv["size"]:
        let slot = inv["slots"][i]
        if slot != nil and slot["id"] == item_id:
            total = total + slot["count"]
        i = i + 1
    return total

proc has_item(inv, item_id, count):
    return item_count(inv, item_id) >= count

proc get_slot(inv, index):
    if index >= 0 and index < inv["size"]:
        return inv["slots"][index]
    return nil

proc set_slot(inv, index, item_id, count):
    if index >= 0 and index < inv["size"]:
        if item_id == nil or count <= 0:
            inv["slots"][index] = nil
        else:
            inv["slots"][index] = {"id": item_id, "count": count}

proc swap_slots(inv, from_idx, to_idx):
    if from_idx >= 0 and from_idx < inv["size"] and to_idx >= 0 and to_idx < inv["size"]:
        let temp = inv["slots"][from_idx]
        inv["slots"][from_idx] = inv["slots"][to_idx]
        inv["slots"][to_idx] = temp

proc clear_inventory(inv):
    let i = 0
    while i < inv["size"]:
        inv["slots"][i] = nil
        i = i + 1

proc inventory_used_slots(inv):
    let count = 0
    let i = 0
    while i < inv["size"]:
        if inv["slots"][i] != nil:
            count = count + 1
        i = i + 1
    return count

proc inventory_total_weight(inv):
    let weight = 0.0
    let i = 0
    while i < inv["size"]:
        let slot = inv["slots"][i]
        if slot != nil:
            let def = get_item_def(slot["id"])
            if def != nil:
                weight = weight + def["weight"] * slot["count"]
        i = i + 1
    return weight

# ============================================================================
# Equipment Slots
# ============================================================================

proc create_equipment():
    return {
        "head": nil,
        "chest": nil,
        "legs": nil,
        "feet": nil,
        "mainhand": nil,
        "offhand": nil,
        "ring1": nil,
        "ring2": nil,
        "amulet": nil
    }

proc equip_item(equipment, slot_name, item_id):
    let prev = equipment[slot_name]
    equipment[slot_name] = item_id
    return prev

proc unequip_item(equipment, slot_name):
    let prev = equipment[slot_name]
    equipment[slot_name] = nil
    return prev

proc equipment_defense(equipment):
    let total = 0
    let keys = dict_keys(equipment)
    let i = 0
    while i < len(keys):
        let item_id = equipment[keys[i]]
        if item_id != nil:
            let def = get_item_def(item_id)
            if def != nil and dict_has(def["properties"], "defense"):
                total = total + def["properties"]["defense"]
        i = i + 1
    return total

proc equipment_damage(equipment):
    let weapon = equipment["mainhand"]
    if weapon != nil:
        let def = get_item_def(weapon)
        if def != nil and dict_has(def["properties"], "damage"):
            return def["properties"]["damage"]
    return 1

# ============================================================================
# Crafting Recipes
# ============================================================================

let _recipes = []

proc register_recipe(name, inputs, output_id, output_count):
    push(_recipes, {"name": name, "inputs": inputs, "output_id": output_id, "output_count": output_count})

proc register_default_recipes():
    register_recipe("Wooden Sword", [["wood", 3]], "sword", 1)
    register_recipe("Arrows (10)", [["wood", 1], ["stone", 1]], "arrow", 10)
    register_recipe("Health Potion", [["gem", 1], ["water", 1]], "potion_hp", 1)
    register_recipe("Shield", [["wood", 2], ["iron", 1]], "shield", 1)
    register_recipe("Chain Mail", [["iron", 5]], "chest", 1)
    register_recipe("Bread (5)", [["wood", 1]], "food", 5)

proc available_recipes(inv):
    let available = []
    let ri = 0
    while ri < len(_recipes):
        let recipe = _recipes[ri]
        let can_craft = true
        let ii = 0
        while ii < len(recipe["inputs"]):
            let input = recipe["inputs"][ii]
            if not has_item(inv, input[0], input[1]):
                can_craft = false
            ii = ii + 1
        if can_craft:
            push(available, recipe)
        ri = ri + 1
    return available

proc craft_recipe(inv, recipe):
    # Consume inputs
    let ii = 0
    while ii < len(recipe["inputs"]):
        let input = recipe["inputs"][ii]
        remove_item(inv, input[0], input[1])
        ii = ii + 1
    # Add output
    return add_item(inv, recipe["output_id"], recipe["output_count"])

# ============================================================================
# Loot Tables — weighted random drops
# ============================================================================

import math

proc create_loot_table(entries):
    # entries: [{"id": item_id, "count": N, "weight": W}, ...]
    return entries

proc roll_loot(table, rolls):
    let loot = []
    let total_weight = 0
    let i = 0
    while i < len(table):
        total_weight = total_weight + table[i]["weight"]
        i = i + 1

    let r = 0
    while r < rolls:
        let roll = math.random() * total_weight
        let cumulative = 0
        i = 0
        while i < len(table):
            cumulative = cumulative + table[i]["weight"]
            if roll <= cumulative:
                push(loot, {"id": table[i]["id"], "count": table[i]["count"]})
                break
            i = i + 1
        r = r + 1
    return loot
