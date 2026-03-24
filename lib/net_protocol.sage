gc_disable()
# -----------------------------------------
# net_protocol.sage - Network message protocol for Sage Engine
# Serialize/deserialize game messages as length-prefixed strings
# Format: 4-char length prefix + type byte + JSON payload
# -----------------------------------------

from json import cJSON_Parse, cJSON_Print, cJSON_Delete
from json import cJSON_CreateObject, cJSON_AddStringToObject, cJSON_AddNumberToObject
from json import cJSON_GetObjectItem, cJSON_GetStringValue, cJSON_GetNumberValue
from json import cJSON_ToSage, cJSON_FromSage

# ============================================================================
# Message types
# ============================================================================
let MSG_CONNECT = "connect"
let MSG_DISCONNECT = "disconnect"
let MSG_PING = "ping"
let MSG_PONG = "pong"
let MSG_CHAT = "chat"
let MSG_PLAYER_JOIN = "player_join"
let MSG_PLAYER_LEAVE = "player_leave"
let MSG_PLAYER_LIST = "player_list"
let MSG_ENTITY_SPAWN = "entity_spawn"
let MSG_ENTITY_DESTROY = "entity_destroy"
let MSG_ENTITY_UPDATE = "entity_update"
let MSG_STATE_SYNC = "state_sync"
let MSG_INPUT = "input"
let MSG_EVENT = "event"
let MSG_LOBBY_CREATE = "lobby_create"
let MSG_LOBBY_JOIN = "lobby_join"
let MSG_LOBBY_LEAVE = "lobby_leave"
let MSG_LOBBY_LIST = "lobby_list"
let MSG_GAME_START = "game_start"
let MSG_GAME_END = "game_end"

# ============================================================================
# Create a message
# ============================================================================
proc create_message(msg_type, payload):
    let msg = {}
    msg["type"] = msg_type
    msg["payload"] = payload
    msg["timestamp"] = 0.0
    msg["sender_id"] = -1
    return msg

# ============================================================================
# Serialize message to string
# ============================================================================
proc serialize_message(msg):
    let root = cJSON_CreateObject()
    cJSON_AddStringToObject(root, "t", msg["type"])
    cJSON_AddNumberToObject(root, "ts", msg["timestamp"])
    cJSON_AddNumberToObject(root, "sid", msg["sender_id"])
    if msg["payload"] != nil:
        let pnode = cJSON_FromSage(msg["payload"])
        if pnode != nil:
            from json import cJSON_AddItemToObject
            cJSON_AddItemToObject(root, "p", pnode)
    let json_str = cJSON_Print(root)
    cJSON_Delete(root)
    if json_str == nil:
        return nil
    # Length prefix: 8-char zero-padded length
    let body_len = len(json_str)
    let prefix = _pad_length(body_len)
    return prefix + json_str

proc _pad_length(n):
    let s = str(n)
    while len(s) < 8:
        s = "0" + s
    return s

proc _all_digits(data, start, count):
    let i = 0
    while i < count:
        if start + i >= len(data):
            return false
        let ch = data[start + i]
        if ch < "0" or ch > "9":
            return false
        i = i + 1
    return true

proc _parse_length_at(data, pos):
    # Preferred: 8-char prefix (current format)
    if pos + 8 <= len(data):
        if _all_digits(data, pos, 8):
            let s8 = ""
            let i = 0
            while i < 8:
                s8 = s8 + data[pos + i]
                i = i + 1
            let n8 = tonumber(s8)
            if n8 > 0:
                return [n8, 8]
    # Backward compatibility: 4-char prefix (legacy format)
    if pos + 4 <= len(data):
        if _all_digits(data, pos, 4):
            let s4 = ""
            let i = 0
            while i < 4:
                s4 = s4 + data[pos + i]
                i = i + 1
            let n4 = tonumber(s4)
            if n4 > 0:
                return [n4, 4]
    return [0, 0]

# ============================================================================
# Deserialize message from string
# ============================================================================
proc deserialize_message(data):
    if len(data) < 5:
        return nil
    let parsed = _parse_length_at(data, 0)
    let body_len = parsed[0]
    let prefix_len = parsed[1]
    if body_len <= 0 or prefix_len <= 0:
        return nil
    if len(data) < prefix_len + body_len:
        return nil
    let body = ""
    let i = prefix_len
    while i < len(data) and i < prefix_len + body_len:
        body = body + data[i]
        i = i + 1
    let root = cJSON_Parse(body)
    if root == nil:
        return nil
    let msg = {}
    let t_node = cJSON_GetObjectItem(root, "t")
    if t_node != nil:
        msg["type"] = cJSON_GetStringValue(t_node)
    else:
        msg["type"] = "unknown"
    let ts_node = cJSON_GetObjectItem(root, "ts")
    if ts_node != nil:
        msg["timestamp"] = cJSON_GetNumberValue(ts_node)
    else:
        msg["timestamp"] = 0.0
    let sid_node = cJSON_GetObjectItem(root, "sid")
    if sid_node != nil:
        msg["sender_id"] = cJSON_GetNumberValue(sid_node)
    else:
        msg["sender_id"] = -1
    let p_node = cJSON_GetObjectItem(root, "p")
    if p_node != nil:
        msg["payload"] = cJSON_ToSage(p_node)
    else:
        msg["payload"] = nil
    cJSON_Delete(root)
    return msg

# ============================================================================
# Extract messages from a buffer (handles partial reads)
# Returns [messages_array, remaining_buffer_string]
# ============================================================================
proc extract_messages(buffer):
    let messages = []
    let pos = 0
    while pos + 4 <= len(buffer):
        let parsed = _parse_length_at(buffer, pos)
        let body_len = parsed[0]
        let prefix_len = parsed[1]
        if body_len <= 0 or prefix_len <= 0:
            pos = pos + 1
            continue
        if pos + prefix_len + body_len > len(buffer):
            # Incomplete message, keep in buffer
            let remaining = ""
            let ri = pos
            while ri < len(buffer):
                remaining = remaining + buffer[ri]
                ri = ri + 1
            return [messages, remaining]
        let msg_data = ""
        let mi = pos
        while mi < pos + prefix_len + body_len:
            msg_data = msg_data + buffer[mi]
            mi = mi + 1
        let msg = deserialize_message(msg_data)
        if msg != nil:
            push(messages, msg)
        pos = pos + prefix_len + body_len
    let remaining = ""
    if pos < len(buffer):
        let ri = pos
        while ri < len(buffer):
            remaining = remaining + buffer[ri]
            ri = ri + 1
    return [messages, remaining]

# ============================================================================
# Convenience message builders
# ============================================================================
proc msg_connect(player_name):
    return create_message(MSG_CONNECT, {"name": player_name})

proc msg_disconnect():
    return create_message(MSG_DISCONNECT, nil)

proc msg_ping(time):
    return create_message(MSG_PING, {"time": time})

proc msg_pong(time):
    return create_message(MSG_PONG, {"time": time})

proc msg_chat(text):
    return create_message(MSG_CHAT, {"text": text})

proc msg_entity_update(entity_id, position, rotation):
    let p = {}
    p["eid"] = entity_id
    p["pos"] = position
    p["rot"] = rotation
    return create_message(MSG_ENTITY_UPDATE, p)

proc msg_entity_spawn(entity_id, entity_type, position):
    let p = {}
    p["eid"] = entity_id
    p["type"] = entity_type
    p["pos"] = position
    return create_message(MSG_ENTITY_SPAWN, p)

proc msg_entity_destroy(entity_id):
    return create_message(MSG_ENTITY_DESTROY, {"eid": entity_id})

proc msg_input(actions):
    return create_message(MSG_INPUT, {"actions": actions})
