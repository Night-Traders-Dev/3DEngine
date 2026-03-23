# test_physics.sage - Sanity checks for rigid body physics
# Run: ./run.sh tests/test_physics.sage

from physics import RigidbodyComponent, StaticBodyComponent
from physics import BoxColliderComponent, SphereColliderComponent
from physics import apply_force, apply_impulse
from physics import create_physics_world, integrate_body, resolve_ground
from components import TransformComponent
from math3d import vec3

import math

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

proc approx(a, b):
    return math.abs(a - b) < 0.1

print "=== Physics System Sanity Checks ==="

# --- Rigidbody creation ---
let rb = RigidbodyComponent(5.0)
check("rb mass", approx(rb["mass"], 5.0))
check("rb inv_mass", approx(rb["inv_mass"], 0.2))
check("rb velocity zero", approx(rb["velocity"][0], 0.0))
check("rb use_gravity true", rb["use_gravity"] == true)
check("rb not kinematic", rb["is_kinematic"] == false)
check("rb restitution", rb["restitution"] > 0.0)
check("rb friction", rb["friction"] > 0.0)
check("rb not grounded", rb["grounded"] == false)

# --- Static body ---
let sb = StaticBodyComponent()
check("static mass 0", approx(sb["mass"], 0.0))
check("static inv_mass 0", approx(sb["inv_mass"], 0.0))
check("static is kinematic", sb["is_kinematic"] == true)
check("static no gravity", sb["use_gravity"] == false)

# --- Colliders ---
let box_col = BoxColliderComponent(1.0, 2.0, 1.0)
check("box collider type", box_col["type"] == "aabb")
check("box collider half x", approx(box_col["half"][0], 1.0))
check("box collider half y", approx(box_col["half"][1], 2.0))
check("box collider not trigger", box_col["is_trigger"] == false)

let sphere_col = SphereColliderComponent(3.0)
check("sphere collider type", sphere_col["type"] == "sphere")
check("sphere collider radius", approx(sphere_col["radius"], 3.0))

# --- Apply force ---
let rb2 = RigidbodyComponent(2.0)
apply_force(rb2, vec3(10.0, 0.0, 0.0))
check("force accumulated", approx(rb2["forces"][0], 10.0))
apply_force(rb2, vec3(5.0, 0.0, 0.0))
check("forces stacked", approx(rb2["forces"][0], 15.0))

# --- Apply impulse ---
let rb3 = RigidbodyComponent(2.0)
apply_impulse(rb3, vec3(4.0, 0.0, 0.0))
check("impulse changes velocity", approx(rb3["velocity"][0], 2.0))

# Static body ignores impulse
let rb_static = StaticBodyComponent()
apply_impulse(rb_static, vec3(100.0, 0.0, 0.0))
check("static ignores impulse", approx(rb_static["velocity"][0], 0.0))

# --- Physics world ---
let pw = create_physics_world()
check("physics world created", pw != nil)
check("gravity set", approx(pw["gravity"][1], -9.81))
check("ground at 0", approx(pw["ground_y"], 0.0))
check("ground enabled", pw["ground_enabled"] == true)

# --- Integration ---
let rb4 = RigidbodyComponent(1.0)
rb4["use_gravity"] = false
rb4["velocity"] = vec3(5.0, 0.0, 0.0)
let t4 = TransformComponent(0.0, 5.0, 0.0)
integrate_body(rb4, t4, pw["gravity"], 1.0)
check("integration moves x", approx(t4["position"][0], 5.0))
check("integration keeps y (no gravity)", approx(t4["position"][1], 5.0))
check("forces cleared after integrate", approx(rb4["forces"][0], 0.0))

# Integration with gravity
let rb5 = RigidbodyComponent(1.0)
let t5 = TransformComponent(0.0, 10.0, 0.0)
integrate_body(rb5, t5, pw["gravity"], 1.0)
check("gravity pulls down velocity", rb5["velocity"][1] < 0.0)
check("gravity moves position down", t5["position"][1] < 10.0)

# --- Ground collision ---
let rb6 = RigidbodyComponent(1.0)
rb6["velocity"] = vec3(0.0, -5.0, 0.0)
let t6 = TransformComponent(0.0, -0.5, 0.0)
let col6 = BoxColliderComponent(0.5, 0.5, 0.5)
resolve_ground(rb6, t6, col6, 0.0)
check("ground pushes up", t6["position"][1] >= 0.0)
check("ground sets grounded", rb6["grounded"] == true)
check("ground stops downward velocity", rb6["velocity"][1] >= 0.0)

# Object above ground (should not collide)
let rb7 = RigidbodyComponent(1.0)
let t7 = TransformComponent(0.0, 5.0, 0.0)
let col7 = BoxColliderComponent(0.5, 0.5, 0.5)
resolve_ground(rb7, t7, col7, 0.0)
check("above ground not grounded", rb7["grounded"] == false)

# Sphere ground collision
let rb8 = RigidbodyComponent(1.0)
rb8["velocity"] = vec3(0.0, -3.0, 0.0)
let t8 = TransformComponent(0.0, 0.3, 0.0)
let col8 = SphereColliderComponent(1.0)
resolve_ground(rb8, t8, col8, 0.0)
check("sphere ground collision", rb8["grounded"] == true)
check("sphere pushed to ground", t8["position"][1] >= 0.0)

# --- Bounce ---
let rb9 = RigidbodyComponent(1.0)
rb9["restitution"] = 0.8
rb9["velocity"] = vec3(0.0, -10.0, 0.0)
let t9 = TransformComponent(0.0, -0.2, 0.0)
let col9 = BoxColliderComponent(0.5, 0.5, 0.5)
resolve_ground(rb9, t9, col9, 0.0)
check("bounce reverses velocity", rb9["velocity"][1] > 0.0)
check("bounce loses energy", rb9["velocity"][1] < 10.0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Physics sanity checks failed!"
else:
    print "All physics sanity checks passed!"
