# test_events.sage - Sanity checks for the event bus
# Run: ./run.sh tests/test_events.sage

from events import create_event_bus, subscribe, emit, emit_immediate, flush_events, clear_events, listener_count

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Event Bus Sanity Checks ==="

# --- Creation ---
let bus = create_event_bus()
check("bus created", bus != nil)
check("no listeners initially", listener_count(bus, "test") == 0)

# --- Subscribe + emit_immediate ---
let received = [nil]
proc on_test(etype, data):
    received[0] = data

subscribe(bus, "test", on_test)
check("listener registered", listener_count(bus, "test") == 1)

emit_immediate(bus, "test", "hello")
check("immediate event received", received[0] == "hello")

# --- Queued emit + flush ---
let queued_val = [0]
proc on_score(etype, data):
    queued_val[0] = queued_val[0] + data["points"]

subscribe(bus, "score", on_score)
emit(bus, "score", {"points": 10})
emit(bus, "score", {"points": 20})
check("queued events not delivered yet", queued_val[0] == 0)

flush_events(bus)
check("queued events delivered after flush", queued_val[0] == 30)

# --- Multiple listeners ---
let count_a = [0]
let count_b = [0]
proc listener_a(etype, data):
    count_a[0] = count_a[0] + 1
proc listener_b(etype, data):
    count_b[0] = count_b[0] + 1

subscribe(bus, "multi", listener_a)
subscribe(bus, "multi", listener_b)
check("2 listeners on multi", listener_count(bus, "multi") == 2)

emit_immediate(bus, "multi", nil)
check("both listeners called", count_a[0] == 1 and count_b[0] == 1)

# --- Clear ---
emit(bus, "test", "should be cleared")
clear_events(bus)
received[0] = nil
flush_events(bus)
check("cleared events not delivered", received[0] == nil)

# --- Emit to non-existent event type ---
emit_immediate(bus, "nonexistent", "data")
check("no crash on non-existent event type", true)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Event bus sanity checks failed!"
else:
    print "All event bus sanity checks passed!"
