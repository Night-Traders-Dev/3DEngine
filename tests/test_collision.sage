# test_collision.sage - Sanity checks for collision detection
# Run: ./run.sh tests/test_collision.sage

from collision import aabb_vs_aabb, sphere_vs_sphere, sphere_vs_aabb
from collision import ray_vs_aabb, ray_vs_sphere, ray_vs_plane
from collision import point_in_aabb, point_aabb_distance
from collision import aabb_shape, sphere_shape
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
    return math.abs(a - b) < 0.01

print "=== Collision System Sanity Checks ==="

# --- Shapes ---
let box = aabb_shape(1.0, 1.0, 1.0)
check("aabb shape type", box["type"] == "aabb")
check("aabb shape half", approx(box["half"][0], 1.0))

let sph = sphere_shape(2.0)
check("sphere shape type", sph["type"] == "sphere")
check("sphere shape radius", approx(sph["radius"], 2.0))

# --- AABB vs AABB ---
let h1 = vec3(1.0, 1.0, 1.0)
# Overlapping
let hit = aabb_vs_aabb(vec3(0.0, 0.0, 0.0), h1, vec3(1.5, 0.0, 0.0), h1)
check("aabb overlap detected", hit != nil)
check("aabb overlap depth > 0", hit["depth"] > 0.0)
check("aabb overlap normal exists", hit["normal"] != nil)

# Not overlapping
let miss = aabb_vs_aabb(vec3(0.0, 0.0, 0.0), h1, vec3(5.0, 0.0, 0.0), h1)
check("aabb no overlap", miss == nil)

# Y-axis overlap (stacked boxes)
let y_hit = aabb_vs_aabb(vec3(0.0, 0.0, 0.0), h1, vec3(0.0, 1.5, 0.0), h1)
check("aabb y-axis overlap", y_hit != nil)
check("aabb y-axis normal is vertical", approx(math.abs(y_hit["normal"][1]), 1.0))

# --- Sphere vs Sphere ---
let s_hit = sphere_vs_sphere(vec3(0.0, 0.0, 0.0), 1.0, vec3(1.5, 0.0, 0.0), 1.0)
check("sphere overlap detected", s_hit != nil)
check("sphere overlap depth > 0", s_hit["depth"] > 0.0)
check("sphere normal points away", s_hit["normal"][0] < 0.0)

let s_miss = sphere_vs_sphere(vec3(0.0, 0.0, 0.0), 1.0, vec3(5.0, 0.0, 0.0), 1.0)
check("sphere no overlap", s_miss == nil)

# Coincident spheres
let s_co = sphere_vs_sphere(vec3(0.0, 0.0, 0.0), 1.0, vec3(0.0, 0.0, 0.0), 1.0)
check("coincident spheres overlap", s_co != nil)
check("coincident spheres have depth", s_co["depth"] > 0.0)

# --- Sphere vs AABB ---
let sa_hit = sphere_vs_aabb(vec3(1.8, 0.0, 0.0), 1.0, vec3(0.0, 0.0, 0.0), h1)
check("sphere-aabb overlap", sa_hit != nil)
check("sphere-aabb depth > 0", sa_hit["depth"] > 0.0)

let sa_miss = sphere_vs_aabb(vec3(5.0, 0.0, 0.0), 1.0, vec3(0.0, 0.0, 0.0), h1)
check("sphere-aabb no overlap", sa_miss == nil)

# Sphere inside box
let sa_inside = sphere_vs_aabb(vec3(0.0, 0.0, 0.0), 0.5, vec3(0.0, 0.0, 0.0), h1)
check("sphere inside aabb", sa_inside != nil)

# --- Ray vs AABB ---
let r_hit = ray_vs_aabb(vec3(-5.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), h1)
check("ray-aabb hit", r_hit != nil)
check("ray-aabb t > 0", r_hit["t"] > 0.0)
check("ray-aabb hit point near box", approx(r_hit["point"][0], -1.0))

let r_miss = ray_vs_aabb(vec3(-5.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), h1)
check("ray-aabb miss", r_miss == nil)

# Ray from behind (should miss)
let r_behind = ray_vs_aabb(vec3(-5.0, 0.0, 0.0), vec3(-1.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), h1)
check("ray-aabb behind miss", r_behind == nil)

# --- Ray vs Sphere ---
let rs_hit = ray_vs_sphere(vec3(-5.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), 2.0)
check("ray-sphere hit", rs_hit != nil)
check("ray-sphere t > 0", rs_hit["t"] > 0.0)
check("ray-sphere normal points away", rs_hit["normal"][0] < 0.0)

let rs_miss = ray_vs_sphere(vec3(-5.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0), 2.0)
check("ray-sphere miss", rs_miss == nil)

# --- Ray vs Plane ---
let rp_hit = ray_vs_plane(vec3(0.0, 5.0, 0.0), vec3(0.0, -1.0, 0.0), 0.0)
check("ray-plane hit", rp_hit != nil)
check("ray-plane t = 5", approx(rp_hit["t"], 5.0))
check("ray-plane point at y=0", approx(rp_hit["point"][1], 0.0))

# Parallel ray (no hit)
let rp_par = ray_vs_plane(vec3(0.0, 5.0, 0.0), vec3(1.0, 0.0, 0.0), 0.0)
check("ray-plane parallel miss", rp_par == nil)

# Ray away from plane
let rp_away = ray_vs_plane(vec3(0.0, 5.0, 0.0), vec3(0.0, 1.0, 0.0), 0.0)
check("ray-plane away miss", rp_away == nil)

# --- Point in AABB ---
check("point inside aabb", point_in_aabb(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), h1))
check("point outside aabb", point_in_aabb(vec3(5.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), h1) == false)
check("point on edge aabb", point_in_aabb(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), h1))

# --- Point-AABB distance ---
let d1 = point_aabb_distance(vec3(3.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), h1)
check("point-aabb distance", approx(d1, 2.0))

let d2 = point_aabb_distance(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), h1)
check("point inside aabb distance = 0", approx(d2, 0.0))

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Collision sanity checks failed!"
else:
    print "All collision sanity checks passed!"
