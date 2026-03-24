gc_disable()
# -----------------------------------------
# frame_graph.sage - Feature 15: Frame Graph
# Automatic render pass ordering and resource barriers
# -----------------------------------------

import gpu

# ============================================================================
# Pass types
# ============================================================================
let PASS_GRAPHICS = 0
let PASS_COMPUTE = 1

# ============================================================================
# Frame graph pass definition
# ============================================================================
proc create_pass(name, pass_type):
    let p = {}
    p["name"] = name
    p["type"] = pass_type
    p["reads"] = []
    p["writes"] = []
    p["execute"] = nil
    p["enabled"] = true
    return p

proc pass_reads(pass, resource_name):
    push(pass["reads"], resource_name)

proc pass_writes(pass, resource_name):
    push(pass["writes"], resource_name)

proc pass_set_execute(pass, fn):
    pass["execute"] = fn

# ============================================================================
# Frame graph
# ============================================================================
proc create_frame_graph():
    let fg = {}
    fg["passes"] = []
    fg["resources"] = {}
    fg["sorted"] = []
    return fg

proc fg_add_pass(fg, pass):
    push(fg["passes"], pass)

proc fg_add_resource(fg, name, resource_handle):
    fg["resources"][name] = resource_handle

# ============================================================================
# Topological sort (dependency ordering)
# ============================================================================
proc fg_compile(fg):
    # Simple dependency sort: passes that write before passes that read
    let passes = fg["passes"]
    let sorted = []
    let visited = {}

    # Build write→pass mapping
    let write_map = {}
    let i = 0
    while i < len(passes):
        let p = passes[i]
        let j = 0
        while j < len(p["writes"]):
            write_map[p["writes"][j]] = i
            j = j + 1
        i = i + 1

    # Visit in dependency order
    proc visit(idx):
        let key = str(idx)
        if dict_has(visited, key):
            return nil
        visited[key] = true
        let p = passes[idx]
        # Visit dependencies first
        let r = 0
        while r < len(p["reads"]):
            let res = p["reads"][r]
            if dict_has(write_map, res):
                let dep = write_map[res]
                if dep != idx:
                    visit(dep)
            r = r + 1
        push(sorted, idx)

    i = 0
    while i < len(passes):
        visit(i)
        i = i + 1

    fg["sorted"] = sorted
    return sorted

# ============================================================================
# Execute frame graph
# ============================================================================
proc fg_execute(fg, cmd):
    let passes = fg["passes"]
    let order = fg["sorted"]
    let i = 0
    while i < len(order):
        let p = passes[order[i]]
        if p["enabled"]:
            if p["execute"] != nil:
                p["execute"](cmd, fg["resources"])
        i = i + 1

# ============================================================================
# Debug info
# ============================================================================
proc fg_print(fg):
    print "Frame Graph:"
    print "  Passes: " + str(len(fg["passes"]))
    print "  Resources: " + str(len(dict_keys(fg["resources"])))
    print "  Execution order:"
    let i = 0
    while i < len(fg["sorted"]):
        let p = fg["passes"][fg["sorted"][i]]
        let status = "enabled"
        if p["enabled"] == false:
            status = "disabled"
        print "    " + str(i) + ". " + p["name"] + " (" + status + ")"
        i = i + 1

# ============================================================================
# Frame graph GPU integration
# ============================================================================
proc fg_add_graphics_pass(fg, name, render_pass, framebuffer, execute_fn):
    let pass_data = create_pass(name, PASS_GRAPHICS)
    pass_data["render_pass"] = render_pass
    pass_data["framebuffer"] = framebuffer
    pass_data["execute"] = execute_fn
    fg_add_pass(fg, pass_data)
    return pass_data

proc fg_add_compute_pass(fg, name, execute_fn):
    let pass_data = create_pass(name, PASS_COMPUTE)
    pass_data["execute"] = execute_fn
    fg_add_pass(fg, pass_data)
    return pass_data

proc fg_execute_with_barriers(fg, cmd):
    let order = fg_compile(fg)
    let passes = fg["passes"]
    let i = 0
    while i < len(order):
        let pass_data = passes[order[i]]
        if pass_data["enabled"]:
            if pass_data["type"] == PASS_COMPUTE:
                pass_data["execute"](cmd, fg["resources"])
                gpu.cmd_pipeline_barrier(cmd, gpu.PIPE_COMPUTE, gpu.PIPE_FRAGMENT, gpu.ACCESS_SHADER_WRITE, gpu.ACCESS_SHADER_READ)
            else:
                pass_data["execute"](cmd, fg["resources"])
        i = i + 1
