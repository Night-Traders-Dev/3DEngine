gc_disable()
# -----------------------------------------
# asset_browser.sage - Asset browser for Sage Engine Editor
# Lists available meshes, scenes, presets
# -----------------------------------------

import io
import ui_core
from ui_core import create_widget, create_panel, create_rect, create_label
from ui_core import add_child

let rgba = ui_core.rgba
let COLOR_WHITE = ui_core.COLOR_WHITE
let ANCHOR_BOTTOM_LEFT = ui_core.ANCHOR_BOTTOM_LEFT

# ============================================================================
# Asset Entry
# ============================================================================
proc _create_asset_entry(name, asset_type, path):
    let e = {}
    e["name"] = name
    e["type"] = asset_type
    e["path"] = path
    e["selected"] = false
    return e

# ============================================================================
# Asset Browser
# ============================================================================
proc create_asset_browser():
    let ab = {}
    ab["panel"] = create_panel(0.0, 0.0, 300.0, 200.0, rgba(0.08, 0.08, 0.12, 0.9))
    ab["panel"]["anchor"] = ANCHOR_BOTTOM_LEFT
    ab["panel"]["x"] = 10.0
    ab["panel"]["y"] = -210.0
    ab["entries"] = []
    ab["selected_index"] = -1
    ab["visible"] = true
    ab["categories"] = {}
    ab["active_category"] = "all"
    return ab

# ============================================================================
# Add assets
# ============================================================================
proc add_asset(ab, name, asset_type, path):
    let entry = _create_asset_entry(name, asset_type, path)
    push(ab["entries"], entry)
    if dict_has(ab["categories"], asset_type) == false:
        ab["categories"][asset_type] = []
    push(ab["categories"][asset_type], len(ab["entries"]) - 1)

proc add_primitive_assets(ab):
    add_asset(ab, "Cube", "mesh", "primitive:cube")
    add_asset(ab, "Sphere", "mesh", "primitive:sphere")
    add_asset(ab, "Plane", "mesh", "primitive:plane")
    add_asset(ab, "Large Plane", "mesh", "primitive:plane_large")

proc add_vfx_assets(ab):
    add_asset(ab, "Fire", "vfx", "vfx:fire")
    add_asset(ab, "Smoke", "vfx", "vfx:smoke")
    add_asset(ab, "Sparks", "vfx", "vfx:sparks")
    add_asset(ab, "Explosion", "vfx", "vfx:explosion")
    add_asset(ab, "Rain", "vfx", "vfx:rain")
    add_asset(ab, "Dust", "vfx", "vfx:dust")
    add_asset(ab, "Magic", "vfx", "vfx:magic")

# ============================================================================
# Scan directory for .obj and .json scene files
# ============================================================================
proc _asset_type_from_name(name):
    if endswith(name, ".obj") or endswith(name, ".gltf") or endswith(name, ".glb"):
        return "mesh"
    if endswith(name, ".json"):
        return "scene"
    if endswith(name, ".png") or endswith(name, ".jpg"):
        return "texture"
    if endswith(name, ".wav") or endswith(name, ".ogg"):
        return "audio"
    return ""

proc _has_asset_path(ab, path):
    let i = 0
    while i < len(ab["entries"]):
        if ab["entries"][i]["path"] == path:
            return true
        i = i + 1
    return false

proc scan_directory(ab, dir_path):
    let files = io.listdir(dir_path)
    if files == nil:
        return nil
    let i = 0
    while i < len(files):
        let name = files[i]
        let atype = _asset_type_from_name(name)
        if atype != "":
            let fpath = dir_path + "/" + name
            if _has_asset_path(ab, fpath) == false:
                add_asset(ab, name, atype, fpath)
        i = i + 1

# ============================================================================
# Selection
# ============================================================================
proc select_asset(ab, index):
    if index < 0 or index >= len(ab["entries"]):
        return nil
    # Deselect previous
    if ab["selected_index"] >= 0:
        ab["entries"][ab["selected_index"]]["selected"] = false
    ab["selected_index"] = index
    ab["entries"][index]["selected"] = true
    return ab["entries"][index]

proc get_selected_asset(ab):
    if ab["selected_index"] < 0:
        return nil
    return ab["entries"][ab["selected_index"]]

proc asset_count(ab):
    return len(ab["entries"])

proc asset_count_by_type(ab, asset_type):
    if dict_has(ab["categories"], asset_type) == false:
        return 0
    return len(ab["categories"][asset_type])

# ============================================================================
# Filter by category
# ============================================================================
proc set_category_filter(ab, category):
    ab["active_category"] = category

proc get_filtered_entries(ab):
    if ab["active_category"] == "all":
        return ab["entries"]
    let result = []
    let i = 0
    while i < len(ab["entries"]):
        if ab["entries"][i]["type"] == ab["active_category"]:
            push(result, ab["entries"][i])
        i = i + 1
    return result

# ============================================================================
# Build UI representation
# ============================================================================
proc rebuild_browser_ui(ab):
    ab["panel"]["children"] = []
    let y_off = 8.0
    # Header
    let header = create_label(10.0, y_off, "Assets (" + str(len(ab["entries"])) + ")", COLOR_WHITE)
    add_child(ab["panel"], header)
    y_off = y_off + 20.0
    # Separator
    let sep = create_rect(10.0, y_off, 280.0, 1.0, rgba(0.3, 0.3, 0.3, 0.5))
    add_child(ab["panel"], sep)
    y_off = y_off + 6.0
    # Entries
    let filtered = get_filtered_entries(ab)
    let i = 0
    while i < len(filtered) and i < 10:
        let entry = filtered[i]
        let bg_color = rgba(0.15, 0.15, 0.2, 0.6)
        if entry["selected"]:
            bg_color = rgba(0.3, 0.35, 0.5, 0.8)
        let row = create_rect(10.0, y_off, 280.0, 16.0, bg_color)
        add_child(ab["panel"], row)
        let type_color = rgba(0.5, 0.5, 0.5, 1.0)
        if entry["type"] == "mesh":
            type_color = rgba(0.4, 0.7, 1.0, 1.0)
        if entry["type"] == "vfx":
            type_color = rgba(1.0, 0.6, 0.2, 1.0)
        if entry["type"] == "scene":
            type_color = rgba(0.4, 1.0, 0.4, 1.0)
        let lbl = create_label(14.0, y_off + 1.0, "[" + entry["type"] + "] " + entry["name"], type_color)
        add_child(ab["panel"], lbl)
        y_off = y_off + 18.0
        i = i + 1
    ab["panel"]["height"] = y_off + 10.0

proc search_assets(browser, query):
    # Filter assets by name containing query string
    let results = []
    let all = browser["entries"]
    let i = 0
    while i < len(all):
        if contains(lower(all[i]["name"]), lower(query)):
            push(results, all[i])
        i = i + 1
    return results

proc get_asset_by_name(browser, name):
    let all = browser["entries"]
    let i = 0
    while i < len(all):
        if all[i]["name"] == name:
            return all[i]
        i = i + 1
    return nil

proc add_custom_asset(browser, name, category, data):
    let asset = {}
    asset["name"] = name
    asset["category"] = category
    asset["data"] = data
    asset["custom"] = true
    push(browser["entries"], asset)
    return asset

proc get_asset_categories(browser):
    let cats = {}
    let all = browser["entries"]
    let i = 0
    while i < len(all):
        let cat = all[i]["type"]
        if dict_has(cats, cat) == false:
            cats[cat] = 0
        cats[cat] = cats[cat] + 1
        i = i + 1
    return cats
