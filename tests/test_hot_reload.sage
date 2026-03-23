# test_hot_reload.sage - Sanity checks for hot reload system
import io
import sys
from hot_reload import create_file_watcher, watch_file, unwatch_file
from hot_reload import poll_changes, has_changes, clear_changes
from hot_reload import create_hot_reload_manager, register_reload_handler
from hot_reload import update_hot_reload, reload_stats

let p = 0
let f = 0
proc check(n, c):
    if c:
        p = p + 1
    else:
        print "  FAIL: " + n
        f = f + 1

print "=== Hot Reload Sanity Checks ==="

# --- File watcher ---
let fw = create_file_watcher()
check("watcher created", fw != nil)
check("no watched files", len(dict_keys(fw["watched"])) == 0)

# Create test file
io.writefile("/tmp/sage_hr_test.txt", "hello")
let watched = watch_file(fw, "/tmp/sage_hr_test.txt")
check("watch file succeeds", watched == true)
check("1 watched file", len(dict_keys(fw["watched"])) == 1)

# Watch non-existent file
let bad = watch_file(fw, "/tmp/nonexistent_file_xyz.txt")
check("watch nonexistent fails", bad == false)

# Poll (no changes yet)
fw["poll_interval"] = 0.0
let changes = poll_changes(fw)
check("no changes initially", len(changes) == 0)

# Modify file
io.writefile("/tmp/sage_hr_test.txt", "hello world updated")
let changes2 = poll_changes(fw)
check("detected change", len(changes2) > 0)
check("has_changes true", has_changes(fw))

# Clear changes
clear_changes(fw)
check("cleared changes", has_changes(fw) == false)

# Unwatch
unwatch_file(fw, "/tmp/sage_hr_test.txt")
check("unwatched", len(dict_keys(fw["watched"])) == 0)

# --- Hot reload manager ---
let hrm = create_hot_reload_manager()
check("manager created", hrm != nil)
check("enabled", hrm["enabled"] == true)

let reloaded = [false]
proc on_sage_reload(path):
    reloaded[0] = true

register_reload_handler(hrm, ".sage", on_sage_reload)
check("handler registered", dict_has(hrm["reload_callbacks"], ".sage"))

let rs = reload_stats(hrm)
check("stats reload count 0", rs["reload_count"] == 0)

# Cleanup
io.remove("/tmp/sage_hr_test.txt")

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Hot reload sanity checks failed!"
else:
    print "All hot reload sanity checks passed!"
