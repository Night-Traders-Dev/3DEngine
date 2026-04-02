# test_render_system.sage - Sanity checks for the render system (non-GPU parts)
# Run: ./run.sh tests/test_render_system.sage

from render_system import create_material_registry, register_material, get_material, build_lit_push_data

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Render System Sanity Checks ==="

# --- Material registry ---
let reg = create_material_registry()
check("registry created", reg != nil)
check("materials dict exists", dict_has(reg, "materials"))

# --- Register material ---
let mat_data = {}
mat_data["name"] = "test_mat"
mat_data["pipeline"] = 42
mat_data["pipe_layout"] = 7
register_material(reg, "test_mat", mat_data)

let got = get_material(reg, "test_mat")
check("get registered material", got != nil)
check("material name matches", got["name"] == "test_mat")
check("material pipeline id", got["pipeline"] == 42)

# --- Non-existent material ---
let missing = get_material(reg, "nonexistent")
check("missing material returns nil", missing == nil)

# --- Multiple materials ---
let mat2 = {}
mat2["name"] = "lit"
mat2["pipeline"] = 100
register_material(reg, "lit", mat2)

let mat3 = {}
mat3["name"] = "unlit"
mat3["pipeline"] = 200
register_material(reg, "unlit", mat3)

check("lit material exists", get_material(reg, "lit") != nil)
check("unlit material exists", get_material(reg, "unlit") != nil)
check("lit pipeline correct", get_material(reg, "lit")["pipeline"] == 100)
check("unlit pipeline correct", get_material(reg, "unlit")["pipeline"] == 200)

# --- Overwrite material ---
let mat_override = {}
mat_override["name"] = "test_mat"
mat_override["pipeline"] = 99
register_material(reg, "test_mat", mat_override)
let overwritten = get_material(reg, "test_mat")
check("overwritten material updated", overwritten["pipeline"] == 99)

# --- Lit push data ---
let mvp = []
let model = []
let i = 0
while i < 16:
    push(mvp, i + 0.0)
    push(model, 100.0 + i)
    i = i + 1
let lit_push = build_lit_push_data(mvp, model, [0.2, 0.4, 0.6, 0.8])
check("lit push has 36 floats", len(lit_push) == 36)
check("lit push starts with mvp", lit_push[0] == 0.0 and lit_push[15] == 15.0)
check("lit push includes model", lit_push[16] == 100.0 and lit_push[31] == 115.0)
check("lit push includes base color", lit_push[32] == 0.2 and lit_push[35] == 0.8)

let default_push = build_lit_push_data(mvp, model, nil)
check("default lit alpha is 1", default_push[35] == 1.0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Render system sanity checks failed!"
else:
    print "All render system sanity checks passed!"
