extends Node3D
## Match orchestrator. Every peer builds the same scene (map + players + HUD).
## The server additionally owns the MatchState instance, runs line-of-sight
## scoring, validates shots, and broadcasts everything through Net.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const LOS_INTERVAL := 0.25
const LOS_MAX_DIST := 40.0
const LOS_HALF_ANGLE_DEG := 38.0
const FALL_RECOVERY_Y := -20.0
const FALL_RECOVERY_WIDTH := 2048.0

var match_state: MatchState  # server only
var map: Node3D
var players_node: Node3D
var hud: CanvasLayer
var pause_menu: CanvasLayer
var my_role: int = MatchState.Role.NONE
var current_phase: int = MatchState.Phase.LOBBY
var total_hiders := 0

var _los_timer := 0.0
var _spotted_now := {}  # hider id -> bool, server-side edge detection
var _snd_shoot: AudioStream
var _snd_elim: AudioStream
var _snd_phase: AudioStream
var _snd_win: AudioStream
var _snd_lose: AudioStream
var _replay_loading := false
var _my_hidden := false
var _all_hiders_hidden := false
var _followed_seeker_id := -1
var _final_scores: Array = []
var _final_winner: int = MatchState.Team.NOBODY


func _ready() -> void:
	var map_scene := load(App.selected_map_scene()) as PackedScene
	if map_scene == null:
		push_error("Could not load selected map: %s" % App.selected_map_scene())
		return
	map = map_scene.instantiate()
	add_child(map)
	_build_fall_recovery()
	players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node)
	hud = preload("res://scripts/hud.gd").new()
	add_child(hud)
	hud.ragdoll_toggled.connect(_toggle_local_ragdoll)
	hud.replay_ready_toggled.connect(Net.request_replay_ready)
	hud.replay_start_requested.connect(_on_replay_start_requested)
	hud.hidden_toggled.connect(Net.request_hidden_ready)
	hud.start_seeking_requested.connect(Net.request_start_seeking)
	pause_menu = preload("res://scripts/pause_menu.gd").new()
	add_child(pause_menu)
	pause_menu.opened.connect(_set_ui_blocked.bind(true))
	pause_menu.resumed.connect(_set_ui_blocked.bind(false))

	_snd_shoot = load("res://assets/audio/shoot.ogg")
	_snd_elim = load("res://assets/audio/eliminated.ogg")
	_snd_phase = load("res://assets/audio/phase.ogg")
	_snd_win = load("res://assets/audio/win.ogg")
	_snd_lose = load("res://assets/audio/lose.ogg")

	Net.match_setup.connect(_on_match_setup)
	Net.phase_changed.connect(_on_phase_changed)
	Net.player_eliminated_sig.connect(_on_player_eliminated)
	Net.shot_fired_sig.connect(_on_shot_fired)
	Net.spotted_changed.connect(_on_spotted_changed)
	Net.scores_updated.connect(_on_scores_updated)
	Net.player_despawned.connect(_on_player_despawned)
	Net.replay_readiness_changed.connect(_on_replay_readiness_changed)
	Net.hiding_readiness_changed.connect(_on_hiding_readiness_changed)

	if Net.is_server():
		match_state = MatchState.new()
		match_state.phase_entered.connect(_server_on_phase_entered)
		match_state.player_eliminated.connect(_server_on_eliminated)
		Net.all_peers_scene_ready.connect(_server_setup_match)
		Net.all_peers_match_ready.connect(_server_begin_match)
		Net.shot_requested.connect(_server_handle_shot)
		Net.player_left.connect(_server_on_player_left)
		Net.hidden_ready_requested.connect(_server_set_hidden)
		Net.start_seeking_requested.connect(_server_start_seeking)
	Net.notify_scene_ready()


# --- server: match lifecycle -------------------------------------------------

func _server_setup_match() -> void:
	match_state.configure(App.settings)
	for id: int in Net.round_player_ids:
		if not Net.players.has(id):
			continue
		match_state.add_player(id, Net.players[id]["name"])
	match_state.assign_role_ids(Net.assign_session_roles(App.settings["seeker_count"]))

	var hider_spots: Array = map.hider_spawns()
	var seeker_spots: Array = map.seeker_spawns()
	hider_spots.shuffle()
	var payload := {"players": []}
	var hi := 0
	var si := 0
	var seeker_ids := match_state.seekers()
	for id: int in match_state.players:
		var role: int = match_state.players[id]["role"]
		var balance_size: float = (
				Net.session.balanced_hider_size(id, seeker_ids)
				if role == MatchState.Role.HIDER else 1.0)
		var ratings: Dictionary = Net.session.rating_snapshot(id)
		var pos: Vector3
		if role == MatchState.Role.SEEKER:
			pos = seeker_spots[si % seeker_spots.size()]
			si += 1
		else:
			pos = hider_spots[hi % hider_spots.size()]
			hi += 1
		payload["players"].append({
			"id": id,
			"name": match_state.players[id]["name"],
			"avatar": AvatarCatalog.normalize(str(Net.players[id].get("avatar", AvatarCatalog.DEFAULT_ID))),
			"role": role,
			"balance_size": balance_size,
			"hiding_rating": ratings["hiding"],
			"seeking_rating": ratings["seeking"],
			"pos": pos,
		})
	Net.broadcast_match_setup(payload)


func _server_begin_match() -> void:
	match_state.start()


func _server_on_phase_entered(phase: int) -> void:
	var extra := {}
	var duration := 0.0
	match phase:
		MatchState.Phase.PAINT:
			duration = match_state.cfg["paint_time"]
			_server_broadcast_hiding_readiness()
		MatchState.Phase.SEEK:
			duration = match_state.cfg["seek_time"]
			if not match_state.seekers().is_empty():
				extra["ammo"] = match_state.ammo_of(match_state.seekers()[0])
		MatchState.Phase.REVEAL:
			duration = match_state.cfg["reveal_time"]
			extra["winner"] = match_state.winner
			# Capture scores before the timed reveal so disconnects or inspection
			# movement cannot change the completed round snapshot.
			_final_scores = Net.record_round_scores(match_state.scores_snapshot())
			_final_winner = match_state.winner
		MatchState.Phase.RESULTS:
			Net.broadcast_scores(_final_scores, _final_winner)
			Net.begin_replay_readiness()
	Net.broadcast_phase(phase, duration, extra)


func _server_on_eliminated(victim_id: int, shooter_id: int) -> void:
	Net.broadcast_elimination(victim_id, shooter_id)


func _server_on_player_left(id: int) -> void:
	if match_state != null:
		match_state.remove_player(id)
		Net.broadcast_despawn(id)
		if match_state.phase == MatchState.Phase.PAINT:
			_server_broadcast_hiding_readiness()


func _server_set_hidden(id: int, hidden: bool) -> void:
	if match_state != null and match_state.set_hidden(id, hidden):
		_server_broadcast_hiding_readiness()


func _server_start_seeking() -> void:
	if match_state != null:
		match_state.start_seek_early()


func _server_broadcast_hiding_readiness() -> void:
	Net.broadcast_hiding_readiness(match_state.hidden_hiders(), match_state.hiders().size())


func _physics_process(delta: float) -> void:
	if match_state == null or _replay_loading:
		return
	match_state.tick(delta)
	if match_state.phase == MatchState.Phase.SEEK:
		_los_timer += delta
		if _los_timer >= LOS_INTERVAL:
			_los_timer = 0.0
			_server_update_line_of_sight()


## The bold-points check: a hider is "in sight" while any seeker has them
## within a view cone and an unobstructed (world-geometry) ray.
func _server_update_line_of_sight() -> void:
	var space := get_world_3d().direct_space_state
	for hider_id: int in match_state.alive_hiders():
		var hider := _player(hider_id)
		if hider == null:
			continue
		var seen := false
		var target: Vector3 = hider.target_position_global()
		for seeker_id: int in match_state.seekers():
			var seeker := _player(seeker_id)
			if seeker == null:
				continue
			var eye: Vector3 = seeker.eye_position_global()
			var to_hider := target - eye
			if to_hider.length() > LOS_MAX_DIST:
				continue
			var look: Vector3 = seeker.look_dir
			if look.angle_to(to_hider) > deg_to_rad(LOS_HALF_ANGLE_DEG):
				continue
			var params := PhysicsRayQueryParameters3D.create(eye, target, 1)
			if space.intersect_ray(params).is_empty():
				seen = true
				break
		if _spotted_now.get(hider_id, false) != seen:
			_spotted_now[hider_id] = seen
			match_state.set_in_sight(hider_id, seen)
			Net.notify_spotted(hider_id, seen)


func _server_handle_shot(shooter_id: int, origin: Vector3, dir: Vector3) -> void:
	if match_state == null or not match_state.consume_shot(shooter_id):
		return
	var shooter := _player(shooter_id)
	var exclude: Array = []
	if shooter != null:
		exclude = shooter.body.body_rids()
		exclude.append(shooter.get_rid())
	var to := origin + dir.normalized() * 60.0
	var params := PhysicsRayQueryParameters3D.create(origin, to, 1 | 2, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	var hit_pos := to
	var victim_id := -1
	if not hit.is_empty():
		hit_pos = hit["position"]
		var collider: Object = hit["collider"]
		if collider.has_meta("peer_id"):
			victim_id = int(collider.get_meta("peer_id"))
	Net.broadcast_shot(shooter_id, origin, hit_pos)
	if victim_id > 0:
		match_state.report_hit(shooter_id, victim_id)
	# Evaluate total ammo only after the final shot's raycast and elimination
	# have resolved, so a last-round sweep still belongs to the seekers.
	match_state.complete_shot()


# --- all peers: reactions to broadcasts ---------------------------------------

func _on_match_setup(payload: Dictionary) -> void:
	var my_id := multiplayer.get_unique_id()
	var my_balance_size := 1.0
	for info: Dictionary in payload["players"]:
		if int(info["id"]) == my_id:
			my_role = int(info["role"])
			my_balance_size = float(info.get("balance_size", 1.0))
	total_hiders = 0
	for info: Dictionary in payload["players"]:
		if int(info["role"]) == MatchState.Role.HIDER:
			total_hiders += 1
		_spawn_player(info)
	print("[game] match setup: %d players, my_role=%s" % [
			payload["players"].size(), MatchState.Role.keys()[my_role]])
	hud.setup(my_role, Net.is_server())
	hud.set_balance_size(my_role, my_balance_size)
	hud.set_alive(total_hiders, total_hiders)
	# Hiders' nameplates would betray them: seekers never see them.
	if my_role == MatchState.Role.SEEKER:
		for info: Dictionary in payload["players"]:
			if int(info["role"]) == MatchState.Role.HIDER:
				var p := _player(int(info["id"]))
				if p != null:
					p.set_nameplate_visible(false)
	Net.notify_match_ready()


func _spawn_player(info: Dictionary) -> void:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(int(info["id"]))
	p.display_name = str(info["name"])
	p.avatar_id = AvatarCatalog.normalize(str(info.get("avatar", AvatarCatalog.DEFAULT_ID)))
	p.balance_size = float(info.get("balance_size", 1.0))
	p.role = int(info["role"])
	p.position = info["pos"]
	p.respawn_position = info["pos"]
	players_node.add_child(p)


## Hidden catch volume far below the map. Each peer simulates only its own
## player recovery; the normal transform RPC then updates everybody else.
func _build_fall_recovery() -> void:
	var recovery := Area3D.new()
	recovery.name = "FallRecovery"
	recovery.position.y = FALL_RECOVERY_Y
	recovery.collision_layer = 0
	recovery.collision_mask = 4  # player CharacterBody3D layer
	recovery.body_entered.connect(_on_fall_recovery_body_entered)
	add_child(recovery)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(FALL_RECOVERY_WIDTH, 4.0, FALL_RECOVERY_WIDTH)
	col.shape = shape
	recovery.add_child(col)


func _on_fall_recovery_body_entered(fallen: Node3D) -> void:
	if fallen.has_method("is_local") and fallen.is_local():
		fallen.recover_from_fall()


func _on_phase_changed(phase: int, duration: float, extra: Dictionary) -> void:
	print("[game] phase -> %s (%.0fs)" % [MatchState.Phase.keys()[phase], duration])
	current_phase = phase
	map.set_seek_open(phase == MatchState.Phase.SEEK or phase == MatchState.Phase.REVEAL \
			or phase == MatchState.Phase.RESULTS)
	hud.on_phase(phase, duration, my_role, extra)
	_play2d(_snd_phase)
	var me := _player(multiplayer.get_unique_id())
	if me != null:
		me.on_phase(phase, extra)
	if phase != MatchState.Phase.SEEK:
		_followed_seeker_id = -1
		hud.set_follow_camera("")
	if phase == MatchState.Phase.REVEAL:
		for player in players_node.get_children():
			player.set_survivor_reveal(
					player.role == MatchState.Role.HIDER and not player.eliminated)
		var winner: int = int(extra.get("winner", MatchState.Team.NOBODY))
		var reveal_text := "HIDERS SURVIVED — FIND THEIR HIDING SPOTS" \
				if winner == MatchState.Team.HIDERS else "ROUND OVER — HIDING SPOTS REVEALED"
		hud.show_banner(reveal_text, Color("fff06a"))
	if phase == MatchState.Phase.RESULTS:
		# Player phase cleanup may leave paint mode, which normally captures the
		# cursor. Results own the mouse now so the replay controls stay clickable.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if phase == MatchState.Phase.SEEK and my_role == MatchState.Role.HIDER:
		hud.show_banner("seekers released!", Color("ff8a5c"))


func _on_player_eliminated(victim_id: int, shooter_id: int) -> void:
	var victim := _player(victim_id)
	if victim != null:
		victim.on_eliminated()
		_play3d(_snd_elim, victim.global_position)
	var alive := 0
	for p in players_node.get_children():
		if p.role == MatchState.Role.HIDER and not p.eliminated:
			alive += 1
	hud.set_alive(alive, total_hiders)
	if victim_id == multiplayer.get_unique_id():
		hud.show_banner("ELIMINATED", Color("ff5a4d"))
		hud.set_spotted(false)


func _on_shot_fired(shooter_id: int, origin: Vector3, hit_pos: Vector3) -> void:
	_play3d(_snd_shoot, origin)
	_spawn_tracer(origin, hit_pos)
	if shooter_id == multiplayer.get_unique_id():
		var me := _player(shooter_id)
		if me != null:
			hud.set_ammo(me.ammo)


func _on_spotted_changed(spotted: bool) -> void:
	hud.set_spotted(spotted)


func _on_scores_updated(scores: Array, winner: int) -> void:
	print("[game] results: winner=%s scores=%s" % [MatchState.Team.keys()[winner], scores])
	hud.show_results(scores, winner, multiplayer.get_unique_id(), Net.is_server())
	var i_won := (
		(winner == MatchState.Team.HIDERS and my_role == MatchState.Role.HIDER)
		or (winner == MatchState.Team.SEEKERS and my_role == MatchState.Role.SEEKER)
	)
	_play2d(_snd_win if i_won else _snd_lose)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_replay_readiness_changed(ready_ids: Array, player_count: int) -> void:
	hud.set_replay_readiness(ready_ids, multiplayer.get_unique_id(), player_count)


func _on_hiding_readiness_changed(hidden_count: int, hider_count: int, my_hidden: bool) -> void:
	_my_hidden = my_hidden
	_all_hiders_hidden = hider_count > 0 and hidden_count == hider_count
	hud.set_hiding_readiness(hidden_count, hider_count, my_hidden)


func _on_replay_start_requested() -> void:
	_replay_loading = Net.request_replay_start()


func _unhandled_input(event: InputEvent) -> void:
	if pause_menu == null or pause_menu.visible:
		return
	if current_phase == MatchState.Phase.RESULTS \
			and event.is_action_pressed("toggle_results"):
		hud.toggle_results_inspection()
		get_viewport().set_input_as_handled()
		return
	if my_role == MatchState.Role.HIDER and current_phase == MatchState.Phase.SEEK \
			and event.is_action_pressed("cycle_seeker_camera"):
		_cycle_seeker_camera()
		get_viewport().set_input_as_handled()
		return
	if current_phase != MatchState.Phase.PAINT:
		return
	if my_role == MatchState.Role.HIDER and event.is_action_pressed("toggle_hidden"):
		Net.request_hidden_ready(not _my_hidden)
		get_viewport().set_input_as_handled()
	elif Net.is_server() and _all_hiders_hidden \
			and event.is_action_pressed("start_seeking_early"):
		Net.request_start_seeking()
		get_viewport().set_input_as_handled()


func _on_player_despawned(peer_id: int) -> void:
	var p := _player(peer_id)
	if peer_id == _followed_seeker_id:
		_stop_following_seeker()
	if p != null:
		p.queue_free()


func _process(_delta: float) -> void:
	# Keep the hider's palette swatch, paint-mode state, and brush ring in sync.
	var me := _player(multiplayer.get_unique_id())
	if me != null and my_role == MatchState.Role.HIDER:
		hud.set_swatch(me.current_color, me.brush_radius)
		hud.set_paint_mode(me.paint_mode)
		hud.set_ragdoll(me.ragdolled)
		if me.paint_mode:
			var mp: Vector2 = get_viewport().get_mouse_position()
			hud.set_brush_cursor(mp, me.brush_cursor_px(mp), me.current_color)


func _set_ui_blocked(blocked: bool) -> void:
	var me := _player(multiplayer.get_unique_id())
	if me != null:
		me.set_ui_blocked(blocked)


func _toggle_local_ragdoll() -> void:
	var me := _player(multiplayer.get_unique_id())
	if me != null:
		me.toggle_ragdoll()


func _cycle_seeker_camera() -> void:
	var me := _player(multiplayer.get_unique_id())
	if me == null or me.eliminated:
		return
	if me.paint_mode:
		hud.show_banner("EXIT PAINT MODE FIRST", Color("e0b34d"))
		return
	var seekers: Array = []
	for player in players_node.get_children():
		if player.role == MatchState.Role.SEEKER and not player.eliminated:
			seekers.append(player)
	seekers.sort_custom(func(a, b) -> bool: return a.peer_id < b.peer_id)
	if seekers.is_empty():
		_stop_following_seeker()
		hud.show_banner("NO SEEKER TO FOLLOW", Color("e0b34d"))
		return
	var next_index := 0
	if _followed_seeker_id > 0:
		var current_index := -1
		for i in seekers.size():
			if seekers[i].peer_id == _followed_seeker_id:
				current_index = i
				break
		next_index = current_index + 1
		if current_index < 0 or next_index >= seekers.size():
			_stop_following_seeker()
			return
	var target = seekers[next_index]
	if me.set_follow_target(target):
		_followed_seeker_id = target.peer_id
		hud.set_follow_camera(target.display_name, next_index + 1, seekers.size())


func _stop_following_seeker() -> void:
	var me := _player(multiplayer.get_unique_id())
	if me != null:
		me.clear_follow_target()
	_followed_seeker_id = -1
	if hud != null:
		hud.set_follow_camera("")


# --- helpers -------------------------------------------------------------------

func _player(id: int) -> Node:
	return players_node.get_node_or_null(str(id))


func _play2d(stream: AudioStream) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _play3d(stream: AudioStream, pos: Vector3) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.4)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_add_vertex(from + Vector3(0, -0.15, 0))
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(mi.queue_free)
