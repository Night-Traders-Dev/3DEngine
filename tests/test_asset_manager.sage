# test_asset_manager.sage - Sanity checks for asset manager (non-GPU parts)
# Run: ./run.sh tests/test_asset_manager.sage

from asset_manager import create_asset_manager, has_mesh, get_mesh
from asset_manager import invalidate_mesh, invalidate_all, asset_stats

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Asset Manager Sanity Checks ==="

# --- Creation ---
let am = create_asset_manager()
check("manager created", am != nil)
check("meshes dict exists", dict_has(am, "meshes"))
check("shaders dict exists", dict_has(am, "shaders"))
check("stats exists", dict_has(am, "stats"))

# --- Stats ---
let s = asset_stats(am)
check("initial 0 meshes", s["meshes"] == 0)
check("initial 0 shaders", s["shaders"] == 0)
check("initial 0 loads", s["loads"] == 0)
check("initial 0 cache hits", s["cache_hits"] == 0)

# --- Manually insert a mesh for testing ---
let fake_mesh = {}
fake_mesh["vbuf"] = 42
fake_mesh["ibuf"] = 43
fake_mesh["index_count"] = 36
am["meshes"]["test_cube"] = fake_mesh
am["stats"]["loads"] = 1

check("has_mesh true", has_mesh(am, "test_cube"))
check("has_mesh false", has_mesh(am, "nonexistent") == false)

# --- Get mesh (cache hit) ---
let got = get_mesh(am, "test_cube")
check("get_mesh returns mesh", got != nil)
check("get_mesh correct vbuf", got["vbuf"] == 42)
check("cache hit incremented", am["stats"]["cache_hits"] == 1)

# Get again
get_mesh(am, "test_cube")
check("second cache hit", am["stats"]["cache_hits"] == 2)

# Miss
let miss = get_mesh(am, "nonexistent")
check("get_mesh nil for missing", miss == nil)

# --- Invalidate ---
invalidate_mesh(am, "test_cube")
check("invalidated mesh gone", has_mesh(am, "test_cube") == false)

# --- Add multiple, then invalidate all ---
am["meshes"]["a"] = fake_mesh
am["meshes"]["b"] = fake_mesh
am["shaders"]["s1"] = 10
check("2 meshes before clear", len(dict_keys(am["meshes"])) == 2)
invalidate_all(am)
check("0 meshes after clear", len(dict_keys(am["meshes"])) == 0)
check("0 shaders after clear", len(dict_keys(am["shaders"])) == 0)

# --- File loading (test with a real file) ---
import io
io.writefile("/tmp/sage_test_asset.txt", "hello_asset")
let content = io.readfile("/tmp/sage_test_asset.txt")
check("file read works", content == "hello_asset")
io.remove("/tmp/sage_test_asset.txt")

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Asset manager sanity checks failed!"
else:
    print "All asset manager sanity checks passed!"
