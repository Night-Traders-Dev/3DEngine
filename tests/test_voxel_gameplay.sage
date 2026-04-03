# test_voxel_gameplay.sage - Sanity checks for shared voxel gameplay helpers

from voxel_gameplay import create_voxel_gameplay_state, spawn_voxel_pickup, update_voxel_pickups
from voxel_gameplay import pickup_draw_position, spawn_voxel_mob, update_voxel_mobs
from voxel_gameplay import ensure_voxel_mob_population, find_target_voxel_mob, collect_dead_voxel_mobs
from voxel_gameplay import voxel_alive_mob_count, voxel_pickup_count, voxel_gameplay_to_sage, voxel_gameplay_from_sage
from voxel_world import create_voxel_world, create_voxel_inventory, voxel_inventory_count, fill_voxel_box
from gameplay import HealthComponent, damage
from math3d import vec3

let p = 0
let f = 0

proc check(name, condition):
    if condition:
        p = p + 1
    else:
        print "  FAIL: " + name
        f = f + 1

print "=== Voxel Gameplay Sanity Checks ==="

let state = create_voxel_gameplay_state()
check("gameplay state created", state != nil)
check("starts with no pickups or mobs", voxel_pickup_count(state) == 0 and voxel_alive_mob_count(state) == 0)

let world = create_voxel_world(32, 8, 32)
fill_voxel_box(world, 0, 0, 0, 32, 2, 32, 3)
let inventory = create_voxel_inventory()

let pickup = spawn_voxel_pickup(state, 3, 2, vec3(0.0, 2.2, 0.0))
check("pickup spawned", pickup != nil and voxel_pickup_count(state) == 1)
let pickup_draw = pickup_draw_position(pickup, 0.0)
check("pickup draw position floats above ground", pickup_draw[1] > pickup["position"][1])
let collected = update_voxel_pickups(state, inventory, vec3(0.0, 2.0, 0.0), 0.016)
check("pickup collected into inventory", len(collected) == 1 and voxel_inventory_count(inventory, 3) == 2 and voxel_pickup_count(state) == 0)

let stale_pickup = spawn_voxel_pickup(state, 1, 1, vec3(8.0, 2.2, 0.0))
stale_pickup["age"] = stale_pickup["max_age"] + 1.0
update_voxel_pickups(state, inventory, vec3(0.0, 2.0, 0.0), 0.016)
check("stale pickup despawns", voxel_pickup_count(state) == 0)

let mob = spawn_voxel_mob(state, vec3(1.0, 2.0, 0.0), "slime")
check("mob spawned", mob != nil and voxel_alive_mob_count(state) == 1)
let target = find_target_voxel_mob(state, vec3(0.0, 2.6, 0.0), vec3(1.0, 0.0, 0.0), 4.0)
check("front-facing ray finds mob", target != nil and target["mob"]["id"] == mob["id"])

let player_health = HealthComponent(100.0)
let mob_events = update_voxel_mobs(state, world, vec3(0.0, 2.0, 0.0), player_health, 0.1, 1.0)
check("near mob damages player", len(mob_events) == 1 and player_health["current"] < 100.0)
let mob_events_cooldown = update_voxel_mobs(state, world, vec3(0.0, 2.0, 0.0), player_health, 0.1, 1.2)
check("mob attack cooldown prevents rapid repeat hit", len(mob_events_cooldown) == 0)

damage(mob["health"], 50.0, 2.0)
let dead_mobs = collect_dead_voxel_mobs(state)
check("dead mobs are removed from active list", len(dead_mobs) == 1 and voxel_alive_mob_count(state) == 0)

let spawned = ensure_voxel_mob_population(state, world, vec3(0.0, 2.0, 0.0), 2, 7.0)
check("mob population helper spawns nearby hostiles", spawned == 2 and voxel_alive_mob_count(state) == 2)

spawn_voxel_pickup(state, 4, 1, vec3(2.0, 2.2, 2.0))
spawn_voxel_mob(state, vec3(2.0, 2.0, 0.0), "slime")
let saved = voxel_gameplay_to_sage(state)
let restored = voxel_gameplay_from_sage(saved)
check("gameplay save keeps pickup count", voxel_pickup_count(restored) == 1)
check("gameplay save keeps mobs alive", voxel_alive_mob_count(restored) == 3)
let restored_target = find_target_voxel_mob(restored, vec3(0.0, 2.6, 0.0), vec3(1.0, 0.0, 0.0), 20.0)
check("restored state still exposes targetable mobs", restored_target != nil)

print ""
print "Results: " + str(p) + " passed, " + str(f) + " failed"
if f > 0:
    raise "Voxel gameplay sanity checks failed!"
else:
    print "All voxel gameplay sanity checks passed!"
