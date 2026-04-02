# test_codegen.sage - Sanity checks for code generator
from codegen import generate_game_script
from ecs import create_world, spawn, add_component
from components import TransformComponent, NameComponent, MaterialComponent
from physics import RigidbodyComponent, SphereColliderComponent
from gameplay import HealthComponent
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
t2["rotation"] = vec3(0.0, 0.25, 0.0)
t2["scale"] = vec3(2.0, 2.0, 2.0)
add_component(w, e2, "transform", t2)
add_component(w, e2, "name", NameComponent("BigSphere"))
add_component(w, e2, "mesh_id", {"mesh": nil, "name": "sphere"})
let m2 = MaterialComponent(0.9, 0.4, 0.2)
m2["metallic"] = 0.75
m2["roughness"] = 0.35
m2["emission"] = vec3(0.1, 0.2, 0.3)
m2["emission_strength"] = 2.5
m2["alpha"] = 0.8
add_component(w, e2, "material", m2)
let rb2 = RigidbodyComponent(2.0)
rb2["use_gravity"] = false
rb2["restitution"] = 0.8
rb2["friction"] = 0.2
rb2["linear_damping"] = 0.03
add_component(w, e2, "rigidbody", rb2)
let col2 = SphereColliderComponent(1.25)
col2["offset"] = vec3(0.0, 1.0, 0.0)
col2["is_trigger"] = true
add_component(w, e2, "collider", col2)
let hp2 = HealthComponent(100.0)
hp2["current"] = 40.0
hp2["invulnerable"] = true
hp2["regen_rate"] = 3.0
hp2["regen_delay"] = 1.5
hp2["last_damage_time"] = 8.0
add_component(w, e2, "health", hp2)

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
check("contains full transform import", contains(code, "TransformComponentFull"))
check("contains full transform usage", contains(code, "TransformComponentFull(vec3("))
check("contains material ctor", contains(code, "MaterialComponent("))
check("contains material-aware draw import", contains(code, "draw_mesh_lit_surface"))
check("contains material metallic", contains(code, "[\"metallic\"] = 0.75"))
check("contains material emission", contains(code, "[\"emission\"] = vec3(0.1, 0.2, 0.3)"))
check("contains material-aware draw branch", contains(code, "if has_component(world, eid, \"material\")"))
check("contains rigidbody ctor", contains(code, "RigidbodyComponent(2"))
check("contains rigidbody gravity flag", contains(code, "[\"use_gravity\"] = false"))
check("contains collider trigger flag", contains(code, "[\"is_trigger\"] = true"))
check("contains collider offset", contains(code, "[\"offset\"] = vec3(0, 1, 0)"))
check("contains health current", contains(code, "[\"current\"] = 40"))
check("contains health regen", contains(code, "[\"regen_rate\"] = 3"))

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
