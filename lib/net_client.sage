gc_disable()
# -----------------------------------------
# net_client.sage - Game client for Sage Engine
# Connects to server, sends/receives messages
# -----------------------------------------

import tcp
import socket
from net_protocol import serialize_message, extract_messages, deserialize_message
from net_protocol import create_message, MSG_CONNECT, MSG_DISCONNECT, MSG_PING, MSG_PONG

# ============================================================================
# Game Client
# ============================================================================
proc create_client():
    let cl = {}
    cl["socket"] = nil
    cl["connected"] = false
    cl["player_id"] = -1
    cl["player_name"] = "Player"
    cl["buffer"] = ""
    cl["message_queue"] = []
    cl["on_message"] = nil
    cl["on_connect"] = nil
    cl["on_disconnect"] = nil
    cl["ping"] = 0.0
    cl["last_ping_time"] = 0.0
    cl["server_host"] = ""
    cl["server_port"] = 0
    return cl

# ============================================================================
# Connect to server
# ============================================================================
proc connect_to_server(cl, host, port, player_name):
    let sock = tcp.connect(host, port)
    if sock == nil or sock < 0:
        print "CLIENT ERROR: Failed to connect to " + host + ":" + str(port)
        return false
    cl["socket"] = sock
    cl["connected"] = true
    cl["player_name"] = player_name
    cl["server_host"] = host
    cl["server_port"] = port
    socket.nonblock(sock)
    # Send connect message
    let msg = create_message(MSG_CONNECT, {"name": player_name})
    send_message(cl, msg)
    print "Client: Connected to " + host + ":" + str(port)
    if cl["on_connect"] != nil:
        cl["on_connect"](cl)
    return true

# ============================================================================
# Poll for incoming messages
# ============================================================================
proc poll_client(cl):
    if cl["connected"] == false:
        return nil
    let data = tcp.recv(cl["socket"], 4096)
    if data == nil or len(data) == 0:
        return nil
    cl["buffer"] = cl["buffer"] + data
    let result = extract_messages(cl["buffer"])
    let messages = result[0]
    cl["buffer"] = result[1]
    let i = 0
    while i < len(messages):
        let msg = messages[i]
        # Handle ping/pong internally
        if msg["type"] == "pong":
            import sys
            cl["ping"] = (sys.clock() - cl["last_ping_time"]) * 1000.0
        else:
            push(cl["message_queue"], msg)
            if cl["on_message"] != nil:
                cl["on_message"](cl, msg)
        if msg["type"] == "disconnect":
            _handle_disconnect(cl)
            return nil
        i = i + 1

# ============================================================================
# Send message
# ============================================================================
proc send_message(cl, msg):
    if cl["connected"] == false:
        return false
    let data = serialize_message(msg)
    if data == nil:
        return false
    tcp.sendall(cl["socket"], data)
    return true

# ============================================================================
# Send ping
# ============================================================================
proc send_ping(cl):
    import sys
    cl["last_ping_time"] = sys.clock()
    let msg = create_message(MSG_PING, {"time": cl["last_ping_time"]})
    send_message(cl, msg)

# ============================================================================
# Drain message queue
# ============================================================================
proc drain_client_messages(cl):
    let msgs = cl["message_queue"]
    cl["message_queue"] = []
    return msgs

# ============================================================================
# Disconnect
# ============================================================================
proc _handle_disconnect(cl):
    cl["connected"] = false
    print "Client: Disconnected from server"
    if cl["on_disconnect"] != nil:
        cl["on_disconnect"](cl)

proc disconnect(cl):
    if cl["connected"] == false:
        return nil
    let msg = create_message(MSG_DISCONNECT, nil)
    send_message(cl, msg)
    tcp.close(cl["socket"])
    cl["connected"] = false
    print "Client: Disconnected"
