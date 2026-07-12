class_name MatchState
extends RefCounted
## Pure match rules: phases, timers, roles, ammo, eliminations, scoring, wins.
## No scene tree, no networking, no rendering — a whole match can run in a
## headless unit test by calling tick(delta) in a loop. The server owns the
## single live instance; clients only ever see broadcasts derived from it.

signal phase_entered(phase: int)
signal player_eliminated(victim_id: int, shooter_id: int)

enum Phase { LOBBY, PAINT, SEEK, RESULTS, DONE }
enum Role { NONE, HIDER, SEEKER }
enum Team { NOBODY, HIDERS, SEEKERS }

var cfg := {
	"paint_time": 90.0,
	"seek_time": 180.0,
	"results_time": 12.0,
	"shot_cooldown": 0.8,
	"ammo_per_hider": 3,
	"survival_pps": 1.0,   # hider points per second alive during SEEK
	"bold_pps": 3.0,       # extra points per second while in a seeker's sight
	"kill_points": 100,
	"survive_bonus": 75,
	"sweep_bonus": 50,     # per seeker when every hider is found
}

var phase: int = Phase.LOBBY
var time_left := 0.0
var winner: int = Team.NOBODY
## id -> {name, role, alive, survival, bold, kills, bonus, in_sight, cooldown, ammo}
## A player's total score is derived from the components (see score_of), so the
## results breakdown can never disagree with the total.
var players := {}


func configure(overrides: Dictionary) -> void:
	for k: String in overrides:
		if cfg.has(k):
			cfg[k] = overrides[k]


func add_player(id: int, pname: String) -> void:
	players[id] = {
		"name": pname,
		"role": Role.NONE,
		"alive": true,
		"survival": 0.0,  # points from time alive during SEEK
		"bold": 0.0,      # extra points from time in a seeker's sight
		"kills": 0,       # hiders found (seekers only)
		"bonus": 0.0,     # end-of-round survive/sweep bonus
		"in_sight": false,
		"cooldown": 0.0,
		"ammo": 0,
	}


func remove_player(id: int) -> void:
	players.erase(id)
	if phase == Phase.PAINT or phase == Phase.SEEK:
		_check_team_collapse()


## Randomly promotes `seeker_count` players to seekers; the rest are hiders.
## Pass a seed for deterministic tests. With a single player, everyone hides
## (solo test mode: no seekers, phases still flow).
func assign_roles(seeker_count: int, seed_val: int = -1) -> void:
	var ids: Array = players.keys()
	var rng := RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()
	# Fisher-Yates shuffle with our own rng for determinism.
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	seeker_count = clampi(seeker_count, 0, maxi(0, ids.size() - 1))
	for i in ids.size():
		players[ids[i]]["role"] = Role.SEEKER if i < seeker_count else Role.HIDER


func start() -> void:
	winner = Team.NOBODY
	_enter_phase(Phase.PAINT)


func tick(delta: float) -> void:
	match phase:
		Phase.PAINT, Phase.SEEK, Phase.RESULTS:
			pass
		_:
			return
	if phase == Phase.SEEK:
		for id: int in players:
			var p: Dictionary = players[id]
			p["cooldown"] = maxf(0.0, p["cooldown"] - delta)
			if p["role"] == Role.HIDER and p["alive"]:
				p["survival"] += cfg["survival_pps"] * delta
				if p["in_sight"]:
					p["bold"] += cfg["bold_pps"] * delta
	time_left -= delta
	if time_left <= 0.0:
		_advance()


## Validates and consumes one shot (cooldown + ammo). Returns whether the
## shot may be fired at all; hit resolution is separate (report_hit).
func consume_shot(id: int) -> bool:
	if phase != Phase.SEEK or not players.has(id):
		return false
	var p: Dictionary = players[id]
	if p["role"] != Role.SEEKER or p["cooldown"] > 0.0 or p["ammo"] <= 0:
		return false
	p["cooldown"] = cfg["shot_cooldown"]
	p["ammo"] -= 1
	return true


## A validated shot hit a hider. Returns true if the elimination stands.
func report_hit(shooter_id: int, victim_id: int) -> bool:
	if phase != Phase.SEEK:
		return false
	if not players.has(shooter_id) or not players.has(victim_id):
		return false
	var shooter: Dictionary = players[shooter_id]
	var victim: Dictionary = players[victim_id]
	if shooter["role"] != Role.SEEKER or victim["role"] != Role.HIDER or not victim["alive"]:
		return false
	victim["alive"] = false
	victim["in_sight"] = false
	shooter["kills"] += 1
	player_eliminated.emit(victim_id, shooter_id)
	_check_team_collapse()
	return true


func set_in_sight(id: int, value: bool) -> void:
	if players.has(id):
		players[id]["in_sight"] = value


func alive_hiders() -> Array:
	var out := []
	for id: int in players:
		if players[id]["role"] == Role.HIDER and players[id]["alive"]:
			out.append(id)
	return out


func seekers() -> Array:
	var out := []
	for id: int in players:
		if players[id]["role"] == Role.SEEKER:
			out.append(id)
	return out


func hiders() -> Array:
	var out := []
	for id: int in players:
		if players[id]["role"] == Role.HIDER:
			out.append(id)
	return out


func ammo_of(id: int) -> int:
	return players[id]["ammo"] if players.has(id) else 0


## Total score derived from the per-component tallies.
func score_of(id: int) -> float:
	if not players.has(id):
		return 0.0
	var p: Dictionary = players[id]
	return p["survival"] + p["bold"] + p["kills"] * cfg["kill_points"] + p["bonus"]


## Sorted scoreboard rows for broadcast/display, with the score breakdown.
func scores_snapshot() -> Array:
	var rows := []
	for id: int in players:
		var p: Dictionary = players[id]
		rows.append({
			"id": id,
			"name": p["name"],
			"role": p["role"],
			"score": int(roundf(score_of(id))),
			"survival": int(roundf(p["survival"])),
			"bold": int(roundf(p["bold"])),
			"kills": int(p["kills"]),
			"kill_points": int(p["kills"] * cfg["kill_points"]),
			"bonus": int(roundf(p["bonus"])),
			"alive": p["alive"],
		})
	rows.sort_custom(func(a, b) -> bool: return a["score"] > b["score"])
	return rows


# --- internals --------------------------------------------------------------

func _enter_phase(new_phase: int) -> void:
	phase = new_phase
	match new_phase:
		Phase.PAINT:
			time_left = cfg["paint_time"]
		Phase.SEEK:
			time_left = cfg["seek_time"]
			var ammo: int = cfg["ammo_per_hider"] * maxi(1, hiders().size())
			for id: int in seekers():
				players[id]["ammo"] = ammo
		Phase.RESULTS:
			time_left = cfg["results_time"]
		Phase.DONE, Phase.LOBBY:
			time_left = 0.0
	phase_entered.emit(new_phase)


func _advance() -> void:
	match phase:
		Phase.PAINT:
			_enter_phase(Phase.SEEK)
		Phase.SEEK:
			# Timer ran out with hiders still standing: hiders win.
			_finish(Team.HIDERS if not alive_hiders().is_empty() else Team.SEEKERS)
		Phase.RESULTS:
			_enter_phase(Phase.DONE)


func _finish(winning_team: int) -> void:
	winner = winning_team
	if winning_team == Team.HIDERS:
		for id: int in alive_hiders():
			players[id]["bonus"] += cfg["survive_bonus"]
	elif winning_team == Team.SEEKERS:
		for id: int in seekers():
			players[id]["bonus"] += cfg["sweep_bonus"]
	_enter_phase(Phase.RESULTS)


## Ends the round early when one side no longer exists (all hiders eliminated,
## or a whole team disconnected).
func _check_team_collapse() -> void:
	if phase != Phase.PAINT and phase != Phase.SEEK:
		return
	var no_seekers := seekers().is_empty()
	var no_hiders := hiders().is_empty()
	if no_seekers and no_hiders:
		_finish(Team.NOBODY)
	elif no_seekers and phase == Phase.SEEK:
		# Every seeker disconnected mid-hunt: hiders win by default.
		_finish(Team.HIDERS)
	elif alive_hiders().is_empty() and not no_seekers:
		_finish(Team.SEEKERS)
