# test_net_protocol.sage - Sanity checks for network protocol
# Run: ./run.sh tests/test_net_protocol.sage

from net_protocol import create_message, serialize_message, deserialize_message
from net_protocol import extract_messages, msg_connect, msg_chat, msg_ping
from net_protocol import msg_entity_update, msg_entity_spawn, msg_entity_destroy
from net_protocol import MSG_CONNECT, MSG_CHAT, MSG_PING, MSG_ENTITY_UPDATE

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

print "=== Network Protocol Sanity Checks ==="

# --- Message creation ---
let msg = create_message(MSG_CONNECT, {"name": "Alice"})
check("msg created", msg != nil)
check("msg type", msg["type"] == MSG_CONNECT)
check("msg payload", msg["payload"]["name"] == "Alice")

# --- Serialize ---
let data = serialize_message(msg)
check("serialized not nil", data != nil)
check("serialized has length prefix", len(data) > 4)
# First 4 chars are the length
let prefix = ""
let pi = 0
while pi < 4:
    prefix = prefix + data[pi]
    pi = pi + 1
let body_len = tonumber(prefix)
check("length prefix matches", body_len + 4 == len(data))

# --- Deserialize ---
let msg2 = deserialize_message(data)
check("deserialized not nil", msg2 != nil)
check("deserialized type", msg2["type"] == MSG_CONNECT)
check("deserialized payload", msg2["payload"]["name"] == "Alice")

# --- Round trip with different types ---
let chat = msg_chat("Hello world")
let chat_data = serialize_message(chat)
let chat2 = deserialize_message(chat_data)
check("chat round-trip type", chat2["type"] == MSG_CHAT)
check("chat round-trip text", chat2["payload"]["text"] == "Hello world")

let ping = msg_ping(1.5)
let ping_data = serialize_message(ping)
let ping2 = deserialize_message(ping_data)
check("ping round-trip type", ping2["type"] == MSG_PING)
check("ping round-trip time", approx(ping2["payload"]["time"], 1.5))

# --- Entity messages ---
let eu = msg_entity_update(42, [1.0, 2.0, 3.0], [0.1, 0.2, 0.3])
let eu_data = serialize_message(eu)
let eu2 = deserialize_message(eu_data)
check("entity update eid", approx(eu2["payload"]["eid"], 42))
check("entity update pos", approx(eu2["payload"]["pos"][0], 1.0))
check("entity update rot", approx(eu2["payload"]["rot"][2], 0.3))

let es = msg_entity_spawn(7, "cube", [5.0, 0.0, 5.0])
let es_data = serialize_message(es)
let es2 = deserialize_message(es_data)
check("entity spawn type", es2["payload"]["type"] == "cube")

let ed = msg_entity_destroy(99)
let ed_data = serialize_message(ed)
let ed2 = deserialize_message(ed_data)
check("entity destroy eid", approx(ed2["payload"]["eid"], 99))

# --- Extract multiple messages from buffer ---
let m1 = serialize_message(msg_chat("first"))
let m2 = serialize_message(msg_chat("second"))
let m3 = serialize_message(msg_chat("third"))
let combined = m1 + m2 + m3
let result = extract_messages(combined)
let msgs = result[0]
let remaining = result[1]
check("extracted 3 messages", len(msgs) == 3)
check("no remaining", len(remaining) == 0)
check("first msg text", msgs[0]["payload"]["text"] == "first")
check("third msg text", msgs[2]["payload"]["text"] == "third")

# --- Partial message in buffer ---
let partial = m1 + m2
# Cut last message in half
let half = ""
let hi = 0
while hi < len(m2) - 5:
    half = half + m2[hi]
    hi = hi + 1
let partial_buf = m1 + half
let result2 = extract_messages(partial_buf)
check("extracted 1 from partial", len(result2[0]) == 1)
check("remaining buffer not empty", len(result2[1]) > 0)

# --- Empty/invalid ---
let empty_result = extract_messages("")
check("empty buffer gives 0 msgs", len(empty_result[0]) == 0)

let bad = deserialize_message("xxxx")
check("bad data returns nil", bad == nil)

let short = deserialize_message("abc")
check("short data returns nil", short == nil)

# --- Sender ID ---
let msg3 = create_message(MSG_CONNECT, nil)
msg3["sender_id"] = 7
msg3["timestamp"] = 12.5
let d3 = serialize_message(msg3)
let msg4 = deserialize_message(d3)
check("sender_id preserved", approx(msg4["sender_id"], 7))
check("timestamp preserved", approx(msg4["timestamp"], 12.5))

# --- Nil payload ---
let nil_msg = create_message(MSG_PING, nil)
let nil_data = serialize_message(nil_msg)
let nil2 = deserialize_message(nil_data)
check("nil payload round-trip", nil2 != nil)
check("nil payload type", nil2["type"] == MSG_PING)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Network protocol sanity checks failed!"
else:
    print "All network protocol sanity checks passed!"
