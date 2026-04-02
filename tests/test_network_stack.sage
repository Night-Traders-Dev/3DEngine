# test_network_stack.sage - Integration sanity checks for client/server transport
# Exercises the real net_client/net_server path against the Sage networking runtime.

import sys
import thread

from net_client import create_client, connect_to_server, send_message, disconnect, connect_secure
from net_server import create_server, start_server, poll_server, drain_messages, stop_server
from net_protocol import msg_chat

let pass_count = 0
let fail_count = 0
let TEST_PORT = 39457

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

proc run_server(port):
    let srv = create_server(port)
    let result = {}
    result["started"] = start_server(srv)
    result["messages"] = []
    if result["started"] == false:
        return result

    let deadline = sys.clock() + 1.5
    while sys.clock() < deadline:
        poll_server(srv)
        let msgs = drain_messages(srv)
        let i = 0
        while i < len(msgs):
            push(result["messages"], msgs[i])
            i = i + 1
        if len(result["messages"]) >= 2:
            deadline = sys.clock()

    stop_server(srv)
    return result

print "=== Network Stack Integration Checks ==="

# --- Plain TCP client/server path ---
let server_thread = thread.spawn(run_server, TEST_PORT)
let boot_deadline = sys.clock() + 0.05
while sys.clock() < boot_deadline:
    nil
let client = create_client()
let connected = false
let connect_deadline = sys.clock() + 1.0
while connected == false and sys.clock() < connect_deadline:
    connected = connect_to_server(client, "127.0.0.1", TEST_PORT, "Alice")

check("client connected to local server", connected == true)

let chat_sent = false
if connected:
    chat_sent = send_message(client, msg_chat("hello from integration test"))
    let settle_deadline = sys.clock() + 0.1
    while sys.clock() < settle_deadline:
        nil
    disconnect(client)

check("client chat message sent", chat_sent == true)

let server_result = thread.join(server_thread)
check("server started", server_result["started"] == true)

let saw_connect = false
let saw_chat = false
let chat_sender = -1
let i = 0
while i < len(server_result["messages"]):
    let msg = server_result["messages"][i]
    if msg["type"] == "connect":
        saw_connect = true
    if msg["type"] == "chat":
        if msg["payload"] != nil and msg["payload"]["text"] == "hello from integration test":
            saw_chat = true
            chat_sender = msg["sender_id"]
    i = i + 1

check("server received connect message", saw_connect == true)
check("server received chat message", saw_chat == true)
check("server annotated sender_id", chat_sender > 0)

# --- Secure connect failure path ---
let secure_failed = false
let secure_result = nil
try:
    secure_result = connect_secure("127.0.0.1", TEST_PORT + 1)
catch e:
    secure_failed = true

check("connect_secure failure does not throw", secure_failed == false)
check("connect_secure failure returns nil", secure_result == nil)

print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Network stack integration checks failed!"
else:
    print "All network stack integration checks passed!"
