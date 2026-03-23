gc_disable()
# -----------------------------------------
# behavior_tree.sage - Behavior Trees for Sage Engine
# Composable AI decision-making framework
# Node types: sequence, selector, decorator, action, condition
# -----------------------------------------

let BT_SUCCESS = "success"
let BT_FAILURE = "failure"
let BT_RUNNING = "running"

# ============================================================================
# Node constructors
# ============================================================================
proc bt_action(name, action_fn):
    let n = {}
    n["type"] = "action"
    n["name"] = name
    n["fn"] = action_fn
    return n

proc bt_condition(name, condition_fn):
    let n = {}
    n["type"] = "condition"
    n["name"] = name
    n["fn"] = condition_fn
    return n

proc bt_sequence(name, children):
    let n = {}
    n["type"] = "sequence"
    n["name"] = name
    n["children"] = children
    n["running_index"] = 0
    return n

proc bt_selector(name, children):
    let n = {}
    n["type"] = "selector"
    n["name"] = name
    n["children"] = children
    n["running_index"] = 0
    return n

proc bt_inverter(name, child):
    let n = {}
    n["type"] = "inverter"
    n["name"] = name
    n["child"] = child
    return n

proc bt_repeater(name, child, count):
    let n = {}
    n["type"] = "repeater"
    n["name"] = name
    n["child"] = child
    n["max_count"] = count
    n["current_count"] = 0
    return n

proc bt_succeeder(name, child):
    let n = {}
    n["type"] = "succeeder"
    n["name"] = name
    n["child"] = child
    return n

proc bt_wait(name, duration):
    let n = {}
    n["type"] = "wait"
    n["name"] = name
    n["duration"] = duration
    n["elapsed"] = 0.0
    return n

# ============================================================================
# Tick a behavior tree node
# Returns BT_SUCCESS, BT_FAILURE, or BT_RUNNING
# context is a dict with entity data, world, dt, etc.
# ============================================================================
proc bt_tick(node, context):
    let ntype = node["type"]

    if ntype == "action":
        return node["fn"](context)

    if ntype == "condition":
        if node["fn"](context):
            return BT_SUCCESS
        return BT_FAILURE

    if ntype == "sequence":
        let i = node["running_index"]
        while i < len(node["children"]):
            let result = bt_tick(node["children"][i], context)
            if result == BT_RUNNING:
                node["running_index"] = i
                return BT_RUNNING
            if result == BT_FAILURE:
                node["running_index"] = 0
                return BT_FAILURE
            i = i + 1
        node["running_index"] = 0
        return BT_SUCCESS

    if ntype == "selector":
        let i = node["running_index"]
        while i < len(node["children"]):
            let result = bt_tick(node["children"][i], context)
            if result == BT_RUNNING:
                node["running_index"] = i
                return BT_RUNNING
            if result == BT_SUCCESS:
                node["running_index"] = 0
                return BT_SUCCESS
            i = i + 1
        node["running_index"] = 0
        return BT_FAILURE

    if ntype == "inverter":
        let result = bt_tick(node["child"], context)
        if result == BT_SUCCESS:
            return BT_FAILURE
        if result == BT_FAILURE:
            return BT_SUCCESS
        return BT_RUNNING

    if ntype == "repeater":
        let result = bt_tick(node["child"], context)
        if result == BT_RUNNING:
            return BT_RUNNING
        node["current_count"] = node["current_count"] + 1
        if node["max_count"] > 0 and node["current_count"] >= node["max_count"]:
            node["current_count"] = 0
            return BT_SUCCESS
        return BT_RUNNING

    if ntype == "succeeder":
        bt_tick(node["child"], context)
        return BT_SUCCESS

    if ntype == "wait":
        node["elapsed"] = node["elapsed"] + context["dt"]
        if node["elapsed"] >= node["duration"]:
            node["elapsed"] = 0.0
            return BT_SUCCESS
        return BT_RUNNING

    return BT_FAILURE

# ============================================================================
# Reset a behavior tree (clear running state)
# ============================================================================
proc bt_reset(node):
    if dict_has(node, "running_index"):
        node["running_index"] = 0
    if dict_has(node, "current_count"):
        node["current_count"] = 0
    if dict_has(node, "elapsed"):
        node["elapsed"] = 0.0
    if dict_has(node, "children"):
        let i = 0
        while i < len(node["children"]):
            bt_reset(node["children"][i])
            i = i + 1
    if dict_has(node, "child"):
        bt_reset(node["child"])

# ============================================================================
# Behavior Tree Component (for ECS)
# ============================================================================
proc BehaviorTreeComponent(root_node):
    let c = {}
    c["root"] = root_node
    c["context"] = {}
    c["last_result"] = BT_SUCCESS
    c["enabled"] = true
    return c

proc update_behavior_tree(bt_comp, world, entity, dt):
    if bt_comp["enabled"] == false:
        return nil
    bt_comp["context"]["world"] = world
    bt_comp["context"]["entity"] = entity
    bt_comp["context"]["dt"] = dt
    bt_comp["last_result"] = bt_tick(bt_comp["root"], bt_comp["context"])
    return bt_comp["last_result"]

# ============================================================================
# Common AI action builders
# ============================================================================
proc bt_action_move_to(target_key, speed_key):
    proc move_to_fn(ctx):
        from math3d import v3_sub, v3_length, v3_normalize, v3_scale, v3_add
        from ecs import get_component
        let world = ctx["world"]
        let entity = ctx["entity"]
        let t = get_component(world, entity, "transform")
        if t == nil:
            return BT_FAILURE
        if dict_has(ctx, target_key) == false:
            return BT_FAILURE
        let target = ctx[target_key]
        let speed = 3.0
        if dict_has(ctx, speed_key):
            speed = ctx[speed_key]
        let to_target = v3_sub(target, t["position"])
        let dist = v3_length(to_target)
        if dist < 0.5:
            return BT_SUCCESS
        let dir = v3_normalize(to_target)
        let move = v3_scale(dir, speed * ctx["dt"])
        t["position"] = v3_add(t["position"], move)
        t["dirty"] = true
        return BT_RUNNING
    return bt_action("move_to_" + target_key, move_to_fn)

proc bt_condition_in_range(target_key, range):
    proc range_check(ctx):
        from math3d import v3_sub, v3_length
        from ecs import get_component
        let t = get_component(ctx["world"], ctx["entity"], "transform")
        if t == nil:
            return false
        if dict_has(ctx, target_key) == false:
            return false
        let dist = v3_length(v3_sub(t["position"], ctx[target_key]))
        return dist <= range
    return bt_condition("in_range_" + str(range), range_check)

proc bt_condition_health_above(threshold):
    proc health_check(ctx):
        from ecs import get_component, has_component
        if has_component(ctx["world"], ctx["entity"], "health") == false:
            return false
        let h = get_component(ctx["world"], ctx["entity"], "health")
        return h["current"] / h["max"] > threshold
    return bt_condition("health_above_" + str(threshold), health_check)
