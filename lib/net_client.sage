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
# Transport helpers
# ============================================================================
proc _socket_fd(sock):
    if sock == nil:
        return -1
    if type(sock) == "dict":
        if dict_has(sock, "fd"):
            return sock["fd"]
        return -1
    if type(sock) == "number":
        return sock
    return -1

proc _client_recv(cl, max_len):
    if cl["secure"] and cl["ssl_sock"] != nil:
        import ssl
        return ssl.recv(cl["ssl_sock"], max_len)
    return tcp.recv(cl["socket"], max_len)

proc _client_send(cl, data):
    if cl["secure"] and cl["ssl_sock"] != nil:
        import ssl
        return ssl.send(cl["ssl_sock"], data) >= 0
    return tcp.sendall(cl["socket"], data)

proc _cleanup_ssl_state(cl):
    if cl["ssl_sock"] != nil or cl["ssl_ctx"] != nil:
        try:
            import ssl
            if cl["ssl_sock"] != nil:
                ssl.shutdown(cl["ssl_sock"])
                ssl.free(cl["ssl_sock"])
            if cl["ssl_ctx"] != nil:
                ssl.free_context(cl["ssl_ctx"])
        catch e:
            nil
        cl["ssl_sock"] = nil
        cl["ssl_ctx"] = nil

proc _client_close_transport(cl):
    _cleanup_ssl_state(cl)
    if cl["socket"] != nil:
        tcp.close(cl["socket"])
        cl["socket"] = nil

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
    cl["secure"] = false
    cl["ssl_ctx"] = nil
    cl["ssl_sock"] = nil
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
    cl["secure"] = false
    cl["ssl_ctx"] = nil
    cl["ssl_sock"] = nil
    socket.nonblock(sock, true)
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
    let data = _client_recv(cl, 4096)
    if data == nil:
        return nil
    # Zero-length read means server closed the connection
    if len(data) == 0:
        _handle_disconnect(cl)
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
    return _client_send(cl, data)

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
    _client_close_transport(cl)
    _handle_disconnect(cl)

# ============================================================================
# Secure client (SSL/TLS)
# ============================================================================
proc connect_secure(host, port):
    let client = create_client()
    let sock = tcp.connect(host, port)
    if sock == nil or sock < 0:
        return nil
    client["socket"] = sock
    client["connected"] = true
    client["player_name"] = "Player"
    client["server_host"] = host
    client["server_port"] = port
    try:
        import ssl
        client["ssl_ctx"] = ssl.context("tls_client")
        client["ssl_sock"] = ssl.wrap(client["ssl_ctx"], client["socket"])
        if client["ssl_sock"] != nil:
            client["secure"] = ssl.connect(client["ssl_sock"], host)
        else:
            client["secure"] = false
        if client["secure"]:
            print "SSL connected to " + host + ":" + str(port)
        else:
            print "SSL handshake failed, using plain TCP"
            _cleanup_ssl_state(client)
    catch e:
        print "SSL not available, using plain TCP: " + str(e)
        _cleanup_ssl_state(client)
        client["secure"] = false
    socket.nonblock(sock, true)
    let msg = create_message(MSG_CONNECT, {"name": client["player_name"]})
    send_message(client, msg)
    return client
