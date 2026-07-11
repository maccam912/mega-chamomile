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

var players := {}  ## peer_id -> {"name": String}
var my_name := "Chamomile"

var _ready_peers := {}
var _match_ready_peers := {}


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
	players_changed.emit()
	return OK


func join_game(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, App.PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_ready_peers.clear()
	_match_ready_peers.clear()


# --- connection lifecycle -------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_server() and App.in_match:
		# No late joins mid-match in the MVP.
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	players.erase(id)
	_ready_peers.erase(id)
	_match_ready_peers.erase(id)
	rpc(&"_sync_players", players)
	players_changed.emit()
	player_left.emit(id)
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
		rpc(&"_load_game")


@rpc("authority", "call_local", "reliable")
func _load_game() -> void:
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
