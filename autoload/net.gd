extends Node
## Networking singleton: ENet host/join, replicated player registry, and every
## match-orchestration RPC. Living on an autoload means RPC node paths always
## match on every peer, regardless of which scene is loaded.

signal players_changed
signal join_failed(msg: String)
signal joined_ok
signal player_left(peer_id: int)
signal all_peers_scene_ready          ## server only
signal all_peers_match_ready          ## server only
signal shot_requested(shooter_id: int, origin: Vector3, dir: Vector3)  ## server only
signal match_setup(payload: Dictionary)
signal phase_changed(phase: int, duration: float, extra: Dictionary)
signal player_eliminated_sig(victim_id: int, shooter_id: int)
signal shot_fired_sig(shooter_id: int, origin: Vector3, hit_pos: Vector3)
signal spotted_changed(is_spotted: bool)
signal scores_updated(scores: Array, winner: int)
signal player_despawned(peer_id: int)
signal replay_readiness_changed(ready_ids: Array, player_count: int)
signal hiding_readiness_changed(hidden_count: int, hider_count: int, my_hidden: bool)
signal hidden_ready_requested(peer_id: int, hidden: bool)  ## server only
signal start_seeking_requested  ## server only

const SessionStateScript := preload("res://scripts/session_state.gd")

var players := {}  ## peer_id -> {"name": String}
var my_name := "Chamomile"

var _ready_peers := {}
var _match_ready_peers := {}
var session: RefCounted = SessionStateScript.new()
var _accepting_replay_ready := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func host_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(App.PORT, 16)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": my_name}}
	session.reset([1])
	_accepting_replay_ready = false
	App.last_scores.clear()
	App.last_winner = 0
	players_changed.emit()
	return OK


func join_game(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, App.PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	session.reset([])
	_accepting_replay_ready = false
	App.last_scores.clear()
	App.last_winner = 0
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_ready_peers.clear()
	_match_ready_peers.clear()
	session.reset([])
	_accepting_replay_ready = false
	App.last_scores.clear()
	App.last_winner = 0


# --- connection lifecycle -------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_server() and App.in_match:
		# No late joins mid-match in the MVP.
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	players.erase(id)
	session.remove_player(id)
	_ready_peers.erase(id)
	_match_ready_peers.erase(id)
	rpc(&"_sync_players", players)
	players_changed.emit()
	player_left.emit(id)
	if _accepting_replay_ready:
		_broadcast_replay_readiness()
	_check_barriers()


func _on_connected_ok() -> void:
	rpc_id(1, &"_register_player", my_name)
	joined_ok.emit()


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("Could not connect to host.")


func _on_server_disconnected() -> void:
	leave()
	App.to_main_menu("Host disconnected.")


# --- player registry ------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _register_player(pname: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"name": pname.substr(0, 20)}
	session.add_player(id)
	rpc(&"_sync_players", players)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_players(new_players: Dictionary) -> void:
	players = new_players
	players_changed.emit()


# --- match orchestration (host -> everyone) --------------------------------

## Host calls this from the lobby to move everyone into the game scene.
func request_start() -> void:
	if is_server():
		_begin_game_load()


## Every player opts in from the results screen. Once all connected players
## are ready, the host may reload the game scene for the next round.
func begin_replay_readiness() -> void:
	if not is_server():
		return
	_accepting_replay_ready = true
	session.begin_replay_vote(players.keys())
	_broadcast_replay_readiness()


func request_replay_ready(ready: bool) -> void:
	if is_server():
		_set_replay_ready(1, ready)
	else:
		rpc_id(1, &"_request_replay_ready", ready)


@rpc("any_peer", "call_remote", "reliable")
func _request_replay_ready(ready: bool) -> void:
	if is_server():
		_set_replay_ready(multiplayer.get_remote_sender_id(), ready)


func _set_replay_ready(id: int, ready: bool) -> void:
	if not _accepting_replay_ready or not players.has(id):
		return
	if session.set_replay_ready(id, ready):
		_broadcast_replay_readiness()


func request_replay_start() -> bool:
	if not is_server() or not _accepting_replay_ready:
		return false
	if session.all_replay_ready(players.keys()):
		_begin_game_load()
		return true
	return false


func _begin_game_load() -> void:
	_accepting_replay_ready = false
	_ready_peers.clear()
	_match_ready_peers.clear()
	rpc(&"_load_game", str(App.settings["map_id"]))


func _broadcast_replay_readiness() -> void:
	rpc(&"_receive_replay_readiness", session.ready_ids(), players.size())


@rpc("authority", "call_local", "reliable")
func _receive_replay_readiness(ready_ids: Array, player_count: int) -> void:
	replay_readiness_changed.emit(ready_ids, player_count)


## Hiding readiness is personalized: everyone receives only the aggregate
## count plus their own state, never the identities of ready hiders.
func broadcast_hiding_readiness(hidden_ids: Array, hider_count: int) -> void:
	if not is_server():
		return
	var hidden_count := hidden_ids.size()
	for id: int in players:
		var my_hidden := hidden_ids.has(id)
		if id == 1:
			_receive_hiding_readiness(hidden_count, hider_count, my_hidden)
		else:
			rpc_id(id, &"_receive_hiding_readiness", hidden_count, hider_count, my_hidden)


@rpc("authority", "call_remote", "reliable")
func _receive_hiding_readiness(hidden_count: int, hider_count: int, my_hidden: bool) -> void:
	hiding_readiness_changed.emit(hidden_count, hider_count, my_hidden)


func request_hidden_ready(hidden: bool) -> void:
	if is_server():
		hidden_ready_requested.emit(1, hidden)
	else:
		rpc_id(1, &"_request_hidden_ready", hidden)


@rpc("any_peer", "call_remote", "reliable")
func _request_hidden_ready(hidden: bool) -> void:
	if is_server():
		hidden_ready_requested.emit(multiplayer.get_remote_sender_id(), hidden)


func request_start_seeking() -> void:
	if is_server():
		start_seeking_requested.emit()


@rpc("authority", "call_local", "reliable")
func _load_game(map_id: String) -> void:
	App.select_map(map_id)
	App.in_match = true
	App.status_message = ""
	App.goto_scene(App.GAME_SCENE)


## Each peer's game scene reports in once its tree is ready.
func notify_scene_ready() -> void:
	if is_server():
		_mark_scene_ready(1)
	else:
		rpc_id(1, &"_peer_scene_ready")


@rpc("any_peer", "call_remote", "reliable")
func _peer_scene_ready() -> void:
	if is_server():
		_mark_scene_ready(multiplayer.get_remote_sender_id())


func _mark_scene_ready(id: int) -> void:
	_ready_peers[id] = true
	_check_barriers()


func notify_match_ready() -> void:
	if is_server():
		_mark_match_ready(1)
	else:
		rpc_id(1, &"_peer_match_ready")


@rpc("any_peer", "call_remote", "reliable")
func _peer_match_ready() -> void:
	if is_server():
		_mark_match_ready(multiplayer.get_remote_sender_id())


func _mark_match_ready(id: int) -> void:
	_match_ready_peers[id] = true
	_check_barriers()


func _check_barriers() -> void:
	if not is_server():
		return
	if not _ready_peers.is_empty() and _all_present(_ready_peers):
		_ready_peers.clear()
		all_peers_scene_ready.emit()
	if not _match_ready_peers.is_empty() and _all_present(_match_ready_peers):
		_match_ready_peers.clear()
		all_peers_match_ready.emit()


func _all_present(marks: Dictionary) -> bool:
	for id: int in players:
		if not marks.has(id):
			return false
	return true


func broadcast_match_setup(payload: Dictionary) -> void:
	rpc(&"_receive_match_setup", payload)


@rpc("authority", "call_local", "reliable")
func _receive_match_setup(payload: Dictionary) -> void:
	match_setup.emit(payload)


func broadcast_phase(phase: int, duration: float, extra := {}) -> void:
	rpc(&"_receive_phase", phase, duration, extra)


@rpc("authority", "call_local", "reliable")
func _receive_phase(phase: int, duration: float, extra: Dictionary) -> void:
	phase_changed.emit(phase, duration, extra)


func broadcast_elimination(victim_id: int, shooter_id: int) -> void:
	rpc(&"_receive_elimination", victim_id, shooter_id)


@rpc("authority", "call_local", "reliable")
func _receive_elimination(victim_id: int, shooter_id: int) -> void:
	player_eliminated_sig.emit(victim_id, shooter_id)


func broadcast_shot(shooter_id: int, origin: Vector3, hit_pos: Vector3) -> void:
	rpc(&"_receive_shot", shooter_id, origin, hit_pos)


@rpc("authority", "call_local", "reliable")
func _receive_shot(shooter_id: int, origin: Vector3, hit_pos: Vector3) -> void:
	shot_fired_sig.emit(shooter_id, origin, hit_pos)


func notify_spotted(peer_id: int, is_spotted: bool) -> void:
	if peer_id == 1:
		_receive_spotted(is_spotted)
	else:
		rpc_id(peer_id, &"_receive_spotted", is_spotted)


@rpc("authority", "call_remote", "reliable")
func _receive_spotted(is_spotted: bool) -> void:
	spotted_changed.emit(is_spotted)


func broadcast_scores(scores: Array, winner: int) -> void:
	rpc(&"_receive_scores", scores, winner)


func record_round_scores(scores: Array) -> Array:
	return session.record_round(scores) if is_server() else []


@rpc("authority", "call_local", "reliable")
func _receive_scores(scores: Array, winner: int) -> void:
	App.last_scores = scores
	App.last_winner = winner
	scores_updated.emit(scores, winner)


func broadcast_despawn(peer_id: int) -> void:
	rpc(&"_receive_despawn", peer_id)


@rpc("authority", "call_local", "reliable")
func _receive_despawn(peer_id: int) -> void:
	player_despawned.emit(peer_id)


func broadcast_back_to_lobby() -> void:
	rpc(&"_receive_back_to_lobby")


@rpc("authority", "call_local", "reliable")
func _receive_back_to_lobby() -> void:
	print("[net] back to lobby")
	_accepting_replay_ready = false
	App.in_match = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	App.goto_scene(App.LOBBY_SCENE)


# --- gameplay requests (client -> server) -----------------------------------

## Seeker asks the server to fire a shot from their camera ray.
func request_shot(origin: Vector3, dir: Vector3) -> void:
	if is_server():
		shot_requested.emit(1, origin, dir)
	else:
		rpc_id(1, &"_request_shot", origin, dir)


@rpc("any_peer", "call_remote", "reliable")
func _request_shot(origin: Vector3, dir: Vector3) -> void:
	if is_server():
		shot_requested.emit(multiplayer.get_remote_sender_id(), origin, dir)
