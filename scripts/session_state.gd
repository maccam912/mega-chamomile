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
var identities := {}  ## peer_id -> stable lobby identity (currently player name)
var role_history := {}  ## identity -> {hider: last round, seeker: last round}


func reset(player_ids: Array) -> void:
	totals.clear()
	replay_ready.clear()
	identities.clear()
	role_history.clear()
	rounds_played = 0
	for id: int in player_ids:
		add_player(id)


func add_player(id: int, identity := "") -> void:
	if not totals.has(id):
		totals[id] = 0
	replay_ready[id] = false
	var stable_identity := identity if not identity.is_empty() else str(id)
	identities[id] = stable_identity
	if not role_history.has(stable_identity):
		role_history[stable_identity] = {"hider": -1, "seeker": -1}


func remove_player(id: int) -> void:
	totals.erase(id)
	replay_ready.erase(id)
	identities.erase(id)
	# Keep role_history: reconnecting with the same lobby identity must not
	# reset how long that player has waited for either role.


## Preference-aware, least-recently-served seeker selection for the next
## round. Preferences are honored only when both role pools have volunteers.
func assign_roles(preferences: Dictionary, seeker_count: int, seed_val := -1) -> Array:
	var ids: Array = preferences.keys()
	seeker_count = clampi(seeker_count, 0, maxi(0, ids.size() - 1))
	var seeker_volunteers := ids.filter(func(id): return preferences[id] == "seeker")
	var hider_volunteers := ids.filter(func(id): return preferences[id] == "hider")
	var rng := RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()
	_shuffle(ids, rng)
	var ordered := ids.duplicate()
	if not seeker_volunteers.is_empty() and not hider_volunteers.is_empty():
		var neutral := ids.filter(func(id): return preferences[id] == "none")
		_shuffle(seeker_volunteers, rng)
		_shuffle(neutral, rng)
		_shuffle(hider_volunteers, rng)
		_sort_least_recent(seeker_volunteers, "seeker")
		_sort_least_recent(neutral, "seeker")
		_sort_least_recent(hider_volunteers, "seeker")
		ordered = seeker_volunteers + neutral + hider_volunteers
	else:
		_sort_least_recent(ordered, "seeker")
	var selected := ordered.slice(0, seeker_count)
	for id in ids:
		var identity := str(identities.get(id, str(id)))
		if not role_history.has(identity):
			role_history[identity] = {"hider": -1, "seeker": -1}
		var role_key := "seeker" if selected.has(id) else "hider"
		role_history[identity][role_key] = rounds_played
	return selected


func _sort_least_recent(ids: Array, role_key: String) -> void:
	ids.sort_custom(func(a, b) -> bool:
		var a_identity := str(identities.get(a, str(a)))
		var b_identity := str(identities.get(b, str(b)))
		var a_round := int(role_history.get(a_identity, {}).get(role_key, -1))
		var b_round := int(role_history.get(b_identity, {}).get(role_key, -1))
		return a_round < b_round)


func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = values[i]
		values[i] = values[j]
		values[j] = tmp


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
