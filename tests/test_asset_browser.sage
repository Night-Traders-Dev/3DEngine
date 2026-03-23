# test_asset_browser.sage - Sanity checks for asset browser
# Run: ./run.sh tests/test_asset_browser.sage

from asset_browser import create_asset_browser, add_asset, add_primitive_assets
from asset_browser import add_vfx_assets, select_asset, get_selected_asset
from asset_browser import asset_count, asset_count_by_type
from asset_browser import set_category_filter, get_filtered_entries
from asset_browser import rebuild_browser_ui

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Asset Browser Sanity Checks ==="

# --- Creation ---
let ab = create_asset_browser()
check("browser created", ab != nil)
check("panel exists", ab["panel"] != nil)
check("0 entries", asset_count(ab) == 0)
check("no selection", ab["selected_index"] == -1)

# --- Add assets ---
add_asset(ab, "MyMesh", "mesh", "path/to/mesh.obj")
check("1 entry", asset_count(ab) == 1)
check("1 mesh", asset_count_by_type(ab, "mesh") == 1)

add_asset(ab, "MyScene", "scene", "scenes/test.json")
check("2 entries", asset_count(ab) == 2)
check("1 scene", asset_count_by_type(ab, "scene") == 1)

# --- Primitive presets ---
add_primitive_assets(ab)
check("primitives added", asset_count_by_type(ab, "mesh") >= 4)

# --- VFX presets ---
add_vfx_assets(ab)
check("vfx added", asset_count_by_type(ab, "vfx") >= 7)
check("total > 10", asset_count(ab) > 10)

# --- Selection ---
let sel = select_asset(ab, 0)
check("selected first", sel != nil)
check("selected name", sel["name"] == "MyMesh")
check("selected flag", sel["selected"] == true)
check("selected index", ab["selected_index"] == 0)

let sel2 = select_asset(ab, 1)
check("switched selection", sel2["name"] == "MyScene")
check("previous deselected", ab["entries"][0]["selected"] == false)

# Get selected
let got = get_selected_asset(ab)
check("get selected works", got["name"] == "MyScene")

# Select out of range
let bad = select_asset(ab, 999)
check("bad select returns nil", bad == nil)

# No selection
let ab2 = create_asset_browser()
check("no selection returns nil", get_selected_asset(ab2) == nil)

# --- Category filter ---
set_category_filter(ab, "mesh")
let mesh_only = get_filtered_entries(ab)
check("filter mesh only", len(mesh_only) >= 4)
let all_mesh = true
let i = 0
while i < len(mesh_only):
    if mesh_only[i]["type"] != "mesh":
        all_mesh = false
    i = i + 1
check("all filtered are mesh", all_mesh)

set_category_filter(ab, "vfx")
let vfx_only = get_filtered_entries(ab)
check("filter vfx only", len(vfx_only) >= 7)

set_category_filter(ab, "all")
let all_entries = get_filtered_entries(ab)
check("all filter returns everything", len(all_entries) == asset_count(ab))

# --- Zero entries for unknown type ---
check("unknown type = 0", asset_count_by_type(ab, "audio") == 0)

# --- UI rebuild ---
rebuild_browser_ui(ab)
check("ui rebuilt", len(ab["panel"]["children"]) > 0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Asset browser sanity checks failed!"
else:
    print "All asset browser sanity checks passed!"
