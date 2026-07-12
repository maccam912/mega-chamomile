class_name SessionState
extends RefCounted
## Lobby-session state that survives scene reloads between rounds.
##
## Peer IDs are the session identity for now. A disconnect removes that
## identity and its total; a reconnect receives a new peer ID and starts at
## zero, so scores can never be inherited accidentally.

var totals := {}  ## peer_id -> cumulative integer score
var replay_ready := {}  ## peer_id -> bool
var rounds_played := 0


func reset(player_ids: Array) -> void:
	totals.clear()
	replay_ready.clear()
	rounds_played = 0
	for id: int in player_ids:
		add_player(id)


func add_player(id: int) -> void:
	if not totals.has(id):
		totals[id] = 0
	replay_ready[id] = false


func remove_player(id: int) -> void:
	totals.erase(id)
	replay_ready.erase(id)


## Records one authoritative round and returns display-ready rows containing
## both the round score and the cumulative session score.
func record_round(rows: Array) -> Array:
	rounds_played += 1
	var out := []
	for source: Dictionary in rows:
		var row: Dictionary = source.duplicate(true)
		var id := int(row["id"])
		if not totals.has(id):
			# Handles a score snapshot racing a disconnect without inventing an
			# identity that can persist into a later round.
			continue
		var round_score := int(row["score"])
		totals[id] = int(totals[id]) + round_score
		row["round_score"] = round_score
		row["session_score"] = int(totals[id])
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["session_score"] == b["session_score"]:
			return a["round_score"] > b["round_score"]
		return a["session_score"] > b["session_score"])
	return out


func begin_replay_vote(player_ids: Array) -> void:
	replay_ready.clear()
	for id: int in player_ids:
		replay_ready[id] = false


func set_replay_ready(id: int, ready: bool) -> bool:
	if not replay_ready.has(id):
		return false
	replay_ready[id] = ready
	return true


func ready_ids() -> Array:
	var ids := []
	for id: int in replay_ready:
		if replay_ready[id]:
			ids.append(id)
	ids.sort()
	return ids


func all_replay_ready(player_ids: Array) -> bool:
	if player_ids.is_empty():
		return false
	for id: int in player_ids:
		if not replay_ready.get(id, false):
			return false
	return true
