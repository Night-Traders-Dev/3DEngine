gc_disable()
# -----------------------------------------
# net_server.sage - Game server for Sage Engine
# Listens for TCP connections, manages clients, broadcasts state
# -----------------------------------------

import tcp
import socket
import thread
from net_protocol import serialize_message, extract_messages
from net_protocol import create_message, MSG_PLAYER_JOIN, MSG_PLAYER_LEAVE
from net_protocol import MSG_PLAYER_LIST, MSG_DISCONNECT

# ============================================================================
# Client connection
# ============================================================================
proc _create_client(sock, client_id):
    let c = {}
    c["socket"] = sock
    c["id"] = client_id
    c["name"] = "Player_" + str(client_id)
    c["buffer"] = ""
    c["connected"] = true
    c["last_ping"] = 0.0
    return c

# ============================================================================
# Game Server
# ============================================================================
proc create_server(port):
    let srv = {}
    srv["port"] = port
    srv["socket"] = nil
    srv["clients"] = {}
    srv["next_client_id"] = 1
    srv["running"] = false
    srv["on_message"] = nil
    srv["on_connect"] = nil
    srv["on_disconnect"] = nil
    srv["message_queue"] = []
    srv["max_clients"] = 16
    srv["mutex"] = thread.mutex()
    return srv

# ============================================================================
# Start listening
# ============================================================================
proc start_server(srv):
    let sock = tcp.listen(srv["port"])
    if sock == nil or sock < 0:
        print "SERVER ERROR: Failed to listen on port " + str(srv["port"])
        return false
    srv["socket"] = sock
    srv["running"] = true
    # Make non-blocking for polling
    socket.nonblock(sock)
    print "Server listening on port " + str(srv["port"])
    return true

# ============================================================================
# Poll for new connections and incoming data
# Call this each frame from the server's game loop
# ============================================================================
proc poll_server(srv):
    if srv["running"] == false:
        return nil
    # Accept new connections
    let new_sock = tcp.accept(srv["socket"])
    if new_sock != nil and new_sock >= 0:
        if client_count(srv) >= srv["max_clients"]:
            print "Server: Rejecting connection (max clients reached)"
            tcp.close(new_sock)
            return nil
        let cid = srv["next_client_id"]
        srv["next_client_id"] = cid + 1
        let client = _create_client(new_sock, cid)
        srv["clients"][str(cid)] = client
        socket.nonblock(new_sock)
        print "Server: Client " + str(cid) + " connected"
        if srv["on_connect"] != nil:
            srv["on_connect"](srv, client)
        # Notify others
        let join_msg = create_message(MSG_PLAYER_JOIN, {"id": cid, "name": client["name"]})
        broadcast(srv, join_msg, cid)
    # Read from connected clients
    let cids = dict_keys(srv["clients"])
    let i = 0
    while i < len(cids):
        let client = srv["clients"][cids[i]]
        if client["connected"]:
            _read_client(srv, client)
        i = i + 1

proc _read_client(srv, client):
    let data = tcp.recv(client["socket"], 4096)
    if data == nil:
        return nil
    # Zero-length read means remote closed connection
    if len(data) == 0:
        _disconnect_client(srv, client)
        return nil
    client["buffer"] = client["buffer"] + data
    let result = extract_messages(client["buffer"])
    let messages = result[0]
    client["buffer"] = result[1]
    let i = 0
    while i < len(messages):
        let msg = messages[i]
        msg["sender_id"] = client["id"]
        if msg["type"] == "disconnect":
            _disconnect_client(srv, client)
            return nil
        thread.lock(srv["mutex"])
        push(srv["message_queue"], msg)
        thread.unlock(srv["mutex"])
        if srv["on_message"] != nil:
            srv["on_message"](srv, client, msg)
        i = i + 1

proc _disconnect_client(srv, client):
    client["connected"] = false
    tcp.close(client["socket"])
    print "Server: Client " + str(client["id"]) + " disconnected"
    if srv["on_disconnect"] != nil:
        srv["on_disconnect"](srv, client)
    let leave_msg = create_message(MSG_PLAYER_LEAVE, {"id": client["id"]})
    broadcast(srv, leave_msg, client["id"])

# ============================================================================
# Send message to a specific client
# ============================================================================
proc send_to(srv, client_id, msg):
    let cid_str = str(client_id)
    if dict_has(srv["clients"], cid_str) == false:
        return false
    let client = srv["clients"][cid_str]
    if client["connected"] == false:
        return false
    let data = serialize_message(msg)
    if data == nil:
        return false
    tcp.sendall(client["socket"], data)
    return true

# ============================================================================
# Broadcast to all connected clients (except exclude_id)
# ============================================================================
proc broadcast(srv, msg, exclude_id):
    let data = serialize_message(msg)
    if data == nil:
        return nil
    let cids = dict_keys(srv["clients"])
    let i = 0
    while i < len(cids):
        let client = srv["clients"][cids[i]]
        if client["connected"] and client["id"] != exclude_id:
            tcp.sendall(client["socket"], data)
        i = i + 1

# ============================================================================
# Get queued messages (thread-safe)
# ============================================================================
proc drain_messages(srv):
    thread.lock(srv["mutex"])
    let msgs = srv["message_queue"]
    srv["message_queue"] = []
    thread.unlock(srv["mutex"])
    return msgs

# ============================================================================
# Client management
# ============================================================================
proc client_count(srv):
    let count = 0
    let cids = dict_keys(srv["clients"])
    let i = 0
    while i < len(cids):
        if srv["clients"][cids[i]]["connected"]:
            count = count + 1
        i = i + 1
    return count

proc get_client_list(srv):
    let result = []
    let cids = dict_keys(srv["clients"])
    let i = 0
    while i < len(cids):
        let c = srv["clients"][cids[i]]
        if c["connected"]:
            push(result, {"id": c["id"], "name": c["name"]})
        i = i + 1
    return result

# ============================================================================
# Stop server
# ============================================================================
proc stop_server(srv):
    srv["running"] = false
    # Disconnect all clients
    let cids = dict_keys(srv["clients"])
    let i = 0
    while i < len(cids):
        let client = srv["clients"][cids[i]]
        if client["connected"]:
            let disc = create_message(MSG_DISCONNECT, nil)
            let data = serialize_message(disc)
            if data != nil:
                tcp.sendall(client["socket"], data)
            tcp.close(client["socket"])
            client["connected"] = false
        i = i + 1
    tcp.close(srv["socket"])
    print "Server stopped"
