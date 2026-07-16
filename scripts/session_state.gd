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
## Separate opponent-adjusted estimates for the two fundamentally different
## jobs. `*_games` acts as the lightweight uncertainty term: early results move
## a rating quickly, while an established estimate changes more cautiously.
var skill_ratings := {}  ## identity -> {hiding, seeking, hiding_games, seeking_games}

const HIDER_ROLE := 1
const SEEKER_ROLE := 2
const DEFAULT_RATING := 1000.0
const MIN_RATING := 600.0
const MAX_RATING := 1400.0
const RATING_SPREAD := 400.0
const NEW_PLAYER_K := 48.0
const ESTABLISHED_K := 20.0
const ESTABLISHED_AFTER_GAMES := 12.0
const SIZE_RATING_RANGE := 200.0
const MAX_PERSONAL_SIZE_EFFECT := 0.5
const MAX_SEEKER_SIZE_EFFECT := 0.5
const MIN_BALANCED_SIZE := 0.25
const MAX_BALANCED_SIZE := 1.25


func reset(player_ids: Array) -> void:
	totals.clear()
	replay_ready.clear()
	identities.clear()
	role_history.clear()
	skill_ratings.clear()
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
	_ensure_skill_profile(stable_identity)


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
	_update_skill_ratings(rows)
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
		var ratings := rating_snapshot(id)
		row["hiding_rating"] = ratings["hiding"]
		row["seeking_rating"] = ratings["seeking"]
		row["hiding_games"] = ratings["hiding_games"]
		row["seeking_games"] = ratings["seeking_games"]
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["session_score"] == b["session_score"]:
			return a["round_score"] > b["round_score"]
		return a["session_score"] > b["session_score"])
	return out


## Public, display-ready view of one player's two independent estimates.
func rating_snapshot(id: int) -> Dictionary:
	var identity := str(identities.get(id, str(id)))
	var profile: Dictionary = _ensure_skill_profile(identity)
	return {
		"hiding": int(roundf(float(profile["hiding"]))),
		"seeking": int(roundf(float(profile["seeking"]))),
		"hiding_games": int(profile["hiding_games"]),
		"seeking_games": int(profile["seeking_games"]),
	}


## Hiders receive both a personal handicap and an opponent handicap. A weak
## hider gets smaller; a strong hider gets larger. Strong seekers make every
## hider they face smaller, while struggling seekers get larger targets. The
## final clamp keeps movement, painting, and ragdoll physics in a safe range.
func balanced_hider_size(id: int, seeker_ids: Array) -> float:
	if not identities.has(id) or seeker_ids.is_empty():
		return 1.0
	var hiding := float(_ensure_skill_profile(str(identities[id]))["hiding"])
	var seeking_total := 0.0
	var seeking_count := 0
	for seeker_id: int in seeker_ids:
		if not identities.has(seeker_id):
			continue
		seeking_total += float(
				_ensure_skill_profile(str(identities[seeker_id]))["seeking"])
		seeking_count += 1
	if seeking_count == 0:
		return 1.0
	var seeker_average: float = seeking_total / seeking_count
	var personal_strength := clampf(
			(hiding - DEFAULT_RATING) / SIZE_RATING_RANGE, -1.0, 1.0)
	var seeker_strength := clampf(
			(seeker_average - DEFAULT_RATING) / SIZE_RATING_RANGE, -1.0, 1.0)
	var personal_factor := 1.0 + personal_strength * MAX_PERSONAL_SIZE_EFFECT
	var opponent_factor := 1.0 - seeker_strength * MAX_SEEKER_SIZE_EFFECT
	return clampf(personal_factor * opponent_factor,
			MIN_BALANCED_SIZE, MAX_BALANCED_SIZE)


func _ensure_skill_profile(identity: String) -> Dictionary:
	if not skill_ratings.has(identity):
		skill_ratings[identity] = {
			"hiding": DEFAULT_RATING,
			"seeking": DEFAULT_RATING,
			"hiding_games": 0,
			"seeking_games": 0,
		}
	return skill_ratings[identity]


## One round is treated as hiders playing against the average strength of the
## seeker team. Survival is a hider win; elimination is a seeker win. All
## deltas are calculated from the pre-round snapshot so row iteration order can
## never affect the result.
func _update_skill_ratings(rows: Array) -> void:
	var hiders: Array[Dictionary] = []
	var seekers: Array[Dictionary] = []
	for value in rows:
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var id := int(row.get("id", -1))
		if not identities.has(id):
			continue
		var role := int(row.get("role", 0))
		if role == HIDER_ROLE and row.has("alive"):
			hiders.append(row)
		elif role == SEEKER_ROLE:
			seekers.append(row)
	if hiders.is_empty() or seekers.is_empty():
		return

	var pre_round := {}
	var seeker_rating_total := 0.0
	for row: Dictionary in hiders + seekers:
		var id := int(row["id"])
		var identity := str(identities[id])
		if not pre_round.has(identity):
			pre_round[identity] = _ensure_skill_profile(identity).duplicate(true)
	for row: Dictionary in seekers:
		var identity := str(identities[int(row["id"])])
		seeker_rating_total += float(pre_round[identity]["seeking"])
	var seeker_average := seeker_rating_total / seekers.size()

	var seeker_error_total := 0.0
	for row: Dictionary in hiders:
		var identity := str(identities[int(row["id"])])
		var old: Dictionary = pre_round[identity]
		var expected_survival := _expected_score(float(old["hiding"]), seeker_average)
		var actual_survival := 1.0 if bool(row["alive"]) else 0.0
		var error := actual_survival - expected_survival
		var profile: Dictionary = _ensure_skill_profile(identity)
		profile["hiding"] = clampf(
				float(old["hiding"]) + _k_factor(int(old["hiding_games"])) * error,
				MIN_RATING, MAX_RATING)
		profile["hiding_games"] = int(old["hiding_games"]) + 1
		seeker_error_total -= error

	var seeker_error := seeker_error_total / hiders.size()
	for row: Dictionary in seekers:
		var identity := str(identities[int(row["id"])])
		var old: Dictionary = pre_round[identity]
		var profile: Dictionary = _ensure_skill_profile(identity)
		profile["seeking"] = clampf(
				float(old["seeking"]) + _k_factor(int(old["seeking_games"])) * seeker_error,
				MIN_RATING, MAX_RATING)
		profile["seeking_games"] = int(old["seeking_games"]) + 1


func _expected_score(own_rating: float, opponent_rating: float) -> float:
	return 1.0 / (1.0 + pow(10.0, (opponent_rating - own_rating) / RATING_SPREAD))


func _k_factor(games: int) -> float:
	var experience := clampf(float(games) / ESTABLISHED_AFTER_GAMES, 0.0, 1.0)
	return lerpf(NEW_PLAYER_K, ESTABLISHED_K, experience)


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
