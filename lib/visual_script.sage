gc_disable()
# visual_script.sage — Visual Scripting / Blueprint System
# Node-graph based programming without writing code.
# Supports: event nodes, flow control, variables, math, entity operations,
# custom function nodes, execution pins, data pins.
#
# Usage:
#   let graph = create_visual_graph("PlayerLogic")
#   let on_tick = add_event_node(graph, "on_tick")
#   let get_hp = add_get_var_node(graph, "health")
#   let branch = add_branch_node(graph)
#   let print_n = add_action_node(graph, "print", ["text"])
#   connect_exec(graph, on_tick, branch)
#   connect_data(graph, get_hp, "value", branch, "condition")
#   execute_graph(graph, context)

# ============================================================================
# Node Types
# ============================================================================

let VS_EVENT = "event"
let VS_ACTION = "action"
let VS_BRANCH = "branch"
let VS_LOOP = "loop"
let VS_GET_VAR = "get_variable"
let VS_SET_VAR = "set_variable"
let VS_MATH = "math"
let VS_COMPARE = "compare"
let VS_SEQUENCE = "sequence"
let VS_CUSTOM = "custom_function"
let VS_SPAWN = "spawn_entity"
let VS_DESTROY = "destroy_entity"
let VS_GET_COMPONENT = "get_component"
let VS_SET_COMPONENT = "set_component"
let VS_DELAY = "delay"
let VS_FOR_EACH = "for_each"
let VS_SWITCH = "switch"
let VS_CAST = "cast"

# ============================================================================
# Visual Graph
# ============================================================================

proc create_visual_graph(name):
    return {
        "name": name,
        "nodes": {},
        "connections_exec": [],    # Execution flow connections
        "connections_data": [],    # Data wire connections
        "variables": {},           # Graph-level variables
        "next_id": 1,
        "entry_points": []         # Event nodes that start execution
    }

proc _new_node_id(graph):
    let id = graph["next_id"]
    graph["next_id"] = id + 1
    return "n" + str(id)

# ============================================================================
# Node Creation
# ============================================================================

proc add_event_node(graph, event_name):
    let id = _new_node_id(graph)
    graph["nodes"][id] = {
        "id": id, "type": VS_EVENT, "event": event_name,
        "exec_out": nil, "data_out": {}, "position": [0, 0]
    }
    push(graph["entry_points"], id)
    return id

proc add_action_node(graph, action_name, param_names):
    let id = _new_node_id(graph)
    let params = {}
    let i = 0
    while i < len(param_names):
        params[param_names[i]] = nil
        i = i + 1
    graph["nodes"][id] = {
        "id": id, "type": VS_ACTION, "action": action_name,
        "exec_in": nil, "exec_out": nil, "data_in": params, "data_out": {},
        "position": [0, 0]
    }
    return id

proc add_branch_node(graph):
    let id = _new_node_id(graph)
    graph["nodes"][id] = {
        "id": id, "type": VS_BRANCH,
        "exec_in": nil, "exec_true": nil, "exec_false": nil,
        "data_in": {"condition": nil}, "position": [0, 0]
    }
    return id

proc add_loop_node(graph, count_or_array):
    let id = _new_node_id(graph)
    graph["nodes"][id] = {
        "id": id, "type": VS_LOOP,
        "exec_in": nil, "exec_body": nil, "exec_done": nil,
        "data_in": {"count": count_or_array},
        "data_out": {"index": nil, "element": nil},
        "position": [0, 0]
    }
    return id

proc add_get_var_node(graph, var_name):
    let id = _new_node_id(graph)
    graph["nodes"][id] = {
        "id": id, "type": VS_GET_VAR, "var_name": var_name,
        "data_out": {"value": nil}, "position": [0, 0]
    }
    return id

proc add_set_var_node(graph, var_name):
    let id = _new_node_id(graph)
    graph["nodes"][id] = {
        "id": id, "type": VS_SET_VAR, "var_name": var_name,
        "exec_in": nil, "exec_out": nil,
        "data_in": {"value": nil}, "position": [0, 0]
    }
    return id

proc add_math_node(graph, operation):
    let id = _new_node_id(graph)
    graph["nodes"][id] = {
        "id": id, "type": VS_MATH, "operation": operation,
        "data_in": {"a": nil, "b": nil},
        "data_out": {"result": nil}, "position": [0, 0]
    }
    return id

proc add_compare_node(graph, operation):
    let id = _new_node_id(graph)
    graph["nodes"][id] = {
        "id": id, "type": VS_COMPARE, "operation": operation,
        "data_in": {"a": nil, "b": nil},
        "data_out": {"result": nil}, "position": [0, 0]
    }
    return id

proc add_sequence_node(graph, output_count):
    let id = _new_node_id(graph)
    let outputs = []
    let i = 0
    while i < output_count:
        push(outputs, nil)
        i = i + 1
    graph["nodes"][id] = {
        "id": id, "type": VS_SEQUENCE,
        "exec_in": nil, "exec_outputs": outputs,
        "position": [0, 0]
    }
    return id

proc add_delay_node(graph, seconds):
    let id = _new_node_id(graph)
    graph["nodes"][id] = {
        "id": id, "type": VS_DELAY, "duration": seconds,
        "exec_in": nil, "exec_out": nil,
        "elapsed": 0.0, "waiting": false, "position": [0, 0]
    }
    return id

proc add_custom_function_node(graph, func_name, func_ref, input_names, output_names):
    let id = _new_node_id(graph)
    let inputs = {}
    let i = 0
    while i < len(input_names):
        inputs[input_names[i]] = nil
        i = i + 1
    let outputs = {}
    i = 0
    while i < len(output_names):
        outputs[output_names[i]] = nil
        i = i + 1
    graph["nodes"][id] = {
        "id": id, "type": VS_CUSTOM, "func_name": func_name, "func": func_ref,
        "exec_in": nil, "exec_out": nil,
        "data_in": inputs, "data_out": outputs, "position": [0, 0]
    }
    return id

# ============================================================================
# Connections
# ============================================================================

proc connect_exec(graph, from_node, to_node):
    push(graph["connections_exec"], {"from": from_node, "to": to_node, "pin": "exec_out"})
    if dict_has(graph["nodes"][from_node], "exec_out"):
        graph["nodes"][from_node]["exec_out"] = to_node

proc connect_exec_pin(graph, from_node, pin_name, to_node):
    push(graph["connections_exec"], {"from": from_node, "to": to_node, "pin": pin_name})
    graph["nodes"][from_node][pin_name] = to_node

proc connect_data(graph, from_node, from_pin, to_node, to_pin):
    push(graph["connections_data"], {
        "from_node": from_node, "from_pin": from_pin,
        "to_node": to_node, "to_pin": to_pin
    })

# ============================================================================
# Variables
# ============================================================================

proc set_graph_variable(graph, name, value):
    graph["variables"][name] = value

proc get_graph_variable(graph, name):
    if dict_has(graph["variables"], name):
        return graph["variables"][name]
    return nil

# ============================================================================
# Execution Engine
# ============================================================================

proc execute_graph(graph, context):
    # context: {"dt": delta_time, "entity": entity_id, "world": ecs_world, ...}
    let i = 0
    while i < len(graph["entry_points"]):
        let entry = graph["entry_points"][i]
        let node = graph["nodes"][entry]
        # Check if this event matches
        if node["type"] == VS_EVENT:
            if node["event"] == "on_tick" or node["event"] == context["event"]:
                _execute_from(graph, node["exec_out"], context)
        i = i + 1

proc _resolve_data(graph, node_id, pin_name, context):
    # Find data connection targeting this pin
    let i = 0
    while i < len(graph["connections_data"]):
        let conn = graph["connections_data"][i]
        if conn["to_node"] == node_id and conn["to_pin"] == pin_name:
            let source_node = graph["nodes"][conn["from_node"]]
            return _evaluate_data_node(graph, source_node, conn["from_pin"], context)
        i = i + 1
    # No connection — check if there's a literal value
    let node = graph["nodes"][node_id]
    if dict_has(node, "data_in") and dict_has(node["data_in"], pin_name):
        return node["data_in"][pin_name]
    return nil

proc _evaluate_data_node(graph, node, pin, context):
    if node["type"] == VS_GET_VAR:
        return get_graph_variable(graph, node["var_name"])
    if node["type"] == VS_MATH:
        let a = _resolve_data(graph, node["id"], "a", context)
        let b = _resolve_data(graph, node["id"], "b", context)
        if a == nil:
            a = 0
        if b == nil:
            b = 0
        if node["operation"] == "add":
            return a + b
        if node["operation"] == "sub":
            return a - b
        if node["operation"] == "mul":
            return a * b
        if node["operation"] == "div" and b != 0:
            return a / b
        if node["operation"] == "mod" and b != 0:
            return a % b
        return 0
    if node["type"] == VS_COMPARE:
        let a = _resolve_data(graph, node["id"], "a", context)
        let b = _resolve_data(graph, node["id"], "b", context)
        if node["operation"] == "equal":
            return a == b
        if node["operation"] == "not_equal":
            return a != b
        if node["operation"] == "greater":
            return a > b
        if node["operation"] == "less":
            return a < b
        if node["operation"] == "greater_equal":
            return a >= b
        if node["operation"] == "less_equal":
            return a <= b
        return false
    if node["type"] == VS_CUSTOM:
        # Evaluate inputs and call function
        let inputs = {}
        let keys = dict_keys(node["data_in"])
        let ki = 0
        while ki < len(keys):
            inputs[keys[ki]] = _resolve_data(graph, node["id"], keys[ki], context)
            ki = ki + 1
        if node["func"] != nil:
            let result = node["func"](inputs, context)
            if dict_has(result, pin):
                return result[pin]
        return nil
    return nil

proc _execute_from(graph, node_id, context):
    if node_id == nil:
        return
    if not dict_has(graph["nodes"], node_id):
        return
    let node = graph["nodes"][node_id]

    if node["type"] == VS_ACTION:
        # Resolve all data inputs
        let resolved = {}
        if dict_has(node, "data_in"):
            let keys = dict_keys(node["data_in"])
            let ki = 0
            while ki < len(keys):
                resolved[keys[ki]] = _resolve_data(graph, node_id, keys[ki], context)
                ki = ki + 1
        # Execute action
        _execute_action(node["action"], resolved, context)
        # Continue execution flow
        if dict_has(node, "exec_out"):
            _execute_from(graph, node["exec_out"], context)

    elif node["type"] == VS_SET_VAR:
        let val = _resolve_data(graph, node_id, "value", context)
        set_graph_variable(graph, node["var_name"], val)
        if dict_has(node, "exec_out"):
            _execute_from(graph, node["exec_out"], context)

    elif node["type"] == VS_BRANCH:
        let cond = _resolve_data(graph, node_id, "condition", context)
        if cond:
            _execute_from(graph, node["exec_true"], context)
        else:
            _execute_from(graph, node["exec_false"], context)

    elif node["type"] == VS_LOOP:
        let count = _resolve_data(graph, node_id, "count", context)
        if count == nil:
            count = 0
        if type(count) == "number":
            let li = 0
            while li < count:
                node["data_out"]["index"] = li
                _execute_from(graph, node["exec_body"], context)
                li = li + 1
        elif type(count) == "array":
            let li = 0
            while li < len(count):
                node["data_out"]["index"] = li
                node["data_out"]["element"] = count[li]
                _execute_from(graph, node["exec_body"], context)
                li = li + 1
        if dict_has(node, "exec_done"):
            _execute_from(graph, node["exec_done"], context)

    elif node["type"] == VS_SEQUENCE:
        let oi = 0
        while oi < len(node["exec_outputs"]):
            _execute_from(graph, node["exec_outputs"][oi], context)
            oi = oi + 1

    elif node["type"] == VS_CUSTOM:
        let inputs = {}
        if dict_has(node, "data_in"):
            let keys = dict_keys(node["data_in"])
            let ki = 0
            while ki < len(keys):
                inputs[keys[ki]] = _resolve_data(graph, node_id, keys[ki], context)
                ki = ki + 1
        if node["func"] != nil:
            let result = node["func"](inputs, context)
            if dict_has(node, "data_out"):
                let out_keys = dict_keys(node["data_out"])
                let ok = 0
                while ok < len(out_keys):
                    if dict_has(result, out_keys[ok]):
                        node["data_out"][out_keys[ok]] = result[out_keys[ok]]
                    ok = ok + 1
        if dict_has(node, "exec_out"):
            _execute_from(graph, node["exec_out"], context)

proc _execute_action(action_name, params, context):
    if action_name == "print":
        if dict_has(params, "text"):
            print str(params["text"])
    elif action_name == "set_position":
        if dict_has(context, "entity") and dict_has(params, "position"):
            # Would set entity transform position
            pass
    elif action_name == "spawn":
        pass
    elif action_name == "destroy":
        pass
    elif action_name == "play_sound":
        pass
    elif action_name == "apply_damage":
        pass
    elif action_name == "heal":
        pass
    elif action_name == "add_force":
        pass

# ============================================================================
# Graph Serialization
# ============================================================================

proc serialize_graph(graph):
    return {
        "name": graph["name"],
        "nodes": graph["nodes"],
        "connections_exec": graph["connections_exec"],
        "connections_data": graph["connections_data"],
        "variables": graph["variables"],
        "entry_points": graph["entry_points"]
    }

proc graph_node_count(graph):
    return len(dict_keys(graph["nodes"]))

proc graph_connection_count(graph):
    return len(graph["connections_exec"]) + len(graph["connections_data"])
