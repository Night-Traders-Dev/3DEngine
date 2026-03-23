gc_disable()
# -----------------------------------------
# events.sage - Event bus for Sage Engine
# Decoupled communication between engine systems
# -----------------------------------------

# ============================================================================
# Event Bus
# ============================================================================
proc create_event_bus():
    let bus = {}
    bus["listeners"] = {}
    bus["queue"] = []
    return bus

proc subscribe(bus, event_type, callback):
    if dict_has(bus["listeners"], event_type) == false:
        bus["listeners"][event_type] = []
    push(bus["listeners"][event_type], callback)

proc emit(bus, event_type, data):
    let evt = {}
    evt["type"] = event_type
    evt["data"] = data
    push(bus["queue"], evt)

proc emit_immediate(bus, event_type, data):
    if dict_has(bus["listeners"], event_type) == false:
        return nil
    let handlers = bus["listeners"][event_type]
    let i = 0
    while i < len(handlers):
        handlers[i](event_type, data)
        i = i + 1

proc flush_events(bus):
    let events = bus["queue"]
    bus["queue"] = []
    let i = 0
    while i < len(events):
        let evt = events[i]
        let etype = evt["type"]
        if dict_has(bus["listeners"], etype):
            let handlers = bus["listeners"][etype]
            let j = 0
            while j < len(handlers):
                handlers[j](etype, evt["data"])
                j = j + 1
        i = i + 1

proc clear_events(bus):
    bus["queue"] = []

proc listener_count(bus, event_type):
    if dict_has(bus["listeners"], event_type) == false:
        return 0
    return len(bus["listeners"][event_type])
