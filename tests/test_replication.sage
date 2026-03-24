# test_replication.sage - Sanity checks for entity replication
# Run: ./run.sh tests/test_replication.sage

from net_replication import create_replication_manager, register_entity
from net_replication import get_net_id, get_local_id, build_update_messages
from net_replication import apply_remote_update, interpolate_remotes
from net_replication import handle_replication_message, replication_stats
from ecs import create_world, spawn, add_component, get_component, has_component, entity_count
from components import TransformComponent
from net_protocol import msg_entity_update, msg_entity_spawn, msg_entity_destroy
from math3d import vec3, v3_length, v3_sub

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

print "=== Replication System Sanity Checks ==="

# --- Manager creation ---
let rm = create_replication_manager()
check("manager created", rm != nil)
let stats = replication_stats(rm)
check("0 replicated", stats["replicated_entities"] == 0)

# --- Register entity ---
let w = create_world()
let e1 = spawn(w)
add_component(w, e1, "transform", TransformComponent(1.0, 2.0, 3.0))
let net_id = register_entity(rm, e1)
check("net_id assigned", net_id > 0)
check("get_net_id", get_net_id(rm, e1) == net_id)
check("get_local_id", get_local_id(rm, net_id) == e1)
check("1 replicated", replication_stats(rm)["replicated_entities"] == 1)

# --- Build update messages ---
let msgs = build_update_messages(rm, w, 0.01)
check("first update sends", len(msgs) > 0)
check("update msg type", msgs[0]["type"] == "entity_update")

# No change -> no message (below threshold)
let msgs2 = build_update_messages(rm, w, 0.01)
check("no change = no message", len(msgs2) == 0)

# Move entity -> sends update
let t1 = get_component(w, e1, "transform")
t1["position"] = vec3(10.0, 2.0, 3.0)
let msgs3 = build_update_messages(rm, w, 0.01)
check("moved entity sends update", len(msgs3) > 0)

# Rotate entity -> also sends update
t1["rotation"] = vec3(0.0, 1.0, 0.0)
let msgs4 = build_update_messages(rm, w, 0.01)
check("rotated entity sends update", len(msgs4) > 0)

# --- Apply remote update ---
let rm2 = create_replication_manager()
let w2 = create_world()
# Receive update for unknown entity -> auto-spawn
apply_remote_update(rm2, w2, 99, [5.0, 6.0, 7.0], [0.0, 0.0, 0.0], 0.0)
let local = get_local_id(rm2, 99)
check("auto-spawned entity", local > 0)
check("auto-spawn has transform", has_component(w2, local, "transform"))
let rt = get_component(w2, local, "transform")
check("remote pos x", approx(rt["position"][0], 5.0))

# --- Interpolation ---
apply_remote_update(rm2, w2, 99, [10.0, 6.0, 7.0], [0.0, 0.0, 0.0], 1.0)
interpolate_remotes(rm2, w2, 0.016)
let rt2 = get_component(w2, local, "transform")
# Should have moved toward 10.0 but not yet there (dt=0.016, speed=10 -> lerp_t=0.16)
check("interpolation moves toward target", rt2["position"][0] > 5.0)
check("interpolation not instant", rt2["position"][0] < 9.5)

# More interpolation
let ii = 0
while ii < 20:
    interpolate_remotes(rm2, w2, 0.1)
    ii = ii + 1
let rt3 = get_component(w2, local, "transform")
check("converges to target", approx(rt3["position"][0], 10.0))

# --- Handle replication messages ---
let rm3 = create_replication_manager()
let w3 = create_world()

# Spawn message
let spawn_msg = msg_entity_spawn(50, "cube", [3.0, 4.0, 5.0])
let handled = handle_replication_message(rm3, w3, spawn_msg, 0.0)
check("spawn msg handled", handled == true)
check("spawned entity exists", get_local_id(rm3, 50) > 0)

# Duplicate spawn message should be idempotent (no extra local entity)
let ecount_before_dup = entity_count(w3)
handle_replication_message(rm3, w3, spawn_msg, 0.1)
check("duplicate spawn does not add entity", entity_count(w3) == ecount_before_dup)

# Update message
let upd_msg = msg_entity_update(50, [8.0, 4.0, 5.0], [0.0, 1.0, 0.0])
handle_replication_message(rm3, w3, upd_msg, 0.5)
check("update applied to buffer", len(rm3["interp_buffers"]) > 0)

# Destroy message
let destroy_msg = msg_entity_destroy(50)
handle_replication_message(rm3, w3, destroy_msg, 1.0)
check("destroyed entity removed", get_local_id(rm3, 50) == -1)

# Unknown message type
from net_protocol import create_message
let unk = create_message("unknown_type", nil)
let unk_handled = handle_replication_message(rm3, w3, unk, 0.0)
check("unknown msg not handled", unk_handled == false)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Replication sanity checks failed!"
else:
    print "All replication sanity checks passed!"
