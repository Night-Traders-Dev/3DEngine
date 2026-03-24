gc_disable()
# -----------------------------------------
# hot_reload.sage - Hot reload support for Sage Engine
# Watches files for changes and triggers reload callbacks
# -----------------------------------------

import io
import sys

# ============================================================================
# File watcher
# ============================================================================
proc create_file_watcher():
    let fw = {}
    fw["watched"] = {}
    fw["poll_interval"] = 1.0
    fw["last_poll"] = 0.0
    fw["on_change"] = nil
    fw["changes"] = []
    return fw

proc watch_file(fw, path):
    if io.exists(path) == false:
        return false
    let size = io.filesize(path)
    let snapshot = io.readfile(path)
    fw["watched"][path] = {"size": size, "last_size": size, "changed": false, "snapshot": snapshot}
    return true

proc watch_directory(fw, dir_path, extension):
    let files = io.listdir(dir_path)
    if files == nil:
        return nil
    let i = 0
    while i < len(files):
        let fname = files[i]
        if extension == "" or endswith(fname, extension):
            let path = dir_path + "/" + fname
            watch_file(fw, path)
        i = i + 1

proc unwatch_file(fw, path):
    if dict_has(fw["watched"], path):
        dict_delete(fw["watched"], path)

# ============================================================================
# Poll for changes
# ============================================================================
proc poll_changes(fw):
    let now = sys.clock()
    if now - fw["last_poll"] < fw["poll_interval"]:
        return []
    fw["last_poll"] = now
    let changes = []
    let paths = dict_keys(fw["watched"])
    let i = 0
    while i < len(paths):
        let path = paths[i]
        let entry = fw["watched"][path]
        if io.exists(path):
            let current_size = io.filesize(path)
            let current_snapshot = io.readfile(path)
            if current_size != entry["size"] or current_snapshot != entry["snapshot"]:
                entry["last_size"] = entry["size"]
                entry["size"] = current_size
                entry["snapshot"] = current_snapshot
                entry["changed"] = true
                push(changes, path)
                if fw["on_change"] != nil:
                    fw["on_change"](path)
            else:
                entry["changed"] = false
        else:
            # Deleted file counts as a change
            entry["changed"] = true
            push(changes, path)
            if fw["on_change"] != nil:
                fw["on_change"](path)
        i = i + 1
    fw["changes"] = changes
    return changes

proc has_changes(fw):
    return len(fw["changes"]) > 0

proc clear_changes(fw):
    fw["changes"] = []
    let paths = dict_keys(fw["watched"])
    let i = 0
    while i < len(paths):
        fw["watched"][paths[i]]["changed"] = false
        i = i + 1

# ============================================================================
# Asset hot reload manager
# ============================================================================
proc create_hot_reload_manager():
    let hrm = {}
    hrm["file_watcher"] = create_file_watcher()
    hrm["reload_callbacks"] = {}
    hrm["reload_count"] = 0
    hrm["enabled"] = true
    hrm["last_reload_time"] = 0.0
    return hrm

proc register_reload_handler(hrm, extension, callback):
    hrm["reload_callbacks"][extension] = callback

proc update_hot_reload(hrm):
    if hrm["enabled"] == false:
        return nil
    let fw = hrm["file_watcher"]
    let changes = poll_changes(fw)
    let i = 0
    while i < len(changes):
        let path = changes[i]
        # Find extension
        let ext = _get_extension(path)
        if dict_has(hrm["reload_callbacks"], ext):
            hrm["reload_callbacks"][ext](path)
            hrm["reload_count"] = hrm["reload_count"] + 1
            hrm["last_reload_time"] = sys.clock()
            print "HOT RELOAD: " + path
        i = i + 1

proc _get_extension(path):
    let last_dot = -1
    let i = 0
    while i < len(path):
        if path[i] == ".":
            last_dot = i
        i = i + 1
    if last_dot < 0:
        return ""
    let ext = ""
    i = last_dot
    while i < len(path):
        ext = ext + path[i]
        i = i + 1
    return ext

proc reload_stats(hrm):
    let s = {}
    s["watched_files"] = len(dict_keys(hrm["file_watcher"]["watched"]))
    s["reload_count"] = hrm["reload_count"]
    s["enabled"] = hrm["enabled"]
    return s
