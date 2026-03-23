# test_ecs.sage - Sanity checks for the Entity Component System
# Run: ./run.sh tests/test_ecs.sage

from ecs import create_world, spawn, destroy, is_alive, entity_count
from ecs import add_component, get_component, has_component, remove_component
from ecs import add_tag, has_tag, remove_tag, query, query_tag
from ecs import register_system, tick_systems, flush_dead

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== ECS Sanity Checks ==="

# --- World creation ---
let w = create_world()
check("world created", w != nil)
check("empty world has 0 entities", entity_count(w) == 0)

# --- Entity spawning ---
let e1 = spawn(w)
let e2 = spawn(w)
let e3 = spawn(w)
check("first entity id is 1", e1 == 1)
check("second entity id is 2", e2 == 2)
check("third entity id is 3", e3 == 3)
check("3 entities alive", entity_count(w) == 3)
check("e1 is alive", is_alive(w, e1))
check("e2 is alive", is_alive(w, e2))

# --- Entity destruction ---
destroy(w, e2)
check("e2 dead after destroy", is_alive(w, e2) == false)
check("e1 still alive", is_alive(w, e1))
check("2 entities alive after destroy", entity_count(w) == 2)

# --- Components ---
let pos_data = {}
pos_data["x"] = 10.0
pos_data["y"] = 20.0
pos_data["z"] = 30.0
add_component(w, e1, "position", pos_data)
check("e1 has position", has_component(w, e1, "position"))
check("e3 has no position", has_component(w, e3, "position") == false)

let got = get_component(w, e1, "position")
check("get position x", got["x"] == 10.0)
check("get position y", got["y"] == 20.0)

# Non-existent component
let missing = get_component(w, e1, "velocity")
check("missing component returns nil", missing == nil)

# Remove component
remove_component(w, e1, "position")
check("removed component is gone", has_component(w, e1, "position") == false)

# Re-add for query tests
add_component(w, e1, "position", pos_data)
let vel_data = {}
vel_data["vx"] = 1.0
vel_data["vy"] = 0.0
add_component(w, e1, "velocity", vel_data)
add_component(w, e3, "position", pos_data)

# --- Query ---
let pos_entities = query(w, ["position"])
check("query position finds 2 entities", len(pos_entities) == 2)

let pos_vel_entities = query(w, ["position", "velocity"])
check("query position+velocity finds 1 entity", len(pos_vel_entities) == 1)
check("query position+velocity finds e1", pos_vel_entities[0] == e1)

# --- Tags ---
add_tag(w, e1, "player")
add_tag(w, e3, "enemy")
check("e1 has player tag", has_tag(w, e1, "player"))
check("e3 has enemy tag", has_tag(w, e3, "enemy"))
check("e1 has no enemy tag", has_tag(w, e1, "enemy") == false)

let players = query_tag(w, "player")
check("query_tag player finds 1", len(players) == 1)
check("query_tag player finds e1", players[0] == e1)

remove_tag(w, e1, "player")
check("tag removed", has_tag(w, e1, "player") == false)

# --- Systems ---
let system_ran = [false]
proc test_system(world, entities, dt):
    system_ran[0] = true
    let i = 0
    while i < len(entities):
        let p = get_component(world, entities[i], "position")
        let v = get_component(world, entities[i], "velocity")
        p["x"] = p["x"] + v["vx"] * dt
        i = i + 1

register_system(w, "movement", ["position", "velocity"], test_system)
tick_systems(w, 1.0)
check("system ran", system_ran[0])
let updated_pos = get_component(w, e1, "position")
check("system updated position", updated_pos["x"] == 11.0)

# --- Flush dead ---
destroy(w, e3)
flush_dead(w)
check("flushed entity gone from queries", len(query(w, ["position"])) == 1)
let enemies = query_tag(w, "enemy")
check("flushed entity gone from tags", len(enemies) == 0)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "ECS sanity checks failed!"
else:
    print "All ECS sanity checks passed!"
