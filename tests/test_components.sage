# test_components.sage - Sanity checks for built-in components
# Run: ./run.sh tests/test_components.sage

from components import TransformComponent, TransformComponentFull, VelocityComponent
from components import CameraComponent, PointLightComponent, DirectionalLightComponent
from components import NameComponent, ParentComponent, MeshRendererComponent
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
    return math.abs(a - b) < 0.001

print "=== Component Sanity Checks ==="

# --- TransformComponent ---
let t = TransformComponent(1.0, 2.0, 3.0)
check("transform position x", approx(t["position"][0], 1.0))
check("transform position y", approx(t["position"][1], 2.0))
check("transform position z", approx(t["position"][2], 3.0))
check("transform rotation zero", approx(t["rotation"][0], 0.0))
check("transform scale one", approx(t["scale"][0], 1.0))
check("transform starts dirty", t["dirty"] == true)

# --- TransformComponentFull ---
let tf = TransformComponentFull(vec3(5.0, 6.0, 7.0), vec3(0.1, 0.2, 0.3), vec3(2.0, 2.0, 2.0))
check("full transform pos", approx(tf["position"][0], 5.0))
check("full transform rot", approx(tf["rotation"][1], 0.2))
check("full transform scale", approx(tf["scale"][2], 2.0))

# --- VelocityComponent ---
let v = VelocityComponent()
check("velocity linear zero", approx(v["linear"][0], 0.0))
check("velocity angular zero", approx(v["angular"][0], 0.0))
check("velocity has damping", approx(v["damping"], 0.98))

# --- CameraComponent ---
let cam = CameraComponent(60.0, 0.1, 1000.0)
check("camera fov", approx(cam["fov"], 60.0))
check("camera near", approx(cam["near"], 0.1))
check("camera far", approx(cam["far"], 1000.0))
check("camera not active by default", cam["active"] == false)

# --- PointLightComponent ---
let pl = PointLightComponent(1.0, 0.8, 0.6, 5.0, 20.0)
check("point light color", approx(pl["color"][0], 1.0))
check("point light intensity", approx(pl["intensity"], 5.0))
check("point light radius", approx(pl["radius"], 20.0))
check("point light type", pl["type"] == "point")

# --- DirectionalLightComponent ---
let dl = DirectionalLightComponent(1.0, 1.0, 0.9, 1.5)
check("dir light type", dl["type"] == "directional")
check("dir light intensity", approx(dl["intensity"], 1.5))
check("dir light casts shadows", dl["cast_shadows"] == true)

# --- NameComponent ---
let n = NameComponent("TestEntity")
check("name component", n["name"] == "TestEntity")

# --- ParentComponent ---
let p = ParentComponent(42)
check("parent entity", p["parent"] == 42)
check("children empty", len(p["children"]) == 0)

# --- MeshRendererComponent ---
let mr = MeshRendererComponent(7, "default")
check("mesh handle", mr["mesh"] == 7)
check("material id", mr["material"] == "default")
check("visible by default", mr["visible"] == true)
check("cast shadows by default", mr["cast_shadows"] == true)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Component sanity checks failed!"
else:
    print "All component sanity checks passed!"
