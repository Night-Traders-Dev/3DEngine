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

proc _client_recv(client, max_len):
    if client["secure"] and client["ssl_sock"] != nil:
        import ssl
        return ssl.recv(client["ssl_sock"], max_len)
    return tcp.recv(client["socket"], max_len)

proc _client_send(client, data):
    if client["secure"] and client["ssl_sock"] != nil:
        import ssl
        return ssl.send(client["ssl_sock"], data) >= 0
    return tcp.sendall(client["socket"], data)

proc _client_close_transport(client):
    if client["ssl_sock"] != nil:
        try:
            import ssl
            ssl.shutdown(client["ssl_sock"])
            ssl.free(client["ssl_sock"])
        catch e:
            nil
        client["ssl_sock"] = nil
    if client["socket"] != nil:
        tcp.close(client["socket"])
        client["socket"] = nil

# ============================================================================
# Client connection
# ============================================================================
proc _create_client(sock, client_id):
    let c = {}
    c["socket"] = _socket_fd(sock)
    c["peer_host"] = ""
    c["peer_port"] = 0
    if type(sock) == "dict":
        if dict_has(sock, "host"):
            c["peer_host"] = sock["host"]
        if dict_has(sock, "port"):
            c["peer_port"] = sock["port"]
    c["id"] = client_id
    c["name"] = "Player_" + str(client_id)
    c["buffer"] = ""
    c["connected"] = true
    c["last_ping"] = 0.0
    c["secure"] = false
    c["ssl_sock"] = nil
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
    srv["host"] = "0.0.0.0"
    srv["secure"] = false
    srv["ssl_ctx"] = nil
    return srv

# ============================================================================
# Start listening
# ============================================================================
proc start_server(srv):
    let sock = tcp.listen(srv["host"], srv["port"])
    if sock == nil or sock < 0:
        print "SERVER ERROR: Failed to listen on port " + str(srv["port"])
        return false
    srv["socket"] = sock
    srv["running"] = true
    # Make non-blocking for polling
    socket.nonblock(sock, true)
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
    let new_fd = _socket_fd(new_sock)
    if new_sock != nil and new_fd >= 0:
        if client_count(srv) >= srv["max_clients"]:
            print "Server: Rejecting connection (max clients reached)"
            tcp.close(new_fd)
            return nil
        let cid = srv["next_client_id"]
        srv["next_client_id"] = cid + 1
        let client = _create_client(new_sock, cid)
        if srv["secure"] and srv["ssl_ctx"] != nil:
            try:
                import ssl
                client["ssl_sock"] = ssl.wrap(srv["ssl_ctx"], client["socket"])
                if client["ssl_sock"] != nil and ssl.accept(client["ssl_sock"]):
                    client["secure"] = true
                else:
                    print "Server: SSL handshake failed for client " + str(cid)
                    _client_close_transport(client)
                    return nil
            catch e:
                print "Server: SSL handshake error: " + str(e)
                _client_close_transport(client)
                return nil
        socket.nonblock(client["socket"], true)
        srv["clients"][str(cid)] = client
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
    let data = _client_recv(client, 4096)
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
    _client_close_transport(client)
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
    return _client_send(client, data)

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
            _client_send(client, data)
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
                _client_send(client, data)
            _client_close_transport(client)
            client["connected"] = false
        i = i + 1
    if srv["socket"] != nil:
        tcp.close(srv["socket"])
        srv["socket"] = nil
    if srv["secure"] and srv["ssl_ctx"] != nil:
        try:
            import ssl
            ssl.free_context(srv["ssl_ctx"])
        catch e:
            nil
        srv["ssl_ctx"] = nil
    print "Server stopped"

# ============================================================================
# Secure server (SSL/TLS)
# ============================================================================
proc create_secure_server(port, cert_path, key_path):
    let srv = create_server(port)
    if srv == nil:
        return nil
    srv["secure"] = true
    srv["cert_path"] = cert_path
    srv["key_path"] = key_path
    try:
        import ssl
        srv["ssl_ctx"] = ssl.context("tls_server")
        if ssl.load_cert(srv["ssl_ctx"], cert_path, key_path):
            print "SSL server initialized on port " + str(port)
        else:
            print "SSL certificate load failed for port " + str(port)
            srv["secure"] = false
            srv["ssl_ctx"] = nil
    catch e:
        print "SSL not available: " + str(e)
        srv["secure"] = false
    return srv
