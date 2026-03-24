# test_codegen.sage - Sanity checks for code generator
from codegen import generate_game_script
from ecs import create_world, spawn, add_component
from components import TransformComponent, NameComponent
from math3d import vec3

let p = 0
let f = 0
proc check(n, c):
    if c:
        p = p + 1
    else:
        print "  FAIL: " + n
        f = f + 1

print "=== Code Generator Sanity Checks ==="

let w = create_world()
let e1 = spawn(w)
add_component(w, e1, "transform", TransformComponent(1.0, 2.0, 3.0))
add_component(w, e1, "name", NameComponent("TestCube"))
add_component(w, e1, "mesh_id", {"mesh": nil, "name": "cube"})

let e2 = spawn(w)
let t2 = TransformComponent(5.0, 0.0, 0.0)
t2["scale"] = vec3(2.0, 2.0, 2.0)
add_component(w, e2, "transform", t2)
add_component(w, e2, "name", NameComponent("BigSphere"))
add_component(w, e2, "mesh_id", {"mesh": nil, "name": "sphere"})

let code = generate_game_script(w, "TestScene", {"width": 800, "height": 600})
check("code generated", code != nil)
check("code has content", len(code) > 100)
check("contains scene name", contains(code, "TestScene"))
check("contains import", contains(code, "import"))
check("contains spawn", contains(code, "spawn"))
check("contains TestCube", contains(code, "TestCube"))
check("contains BigSphere", contains(code, "BigSphere"))
check("contains TransformComponent", contains(code, "TransformComponent"))
check("contains renderer setup", contains(code, "create_renderer"))
check("contains game loop", contains(code, "while running"))
check("contains draw", contains(code, "draw_mesh_lit"))
check("contains resolution", contains(code, "800"))
check("contains game end", contains(code, "shutdown_renderer"))
check("contains sky", contains(code, "draw_sky"))

# Save and verify
import io
io.writefile("/tmp/sage_codegen_test.sage", code)
check("saved to file", io.exists("/tmp/sage_codegen_test.sage"))
let read_back = io.readfile("/tmp/sage_codegen_test.sage")
check("read back matches", len(read_back) == len(code))
io.remove("/tmp/sage_codegen_test.sage")

# Empty world
let w2 = create_world()
let code2 = generate_game_script(w2, "Empty", {})
check("empty world generates", code2 != nil)
check("empty world has loop", contains(code2, "while running"))

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Code generator sanity checks failed!"
else:
    print "All code generator sanity checks passed!"
