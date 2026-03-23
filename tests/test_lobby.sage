# test_lobby.sage - Sanity checks for lobby system
# Run: ./run.sh tests/test_lobby.sage

from lobby import create_lobby, add_player, remove_player, set_ready
from lobby import player_count, all_ready, can_start, get_player_list
from lobby import start_game, end_game, is_in_game
from lobby import set_game_mode, set_time_limit, set_score_limit
from lobby import create_lobby_manager, create_lobby_in_manager
from lobby import get_lobby, remove_lobby, list_lobbies

import math

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Lobby System Sanity Checks ==="

# --- Lobby creation ---
let lb = create_lobby("Test Room", 4, "Host")
check("lobby created", lb != nil)
check("lobby name", lb["name"] == "Test Room")
check("max players", lb["max_players"] == 4)
check("host set", lb["host"] == "Host")
check("1 player (host)", player_count(lb) == 1)
check("state waiting", lb["state"] == "waiting")

# --- Host is ready ---
check("host is ready", lb["players"]["0"]["ready"] == true)
check("host is_host", lb["players"]["0"]["is_host"] == true)

# --- Add players ---
let added1 = add_player(lb, 1, "Alice")
check("added Alice", added1 == true)
check("2 players", player_count(lb) == 2)

let added2 = add_player(lb, 2, "Bob")
check("added Bob", added2 == true)
check("3 players", player_count(lb) == 3)

# --- Player list ---
let plist = get_player_list(lb)
check("player list has 3", len(plist) == 3)

# --- Max players ---
add_player(lb, 3, "Charlie")
check("4 players", player_count(lb) == 4)
let overflow = add_player(lb, 4, "Dave")
check("5th player rejected", overflow == false)
check("still 4 players", player_count(lb) == 4)

# --- Ready state ---
check("not all ready", all_ready(lb) == false)
set_ready(lb, 1, true)
set_ready(lb, 2, true)
set_ready(lb, 3, true)
check("all ready after setting", all_ready(lb) == true)

# --- Can start ---
check("can start with 4 ready", can_start(lb) == true)

# Unready one
set_ready(lb, 2, false)
check("cannot start with unready", can_start(lb) == false)
set_ready(lb, 2, true)

# --- Remove player ---
remove_player(lb, 3)
check("3 players after remove", player_count(lb) == 3)

# --- Start game ---
let started = start_game(lb)
check("game started", started == true)
check("state playing", lb["state"] == "playing")
check("is in game", is_in_game(lb) == true)

# --- End game ---
end_game(lb)
check("state ended", lb["state"] == "ended")
check("not in game", is_in_game(lb) == false)

# --- Settings ---
set_game_mode(lb, "ctf")
check("game mode set", lb["settings"]["game_mode"] == "ctf")
set_time_limit(lb, 600)
check("time limit set", lb["settings"]["time_limit"] == 600)
set_score_limit(lb, 50)
check("score limit set", lb["settings"]["score_limit"] == 50)

# --- Cannot start with < 2 players ---
let lb2 = create_lobby("Solo", 4, "Lonely")
check("solo lobby cannot start", can_start(lb2) == false)

# --- Lobby Manager ---
let lm = create_lobby_manager()
check("manager created", lm != nil)

let lid1 = create_lobby_in_manager(lm, "Room 1", 8, "Admin")
let lid2 = create_lobby_in_manager(lm, "Room 2", 4, "Player")
check("lobby 1 id", lid1 > 0)
check("lobby 2 id", lid2 > 0)

let gl = get_lobby(lm, lid1)
check("get lobby works", gl != nil)
check("get lobby name", gl["name"] == "Room 1")

let missing = get_lobby(lm, 999)
check("missing lobby nil", missing == nil)

# List lobbies
let lobby_list = list_lobbies(lm)
check("list has 2 lobbies", len(lobby_list) == 2)
check("list entry has name", lobby_list[0]["name"] == "Room 1" or lobby_list[0]["name"] == "Room 2")

# Remove lobby
remove_lobby(lm, lid1)
check("removed lobby", get_lobby(lm, lid1) == nil)
check("list has 1 after remove", len(list_lobbies(lm)) == 1)

# --- Results ---
print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Lobby sanity checks failed!"
else:
    print "All lobby sanity checks passed!"
