# test_render_system.sage - Sanity checks for the render system (non-GPU parts)
# Run: ./run.sh tests/test_render_system.sage

from render_system import create_material_registry, register_material, get_material
from render_system import build_lit_push_data, build_lit_material_uniform_data
from mesh import normalize_mesh_vertices, build_skin_palette_uniform_data, MAX_SKIN_JOINTS

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
let lit_push = build_lit_push_data(mvp, model, [0.2, 0.4, 0.6, 0.8], true)
check("lit push has 32 floats", len(lit_push) == 32)
check("lit push starts with mvp", lit_push[0] == 0.0 and lit_push[15] == 15.0)
check("lit push includes model", lit_push[16] == 100.0 and lit_push[31] == 115.0)

let default_push = build_lit_push_data(mvp, model, nil, false)
check("default lit push keeps transform payload", default_push[0] == 0.0 and default_push[31] == 115.0)

let lit_uniform = build_lit_material_uniform_data([0.2, 0.4, 0.6, 0.8], false, [1.0, 7.0, 2.0], true)
check("lit material uniform has 12 floats", len(lit_uniform) == 12)
check("lit material uniform stores base color", lit_uniform[0] == 0.2 and lit_uniform[3] == 0.8)
check("lit material uniform stores receive shadows", lit_uniform[4] == 0.0)
check("lit material uniform stores voxel texture info", lit_uniform[5] == 1.0 and lit_uniform[6] == 7.0 and lit_uniform[7] == 2.0)
check("lit material uniform stores scene color availability", lit_uniform[8] == 1.0)

let default_uniform = build_lit_material_uniform_data(nil, true, nil, false)
check("default lit material alpha is 1", default_uniform[3] == 1.0)
check("default lit material receives shadows", default_uniform[4] == 1.0)
check("default lit material has no scene color source", default_uniform[8] == 0.0)

# --- Mesh vertex normalization ---
let static_vertices = [1.0, 2.0, 3.0, 0.0, 1.0, 0.0, 0.25, 0.75]
let normalized = normalize_mesh_vertices(static_vertices, 1)
check("normalized mesh expands stride", len(normalized) == 16)
check("normalized mesh keeps position", normalized[0] == 1.0 and normalized[2] == 3.0)
check("normalized mesh keeps uv", normalized[6] == 0.25 and normalized[7] == 0.75)
check("normalized mesh default joints zero", normalized[8] == 0.0 and normalized[11] == 0.0)
check("normalized mesh default weight uses identity joint", normalized[12] == 1.0 and normalized[15] == 0.0)

# --- Skin uniform packing ---
let joint_palette = [[1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 2.0, 3.0, 4.0, 1.0]]
let skin_uniform = build_skin_palette_uniform_data(joint_palette)
check("skin uniform covers fixed joint budget", len(skin_uniform) == MAX_SKIN_JOINTS * 16)
check("skin uniform keeps first matrix translation", skin_uniform[12] == 2.0 and skin_uniform[13] == 3.0 and skin_uniform[14] == 4.0)
check("skin uniform pads remaining joints with identity", skin_uniform[16] == 1.0 and skin_uniform[31] == 1.0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Render system sanity checks failed!"
else:
    print "All render system sanity checks passed!"
