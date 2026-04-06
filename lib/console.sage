gc_disable()
# console.sage — Developer Console / Command System
# In-game command line for debugging, tweaking, and cheats.

proc create_console():
    return {
        "commands": {},
        "history": [],
        "output": [],
        "max_output": 100,
        "max_history": 50,
        "visible": false,
        "input_buffer": "",
        "history_index": -1,
        "aliases": {}
    }

proc register_command(con, name, description, handler):
    con["commands"][name] = {"name": name, "desc": description, "handler": handler}

proc register_alias(con, alias_name, command_string):
    con["aliases"][alias_name] = command_string

proc execute_command(con, input_str):
    push(con["history"], input_str)
    if len(con["history"]) > con["max_history"]:
        let trimmed = []
        let i = 1
        while i < len(con["history"]):
            push(trimmed, con["history"][i])
            i = i + 1
        con["history"] = trimmed
    # Check alias
    if dict_has(con["aliases"], input_str):
        input_str = con["aliases"][input_str]
    # Parse command and args
    let parts = split(input_str, " ")
    if len(parts) == 0:
        return
    let cmd_name = parts[0]
    let args = []
    let i = 1
    while i < len(parts):
        push(args, parts[i])
        i = i + 1
    if cmd_name == "help":
        _show_help(con)
        return
    if dict_has(con["commands"], cmd_name):
        let result = con["commands"][cmd_name]["handler"](args)
        if result != nil:
            console_print(con, str(result))
    else:
        console_print(con, "Unknown command: " + cmd_name)

proc _show_help(con):
    console_print(con, "=== Available Commands ===")
    let keys = dict_keys(con["commands"])
    let i = 0
    while i < len(keys):
        let cmd = con["commands"][keys[i]]
        console_print(con, "  " + cmd["name"] + " — " + cmd["desc"])
        i = i + 1

proc console_print(con, text):
    push(con["output"], text)
    if len(con["output"]) > con["max_output"]:
        let trimmed = []
        let i = 1
        while i < len(con["output"]):
            push(trimmed, con["output"][i])
            i = i + 1
        con["output"] = trimmed

proc toggle_console(con):
    con["visible"] = not con["visible"]

proc is_console_visible(con):
    return con["visible"]

proc get_console_output(con):
    return con["output"]

proc clear_console(con):
    con["output"] = []

proc register_default_commands(con):
    register_command(con, "help", "Show all commands", proc(args): return nil)
    register_command(con, "clear", "Clear console output", proc(args): clear_console(con))
    register_command(con, "echo", "Print text", proc(args): return join(args, " "))
    register_command(con, "quit", "Exit game", proc(args): return "QUIT")
    register_command(con, "god", "Toggle god mode", proc(args): return "God mode toggled")
    register_command(con, "noclip", "Toggle noclip", proc(args): return "Noclip toggled")
    register_command(con, "fly", "Toggle fly mode", proc(args): return "Fly mode toggled")
    register_command(con, "tp", "Teleport to x y z", proc(args):
        if len(args) >= 3:
            return "Teleported to " + args[0] + " " + args[1] + " " + args[2]
        return "Usage: tp x y z"
    )
    register_command(con, "give", "Give item", proc(args):
        if len(args) >= 1:
            return "Gave " + args[0]
        return "Usage: give item_id [count]"
    )
    register_command(con, "spawn", "Spawn entity", proc(args):
        if len(args) >= 1:
            return "Spawned " + args[0]
        return "Usage: spawn entity_type"
    )
    register_command(con, "kill", "Kill target", proc(args): return "Target killed")
    register_command(con, "stat", "Show stats", proc(args): return "Stats: FPS, Memory, Entities")
    register_command(con, "timescale", "Set time scale", proc(args):
        if len(args) >= 1:
            return "Time scale set to " + args[0]
        return "Usage: timescale 0.5"
    )
