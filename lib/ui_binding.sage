gc_disable()
# ui_binding.sage — UI Data Binding System
# Automatically update UI widgets when data changes.
# Supports: one-way binding, two-way binding, computed properties,
# list binding, format strings, conditional visibility.

proc create_binding_context():
    return {
        "properties": {},
        "bindings": [],
        "computed": {},
        "watchers": [],
        "dirty": {}
    }

proc bind_property(ctx, name, initial_value):
    ctx["properties"][name] = initial_value
    ctx["dirty"][name] = true

proc get_property(ctx, name):
    if dict_has(ctx["properties"], name):
        return ctx["properties"][name]
    return nil

proc set_property(ctx, name, value):
    if dict_has(ctx["properties"], name):
        if ctx["properties"][name] != value:
            ctx["properties"][name] = value
            ctx["dirty"][name] = true
            _notify_watchers(ctx, name)

proc _notify_watchers(ctx, prop_name):
    let i = 0
    while i < len(ctx["watchers"]):
        let w = ctx["watchers"][i]
        if w["property"] == prop_name:
            w["callback"](ctx["properties"][prop_name])
        i = i + 1

proc watch_property(ctx, name, callback):
    push(ctx["watchers"], {"property": name, "callback": callback})

proc bind_widget_text(ctx, widget, property_name, format_str):
    push(ctx["bindings"], {
        "type": "text",
        "widget": widget,
        "property": property_name,
        "format": format_str
    })

proc bind_widget_visibility(ctx, widget, property_name):
    push(ctx["bindings"], {
        "type": "visibility",
        "widget": widget,
        "property": property_name
    })

proc bind_widget_progress(ctx, widget, value_property, max_property):
    push(ctx["bindings"], {
        "type": "progress",
        "widget": widget,
        "value_prop": value_property,
        "max_prop": max_property
    })

proc bind_widget_list(ctx, widget, list_property, item_template):
    push(ctx["bindings"], {
        "type": "list",
        "widget": widget,
        "property": list_property,
        "template": item_template
    })

proc add_computed_property(ctx, name, dependencies, compute_fn):
    ctx["computed"][name] = {
        "dependencies": dependencies,
        "compute": compute_fn
    }
    # Initial computation
    let args = []
    let i = 0
    while i < len(dependencies):
        push(args, get_property(ctx, dependencies[i]))
        i = i + 1
    ctx["properties"][name] = compute_fn(args)

proc update_bindings(ctx):
    # Update computed properties
    let comp_keys = dict_keys(ctx["computed"])
    let ci = 0
    while ci < len(comp_keys):
        let name = comp_keys[ci]
        let comp = ctx["computed"][name]
        let needs_update = false
        let di = 0
        while di < len(comp["dependencies"]):
            if dict_has(ctx["dirty"], comp["dependencies"][di]):
                needs_update = true
            di = di + 1
        if needs_update:
            let args = []
            di = 0
            while di < len(comp["dependencies"]):
                push(args, get_property(ctx, comp["dependencies"][di]))
                di = di + 1
            ctx["properties"][name] = comp["compute"](args)
            ctx["dirty"][name] = true
        ci = ci + 1

    # Update widget bindings
    let i = 0
    while i < len(ctx["bindings"]):
        let b = ctx["bindings"][i]
        if b["type"] == "text":
            if dict_has(ctx["dirty"], b["property"]):
                let val = get_property(ctx, b["property"])
                if b["format"] != nil:
                    b["widget"]["text"] = replace(b["format"], "{}", str(val))
                else:
                    b["widget"]["text"] = str(val)
        elif b["type"] == "visibility":
            if dict_has(ctx["dirty"], b["property"]):
                b["widget"]["visible"] = get_property(ctx, b["property"])
        elif b["type"] == "progress":
            let val = get_property(ctx, b["value_prop"])
            let max_val = get_property(ctx, b["max_prop"])
            if val != nil and max_val != nil and max_val > 0:
                b["widget"]["progress"] = val / max_val
        elif b["type"] == "list":
            if dict_has(ctx["dirty"], b["property"]):
                let items = get_property(ctx, b["property"])
                if items != nil:
                    b["widget"]["items"] = items
        i = i + 1

    ctx["dirty"] = {}
