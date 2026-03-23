gc_disable()
# -----------------------------------------
# lobby.sage - Lobby system for Sage Engine
# Host/join games, player management, ready state
# -----------------------------------------

from net_protocol import create_message, MSG_LOBBY_CREATE, MSG_LOBBY_JOIN
from net_protocol import MSG_LOBBY_LEAVE, MSG_LOBBY_LIST, MSG_GAME_START

# ============================================================================
# Lobby
# ============================================================================
proc create_lobby(name, max_players, host_name):
    let lb = {}
    lb["name"] = name
    lb["max_players"] = max_players
    lb["host"] = host_name
    lb["players"] = {}
    lb["players"]["0"] = {"id": 0, "name": host_name, "ready": true, "is_host": true}
    lb["state"] = "waiting"
    lb["settings"] = {}
    lb["settings"]["game_mode"] = "ffa"
    lb["settings"]["time_limit"] = 300
    lb["settings"]["score_limit"] = 100
    return lb

proc add_player(lb, player_id, player_name):
    if player_count(lb) >= lb["max_players"]:
        return false
    let pid = str(player_id)
    lb["players"][pid] = {"id": player_id, "name": player_name, "ready": false, "is_host": false}
    return true

proc remove_player(lb, player_id):
    let pid = str(player_id)
    if dict_has(lb["players"], pid):
        dict_delete(lb["players"], pid)

proc set_ready(lb, player_id, ready):
    let pid = str(player_id)
    if dict_has(lb["players"], pid):
        lb["players"][pid]["ready"] = ready

proc player_count(lb):
    return len(dict_keys(lb["players"]))

proc all_ready(lb):
    let keys = dict_keys(lb["players"])
    let i = 0
    while i < len(keys):
        if lb["players"][keys[i]]["ready"] == false:
            return false
        i = i + 1
    return true

proc can_start(lb):
    return player_count(lb) >= 2 and all_ready(lb)

proc get_player_list(lb):
    let result = []
    let keys = dict_keys(lb["players"])
    let i = 0
    while i < len(keys):
        push(result, lb["players"][keys[i]])
        i = i + 1
    return result

proc start_game(lb):
    if can_start(lb) == false:
        return false
    lb["state"] = "playing"
    return true

proc end_game(lb):
    lb["state"] = "ended"

proc is_in_game(lb):
    return lb["state"] == "playing"

# ============================================================================
# Lobby settings
# ============================================================================
proc set_game_mode(lb, mode):
    lb["settings"]["game_mode"] = mode

proc set_time_limit(lb, seconds):
    lb["settings"]["time_limit"] = seconds

proc set_score_limit(lb, score):
    lb["settings"]["score_limit"] = score

# ============================================================================
# Lobby Manager (tracks multiple lobbies on server)
# ============================================================================
proc create_lobby_manager():
    let lm = {}
    lm["lobbies"] = {}
    lm["next_id"] = 1
    return lm

proc create_lobby_in_manager(lm, name, max_players, host_name):
    let lid = lm["next_id"]
    lm["next_id"] = lid + 1
    let lb = create_lobby(name, max_players, host_name)
    lb["id"] = lid
    lm["lobbies"][str(lid)] = lb
    return lid

proc get_lobby(lm, lobby_id):
    let lid = str(lobby_id)
    if dict_has(lm["lobbies"], lid) == false:
        return nil
    return lm["lobbies"][lid]

proc remove_lobby(lm, lobby_id):
    let lid = str(lobby_id)
    if dict_has(lm["lobbies"], lid):
        dict_delete(lm["lobbies"], lid)

proc list_lobbies(lm):
    let result = []
    let keys = dict_keys(lm["lobbies"])
    let i = 0
    while i < len(keys):
        let lb = lm["lobbies"][keys[i]]
        let info = {}
        info["id"] = lb["id"]
        info["name"] = lb["name"]
        info["players"] = player_count(lb)
        info["max_players"] = lb["max_players"]
        info["state"] = lb["state"]
        push(result, info)
        i = i + 1
    return result
